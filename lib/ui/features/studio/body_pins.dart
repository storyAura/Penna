part of 'body_card.dart';

// 固定区、拖动的把手和落点。

/// 一个固定区。给了 [onUnpin] 才能拖动和取消固定。
class _PinCard extends StatelessWidget {
  const _PinCard({
    required this.text,
    required this.index,
    this.onUnpin,
    this.onDropPin,
    this.section,
  });

  /// 固定的是一整段时,用这个分段框代替琥珀色的固定条。
  final Widget? section;

  final String text;

  /// 这块在 blocks 里的下标,拖动时带着它。
  final int index;
  final VoidCallback? onUnpin;

  /// 别的固定区被拖到这块上:插到它前面。
  final ValueChanged<int>? onDropPin;

  Widget _card({required bool handle}) {
    final style = monoStyle.copyWith(
      color: PennaColors.lockText,
      fontWeight: FontWeight.w500,
    );
    return PennaCard(
      color: PennaColors.lock,
      borderColor: PennaColors.lockBorder,
      radius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        children: [
          Icon(
            handle ? Icons.drag_indicator : Icons.push_pin,
            size: 14,
            color: PennaColors.lockText,
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: style)),
          if (onUnpin != null)
            Tooltip(
              message: tr('取消固定'),
              child: InkWell(
                onTap: onUnpin,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.push_pin,
                    size: 14,
                    color: PennaColors.lockText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (onUnpin == null) return section ?? _card(handle: false);
    final card = section ?? _card(handle: true);
    return _DropSlot(
      self: index,
      onDrop: (from) => onDropPin?.call(from),
      child: Draggable<int>(
        data: index,
        // 让落点跟着鼠标尖走,而不是跟着拖影的左上角。
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          elevation: 6,
          borderRadius: BorderRadius.circular(6),
          child: PennaCard(
            color: PennaColors.lock,
            borderColor: PennaColors.lockBorder,
            radius: 6,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle.copyWith(color: PennaColors.lockText),
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: card),
        child: MouseRegion(cursor: SystemMouseCursors.grab, child: card),
      ),
    );
  }
}

/// 普通的段左上角的把手:抓着它把这段拖到同一栏的另一段上,调先后。
/// 只有把手能拖,段里的文字照常可以选、可以改。
class _SectionHandle extends StatelessWidget {
  const _SectionHandle({
    required this.drag,
    required this.label,
    required this.tint,
  });

  final _SectionDrag drag;
  final String label;
  final _Tint tint;

  @override
  Widget build(BuildContext context) {
    return Draggable<Object>(
      data: drag,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(6),
        child: PennaCard(
          color: tint.bg,
          borderColor: tint.text,
          radius: 6,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tint.text,
            ),
          ),
        ),
      ),
      child: Tooltip(
        message: tr('拖动调整先后'),
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(Icons.drag_indicator, size: 13, color: tint.text),
          ),
        ),
      ),
    );
  }
}

/// 固定区能落下的一个位置:拖着固定区经过时,这里的内容往下让出一格,松手就插到它前面。
class _DropSlot extends StatelessWidget {
  const _DropSlot({
    required this.onDrop,
    required this.child,
    this.self,
    this.section,
    this.onDropSection,
  });

  /// 参数是被拖过来的那块在 blocks 里的下标。
  final ValueChanged<int> onDrop;
  final Widget child;

  /// 这个位置是哪一栏的第几段;给了它,同一栏里别的段也能拖到这里。
  final _SectionDrag? section;

  /// 参数是被拖过来的那一段在它那栏里排第几。
  final ValueChanged<int>? onDropSection;

  /// 这个位置自己就是第几块固定区;拖到自己身上不算。
  final int? self;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) => switch (d.data) {
        final int from => from != self,
        final _SectionDrag from =>
          section != null &&
              from.part == section!.part &&
              from.span != section!.span,
        _ => false,
      },
      onAcceptWithDetails: (d) => switch (d.data) {
        final int from => onDrop(from),
        final _SectionDrag from => onDropSection?.call(from.span),
        _ => null,
      },
      builder: (context, incoming, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: Motion.of(context, Motion.base),
            curve: Motion.swift,
            alignment: Alignment.topCenter,
            child: incoming.isEmpty
                ? const SizedBox(width: double.infinity)
                : Container(
                    height: 30,
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: PennaColors.lock,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: PennaColors.lockBorder),
                    ),
                  ),
          ),
          child,
        ],
      ),
    );
  }
}
