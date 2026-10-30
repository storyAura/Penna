import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

/// 横着的一排小按钮:最多露出前 [visible] 个那么宽,多出来的藏在后面,
/// 两头的箭头一次翻一截(鼠标滚轮也能滚),翻到头的那边箭头变灰。
/// 地方不够时照样缩窄、能翻。
class ScrollStrip extends StatefulWidget {
  const ScrollStrip({
    super.key,
    required this.children,
    required this.visible,
    this.gap = 6,
  });

  final List<Widget> children;
  final int visible;
  final double gap;

  @override
  State<ScrollStrip> createState() => _ScrollStripState();
}

class _ScrollStripState extends State<ScrollStrip> {
  final _scroll = ScrollController();

  /// 左边、右边还有没露出来的。
  bool _back = false;
  bool _forward = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_edges);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _edges() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final back = p.pixels > 0.5;
    final forward = p.pixels < p.maxScrollExtent - 0.5;
    if (back == _back && forward == _forward) return;
    setState(() {
      _back = back;
      _forward = forward;
    });
  }

  /// 往 [dir](-1 左、1 右)翻大半截,留一点上一截的边好接上。
  void _page(int dir) {
    final p = _scroll.position;
    final to = (p.pixels + dir * p.viewportDimension * 0.8).clamp(
      0.0,
      p.maxScrollExtent,
    );
    final d = Motion.of(context, Motion.base);
    d == Duration.zero
        ? _scroll.jumpTo(to)
        : _scroll.animateTo(to, duration: d, curve: Motion.swift);
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

  /// 鼠标滚轮本来是上下滚的,这里把它当成左右滚。
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    _scroll.jumpTo(
      (_scroll.offset + delta).clamp(0, _scroll.position.maxScrollExtent),
    );
  }

  Widget _arrow(IconData icon, bool on, int dir) => IconButton(
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 20),
    iconSize: 18,
    color: PennaColors.slate500,
    disabledColor: PennaColors.slate400.withValues(alpha: 0.4),
    onPressed: on ? () => _page(dir) : null,
    icon: Icon(icon),
  );

  @override
  Widget build(BuildContext context) {
    final strip = Stack(
      children: [
        // 看不见,只用来量出前 visible 个有多宽多高;整排就是这么大。
        ExcludeSemantics(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: _row(widget.children.take(widget.visible)),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Listener(
            onPointerSignal: _wheel,
            // 第一次排好、按钮增减、窗口变窄时都重新看两头还有没有。
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _edges();
                return false;
              },
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: _row(widget.children),
              ),
            ),
          ),
        ),
      ],
    );
    if (widget.children.length <= widget.visible) return strip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _arrow(Icons.chevron_left, _back, -1),
        Flexible(child: strip),
        _arrow(Icons.chevron_right, _forward, 1),
      ],
    );
  }
}
