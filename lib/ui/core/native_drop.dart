import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

/// 原生拖放按真实窗口坐标命中,只交给当前页和最上面的路由。
class PennaDropTarget extends StatelessWidget {
  const PennaDropTarget({
    super.key,
    required this.child,
    this.enabled = true,
    this.onDragEntered,
    this.onDragExited,
    this.onDragDone,
  });

  final Widget child;
  final bool enabled;
  final ValueChanged<DropEventDetails>? onDragEntered, onDragExited;
  final ValueChanged<DropDoneDetails>? onDragDone;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      // desktop_drop 先将物理坐标除以 DPR,随后 globalToLocal 才处理界面缩放。
      // 应用放大后的 DPR 仅给内容使用,否则拖放坐标会被缩放两次。
      data: media.copyWith(devicePixelRatio: View.of(context).devicePixelRatio),
      child: DropTarget(
        enable:
            enabled &&
            TickerMode.valuesOf(context).enabled &&
            (ModalRoute.isCurrentOf(context) ?? true),
        onDragEntered: onDragEntered,
        onDragExited: onDragExited,
        onDragDone: onDragDone,
        child: MediaQuery(data: media, child: child),
      ),
    );
  }
}
