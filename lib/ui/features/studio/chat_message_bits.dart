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
