import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/tour_spot.dart';
import '../../core/widgets.dart';
import 'pixel_mascot.dart';
import 'tour_steps.dart';

/// 新手教程:盖住整个窗口,把这一步讲的那块挖出来高亮,旁边是吉祥物和说明。
/// ← → 翻页,Esc 跳过;底下的东西点不到。
class TourOverlay extends StatefulWidget {
  const TourOverlay({super.key, required this.onPage, required this.onClose});

  /// 这一步要先切到哪一页(`navPages` 的 id 或 'settings')。
  final ValueChanged<String> onPage;

  /// 跳过或走完。
  final VoidCallback onClose;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay>
    with SingleTickerProviderStateMixin {
  var _steps = tourSteps;
  int _at = 0;
  Rect? _hole;

  // 每帧量一次要高亮的那块:切页时它跟着动画滑进来,窗口大小也会变。
  late final Ticker _ticker = createTicker((_) => _measure());

  @override
  void initState() {
    super.initState();
    _ticker.start();
    // 不管焦点在哪(比如对话输入框),教程开着时方向键都归它。
    HardwareKeyboard.instance.addHandler(_onKey);
    // 切页会让外壳 setState,不能在它 build 的时候做。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _go(0);
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    _steps = tourSteps; // 换了界面语言
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _ticker.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0) return;
    if (i >= _steps.length) return widget.onClose();
    setState(() => _at = i);
    if (_steps[i].page case final page?) widget.onPage(page);
  }

  void _measure() {
    final id = _steps[_at].spot;
    final me = context.findRenderObject();
    final box = id == null ? null : tourKey(id).currentContext;
    final target = box?.findRenderObject();
    Rect? rect;
    if (me is RenderBox &&
        me.hasSize &&
        target is RenderBox &&
        target.attached &&
        target.hasSize) {
      rect = MatrixUtils.transformRect(
        target.getTransformTo(me),
        Offset.zero & target.size,
      ).intersect(Offset.zero & me.size);
      if (rect.width <= 0 || rect.height <= 0) rect = null;
    }
    if (rect != _hole) setState(() => _hole = rect);
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.enter) {
      _go(_at + 1);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _go(_at - 1);
    } else if (k == LogicalKeyboardKey.escape) {
      widget.onClose();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_at];
    return GestureDetector(
      // 吃掉底下的点击、滚轮和悬停。
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          // 没有要高亮的就缩成正中的一个点,卡片放正中。
          final hole =
              _hole?.inflate(6) ??
              Rect.fromCenter(
                center: size.center(Offset.zero),
                width: 0,
                height: 0,
              );
          return TweenAnimationBuilder<Rect?>(
            tween: RectTween(end: hole),
            duration: Motion.of(context, Motion.sheet),
            curve: Motion.expand,
            child: _Card(
              step: step,
              at: _at,
              total: _steps.length,
              onBack: _at == 0 ? null : () => _go(_at - 1),
              onNext: () => _go(_at + 1),
              onSkip: widget.onClose,
            ),
            builder: (context, r, card) => Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _Dim(
                      hole: r!,
                      shade: const Color(0x99000000),
                      ring: PennaColors.primary,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomSingleChildLayout(
                    delegate: _Place(r),
                    child: card,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 一层半透明的黑,中间挖掉 [hole],沿洞口描一圈主题色的光。
class _Dim extends CustomPainter {
  _Dim({required this.hole, required this.shade, required this.ring});

  final Rect hole;
  final Color shade, ring;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(hole, const Radius.circular(10));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(r),
      Paint()..color = shade,
    );
    if (hole.width < 2) return;
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = ring.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
  }

  @override
  bool shouldRepaint(_Dim old) =>
      old.hole != hole || old.shade != shade || old.ring != ring;
}

/// 卡片摆在洞口旁边:先试右、左,再试下、上;都放不下就盖在洞口里靠下。
class _Place extends SingleChildLayoutDelegate {
  _Place(this.hole);

  final Rect hole;
  static const _gap = 16.0, _margin = 16.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints.loose(
        Size(
          math.min(520, c.maxWidth - 2 * _margin),
          c.maxHeight - 2 * _margin,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size card) {
    final h = hole;
    double x(double v) =>
        v.clamp(_margin, math.max(_margin, size.width - card.width - _margin));
    double y(double v) => v.clamp(
      _margin,
      math.max(_margin, size.height - card.height - _margin),
    );
    final midX = x(h.center.dx - card.width / 2);
    final midY = y(h.center.dy - card.height / 2);
    final room = (
      w: card.width + _gap + _margin,
      h: card.height + _gap + _margin,
    );
    if (h.width < 2) return Offset(midX, midY);
    if (size.width - h.right >= room.w) return Offset(h.right + _gap, midY);
    if (h.left >= room.w) return Offset(h.left - _gap - card.width, midY);
    if (size.height - h.bottom >= room.h) return Offset(midX, h.bottom + _gap);
    if (h.top >= room.h) return Offset(midX, h.top - _gap - card.height);
    return Offset(midX, y(h.bottom - _gap - card.height));
  }

  @override
  bool shouldRelayout(_Place old) => old.hole != hole;
}

/// 吉祥物从说明框左下探出来。
class _Card extends StatelessWidget {
  const _Card({
    required this.step,
    required this.at,
    required this.total,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final TourStep step;
  final int at, total;
  final VoidCallback? onBack;
  final VoidCallback onNext, onSkip;

  @override
  Widget build(BuildContext context) {
    final last = at == total - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        PixelMascot(look: step.face, height: 200, bob: true),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            decoration: BoxDecoration(
              color: PennaColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PennaColors.primaryBorder),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSize(
                  duration: Motion.of(context, Motion.base),
                  curve: Motion.expand,
                  alignment: Alignment.topLeft,
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.base),
                    switchInCurve: Motion.enter,
                    switchOutCurve: Motion.leave,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topLeft,
                      children: [...previous, ?current],
                    ),
                    child: Column(
                      key: ValueKey(at),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: PennaColors.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          step.body,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.6,
                            color: PennaColors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: PennaColors.slate500,
                      ),
                      child: Text(
                        tr('跳过'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${at + 1} / $total',
                      style: TextStyle(
                        fontSize: 11,
                        color: PennaColors.slate400,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: tr('上一步'),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 2),
                    Bouncy(
                      child: FilledButton(
                        onPressed: onNext,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: PennaColors.primary,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              last ? tr('完成') : tr('下一步'),
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (!last) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward, size: 15),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
