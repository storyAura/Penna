part of 'body_card.dart';

// 成稿里的一段:彩色框、标注、右上角的操作、中文对照。

/// 成稿里的一段:彩色框,左上角是标注,右上角可以拿去讨论或删掉。
/// 有中文对照时点标注那一行展开,默认收着。
class _SectionCard extends StatefulWidget {
  const _SectionCard({
    required this.label,
    required this.tint,
    required this.zh,
    required this.quoted,
    this.onDiscuss,
    this.onPin,
    this.onPolish,
    this.onTranslate,
    this.showTranslate = true,
    this.onRemove,
    this.actions = const [],
    this.openAll = false,
    this.copyText,
    this.onCopied,
    this.onUnpin,
    this.locked = false,
    this.leading,
    this.onDetach,
    this.onRename,
    required this.child,
  });

  /// 右键标注那一行时的「改名」;为 null 时右键没有菜单。
  final VoidCallback? onRename;

  /// 让这一段脱离分段,变成普通文字;为 null 时那个按钮是灰的。
  final VoidCallback? onDetach;

  /// 标注前面的小东西;普通的段用它放拖动的把手。
  final Widget? leading;

  /// 顶栏的「展开」开着;它一变,这段的中文对照跟着展开或收起。
  final bool openAll;

  /// 非空时右上角有「复制这段」,复制的就是它(只有提示词)。
  final String? copyText;
  final VoidCallback? onCopied;

  /// 这段被固定了:罩一层琥珀色,左上角是拖动的把手。
  final bool locked;

  /// 非空时右上角是「取消固定」。
  final VoidCallback? onUnpin;

  final String label;
  final _Tint tint;

  /// 这段的中文对照;没有就是空串。
  final String zh;

  /// 这段正被选来和 Agent 讨论:描边加深。
  final bool quoted;
  final VoidCallback? onDiscuss;

  /// 只对这一段做的固定、润色、翻译;为 null 时那个按钮是灰的。
  final VoidCallback? onPin;
  final VoidCallback? onPolish;
  final VoidCallback? onTranslate;

  /// 英文界面不要对照译文,「翻译这段」整个藏起来。
  final bool showTranslate;

  /// 放在右上角的按钮;待确认的段用它放「采纳」「驳回」。
  final List<Widget> actions;

  /// 为 null 表示这段现在是只读的,不显示右上角的操作。
  final VoidCallback? onRemove;
  final Widget child;

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  late bool _open = widget.openAll;

  @override
  void didUpdateWidget(_SectionCard old) {
    super.didUpdateWidget(old);
    if (old.openAll != widget.openAll) _open = widget.openAll;
  }

  Widget _action(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          icon,
          size: 14,
          color: onTap == null ? widget.tint.border : widget.tint.text,
        ),
      ),
    ),
  );

  /// 标注那一行:能改名时右键弹出「改名」。
  Widget _renamable(Widget header) {
    final rename = widget.onRename;
    if (rename == null) return header;
    return Tooltip(
      message: tr('右键改名'),
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (d) async {
          final picked = await popMenu(context, d.globalPosition, [tr('改名')]);
          if (picked == tr('改名')) rename();
        },
        child: header,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint;
    final hasZh = widget.zh.isNotEmpty;
    final title = Row(
      children: [
        if (widget.locked) ...[
          Icon(
            widget.onUnpin == null ? Icons.push_pin : Icons.drag_indicator,
            size: 13,
            color: tint.text,
          ),
          const SizedBox(width: 2),
        ],
        Flexible(
          child: Text(
            widget.label.isEmpty ? tr('未标注') : widget.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tint.text,
            ),
          ),
        ),
        if (hasZh) ...[
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: _open ? 0.25 : 0,
            duration: Motion.of(context, Motion.base),
            child: Icon(Icons.chevron_right, size: 14, color: tint.text),
          ),
          Text(tr('中文'), style: TextStyle(fontSize: 10.5, color: tint.text)),
        ],
      ],
    );
    return AnimatedContainer(
      duration: Motion.of(context, Motion.base),
      padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
      decoration: BoxDecoration(
        color: tint.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: widget.quoted ? tint.text : tint.border),
      ),
      // 固定的段:原样留着,只在上面罩一层琥珀色。
      foregroundDecoration: BoxDecoration(
        color: widget.locked
            ? PennaColors.amber.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: widget.locked ? PennaColors.lockBorder : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _renamable(
            Row(
              children: [
                ?widget.leading,
                Expanded(
                  child: hasZh
                      ? MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _open = !_open),
                            child: title,
                          ),
                        )
                      : title,
                ),
                ...widget.actions,
                if (widget.copyText case final text?) ...[
                  _action(Icons.content_copy, tr('复制这段'), () {
                    copyWithToast(context, text, tr('已复制'));
                    widget.onCopied?.call();
                  }),
                  const SizedBox(width: 2),
                ],
                if (widget.onUnpin != null)
                  _action(Icons.push_pin, tr('取消固定'), widget.onUnpin),
                if (widget.onRemove != null) ...[
                  _action(Icons.call_split, tr('脱离分段'), widget.onDetach),
                  const SizedBox(width: 2),
                  _action(Icons.push_pin_outlined, tr('固定这段'), widget.onPin),
                  const SizedBox(width: 2),
                  _action(Icons.auto_fix_high, tr('润色这段'), widget.onPolish),
                  const SizedBox(width: 2),
                  if (widget.showTranslate) ...[
                    _action(Icons.translate, tr('翻译这段'), widget.onTranslate),
                    const SizedBox(width: 2),
                  ],
                  _action(
                    Icons.forum_outlined,
                    tr('和 Agent 讨论这段'),
                    widget.onDiscuss,
                  ),
                  const SizedBox(width: 2),
                  _action(Icons.close, tr('删除这段'), widget.onRemove),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),
          widget.child,
          AnimatedSize(
            duration: Motion.of(context, Motion.base),
            curve: Motion.swift,
            alignment: Alignment.topLeft,
            child: hasZh && _open
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SelectableText(
                      contextMenuBuilder: pennaTextMenu,
                      widget.zh,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: PennaColors.slate500,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
