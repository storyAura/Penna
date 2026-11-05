part of 'chat_pane.dart';

// 发送键左边的上下文圆环和悬停时的明细面板。

/// 各部分在圆环上的颜色,按 [ContextMeter.parts] 的先后轮换。
List<Color> get _partColors => [
  PennaColors.primary,
  PennaColors.diffAddText,
  PennaColors.amber,
  PennaColors.diffDelText,
  PennaColors.accent,
  PennaColors.slate500,
  PennaColors.slate400,
];

/// 小圆环:占上限的比例,换对话、用量变了时转过去。悬停浮出 [_ContextPanel]。
class _ContextRing extends StatelessWidget {
  const _ContextRing({required this.meter});

  final ContextMeter meter;

  @override
  Widget build(BuildContext context) {
    final limit = meter.limit;
    // 用 RawTooltip 而不是 Tooltip:浮出、收起的动画要自己画(淡入、上浮、轻微放大)。
    return RawTooltip(
      semanticsTooltip: formatKilo(meter.used),
      hoverDelay: const Duration(milliseconds: 150),
      animationStyle: Motion.popover(context),
      positionDelegate: (c) => positionDependentBox(
        size: c.overlaySize,
        childSize: c.tooltipSize,
        target: c.target,
        verticalOffset: 18,
        preferBelow: false,
        margin: 10,
      ),
      tooltipBuilder: (context, animation) => _Popover(
        animation: animation,
        child: _ContextPanel(meter: meter),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: SizedBox.square(
          dimension: 18,
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              end: limit == null ? 0 : (meter.used / limit).clamp(0.0, 1.0),
            ),
            duration: Motion.of(context, Motion.base),
            curve: Motion.expand,
            builder: (_, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 2.5,
              color: PennaColors.slate500,
              backgroundColor: PennaColors.border,
            ),
          ),
        ),
      ),
    );
  }
}

/// 浮出来的毛玻璃卡片:跟着 [animation] 淡入、从下往上浮 6 像素、从 97% 放大到原样,收起时倒着走。
class _Popover extends StatelessWidget {
  const _Popover({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: _radius,
        boxShadow: [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _radius,
        // 底色半透明,透出后面的字;糊一下免得看不清。
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: PennaColors.card.withValues(alpha: 0.78),
              borderRadius: _radius,
              border: Border.all(
                color: PennaColors.border.withValues(alpha: 0.7),
              ),
            ),
            child: Padding(padding: const EdgeInsets.all(14), child: child),
          ),
        ),
      ),
    ),
    builder: (context, card) {
      final t = animation.value;
      return Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - t)),
          child: Transform.scale(
            scale: 0.97 + 0.03 * t,
            alignment: Alignment.bottomCenter,
            child: card,
          ),
        ),
      );
    },
  );
}

/// 明细:按比例分色的圆环、各部分占比,最下面是当前的接口和模型。
class _ContextPanel extends StatelessWidget {
  const _ContextPanel({required this.meter});

  final ContextMeter meter;

  static String _percent(int part, int whole) =>
      '${(whole == 0 ? 0.0 : part / whole * 100).toStringAsFixed(1)}%';

  TextStyle get _small => TextStyle(fontSize: 12, color: PennaColors.slate500);
  TextStyle get _strong => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: PennaColors.text,
  );

  Widget _info(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        SizedBox(width: 44, child: Text(label, style: _small)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _strong,
          ),
        ),
      ],
    ),
  );

  Widget _partRow(ContextPart part, Color color) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(part.label, style: _small)),
        Text(formatKilo(part.tokens), style: _strong),
        SizedBox(
          width: 50,
          child: Text(
            _percent(part.tokens, meter.used),
            textAlign: TextAlign.right,
            style: _small,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final limit = meter.limit;
    final colors = _partColors;
    final usage = meter.usage;
    final parts = meter.parts;
    final used = formatKilo(meter.used);
    final content = SizedBox(
      // 只在换了口径(预计 / 已使用)、模型、上限时算换内容;数字涨了原地变,不闪。
      key: ValueKey((meter.estimated, limit, meter.api, meter.model)),
      width: 270,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 76,
                // 浮出来、换了内容时,彩色的弧从十二点钟方向转一圈铺开。
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Motion.of(context, Motion.sheet),
                  curve: Motion.expand,
                  builder: (_, progress, child) => CustomPaint(
                    painter: _PartsPainter(
                      progress: progress,
                      slices: [
                        for (final (i, p) in parts.indexed)
                          (
                            share: meter.used == 0
                                ? 0.0
                                : p.tokens / meter.used,
                            color: colors[i % colors.length],
                          ),
                      ],
                      track: PennaColors.border,
                    ),
                    child: child,
                  ),
                  child: Center(
                    child: Text(
                      limit == null ? used : _percent(meter.used, limit),
                      style: _strong,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meter.estimated ? tr('预计加载') : tr('已使用'),
                      style: _small,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      limit == null ? used : '$used / ${formatKilo(limit)}',
                      style: _strong,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (i, p) in parts.indexed)
            _partRow(p, colors[i % colors.length]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Divider(height: 1, color: PennaColors.border),
          ),
          if (usage != null) ...[
            Text(
              [
                tr('输入 {0}', [formatKilo(usage.input)]),
                tr('缓存 {0}', [formatKilo(usage.cached)]),
                tr('输出 {0}', [formatKilo(usage.output)]),
              ].join(' · '),
              style: _small,
            ),
            const SizedBox(height: 4),
          ],
          _info('API', meter.api),
          _info(tr('模型'), meter.model),
        ],
      ),
    );
    // 内容变了(换对话、用量更新):旧的淡出新的淡入,高度跟着缓过去。
    return AnimatedSize(
      duration: Motion.of(context, Motion.base),
      curve: Motion.expand,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.base),
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.leave,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.bottomCenter,
          children: [...previous, ?current],
        ),
        child: content,
      ),
    );
  }
}

/// 一圈按比例分色的弧,份额加起来是一整圈。
class _PartsPainter extends CustomPainter {
  const _PartsPainter({
    required this.slices,
    required this.track,
    this.progress = 1,
  });

  final List<({double share, Color color})> slices;
  final Color track;

  /// 铺开到哪了:0 一点没有,1 整圈。
  final double progress;

  static const _stroke = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = s.share * progress * math.pi * 2;
      canvas.drawArc(rect, start, sweep, false, paint..color = s.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PartsPainter old) =>
      old.track != track ||
      old.progress != progress ||
      !listEquals(old.slices, slices);
}
