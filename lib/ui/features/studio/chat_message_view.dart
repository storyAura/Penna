import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/characters/character_dict.dart';
import '../../../core/harness/chat_peek.dart';
import '../../../core/harness/comfyui.dart' show splitGenerate;
import '../../../core/harness/draft_block.dart';
import '../../../core/harness/layout.dart';
import '../../../core/harness/local/local_tools.dart';
import '../../../core/harness/manga/manga_script.dart' show storyboardTag;
import '../../../core/harness/providers/llm_http.dart' show LlmCut;
import '../../../core/harness/tags/tag_search.dart';
import '../../../core/harness/web_search.dart';
import '../../../data/services/skill_store.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'attachment_view.dart';
import 'comfy_progress_view.dart';
import 'layout_card.dart';
import 'markdown_text.dart';
import 'mention.dart';
import 'option_pick.dart';
import 'skill_card.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

part 'chat_message_bits.dart';

/// ComfyUI 出的图在回复下面显示多高。
const _generatedHeight = 280.0;

/// 工具记录里的一行:压成一行,太长的截掉。
String _preview(String text) {
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return line.length > 80 ? '${line.substring(0, 80)}…' : line;
}

String _clock(DateTime t) =>
    [t.hour, t.minute, t.second].map((n) => '$n'.padLeft(2, '0')).join(':');

/// 回复里那份新成稿和左侧成稿的关系。
enum DraftStatus {
  /// 还没放过去,或放过去后成稿又被改了。
  ready,

  /// 已经放过去,等用户在左侧采纳或驳回。
  pending,

  /// 左侧现在就是这份。
  applied,
}

