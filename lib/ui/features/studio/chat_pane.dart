import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/chat_peek.dart';
import '../../../core/harness/draft_block.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../core/scroll_strip.dart';
import '../../core/smooth_scroll.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../../data/services/skill_store.dart';
import 'attachment_view.dart';
import 'chat_message_view.dart';
import 'chat_tabs.dart';
import 'markdown_text.dart';
import 'mention.dart';
import 'side_chat.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

part 'chat_composer.dart';
part 'chat_header.dart';
part 'side_chat_panel.dart';

// 模型菜单里两个不是模型的选项;真实模型 id 是纯数字,不会撞上。
const _byOrder = '#order';
const _manageModels = '#manage';

/// 快捷操作最多露出几个,多的横着滚。
const _maxQuickActions = 6;

/// 右栏:Agent 对话时间线 + 输入框。
class ChatPane extends StatefulWidget {
  const ChatPane({
    super.key,
    required this.vm,
    required this.config,
    required this.input,
    required this.inputFocus,
    required this.onQuickAction,
    required this.onOpenSettings,
    this.onOpenLayout,
    this.onImage,
  });

  final StudioViewModel vm;
  final ConfigService config;
  final TextEditingController input;
  final FocusNode inputFocus;
  final ValueChanged<String> onQuickAction;
  final VoidCallback onOpenSettings;

  /// 切到区域控制工作台(主工作区才给)。
  final VoidCallback? onOpenLayout;

  /// 输入框里放进了一张图(区域控制工作台拿它看横竖)。
  final ValueChanged<Attachment>? onImage;

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final _scroll = SmoothScrollController();

  /// 已经播过弹入动画的消息序号;滚回视野时不再重播。
  final _shown = <int>{};

  /// 正在打的「@关键词」;为 null 时不显示 Skill 列表。
  MentionQuery? _mention;
  int _mentionIndex = 0;

  /// 下一条消息要引用的 Skill。
  List<String> _mentioned = const [];

  /// 下一条消息要带的附件。
  List<Attachment> _attachments = const [];

  /// 有文件正拖在窗口上方。
  bool _dragging = false;

  /// 副聊天的浮窗开着。
  bool _sideOpen = false;

  bool get _compress => widget.config.config.compressImages;

  /// 加上一个附件;它是压缩过的图就提醒一句(压缩能在软件设置里关掉)。
  void _add(Attachment attachment) {
    setState(() {
      _attachments = List.unmodifiable([..._attachments, attachment]);
    });
    if (attachment.compressed) {
      showToast(context, tr('大图已压缩为 WebP,可在软件设置里关闭'));
    }
    if (attachment.isImage) widget.onImage?.call(attachment);
  }

  /// 把选中或拖进来的文件加成附件;读不了的逐个提示,不影响其余的。
  Future<void> _attach(Iterable<String> paths) async {
    for (final path in paths) {
      if (_attachments.length >= maxAttachments) {
        if (mounted) {
          showToast(context, tr('最多 {0} 个附件', [maxAttachments]), warn: true);
        }
        return;
      }
      try {
        final attachment = await readAttachment(
          File(path),
          compress: _compress,
        );
        if (mounted) _add(attachment);
      } on AttachmentException catch (e) {
        if (mounted) showToast(context, e.message, warn: true);
      }
    }
  }

  /// 把剪贴板里的图片(截图、网页上复制的图)或文件(资源管理器里复制的)加成附件。
  Future<void> _pasteAttachments() async {
    try {
      final files = await Pasteboard.files();
      if (files.isNotEmpty) return await _attach(files);
      // 从表格、文档里复制的内容常常同时带着文字和一张图:有文字就只贴文字。
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (text != null && text.isNotEmpty) return;
      final image = await Pasteboard.image;
      if (image == null || !mounted) return;
      // Windows 给的是不压缩的 BMP,比原图大好几倍:先转成 WebP(压缩开着)或 PNG。
      final attachment = image.length > maxPastedBytes
          ? null
          : await pastedImage(image, compress: _compress);
      if (!mounted) return;
      if (attachment == null) {
        return showToast(context, tr('读不了这张图'), warn: true);
      }
      final problem = attachment.bytes!.length > maxImageBytes
          ? tr('图片超过 {0}', [maxImageLabel])
          : _attachments.length >= maxAttachments
          ? tr('最多 {0} 个附件', [maxAttachments])
          : null;
      if (problem != null) return showToast(context, problem, warn: true);
      _add(attachment);
    } on Object {
      // 剪贴板读不了就当里面没有图,不打扰用户。
    }
  }

  Future<void> _pickFiles() async {
    final picked = await openFiles();
    await _attach(picked.map((f) => f.path));
    widget.inputFocus.requestFocus();
  }

  List<UserSkill> get _allSkills => widget.vm.skills?.all ?? builtinSkillList;

