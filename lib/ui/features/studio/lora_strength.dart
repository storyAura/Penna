import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// LoRA 权重:左边滑条拖(-10 到 10,一格 0.05,松手才写回工作流),右边的数字直接改
/// (回车或点别处生效)。2026-11-24 用户反馈 − + 加减不顺手;2026-11-25 又要 0 在正中、
/// 往左是负权重(滑块类 LoRA 常用负数)。条从中间的 0 画到眼前的值。
class LoraStrength extends StatefulWidget {
  const LoraStrength({
    super.key,
    required this.value,
    required this.onChanged,
    this.muted = false,
  });

  final double value;
  final ValueChanged<double> onChanged;

  /// 关着的 LoRA:颜色淡一点,照样能调。
  final bool muted;

  @override
  State<LoraStrength> createState() => _LoraStrengthState();
}

class _LoraStrengthState extends State<LoraStrength> {
  static const _min = -10.0;
  static const _max = 10.0;

  /// 正在拖时的值;松手前不写回。
  double? _drag;
  late final _input = TextEditingController(text: _show(widget.value));
  final _focus = FocusNode();

  static String _show(double v) => v.toStringAsFixed(2);
  static double _round(double v) => (v * 100).round() / 100;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _submit(_input.text);
    });
  }

  @override
  void didUpdateWidget(LoraStrength old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) _input.text = _show(widget.value);
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final n = double.tryParse(text.trim());
    if (n == null || _round(n) == widget.value) {
      _input.text = _show(widget.value);
      return;
    }
    widget.onChanged(_round(n.clamp(-10, 10).toDouble()));
  }

  @override
  Widget build(BuildContext context) {
    final shown = _drag ?? widget.value;
    final color = widget.muted ? PennaColors.slate400 : PennaColors.primary;
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              // 自带的条只会从最左边填,这里藏起来,由 _CenterTrack 从 0 画起。
              trackHeight: 3,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: SizedBox(
              height: 24,
              child: CustomPaint(
                painter: _CenterTrack(
                  at: (shown.clamp(_min, _max) - _min) / (_max - _min),
                  fill: color,
                  rail: PennaColors.border,
                ),
                child: Slider(
                  value: shown.clamp(_min, _max).toDouble(),
                  min: _min,
                  max: _max,
                  divisions: 400,
                  onChanged: (v) => setState(() {
                    _drag = _round(v);
                    _input.text = _show(_drag!);
                  }),
                  onChangeEnd: (v) {
                    setState(() => _drag = null);
                    if (_round(v) != widget.value) widget.onChanged(_round(v));
                  },
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 44,
          height: 24,
          child: Tooltip(
            message: tr('权重'),
            child: TextField(
              controller: _input,
              focusNode: _focus,
              textAlign: TextAlign.center,
              contextMenuBuilder: pennaTextMenu,
              style: monoStyle.copyWith(
                fontSize: 11.5,
                color: widget.muted ? PennaColors.slate400 : PennaColors.text,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 5),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: PennaColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(5),
                  borderSide: BorderSide(color: PennaColors.primary),
                ),
              ),
              onSubmitted: _submit,
            ),
          ),
        ),
      ],
    );
  }
}

/// 滑条的轨道:灰底、正中一道刻度(0),主题色从正中画到 [at](0 到 1 的位置)。
/// 左右各让出 12,和滑块能走到的范围对齐(Slider 的 overlay 半径)。
class _CenterTrack extends CustomPainter {
  const _CenterTrack({
    required this.at,
    required this.fill,
    required this.rail,
  });

  final double at;
  final Color fill;
  final Color rail;

  static const _pad = 12.0;
  static const _height = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final width = size.width - _pad * 2;
    final mid = _pad + width / 2;
    final x = _pad + width * at;
    final r = const Radius.circular(_height / 2);
    canvas.drawRRect(
      RRect.fromLTRBR(
        _pad,
        y - _height / 2,
        size.width - _pad,
        y + _height / 2,
        r,
      ),
      Paint()..color = rail,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        x < mid ? x : mid,
        y - _height / 2,
        x < mid ? mid : x,
        y + _height / 2,
        r,
      ),
      Paint()..color = fill,
    );
    canvas.drawRect(
      Rect.fromLTWH(mid - 0.75, y - 5, 1.5, 10),
      Paint()..color = fill.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_CenterTrack old) =>
      old.at != at || old.fill != fill || old.rail != rail;
}
