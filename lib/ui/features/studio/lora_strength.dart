import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// LoRA 权重:左边滑条拖(0 到 2,一格 0.05,松手才写回工作流),右边的数字直接改
/// (回车或点别处生效,能写滑条外的值,比如负数)。2026-11-24 用户反馈 − + 加减不顺手。
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
  static const _min = 0.0;
  static const _max = 2.0;

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
              trackHeight: 3,
              activeTrackColor: color,
              inactiveTrackColor: PennaColors.border,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: SizedBox(
              height: 24,
              child: Slider(
                value: shown.clamp(_min, _max).toDouble(),
                min: _min,
                max: _max,
                divisions: 40,
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
