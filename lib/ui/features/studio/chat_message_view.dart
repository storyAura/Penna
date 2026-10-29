import 'package:flutter/material.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/characters/character_dict.dart';
import '../../../core/harness/chat_peek.dart';
import '../../../core/harness/draft_block.dart';
import '../../../core/harness/layout.dart';
import '../../../core/harness/local/local_tools.dart';
import '../../../core/harness/tags/tag_search.dart';
import '../../../data/services/skill_store.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'attachment_view.dart';
import 'layout_card.dart';
import 'markdown_text.dart';
import 'mention.dart';
import 'option_pick.dart';
import 'skill_card.dart';
import 'studio_view_model.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';

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
  });

  /// 当前页成稿的各段(标注 + 提示词开头)。回复问"转哪几段"时直接从这里列。
  final List<PickItem> draftSections;

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

  /// 非空时显示「重新运行」;只给最后一条回复。
  final VoidCallback? onRetry;

  /// Agent 回复的正文:说的话、新成稿卡片,生成完后再加一排操作。
  List<Widget> _reply(BuildContext context) {
    final m = message;
    // 先拆新 Skill:它正文里举例用的成稿标签不能被当成成稿。
    final tools = splitLocalTools(
      splitCharacterTags(
        splitTagSearch(
          splitPeek(splitPeek(m.text, readSideChat).prose, readMainChat).prose,
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
    final (:prose, :drafts) = splitDrafts(asked.prose);
    // 复制出去的是能直接用的:标注和中文对照不带。
    final copyable = [
      prose,
      for (final draft in drafts) stripSectionLabels(draft.text),
    ].where((s) => s.isNotEmpty).join('\n\n');
    return [
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
          !m.stopped)
        const Text('…', style: _bodyStyle),
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
        if (asked.multi)
          PopIn(
            child: MultiPick(items: picks, onSubmit: onOption),
          )
        else
          PopIn(
            child: SinglePick(options: asked.options, onPick: onOption),
          ),
      ],
      if (!streaming) ...[
        const SizedBox(height: 6),
        PopIn(
          child: Row(
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
                  label: tr('重新运行'),
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
              // 程序替模型查回来的资料:查了几轮都收在这一块里。
              if (lookups.isNotEmpty) ...[
                _ToolBlock(
                  summary: lookups.length == 1
                      ? lookups.single.toolSummary ?? tr('查了资料')
                      : tr('查了资料 · {0} 次', [lookups.length]),
                  details: [for (final l in lookups) ...l.toolDetails],
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
              // 只发了附件、没写字的消息不画空气泡。
              if (m.fromUser && m.text.isEmpty)
                const SizedBox.shrink()
              else if (m.fromUser)
                PennaCard(
                  radius: 14,
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    contextMenuBuilder: pennaTextMenu,
                    m.text,
                    style: _bodyStyle,
                  ),
                )
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

/// 回复里另出的新成稿:分段列出,一键放到左侧等用户确认。
class _DraftCard extends StatefulWidget {
  const _DraftCard({
    required this.draft,
    required this.writing,
    required this.status,
    required this.onAdopt,
  });

  final AgentDraft draft;

  /// 还在生成:先不让放。
  final bool writing;
  final DraftStatus status;
  final VoidCallback onAdopt;

  @override
  State<_DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends State<_DraftCard> {
  /// 用户自己点过折叠或展开;没点过就按状态来。
  bool? _open;

  AgentDraft get draft => widget.draft;
  bool get writing => widget.writing;
  DraftStatus get status => widget.status;
  VoidCallback get onAdopt => widget.onAdopt;

  @override
  Widget build(BuildContext context) {
    // 已经送到左侧的收起来(内容在左边看),还没送的、正在写的摊开。
    final open = _open ?? (writing || status == DraftStatus.ready);
    final (label, icon) = switch (status) {
      _ when writing => (tr('正在写'), Icons.edit_outlined),
      // 被打断或出错的半截成稿不让放,免得把残缺的内容盖到成稿上。
      _ when !draft.complete => (tr('不完整'), Icons.error_outline),
      DraftStatus.ready => (tr('放到成稿'), Icons.keyboard_double_arrow_left),
      DraftStatus.pending => (tr('待确认'), Icons.hourglass_empty),
      DraftStatus.applied => (tr('已在成稿'), Icons.check),
    };
    final ready = !writing && draft.complete && status == DraftStatus.ready;
    return AnimatedContainer(
      duration: Motion.base,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PennaColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ready ? PennaColors.primaryBorder : PennaColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // 点标题这一截折叠或展开。
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _open = !open),
                    child: Row(
                      children: [
                        AnimatedRotation(
                          turns: open ? 0.25 : 0,
                          duration: Motion.base,
                          child: Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: PennaColors.primary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            [
                              switch (draft.page) {
                                null => tr('新成稿'),
                                final page when int.tryParse(page) != null =>
                                  tr('新成稿 · 第 {0} 页', [page]),
                                _ => tr('新成稿 · 新的一页'),
                              },
                              ?draft.name,
                            ].where((s) => s.isNotEmpty).join(' · '),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: PennaColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: Motion.base,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: PennaButton(
                  key: ValueKey(label),
                  label: label,
                  icon: icon,
                  background: PennaColors.primary,
                  foreground: Colors.white,
                  onPressed: ready ? onAdopt : null,
                ),
              ),
            ],
          ),
          // 一段一段长出来,卡片跟着平滑变高。
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.swift,
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!open) const SizedBox(width: double.infinity),
                // 收起时各段的标注竖着列一行一个,当摘要。
                if (!open)
                  for (final l in draft.sections.map((s) => s.label))
                    if (l.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 18, top: 4),
                        child: Text(
                          '·  $l',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: PennaColors.slate500,
                          ),
                        ),
                      ),
                for (final s
                    in open ? draft.sections : const <DraftSection>[]) ...[
                  const SizedBox(height: 8),
                  PennaCard(
                    color: PennaColors.slate50,
                    borderColor: PennaColors.slate100,
                    radius: 6,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (s.label.isNotEmpty) ...[
                          Text(
                            s.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: PennaColors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        SelectableText(
                          contextMenuBuilder: pennaTextMenu,
                          s.text,
                          style: monoStyle.copyWith(fontSize: 12),
                        ),
                        if (s.zh.isNotEmpty)
                          Text(
                            s.zh,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              color: PennaColors.slate400,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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

/// 工具调用记录:有细节时是折叠块(默认展开,可收起);只有一句话时就是一行,
/// 不给一个点开是空的箭头。
class _ToolBlock extends StatelessWidget {
  const _ToolBlock({required this.summary, required this.details});

  final String summary;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      Icons.check_circle_outline,
      size: 15,
      color: PennaColors.accent,
    );
    final title = Text(
      summary,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: PennaColors.slate700,
      ),
    );
    final shown = [
      for (final d in details)
        if (d.trim().isNotEmpty) d,
    ];
    if (shown.isEmpty) {
      return PennaCard(
        color: PennaColors.slate50,
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 10),
            Expanded(child: title),
          ],
        ),
      );
    }
    return PennaCard(
      color: PennaColors.slate50,
      radius: 12,
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        // ExpansionTile 的水波纹要画在 Material 上,外层的底色盒子会挡住它。
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            dense: true,
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            childrenPadding: const EdgeInsets.fromLTRB(34, 0, 10, 10),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            expandedAlignment: Alignment.centerLeft,
            leading: icon,
            title: title,
            children: [
              for (final d in shown)
                Text(
                  d,
                  style: monoStyle.copyWith(
                    fontSize: 11,
                    color: PennaColors.slate500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