/// 对话时间线里的一条消息。
class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    super.key,
    required this.message,
    required this.onAdoptDraft,
    required this.draftStatus,
    this.streaming = false,
    this.onRetry,
    this.pager,
    this.onShowReply,
    this.onEdit,
    this.isLast = true,
    this.skillNames = const [],
    this.agentAvatar = '',
    this.userAvatar = '',
    this.userSkills = const [],
    this.onAddSkill,
    this.onAdoptLayout,
    this.onOpenLayout,
    this.lookups = const [],
    this.onOption,
    this.onReuseAttachment,
    this.draftSections = const [],
    this.comfy,
    this.onGenerate,
  });

  /// 当前页成稿的各段(标注 + 提示词开头)。回复问"转哪几段"时直接从这里列。
  final List<PickItem> draftSections;

  /// 出图的进度:这条回复要的图正在出时显示在它下面。
  final ComfyRunner? comfy;

  /// 点了「出图」:回复下面的(null,用出图标签里的提示词)或成稿卡片上的(那份成稿)。
  /// 为 null 时没有这些按钮(区域控制的对话)。
  final void Function(String? prompt)? onGenerate;

  /// 用户点了回复里的一个选项;为 null 时选项只是灰的(不是最后一条回复,或正在生成)。
  final ValueChanged<String>? onOption;

  /// 看大图时点了「附到输入框」:把那张图加进输入框的附件。
  final ValueChanged<Attachment>? onReuseAttachment;

  /// 写这条回复之前查标签的那几次记录,合成一块显示。
  final List<ChatMessage> lookups;

  /// 用户已有的 Skill,用来判断回复里新写的那个加没加进去。
  final List<UserSkill> userSkills;

  /// 把回复里新写的 Skill(整篇 SKILL.md)加进用户的 Skills。
  final ValueChanged<String>? onAddSkill;

  /// 把回复里的布局 JSON 再放到区域控制工作台上。
  final ValueChanged<String>? onAdoptLayout;

  /// 切到区域控制工作台;只在主工作区的对话里有。
  final VoidCallback? onOpenLayout;

  /// 两边头像的图片路径;空串用默认头像。
  final String agentAvatar;
  final String userAvatar;

  /// 这条消息用 @ 引用的 Skill 的名字。
  final List<String> skillNames;

  final ChatMessage message;

  /// 把回复里的一份新成稿放到左侧它该去的那一页。
  final ValueChanged<AgentDraft> onAdoptDraft;
  final DraftStatus Function(String text) draftStatus;

  /// 这条回复还在生成。
  final bool streaming;

  /// 非空时显示「重新回复」;只给最后一条回复。
  final VoidCallback? onRetry;

  /// 重新回复留下了几份时给这个,回复下面出现翻页;只给最后一条回复。
  final ({int at, int total})? pager;
  final ValueChanged<int>? onShowReply;

  /// 改好用户消息再发一次,见 [_UserBubble.onEdit]。
  final bool Function(String text)? onEdit;

  /// 这是对话的最后一条。
  final bool isLast;

  /// 写这条回复之前联网搜过的话,列出搜了什么;有失败的要说出来。
  Widget? _webBlock() {
    final webs = [for (final l in lookups) ...webSearchesIn(l.text)];
    if (webs.isEmpty) return null;
    final failed = webs.where((w) => w.result.failed).length;
    return _ToolBlock(
      icon: failed > 0 ? Icons.error_outline : Icons.language,
      iconColor: failed > 0 ? PennaColors.diffDelText : null,
      summary: failed > 0
          ? tr('联网搜索失败 · {0} / {1} 次', [failed, webs.length])
          : tr('已联网搜索 · {0} 次', [webs.length]),
      details: [
        for (final w in webs)
          tr('「{0}」:{1}', [
            w.query,
            _preview(
              w.result.failed ? tr('搜索失败:{0}', [w.result.text]) : w.result.text,
            ),
          ]),
      ],
    );
  }

  /// 写这条回复前加载了哪些技能(用户要求:用到哪个技能要显示出来)。
  Widget? _skillsBlock() {
    final names = {for (final l in lookups) ...skillsLoadedIn(l.text)};
    if (names.isEmpty) return null;
    return _ToolBlock(
      icon: Icons.auto_stories_outlined,
      summary: tr('已使用技能 · {0}', [names.join(tr('、'))]),
      details: const [],
    );
  }

  /// 这条回复出的图;正在出时是进度条。
  /// 写了出图标签([asked])的回复下面:没在出图时是「出图」按钮
  /// (设成手动确认时要点它才出;出过了是「再出一张」)。
  List<Widget> _images(bool asked) {
    final runner = comfy;
    return [
      if (message.images.isNotEmpty) ...[
        const SizedBox(height: 10),
        AttachmentStrip(
          attachments: [
            for (final p in message.images) comfyImageAttachment(p),
          ],
          onReuse: onReuseAttachment,
          height: _generatedHeight,
        ),
      ],
      if (runner != null && !streaming)
        ListenableBuilder(
          listenable: runner,
          builder: (context, _) => runner.owner == message.time
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ComfyProgressRow(runner: runner),
                )
              : runner.aheadOf(message.time) != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ComfyQueuedRow(runner: runner, owner: message.time),
                )
              : asked && onGenerate != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PennaButton(
                      label: message.images.isEmpty ? tr('出图') : tr('再出一张'),
                      icon: Icons.brush_outlined,
                      background: PennaColors.primary,
                      foreground: Colors.white,
                      // 正在出别的图时也能点:排进队列。
                      onPressed: () => onGenerate!(null),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
    ];
  }

  /// Agent 回复的正文:说的话、新成稿卡片,生成完后再加一排操作。
  List<Widget> _reply(BuildContext context) {
    final m = message;
    // 先拆新 Skill:它正文里举例用的成稿标签不能被当成成稿。
    // 出图标签由程序交给 ComfyUI,聊天里只留进度和出好的图。
    final generate = splitGenerate(m.text);
    // 换工作流的标签也由程序做,结果记在回复的记录上。
    final model = splitToolTag(
      splitToolTag(generate.prose, storyboardTag).prose,
      comfyWorkflowTag,
    );
    final peeked = splitPeek(
      splitPeek(model.prose, readSideChat).prose,
      readMainChat,
    ).prose;
    final tools = splitLocalTools(
      splitCharacterTags(
        splitTagSearch(
          splitToolTag(
            splitToolTag(
              splitToolTag(peeked, webSearchTag).prose,
              loadSkillTag,
            ).prose,
            poseRefTag,
          ).prose,
        ).prose,
      ).prose,
    );
    final made = splitNewSkill(splitAskLayout(tools.prose).prose);
    final newSkill = made.skill;
    final laid = splitLayout(made.prose);
    // 透视、灯光标签由程序放到画板上,聊天里只留回复上那一笔记录。
    final asked = splitOptions(
      splitLighting(splitPerspective(splitLayers(laid.prose).prose).prose)
          .prose,
    );
    // 挑成稿里的段:直接列当前页的各段。模型自己列出的多选项正好全是段名时也照此显示。
    final labels = {for (final s in draftSections) s.label};
    final bySection =
        draftSections.isNotEmpty &&
        (asked.sections ||
            asked.multi &&
                asked.options.isNotEmpty &&
                asked.options.every(labels.contains));
    final picks = <PickItem>[
      if (bySection)
        ...draftSections
      else
        for (final option in asked.options) (label: option, detail: ''),
    ];
    final split = splitDrafts(asked.prose);
    final drafts = split.drafts;
    // 有成稿卡片时,正文里照成稿格式抄的那几行是重复的,只在卡片里显示(用户反馈:没在部件里)。
    final prose = drafts.isEmpty ? split.prose : dropDraftLines(split.prose);
    // 复制出去的是能直接用的:标注和中文对照不带。
    final copyable = [
      prose,
      for (final draft in drafts) stripSectionLabels(draft.text),
    ].where((s) => s.isNotEmpty).join('\n\n');
    // 标签写完就在搜了,搜完这一条回复才收起来;没人替它搜时,回复一结束就不显示。
    final searching = streaming
        ? splitToolTag(peeked, webSearchTag).queries
        : const <String>[];
    // 写了 <load-skill> 到正文取回来之间。
    final loading = streaming
        ? splitToolTag(peeked, loadSkillTag).queries
        : const <String>[];
    return [
      if (loading.isNotEmpty) ...[
        _ToolBlock(
          icon: Icons.auto_stories_outlined,
          summary: tr('正在加载技能 · {0}', [loading.join(tr('、'))]),
          details: const [],
        ),
        const SizedBox(height: 10),
      ],
      if (searching.isNotEmpty) ...[
        _ToolBlock(
          icon: Icons.language,
          summary: tr('正在联网搜索'),
          details: searching,
        ),
        const SizedBox(height: 10),
      ],
      if (prose.isNotEmpty)
        SelectableText.rich(markdownSpan(prose, _bodyStyle))
      else if (streaming &&
          drafts.isEmpty &&
          newSkill == null &&
          laid.json == null)
        const TypingDots()
      else if (drafts.isEmpty &&
          newSkill == null &&
          laid.json == null &&
          picks.isEmpty &&
          !generate.asked &&
          model.queries.isEmpty &&
          !m.stopped)
        // 以前只画一个省略号:模型写了程序没接住的标签时,用户看不出发生了什么。
        _RawReply(m.text),
      // 一份成稿一张卡片;分了页的各去各的页。
      for (final (i, draft) in drafts.indexed) ...[
        if (prose.isNotEmpty || i > 0) const SizedBox(height: 10),
        PopIn(
          child: _DraftCard(
            draft: draft,
            // 只有最后一份可能还在写。
            writing: streaming && i == drafts.length - 1,
            status: draftStatus(draft.text),
            onAdopt: () => onAdoptDraft(draft),
            onGenerate: onGenerate == null
                ? null
                : () => onGenerate!(stripSectionLabels(draft.text)),
          ),
        ),
      ],
      if (newSkill != null) ...[
        if (prose.isNotEmpty || drafts.isNotEmpty) const SizedBox(height: 10),
        PopIn(
          child: NewSkillCard(
            text: newSkill,
            complete: made.complete,
            writing: streaming,
            userSkills: userSkills,
            onAdd: () => onAddSkill?.call(newSkill),
          ),
        ),
      ],
      if (laid.json != null) ...[
        if (prose.isNotEmpty || drafts.isNotEmpty || newSkill != null)
          const SizedBox(height: 10),
        PopIn(
          child: LayoutCard(
            json: laid.json!,
            complete: laid.complete,
            writing: streaming && !laid.complete,
            onAdopt: onAdoptLayout == null
                ? null
                : () => onAdoptLayout!(laid.json!),
            onOpen: onOpenLayout,
          ),
        ),
      ],
      ..._images(generate.asked),
      // 给用户点的选项:点一下就当成他的回答发出去。
      // 这条回复已经把成稿写出来了就不显示:没有什么还要他先点头的。
      // 问挑哪几段,当前页却一段都没有:说一声,让用户自己打字回答。
      if (picks.isEmpty && asked.sections && !streaming && drafts.isEmpty) ...[
        const SizedBox(height: 8),
        Text(
          tr('当前页没有分段'),
          style: TextStyle(fontSize: 11.5, color: PennaColors.slate400),
        ),
      ],
      if (picks.isNotEmpty && !streaming && drafts.isEmpty) ...[
        const SizedBox(height: 10),
        if (asked.form && !bySection)
          PopIn(
            child: FormPick(
              options: asked.options,
              headings: asked.headings,
              onSubmit: onOption,
            ),
          )
        else if (asked.multi || bySection)
          PopIn(
            child: MultiPick(
              items: picks,
              headings: bySection ? const {} : asked.headings,
              onSubmit: onOption,
            ),
          )
        else
          PopIn(
            child: SinglePick(options: asked.options, onPick: onOption),
          ),
      ],
      if (!streaming) ...[
        const SizedBox(height: 6),
        PopIn(
          // 副聊天的浮窗窄,放不下时折到下一行。
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (m.stopped) ...[
                Icon(
                  Icons.stop_circle_outlined,
                  size: 13,
                  color: PennaColors.slate400,
                ),
                const SizedBox(width: 4),
                Text(
                  tr('已停止'),
                  style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                ),
                const SizedBox(width: 8),
              ],
              if (m.cut case final cut?) _CutNote(cut),
              if (pager case (:final at, :final total)?)
                if (onShowReply case final show?)
                  _ReplyPager(
                    at: at,
                    total: total,
                    onShow: show,
                    onRetry: onRetry,
                  ),
              if (copyable.isNotEmpty)
                PennaButton(
                  label: tr('复制回复'),
                  icon: Icons.content_copy,
                  background: Colors.transparent,
                  foreground: PennaColors.slate500,
                  onPressed: () => copyWithToast(context, copyable, tr('已复制')),
                ),
              if (onRetry != null)
                PennaButton(
                  label: tr('重新回复'),
                  icon: Icons.refresh,
                  background: Colors.transparent,
                  foreground: PennaColors.slate500,
                  onPressed: onRetry,
                ),
            ],
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final m = message;
    final found = [
      for (final l in lookups)
        if (l.toolSummary != '') l,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PennaAvatar(
          fromUser: m.fromUser,
          path: m.fromUser ? userAvatar : agentAvatar,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    m.fromUser ? tr('用户') : 'Penna Agent',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (m.by != null) ...[
                    const SizedBox(width: 8),
                    Flexible(child: _ModelTag(name: m.by!)),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    _clock(m.time),
                    style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 联网搜索单独一块,不和别的资料合并(用户要求搜了要提醒出来)。
              if (_skillsBlock() case final used?) ...[
                used,
                const SizedBox(height: 10),
              ],
              if (_webBlock() case final web?) ...[
                web,
                const SizedBox(height: 10),
              ],
              // 程序替模型查回来的资料:查了几轮都收在这一块里。
              // 只联网搜索的那一轮没有摘要,不算在里面。
              if (found.isNotEmpty) ...[
                _ToolBlock(
                  summary: found.length == 1
                      ? found.single.toolSummary ?? tr('查了资料')
                      : tr('查了资料 · {0} 次', [found.length]),
                  details: [for (final l in found) ...l.toolDetails],
                ),
                const SizedBox(height: 10),
              ],
              // 程序附给模型看的图(姿势参考):用户也要看到附了哪几张。
              if (lookups.any((l) => l.attachments.isNotEmpty)) ...[
                AttachmentStrip(
                  attachments: [for (final l in lookups) ...l.attachments],
                  onReuse: onReuseAttachment,
                ),
                const SizedBox(height: 10),
              ],
              if (m.toolSummary != null) ...[
                _ToolBlock(summary: m.toolSummary!, details: m.toolDetails),
                const SizedBox(height: 10),
              ],
              if (m.attachments.isNotEmpty) ...[
                AttachmentStrip(
                  attachments: m.attachments,
                  onReuse: onReuseAttachment,
                ),
                if (m.text.isNotEmpty) const SizedBox(height: 6),
              ],
              if (m.fromUser)
                _UserBubble(text: m.text, isLast: isLast, onEdit: onEdit)
              else
                ..._reply(context),
              if (skillNames.isNotEmpty || m.quote != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (m.quote != null)
                      MentionChip(
                        name: sectionTitle(m.quote!),
                        prefix: tr('段 · '),
                      ),
                    for (final name in skillNames) MentionChip(name: name),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

const _bodyStyle = TextStyle(fontSize: 14, height: 1.6);

/// 等第一个字出来时的三个小点:慢慢地依次亮起、浮起再暗下去,安静不抢眼。
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Row(
          children: [
            for (var i = 0; i < 3; i++)
              Builder(
                builder: (_) {
                  // 三个点依次亮起:每个点比前一个晚 150ms(一圈 1.9 秒)。
                  final t = (_controller.value - i * 0.08) % 1;
                  // 前一半里亮起再暗下(0→1→0,缓入缓出),后一半歇着。
                  final up = t < 0.5
                      ? Curves.easeInOut.transform(1 - (t / 0.25 - 1).abs())
                      : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(right: 3.5),
                    child: Transform.translate(
                      offset: Offset(0, -2 * up),
                      child: CircleAvatar(
                        radius: 1.5 + 0.5 * up,
                        backgroundColor: Color.lerp(
                          PennaColors.slate400,
                          PennaColors.primary,
                          up,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 这条回复出自哪个模型。
class _ModelTag extends StatelessWidget {
  const _ModelTag({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return PennaCard(
      color: PennaColors.slate100,
      borderColor: PennaColors.slate100,
      radius: 4,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text(
        name,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: PennaColors.slate500),
      ),
    );
  }
}
