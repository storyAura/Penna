import 'package:flutter/material.dart';

import '../../core/harness/layout.dart';
import '../../l10n/l10n.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';

/// 宽和高。
typedef PanelSize = ({int width, int height});

/// 拖动板的边长(逻辑像素)。
const _padSide = 240.0;

/// 面板整个的宽(拖动板加两边各 12 的留白),摆弹出位置用。
const sizePanelWidth = _padSide + 24;

/// 拖动板(测试里拿它找)。
const sizePadKey = Key('layout-size-pad');

/// 拖动板上一格点代表多少像素。
const _gridStep = 256;

/// 分辨率面板:一块拖动板(左下角是原点,拖右上角定宽高,拖上边只改高、拖右边只改宽)
/// 和存下的常用尺寸。区域控制的画布、ComfyUI 侧栏的画面大小都用它。
class SizePanel extends StatefulWidget {
  const SizePanel({
    super.key,
    required this.size,
    required this.onSize,
    required this.sizes,
    required this.onSave,
    required this.onRemove,
    required this.maxSizes,
    required this.snap,
    this.defaultSize,
    this.onSetDefault,
  });

  /// 眼下的尺寸。
  final PanelSize size;

  /// 换尺寸(拖完松手、点了常用尺寸)。
  final ValueChanged<PanelSize> onSize;

  /// 存下的常用尺寸。
  final List<PanelSize> sizes;

  /// 存下眼下的尺寸;存满了返回 false。
  final bool Function() onSave;
  final ValueChanged<PanelSize> onRemove;
  final int maxSizes;

  /// 宽高取它的倍数。
  final int Function() snap;

  /// 给了 [onSetDefault] 才有星标(区域控制的新页默认)。
  final PanelSize? defaultSize;
  final VoidCallback? onSetDefault;

  @override
  State<SizePanel> createState() => _SizePanelState();
}

enum _Handle { corner, width, height }

class _SizePanelState extends State<SizePanel> {
  /// 拖动板能拖到的最大边长:2048 或 [maxLayoutSide]。
  late int _range = _fits2k ? 2048 : maxLayoutSide;

  /// 拖着时的尺寸,松手才换画布(每帧都换会把框按比例反复缩放、攒下取整误差)。
  PanelSize? _draft;
  _Handle _handle = _Handle.corner;

  bool get _fits2k => widget.size.width <= 2048 && widget.size.height <= 2048;

  PanelSize get _shown => _draft ?? widget.size;

  double get _scale => _padSide / _range;

  /// 按下的位置离哪个把手近:上边、右边的中点只改一边,其余都是拖右上角。
  _Handle _pick(Offset p) {
    final s = _shown, k = _scale;
    final w = s.width * k, h = s.height * k;
    bool near(Offset q) => (p - q).distance < 12;
    if (near(Offset(w / 2, _padSide - h))) return _Handle.height;
    if (near(Offset(w, _padSide - h / 2))) return _Handle.width;
    return _Handle.corner;
  }

  int _side(double v) =>
      snapLayoutSide((v / _scale).round(), widget.snap(), max: _range);

  void _drag(Offset p) {
    final s = _shown;
    setState(
      () => _draft = (
        width: _handle == _Handle.height ? s.width : _side(p.dx),
        height: _handle == _Handle.width ? s.height : _side(_padSide - p.dy),
      ),
    );
  }

  void _commit() {
    final d = _draft;
    if (d == null) return;
    widget.onSize(d);
    setState(() => _draft = null);
  }

