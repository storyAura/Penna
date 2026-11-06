part of 'chat_message_view.dart';

// 消息里的小零件:用户消息的气泡和编辑框、翻回复、工具记录、没东西可显示时的那行。

/// 用户消息的气泡;点编辑按钮就地换成输入框,改好再发一次。
class _UserBubble extends StatefulWidget {
  const _UserBubble({
    required this.text,
    required this.isLast,
    required this.onEdit,
  });

  final String text;

  /// 后面还有没有对话:有的话发送后会被换掉,要说一声。
  final bool isLast;

  /// 发出去了返回真;发不了返回假,输入框留着。正在生成时是 null,不能改。
  final bool Function(String text)? onEdit;

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  TextEditingController? _draft;

  void _open() => setState(() {
    _draft = TextEditingController(text: widget.text);
  });

  void _close() {
    _draft?.dispose();
    setState(() => _draft = null);
  }

  void _send() {
    if (widget.onEdit?.call(_draft?.text ?? '') ?? false) _close();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || _draft!.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    final enter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (!enter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _draft?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft != null && widget.onEdit != null) return _editor(draft);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 只发了附件、没写字的消息不画空气泡。
        if (widget.text.isNotEmpty)
          PennaCard(
            radius: 14,
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              contextMenuBuilder: pennaTextMenu,
              widget.text,
              style: _bodyStyle,
            ),
          ),
        if (widget.onEdit != null)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: _open,
              tooltip: tr('编辑并重新发送'),
              icon: const Icon(Icons.edit_outlined, size: 14),
              color: PennaColors.slate400,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(24),
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
      ],
    );
  }

  Widget _editor(TextEditingController draft) {
    return PennaCard(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            onKeyEvent: _onKey,
            child: TextField(
              contextMenuBuilder: pennaTextMenu,
              controller: draft,
              autofocus: true,
              minLines: 1,
              maxLines: 10,
              style: _bodyStyle,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (!widget.isLast)
                Expanded(
                  child: Text(
                    tr('发送后,后面的对话会被替换'),
                    style: TextStyle(fontSize: 11, color: PennaColors.slate400),
                  ),
                )
              else
                const Spacer(),
              PennaButton(
                label: tr('取消'),
                background: Colors.transparent,
                foreground: PennaColors.slate500,
                onPressed: _close,
              ),
              const SizedBox(width: 4),
              PennaButton(
                label: tr('发送'),
                icon: Icons.arrow_upward,
                background: PennaColors.primaryBg,
                foreground: PennaColors.primary,
                onPressed: _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 回复没写完:说明原因。里面的成稿要是也没写完,不会送到成稿区。
class _CutNote extends StatelessWidget {
  const _CutNote(this.cut);

  final LlmCut cut;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 11, color: PennaColors.amber);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.content_cut, size: 13, color: PennaColors.amber),
          const SizedBox(width: 4),
          Flexible(
            child: Text(switch (cut) {
              LlmCut.length => tr('没写完:到了输出上限'),
              LlmCut.blocked => tr('没写完:被接口拦下了'),
              LlmCut.broken => tr('没写完:连接提前结束了'),
            }, style: style),
          ),
        ],
      ),
    );
  }
}

/// 翻看重新回复留下的几份:‹ 2/3 ›。翻到最后一份再往后就是再写一份,和酒馆一样。
class _ReplyPager extends StatelessWidget {
  const _ReplyPager({
    required this.at,
    required this.total,
    required this.onShow,
    required this.onRetry,
  });

  final int at;
  final int total;
  final ValueChanged<int> onShow;
  final VoidCallback? onRetry;

  Widget _arrow(IconData icon, String tooltip, VoidCallback? onPressed) =>
      IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 16),
        color: PennaColors.slate500,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(24),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final atEnd = at == total - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _arrow(
          Icons.chevron_left,
          tr('上一份回复'),
          at == 0 ? null : () => onShow(at - 1),
        ),
        Text(
          '${at + 1}/$total',
          style: TextStyle(fontSize: 11, color: PennaColors.slate500),
        ),
        _arrow(
          Icons.chevron_right,
          atEnd ? tr('重新回复') : tr('下一份回复'),
          atEnd ? onRetry : () => onShow(at + 1),
        ),
      ],
    );
  }
}

/// 工具调用记录:有细节时是折叠块(默认展开,可收起);只有一句话时就是一行,
/// 不给一个点开是空的箭头。
class _ToolBlock extends StatelessWidget {
  const _ToolBlock({
    required this.summary,
    required this.details,
    this.icon = Icons.check_circle_outline,
    this.iconColor,
  });

  final String summary;
  final List<String> details;
  final IconData icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      this.icon,
      size: 15,
      color: iconColor ?? PennaColors.accent,
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

/// 回复里没有能显示的东西:模型什么都没回,或者只写了程序没接住的标签。
/// 后一种收成一行灰字,点开看原文,用户至少看得出模型写了什么。
class _RawReply extends StatefulWidget {
  const _RawReply(this.text);

  final String text;

  @override
  State<_RawReply> createState() => _RawReplyState();
}

class _RawReplyState extends State<_RawReply> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final grey = _bodyStyle.copyWith(
      fontSize: 12.5,
      color: PennaColors.slate500,
    );
    if (widget.text.trim().isEmpty) return Text(tr('模型没有返回内容'), style: grey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('没有可显示的话 · 查看原文'), style: grey),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: PennaColors.slate500,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.expand,
          alignment: Alignment.topLeft,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SelectableText(
                    widget.text.trim(),
                    contextMenuBuilder: pennaTextMenu,
                    style: monoStyle.copyWith(
                      fontSize: 11.5,
                      color: PennaColors.slate700,
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
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
    this.onGenerate,
  });

  final AgentDraft draft;

  /// 用这份成稿出图;为 null 时没有这个按钮。
  // ponytail: 只改了几段的成稿,出图用的也只是这几段;整页的在「最终提示词」上出。
  final VoidCallback? onGenerate;

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
              if (widget.onGenerate != null && !writing && draft.complete) ...[
                const SizedBox(width: 8),
                PennaButton(
                  label: tr('出图'),
                  icon: Icons.brush_outlined,
                  foreground: PennaColors.primary,
                  borderColor: PennaColors.primaryBorder,
                  onPressed: widget.onGenerate,
                ),
              ],
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
