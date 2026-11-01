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

/// 小圆环:占上限的比例。悬停弹出 [_ContextPanel]。
class _ContextRing extends StatelessWidget {
  const _ContextRing({required this.meter});

  final ContextMeter meter;

  @override
  Widget build(BuildContext context) {
    final limit = meter.limit;
    return Tooltip(
      richMessage: WidgetSpan(child: _ContextPanel(meter: meter)),
      waitDuration: const Duration(milliseconds: 150),
      preferBelow: false,
      verticalOffset: 18,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PennaColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PennaColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            value: limit == null ? 0 : (meter.used / limit).clamp(0.0, 1.0),
            strokeWidth: 2.5,
            color: PennaColors.slate500,
            backgroundColor: PennaColors.border,
          ),
        ),
      ),
    );
  }
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
    return SizedBox(
      width: 270,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 76,
                child: CustomPaint(
                  painter: _PartsPainter(
                    slices: [
                      for (final (i, p) in parts.indexed)
                        (
                          share: meter.used == 0 ? 0.0 : p.tokens / meter.used,
                          color: colors[i % colors.length],
                        ),
                    ],
                    track: PennaColors.border,
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
  }
}

/// 一圈按比例分色的弧,份额加起来是一整圈。
class _PartsPainter extends CustomPainter {
  const _PartsPainter({required this.slices, required this.track});

  final List<({double share, Color color})> slices;
  final Color track;

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
      final sweep = s.share * math.pi * 2;
      canvas.drawArc(rect, start, sweep, false, paint..color = s.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_PartsPainter old) =>
      old.track != track || !listEquals(old.slices, slices);
}
