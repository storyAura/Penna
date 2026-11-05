import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/models/app_config.dart';
import '../../data/services/config_service.dart';
import '../../l10n/l10n.dart';
import 'theme.dart';
import 'motion.dart';

/// 按设置换配色和界面语言(启动时在 runApp 之前调一次)。
void applyLook(AppConfig cfg, {DateTime? now}) {
  PennaColors.useDark(_wantsDark(cfg, now ?? DateTime.now()));
  useLanguage(cfg.language);
}

bool _wantsDark(AppConfig cfg, DateTime now) => cfg.darkAt(
  systemDark:
      WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark,
  now: now,
);

/// 深浅色切换动画从哪里扩散开:点开关时记下它的位置,没有就从窗口中间。
Offset? lookRevealOrigin;

/// 盯着设置里的深色模式和语言、系统的深浅色、时钟:变了就换上,并让整棵树重建一遍。
/// 换深浅色时先拍下旧画面盖在上面,再从 [lookRevealOrigin] 起一圈圈露出新画面。
class LookSwitcher extends StatefulWidget {
  const LookSwitcher({
    super.key,
    required this.config,
    required this.child,
    this.now = DateTime.now,
  });

  final ConfigService config;
  final Widget child;

  /// 现在几点;测试里换掉。
  final DateTime Function() now;

  @override
  State<LookSwitcher> createState() => _LookSwitcherState();
}

class _LookSwitcherState extends State<LookSwitcher>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _shot = GlobalKey();

  late final Timer _clock;
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  /// 换配色前的画面;动画放完就扔掉。
  ui.Image? _old;
  Offset? _origin;

  @override
  void initState() {
    super.initState();
    widget.config.addListener(_refresh);
    WidgetsBinding.instance.addObserver(this);
    // ponytail: 每 20 秒看一次钟,到点最多晚 20 秒;比算好下一个时间点再定时简单,
    // 电脑睡醒、改系统时间也不用另外管。
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void didChangePlatformBrightness() => _refresh();

  @override
  void dispose() {
    widget.config.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    _clock.cancel();
    _reveal.dispose();
    _old?.dispose();
    super.dispose();
  }

  void _refresh() {
    final cfg = widget.config.config;
    final now = widget.now();
    final dark = _wantsDark(cfg, now) != PennaColors.isDark;
    // 点了模式但深浅色没变:记下的位置作废,不然下次到点从那里扩散。
    if (!dark) lookRevealOrigin = null;
    if (!dark && cfg.language == currentLanguage) return;
    if (dark) _snapshot();
    applyLook(cfg, now: now);
    // 界面里到处是取值时才读的颜色和译文,const 的部件也要重建,
    // 所以走「整棵树重来一遍」(热重载用的那条路,正式版里同样可用)。
    WidgetsBinding.instance.reassembleApplication();
  }

  /// 拍下现在的画面盖住窗口,然后开始扩散动画。
  void _snapshot() {
    final boundary =
        _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null || !boundary.hasSize) return;
    final ui.Image image;
    try {
      image = boundary.toImageSync(
        // 用 MediaQuery 的:「界面大小」放大时它跟着乘上倍数,截图才不糊。
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    } on Object {
      return; // 拍不下来就不放动画,直接换。
    }
    _old?.dispose();
    setState(() {
      _old = image;
      // 记下的是窗口坐标,换成这块画面自己的(「界面大小」放大过时两者不同)。
      _origin = switch (lookRevealOrigin) {
        final o? => boundary.globalToLocal(o),
        null => null,
      };
    });
    lookRevealOrigin = null;
    _reveal.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _old?.dispose();
        _old = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(key: _shot, child: widget.child),
        if (old != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RevealPainter(
                  image: old,
                  origin: _origin,
                  progress: CurvedAnimation(
                    parent: _reveal,
                    curve: Motion.expand,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 画旧画面,但挖掉一个从 [origin] 起越来越大的圆,圆里透出底下的新画面。
class _RevealPainter extends CustomPainter {
  _RevealPainter({
    required this.image,
    required this.origin,
    required this.progress,
  }) : super(repaint: progress);

  final ui.Image image;
  final Offset? origin;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = origin ?? size.center(Offset.zero);
    // 圆要大到盖住离中心最远的那个角。
    final reach = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - center).distance).reduce(math.max);
    final hole = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(
        Rect.fromCircle(center: center, radius: reach * progress.value),
      );
    canvas
      ..save()
      ..clipPath(hole)
      ..drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.image != image || old.origin != origin;
}