  void _save() {
    if (!widget.onSave()) {
      showToast(context, tr('最多存 {0} 个尺寸', [widget.maxSizes]), warn: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _shown;
    final saved = widget.sizes.contains(widget.size);
    final isDefault = widget.defaultSize == widget.size;
    final label = TextStyle(fontSize: 11, color: PennaColors.slate500);
    final value = const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: _padSide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Text('W ', style: label),
                        Text('${s.width}', style: value),
                        const SizedBox(width: 10),
                        Text('H ', style: label),
                        Text('${s.height}', style: value),
                      ],
                    ),
                  ),
                ),
                Tooltip(
                  message: tr('拖动范围'),
                  child: PennaChip(
                    label: '≤ $_range',
                    selected: false,
                    onTap: () => setState(
                      () => _range = _range == 2048 ? maxLayoutSide : 2048,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MouseRegion(
              cursor: SystemMouseCursors.precise,
              child: Listener(
                key: sizePadKey,
                onPointerDown: (e) {
                  _handle = _pick(e.localPosition);
                  _drag(e.localPosition);
                },
                onPointerMove: (e) => _drag(e.localPosition),
                onPointerUp: (_) => _commit(),
                onPointerCancel: (_) => setState(() => _draft = null),
                child: Container(
                  height: _padSide,
                  decoration: BoxDecoration(
                    color: PennaColors.slate50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: PennaColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      size: const Size.square(_padSide),
                      painter: _PadPainter(
                        width: s.width,
                        height: s.height,
                        range: _range,
                        dot: PennaColors.slate400,
                        fill: PennaColors.primaryBg,
                        line: PennaColors.primary,
                        knob: PennaColors.card,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${aspectLabel(s.width, s.height)} · '
                '${(s.width * s.height / 1e6).toStringAsFixed(2)} MP',
                style: label,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(tr('常用尺寸'), style: label),
                const Spacer(),
                if (widget.onSetDefault != null)
                  IconButton(
                    tooltip: tr('设为新页默认'),
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(isDefault ? Icons.star : Icons.star_outline),
                    color: isDefault ? PennaColors.primary : null,
                    onPressed: isDefault ? null : widget.onSetDefault,
                  ),
                IconButton(
                  tooltip: tr('存下这个尺寸'),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    saved ? Icons.bookmark_added : Icons.bookmark_add_outlined,
                  ),
                  onPressed: saved ? null : _save,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final size in widget.sizes)
                  _SizeTile(
                    size: size,
                    selected: size == widget.size,
                    isDefault:
                        widget.onSetDefault != null &&
                        size == widget.defaultSize,
                    onTap: () => widget.onSize(size),
                    onDelete: () => widget.onRemove(size),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 宽高比:约得够简单写成 `13:19`,不然写成 `1.46:1`。
String aspectLabel(int w, int h) {
  final g = w.gcd(h);
  final a = w ~/ g, b = h ~/ g;
  return a <= 32 && b <= 32 ? '$a:$b' : '${(w / h).toStringAsFixed(2)}:1';
}

class _PadPainter extends CustomPainter {
  const _PadPainter({
    required this.width,
    required this.height,
    required this.range,
    required this.dot,
    required this.fill,
    required this.line,
    required this.knob,
  });

  final int width, height, range;
  final Color dot, fill, line, knob;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / range;
    final dots = Paint()..color = dot.withValues(alpha: 0.5);
    for (var x = _gridStep; x < range; x += _gridStep) {
      for (var y = _gridStep; y < range; y += _gridStep) {
        canvas.drawCircle(Offset(x * k, size.height - y * k), 1, dots);
      }
    }
    final w = width * k, h = height * k;
    final rect = Rect.fromLTWH(0, size.height - h, w, h);
    canvas.drawRect(rect, Paint()..color = fill.withValues(alpha: 0.7));
    canvas.drawRect(
      rect,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    void handle(Offset c, double r, Color color) {
      canvas.drawCircle(c, r + 1.5, Paint()..color = knob);
      canvas.drawCircle(c, r, Paint()..color = color);
    }

    handle(Offset(w / 2, rect.top), 4.5, line.withValues(alpha: 0.6));
    handle(Offset(w, rect.top + h / 2), 4.5, line.withValues(alpha: 0.6));
    handle(rect.topRight, 6, line);
  }

  @override
  bool shouldRepaint(_PadPainter old) =>
      old.width != width ||
      old.height != height ||
      old.range != range ||
      old.line != line ||
      old.dot != dot;
}

/// 一个存下的尺寸:画出它的横竖样子;悬停时右上角出一个删除。
class _SizeTile extends StatefulWidget {
  const _SizeTile({
    required this.size,
    required this.selected,
    required this.onTap,
    required this.onDelete,
    this.isDefault = false,
  });

  final PanelSize size;
  final bool selected;

  /// 新页默认用的尺寸:左上角标一颗星。
  final bool isDefault;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_SizeTile> createState() => _SizeTileState();
}

class _SizeTileState extends State<_SizeTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.size, on = widget.selected;
    final color = on ? PennaColors.primary : PennaColors.slate700;
    // 小样塞进 22×22,长边撑满。
    final long = s.width > s.height ? s.width : s.height;
    final thumb = Size(22 * s.width / long, 22 * s.height / long);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.base),
              curve: Motion.swift,
              // 一排三个正好铺满面板:(240 - 两道 6 的间隔) / 3。
              width: (_padSide - 12) / 3,
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 5),
              decoration: BoxDecoration(
                color: on ? PennaColors.primaryBg : PennaColors.slate50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: on ? PennaColors.primary : PennaColors.border,
                ),
              ),
              child: Column(
                children: [
                  SizedBox.square(
                    dimension: 22,
                    child: Center(
                      child: Container(
                        width: thumb.width,
                        height: thumb.height,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: color, width: 1.2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${s.width}×${s.height}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                  Text(
                    aspectLabel(s.width, s.height),
                    style: TextStyle(
                      fontSize: 9.5,
                      color: PennaColors.slate500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.isDefault)
            Positioned(
              top: 3,
              left: 4,
              child: Tooltip(
                message: tr('新页默认'),
                child: Icon(Icons.star, size: 10, color: PennaColors.primary),
              ),
            ),
          if (_hover)
            Positioned(
              top: -5,
              right: -5,
              child: Tooltip(
                message: tr('删除'),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: PennaColors.card,
                      border: Border.all(color: PennaColors.border),
                    ),
                    child: Icon(
                      Icons.close,
                      size: 11,
                      color: PennaColors.slate500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