  /// 列表里可选的:符合关键词、有内容、还没引用过的。
  List<UserSkill> get _mentionMatches => matchSkills(
    _allSkills.where((s) => s.body.isNotEmpty && !_mentioned.contains(s.id)),
    _mention?.query ?? '',
  );

  @override
  void initState() {
    super.initState();
    widget.vm.addListener(_followReply);
    widget.input.addListener(_trackMention);
    _toBottom();
  }

  /// 现在看的这场对话的第一条消息;换了就是换了一场对话。
  late ChatMessage? _head = widget.vm.messages.firstOrNull;

  /// 滚到最新的一条。列表是边滚边排的,一次到不了底就多跳几次。
  void _toBottom([int tries = 6]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final bottom = _scroll.position.maxScrollExtent;
      if (_scroll.offset >= bottom) return;
      _scroll.jumpTo(bottom);
      if (tries > 0) _toBottom(tries - 1);
    });
  }

  @override
  void dispose() {
    widget.vm.removeListener(_followReply);
    widget.input.removeListener(_trackMention);
    _scroll.dispose();
    super.dispose();
  }

  void _trackMention() {
    final value = widget.input.value;
    final next = value.selection.isCollapsed
        ? mentionQueryAt(value.text, value.selection.baseOffset)
        : null;
    if (next == _mention) return;
    setState(() {
      _mention = next;
      _mentionIndex = 0;
    });
  }

  /// 选中一个 Skill:去掉输入框里那段「@关键词」,把它记成一个引用标签。
  void _pickMention(UserSkill skill) {
    final mention = _mention;
    if (mention == null) return;
    final text = widget.input.text;
    final end = mention.start + 1 + mention.query.length;
    // 文字在这期间被别处改短了就不动它,只记下引用。
    if (end > text.length) {
      setState(() {
        _mentioned = List.unmodifiable([..._mentioned, skill.id]);
        _mention = null;
      });
      return;
    }
    widget.input.value = TextEditingValue(
      text: text.replaceRange(mention.start, end, ''),
      selection: TextSelection.collapsed(offset: mention.start),
    );
    setState(() {
      _mentioned = List.unmodifiable([..._mentioned, skill.id]);
      _mention = null;
    });
    widget.inputFocus.requestFocus();
  }

  /// 列表打开时,上下键选、Enter 或 Tab 确认、Esc 关掉。返回 null 表示这个键不归列表管。
  KeyEventResult? _onMentionKey(KeyEvent event) {
    if (_mention == null || event is KeyUpEvent) return null;
    // 输入法正在选字时,方向键、回车、Esc 都是给输入法用的。
    if (widget.input.value.composing.isValid) return null;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _mention = null);
      return KeyEventResult.handled;
    }
    final matches = _mentionMatches;
    if (matches.isEmpty) return null;
    final step = key == LogicalKeyboardKey.arrowDown
        ? 1
        : key == LogicalKeyboardKey.arrowUp
        ? -1
        : 0;
    if (step != 0) {
      setState(() => _mentionIndex = (_mentionIndex + step) % matches.length);
      return KeyEventResult.handled;
    }
    final confirm =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab;
    if (!confirm || widget.input.value.composing.isValid) return null;
    if (event is KeyDownEvent) {
      _pickMention(matches[_mentionIndex.clamp(0, matches.length - 1)]);
    }
    return KeyEventResult.handled;
  }

  /// 是否跟着新内容滚到底;用户往上翻时关掉,翻回底部再打开。
  bool _follow = true;

  /// 离最新的一条比较远:显示「回到底部」。
  bool _away = false;

  bool _onScroll(ScrollNotification n) {
    // 只看时间线自己的滚动,消息里面的小滚动不算。
    if (n.depth != 0) return false;
    final away = n.metrics.extentAfter > 120;
    if (away != _away) setState(() => _away = away);
    // 自动跟随只会往下跳,所以出现往上的位移一定是用户在翻。
    if (n is ScrollUpdateNotification && (n.scrollDelta ?? 0) < 0) {
      _follow = false;
    } else if (n is ScrollEndNotification && n.metrics.extentAfter <= 40) {
      // 停在离底 40 像素以内就算回到了最新,接着跟。
      _follow = true;
    }
    return false;
  }

  /// 回复生成时让时间线跟着滚到底。
  void _followReply() {
    final head = widget.vm.messages.firstOrNull;
    if (!identical(head, _head)) {
      // 打开了另一场对话:从最新的一条看起。
      _head = head;
      _follow = true;
      _toBottom();
    }
    if (!widget.vm.isStreaming || !_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final problem = widget.vm.send(
      widget.input.text,
      skillIds: _mentioned,
      attachments: _attachments,
    );
    if (problem != null) {
      showToast(context, problem, warn: true);
      return;
    }
    widget.input.clear();
    _follow = true;
    setState(() {
      _mentioned = const [];
      _attachments = const [];
    });
  }

  /// 引用的 Skill 的显示名;已经被删掉的 Skill 不显示。
  List<String> _namesOf(List<String> ids) => [
    for (final id in ids)
      for (final s in _allSkills)
        if (s.id == id) s.name,
  ];

  /// [replacing] 是这条回复讨论的那一段成稿;为 null 表示换整篇。
  void _adoptDraft(AgentDraft draft, String? replacing) {
    final problem = widget.vm.placeDraft(
      draft.text,
      page: draft.page,
      replacing: replacing,
    );
    showToast(context, problem ?? tr('已放到左侧'), warn: problem != null);
  }

  void _adoptLayout(String json) {
    final ok = widget.vm.adoptLayout(json);
    showToast(context, ok ? tr('已放到布局画板') : tr('布局读不了'), warn: !ok);
  }

  /// 把回复里新写的 Skill 加进(或替换进)用户的 Skills。
  Future<void> _addSkill(String text) async {
    final store = widget.vm.skills;
    if (store == null) return;
    String? problem;
    try {
      await store.addText(text);
    } on SkillException catch (e) {
      problem = e.message;
    }
    if (!mounted) return;
    // 卡片上的状态是照着 Skills 列表算的,加完要重画一次。
    setState(() {});
    showToast(context, problem ?? tr('已加入 Skills'), warn: problem != null);
  }

  DraftStatus _draftStatus(String text) {
    final vm = widget.vm;
    // 成稿可能送到了同系列的别的页,所以这个系列的每一页都看一眼。
    // 只改了其中几段的成稿是并进去的,所以按行看它在不在,而不是找整段。
    final mine = vm.pages.where((p) => p.series == vm.series);
    bool waiting(DraftPage p) => containsLines(
      [?p.pending, ...p.queued].map((d) => d.added).join('\n'),
      text,
    );
    if (mine.any((p) => p.pending != null && waiting(p))) {
      return DraftStatus.pending;
    }
    return mine.any(
          (p) => containsLines(p.blocks.map((b) => b.text).join(), text),
        )
        ? DraftStatus.applied
        : DraftStatus.ready;
  }

  void _retry() {
    final problem = widget.vm.regenerate();
    if (problem != null) {
      showToast(context, problem, warn: true);
      return;
    }
    _follow = true;
  }

  /// Enter 发送,Shift+Enter 换行;输入法选字时的 Enter 不算发送。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final byMention = _onMentionKey(event);
    if (byMention != null) return byMention;
    // 生成中按 Esc 打断;输入法选字时的 Esc 是给输入法用的。
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        widget.vm.isStreaming &&
        !widget.input.value.composing.isValid) {
      widget.vm.stop();
      return KeyEventResult.handled;
    }
    // Ctrl+V:剪贴板里是图片或文件就加成附件。不拦这次按键,文字照常由输入框粘贴。
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isControlPressed) {
      _pasteAttachments();
    }
    final isEnter =
        event is! KeyUpEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter);
    if (!isEnter ||
        HardwareKeyboard.instance.isShiftPressed ||
        widget.input.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    // 按住 Enter 不放时只发一次,也不往输入框里塞换行。
    if (event is KeyDownEvent) _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.vm.messages;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) => _attach(details.files.map((f) => f.path)),
      child: ColoredBox(color: PennaColors.editorBg, child: _build(messages)),
    );
  }

  Widget _row(List<ChatMessage> messages, ChatRow row) {
    final (index: i, :message, :lookups) = row;
    final last = i == messages.length - 1;
    return PopIn(
      animate: _shown.add(i),
      child: ChatMessageView(
        message: message,
        lookups: lookups,
        agentAvatar: widget.config.config.agentAvatar,
        userAvatar: widget.config.config.userAvatar,
        skillNames: _namesOf(message.skillIds),
        // 中间可能隔着查标签的那几条,所以找用户自己发的最后一条。
        onAdoptDraft: (draft) => _adoptDraft(
          draft,
          messages
              .take(i)
              .where((m) => m.fromUser && !m.tool)
              .lastOrNull
              ?.quote,
        ),
        draftStatus: _draftStatus,
        userSkills: widget.vm.skills?.skills ?? const [],
        onAddSkill: _addSkill,
        onAdoptLayout: _adoptLayout,
        onOpenLayout: widget.onOpenLayout,
        streaming: widget.vm.isStreaming && last,
        onRetry: !widget.vm.isStreaming && last && !message.fromUser
            ? _retry
            : null,
        // 只有最新那条回复的选项能点;点了就当成用户的回答发出去。
        onOption: !widget.vm.isStreaming && last ? _answer : null,
        draftSections: [
          for (final s in widget.vm.sectionsHere)
            (label: s.label, detail: s.text.trim()),
        ],
      ),
    );
  }

  void _answer(String option) {
    final problem = widget.vm.send(option);
    if (problem != null) return showToast(context, problem, warn: true);
    _follow = true;
    _toBottom();
  }

  Widget _list(List<ChatMessage> messages, List<ChatRow> rows) =>
      messages.isEmpty
      ? Center(
          child: Text(
            tr('描述画面,或贴上要改的提示词'),
            style: TextStyle(fontSize: 13, color: PennaColors.slate400),
          ),
        )
      : Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListView.separated(
                controller: _scroll,
                // ponytail: 整场对话都排好版,总高度是量出来的而不是估的;
                // 只排看得见的那几条时,底下的成稿卡片很高,估出的总高度偏差大,
                // 拖滚动条会一下跳很远。上限是一场对话约 100 万像素高。
                scrollCacheExtent: const ScrollCacheExtent.pixels(1e6),
                padding: const EdgeInsets.all(24),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 24),
                itemBuilder: (_, row) => _row(messages, rows[row]),
              ),
            ),
            Positioned(
              right: 18,
              bottom: 12,
              child: IgnorePointer(
                ignoring: !_away,
                child: AnimatedScale(
                  scale: _away ? 1 : 0,
                  duration: Motion.base,
                  curve: Curves.easeOutBack,
                  child: Tooltip(
                    message: tr('回到底部'),
                    child: Material(
                      color: PennaColors.card,
                      elevation: 3,
                      shape: CircleBorder(
                        side: BorderSide(color: PennaColors.border),
                      ),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          _follow = true;
                          _toBottom();
                        },
                        child: Padding(
                          padding: EdgeInsets.all(7),
                          child: Icon(
                            Icons.arrow_downward,
                            size: 16,
                            color: PennaColors.slate700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

  Widget _build(List<ChatMessage> messages) {
    final rows = foldLookups(messages);
    return Column(
      children: [
        _Header(
          vm: widget.vm,
          config: widget.config,
          onOpenSettings: widget.onOpenSettings,
        ),
        ChatTabs(vm: widget.vm),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _list(messages, rows)),
              if (widget.vm.side case final side? when _sideOpen)
                Positioned(
                  top: 8,
                  right: 12,
                  bottom: 8,
                  width: _sideWidth,
                  child: PopIn(
                    child: _SidePanel(
                      chat: side,
                      config: widget.config,
                      onClose: () => setState(() => _sideOpen = false),
                      onOpenSettings: widget.onOpenSettings,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _Composer(
          trailing: widget.vm.side == null
              ? null
              : _SideToggle(
                  open: _sideOpen,
                  onTap: () => setState(() => _sideOpen = !_sideOpen),
                ),
          input: widget.input,
          inputFocus: widget.inputFocus,
          quickActions: widget.config.config.quickActions,
          onQuickAction: widget.onQuickAction,
          onKey: _onKey,
          onSend: _send,
          onStop: widget.vm.isStreaming ? widget.vm.stop : null,
          picker: _mention == null
              ? null
              : MentionList(
                  skills: _mentionMatches,
                  selected: _mentionIndex,
                  onPick: _pickMention,
                ),
          onAttach: _pickFiles,
          autoApprove: widget.config.config.autoApprove,
          onAutoApprove: (on) => widget.config.update(
            widget.config.config.copyWith(autoApprove: on),
          ),
          dragging: _dragging,
          queued: [
            for (final (i, m) in widget.vm.outbox.indexed)
              _QueuedRow(
                text: m.text.isEmpty
                    ? tr('{0} 个附件', [m.attachments.length])
                    : m.text.replaceAll('\n', ' '),
                onSendNow: () {
                  final problem = widget.vm.sendQueuedNow(i);
                  if (problem != null) showToast(context, problem, warn: true);
                  _follow = true;
                },
                onRemove: () => widget.vm.unqueue(i),
              ),
          ],
          chips: [
            if (widget.vm.quote != null)
              MentionChip(
                name: sectionTitle(widget.vm.quote!),
                prefix: widget.vm.layoutOnly ? tr('块 · ') : tr('段 · '),
                onRemove: () => widget.vm.quoteSection(null),
              ),
            for (final (i, attachment) in _attachments.indexed)
              AttachmentChip(
                attachment: attachment,
                onRemove: () => setState(() {
                  _attachments = List.unmodifiable(
                    [..._attachments]..removeAt(i),
                  );
                }),
              ),
            for (final (i, name) in _namesOf(_mentioned).indexed)
              MentionChip(
                name: name,
                onRemove: () => setState(() {
                  _mentioned = List.unmodifiable([..._mentioned]..removeAt(i));
                }),
              ),
          ],
        ),
      ],
    );
  }
}
