import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 把纵向滚轮用于横向列表,并与列表和外层滚动区域共同选出唯一处理者。
void scrollHorizontally(PointerSignalEvent event, ScrollController controller) {
  if (event is! PointerScrollEvent || !controller.hasClients) return;
  final delta = event.scrollDelta.dy != 0
      ? event.scrollDelta.dy
      : event.scrollDelta.dx;
  final target = (controller.offset + delta).clamp(
    controller.position.minScrollExtent,
    controller.position.maxScrollExtent,
  );
  if (target == controller.offset) return;
  GestureBinding.instance.pointerSignalResolver.register(event, (_) {
    controller.jumpTo(target);
    event.respond(allowPlatformDefault: false);
  });
}

/// 横着的一排小按钮:最多露出前 [visible] 个那么宽,多出来的横着滚
/// (底下有滚动条,鼠标滚轮也能滚;[bar] 为假时不画滚动条,只能用滚轮)。
/// 地方不够时照样缩窄、能滚。
class ScrollStrip extends StatefulWidget {
  const ScrollStrip({
    super.key,
    required this.children,
    required this.visible,
    this.gap = 6,
    this.bar = true,
  });

  final List<Widget> children;
  final int visible;
  final double gap;
  final bool bar;

  @override
  State<ScrollStrip> createState() => _ScrollStripState();
}

class _ScrollStripState extends State<ScrollStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Widget _row(Iterable<Widget> items) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, w) in items.indexed) ...[
        if (i > 0) SizedBox(width: widget.gap),
        w,
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final scrolls = widget.bar && widget.children.length > widget.visible;
    // 底下留给滚动条,免得压在按钮上。
    final pad = EdgeInsets.only(bottom: scrolls ? 8 : 0);
    return Stack(
      children: [
        // 看不见,只用来量出前 visible 个有多宽多高;整排就是这么大。
        ExcludeSemantics(
          child: ExcludeFocus(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: pad,
                  child: _row(widget.children.take(widget.visible)),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Listener(
            onPointerSignal: (event) => scrollHorizontally(event, _scroll),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: scrolls,
              thickness: 4,
              radius: const Radius.circular(2),
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: pad,
                child: _row(widget.children),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
