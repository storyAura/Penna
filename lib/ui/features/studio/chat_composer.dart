part of 'chat_pane.dart';

// 对话底部:快捷操作、输入框、附件、发送和停止。

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.inputFocus,
    required this.quickActions,
    required this.onQuickAction,
    required this.onKey,
    required this.onSend,
    required this.onStop,
    required this.picker,
    required this.chips,
    required this.onAttach,
    required this.autoApprove,
    required this.onAutoApprove,
    required this.dragging,
    this.queued = const [],
    this.trailing,
  });

  /// 快捷操作那一排最右边的按钮(副聊天的开关)。
  final Widget? trailing;

  /// 成稿的改动是自动采纳还是等用户点。
  final bool autoApprove;
  final ValueChanged<bool> onAutoApprove;

  /// 排着队等发的那几条,显示在最上面。
  final List<Widget> queued;

  /// 打 @ 时显示在输入框上方的 Skill 列表;不在打 @ 时为 null。
  final Widget? picker;

  /// 附件和已引用的 Skill 的标签,显示在输入框里文字的上方。
  final List<Widget> chips;

  final VoidCallback onAttach;

  /// 有文件正拖在上方:输入框描边变色,提示可以松手。
  final bool dragging;

  final TextEditingController input;
  final FocusNode inputFocus;
  final List<QuickAction> quickActions;
  final ValueChanged<String> onQuickAction;
  final FocusOnKeyEventCallback onKey;
  final VoidCallback onSend;

  /// 非空表示正在生成,发送键变成停止键。
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PennaColors.card,
        border: Border(top: BorderSide(color: PennaColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 排队的条目增减时,高度顺着伸缩。
          AnimatedSize(
            duration: Motion.base,
            curve: Motion.swift,
            alignment: Alignment.bottomCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in queued) ...[row, const SizedBox(height: 6)],
              ],
            ),
          ),
          if (quickActions.isNotEmpty || trailing != null) ...[
            Row(
              children: [
                Expanded(
                  child: _QuickActions(
                    actions: quickActions,
                    visible: _maxQuickActions,
                    onTap: onQuickAction,
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (picker != null) ...[
            PopIn(child: picker!),
            const SizedBox(height: 6),
          ],
          _ComposerFrame(
            focus: inputFocus,
            dragging: dragging,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chips.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Wrap(spacing: 6, runSpacing: 6, children: chips),
                  ),
                Focus(
                  onKeyEvent: onKey,
                  child: TextField(
                    contextMenuBuilder: pennaTextMenu,
                    controller: input,
                    focusNode: inputFocus,
                    // 跟着内容长高,最多十行,再多就在框里滚。
                    minLines: 3,
                    maxLines: 10,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                    decoration: InputDecoration(
                      hintText: tr('Enter 发送 · Shift+Enter 换行 · @ 引用 Skill'),
                      hintStyle: TextStyle(color: PennaColors.slate400),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                Row(
                  children: [
                    // 输入框左边有 16 的留白,往回收一点让图标和文字左缘对齐。
                    Transform.translate(
                      offset: const Offset(-6, 0),
                      child: IconButton(
                        onPressed: onAttach,
                        tooltip: tr('添加图片或文本文件'),
                        icon: const Icon(Icons.attach_file, size: 17),
                        color: PennaColors.slate500,
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(28),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    PennaButton(
                      label: autoApprove ? tr('自动审批') : tr('手动审批'),
                      icon: autoApprove
                          ? Icons.done_all
                          : Icons.front_hand_outlined,
                      tooltip: tr('成稿的改动:自动采纳 / 手动确认'),
                      background: autoApprove ? PennaColors.primaryBg : null,
                      foreground: autoApprove
                          ? PennaColors.primary
                          : PennaColors.slate500,
                      onPressed: () => onAutoApprove(!autoApprove),
                    ),
                    const Spacer(),
                    Bouncy(
                      child: IconButton.filled(
                        onPressed: onStop ?? onSend,
                        tooltip: onStop == null ? tr('发送') : tr('停止生成(Esc)'),
                        icon: AnimatedSwitcher(
                          duration: Motion.base,
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: Icon(
                            onStop == null ? Icons.arrow_upward : Icons.stop,
                            key: ValueKey(onStop == null),
                            size: 16,
                          ),
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: PennaColors.text,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.square(28),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 排着队的一条消息:等正在生成的回复说完自动发,也可以立刻发或撤掉。
class _QueuedRow extends StatelessWidget {
  const _QueuedRow({
    required this.text,
    required this.onSendNow,
    required this.onRemove,
  });

  final String text;
  final VoidCallback onSendNow;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PopIn(
      child: PennaCard(
        color: PennaColors.slate50,
        radius: 10,
        padding: const EdgeInsets.fromLTRB(10, 3, 2, 3),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 14, color: PennaColors.slate400),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: PennaColors.slate700),
              ),
            ),
            PennaButton(
              label: tr('立刻发送'),
              icon: Icons.bolt,
              tooltip: tr('打断正在生成的回复,马上发这条'),
              onPressed: onSendNow,
            ),
            IconButton(
              tooltip: tr('撤掉'),
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              color: PennaColors.slate400,
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入框的外框:平时一层很淡的投影,鼠标移上来、打字时投影和边框各加深一档;
/// 拖文件进来时整个换成主色。
class _ComposerFrame extends StatefulWidget {
  const _ComposerFrame({
    required this.focus,
    required this.dragging,
    required this.child,
  });

  final FocusNode focus;
  final bool dragging;
  final Widget child;

  @override
  State<_ComposerFrame> createState() => _ComposerFrameState();
}

class _ComposerFrameState extends State<_ComposerFrame> {
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_changed);
  }

  @override
  void dispose() {
    widget.focus.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focused = widget.focus.hasFocus;
    final shadow = Colors.black.withValues(
      alpha: focused
          ? 0.08
          : _hover
          ? 0.06
          : 0.035,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.base),
        curve: Motion.swift,
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
        decoration: BoxDecoration(
          color: widget.dragging ? PennaColors.primaryBg : PennaColors.slate50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.dragging
                ? PennaColors.primary
                : focused
                ? PennaColors.primary.withValues(alpha: 0.45)
                : _hover
                ? PennaColors.slate400.withValues(alpha: 0.6)
                : PennaColors.border,
          ),
          boxShadow: [
            BoxShadow(
              color: shadow,
              blurRadius: focused ? 24 : 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

/// 快捷操作那一排,主聊天和副聊天浮窗共用:点了把话接在输入框末尾;
/// 最多露出 [visible] 个,放不下时两头出箭头翻。
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.actions,
    required this.visible,
    required this.onTap,
  });

  final List<QuickAction> actions;
  final int visible;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Text(
          tr('快捷操作:'),
          style: TextStyle(fontSize: 11, color: PennaColors.slate400),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ScrollStrip(
              visible: visible,
              children: [
                for (final action in actions)
                  PennaButton(
                    // 默认的两个按界面语言翻译,自己加的原样。
                    label: tr(action.label),
                    background: PennaColors.slate100,
                    onPressed: () => onTap(tr(action.prompt)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
