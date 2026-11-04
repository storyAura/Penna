import 'package:flutter/material.dart';

import 'motion.dart';

const _wheelDuration = Duration(milliseconds: 240);

/// 鼠标滚轮滚动时平滑滑过去,而不是一格一格地跳。
class SmoothScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SmoothPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    debugLabel: debugLabel,
  );
}

class _SmoothPosition extends ScrollPositionWithSingleContext {
  _SmoothPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.initialPixels,
    super.keepScrollOffset,
    super.debugLabel,
  });

  /// 滚轮动画还没走完时要去的位置;连续滚动在它的基础上累加,手感才跟手。
  double? _target;

  @override
  void pointerScroll(double delta) {
    // 还没排过版时没有可滚范围,交给默认处理。
    if (delta == 0 || !hasContentDimensions) return super.pointerScroll(delta);
    if (MediaQuery.maybeDisableAnimationsOf(context.storageContext) ?? false) {
      _target = null;
      return super.pointerScroll(delta);
    }
    final to = ((_target ?? pixels) + delta).clamp(
      minScrollExtent,
      maxScrollExtent,
    );
    if (to == pixels) return;
    _target = to;
    animateTo(to, duration: _wheelDuration, curve: Motion.swift).whenComplete(
      () {
        if (_target == to) _target = null;
      },
    );
  }
}

/// 给一个可滚动区域配上 [SmoothScrollController],并负责销毁它。
class SmoothScroller extends StatefulWidget {
  const SmoothScroller({super.key, required this.builder});

  final Widget Function(ScrollController controller) builder;

  @override
  State<SmoothScroller> createState() => _SmoothScrollerState();
}

class _SmoothScrollerState extends State<SmoothScroller> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}
