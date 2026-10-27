import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';
import '../../../l10n/l10n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'layout_board.dart';

/// 拖动板的边长(逻辑像素)。
const _padSide = 240.0;

/// 拖动板(测试里拿它找)。
const sizePadKey = Key('layout-size-pad');

/// 拖动板上一格点代表多少像素。
const _gridStep = 256;

/// 顶栏的「分辨率」按钮:点开是一块拖动板(左下角是原点,拖右上角定宽高,
/// 拖上边只改高、拖右边只改宽)和存下的常用尺寸。
class LayoutSizePicker extends StatelessWidget {
  const LayoutSizePicker({super.key, required this.board, required this.snap});

  final LayoutBoard board;

  /// 宽高取它的倍数(设置里的分辨率对齐)。
  final int Function() snap;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    style: MenuStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      backgroundColor: WidgetStatePropertyAll(PennaColors.card),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: PennaColors.border),
        ),
      ),
    ),
    alignmentOffset: const Offset(0, 4),
    menuChildren: [
      ListenableBuilder(
        listenable: board,
        builder: (context, _) => _SizePanel(board: board, snap: snap),
      ),
    ],
    builder: (context, menu, _) => IconButton(
      tooltip: tr('分辨率'),
      iconSize: 16,
      visualDensity: VisualDensity.compact,
      isSelected: menu.isOpen,
      icon: const Icon(Icons.aspect_ratio),
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
    ),
  );
}

class _SizePanel extends StatefulWidget {
  const _SizePanel({required this.board, required this.snap});

  final LayoutBoard board;
  final int Function() snap;

  @override
  State<_SizePanel> createState() => _SizePanelState();
}

enum _Handle { corner, width, height }

class _SizePanelState extends State<_SizePanel> {
  LayoutBoard get board => widget.board;

  /// 拖动板能拖到的最大边长:2048 或 [maxLayoutSide]。
  late int _range = _fits2k ? 2048 : maxLayoutSide;

  /// 拖着时的尺寸,松手才换画布(每帧都换会把框按比例反复缩放、攒下取整误差)。
  LayoutSize? _draft;
  _Handle _handle = _Handle.corner;

  bool get _fits2k => board.layout.width <= 2048 && board.layout.height <= 2048;

  LayoutSize get _shown =>
      _draft ?? (width: board.layout.width, height: board.layout.height);

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
    board.setSize(d.width, d.height);
    setState(() => _draft = null);
  }

  void _save() {
    if (!board.saveSize()) {
      showToast(context, tr('最多存 {0} 个尺寸', [LayoutBoard.maxSizes]), warn: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _shown;
    final saved = board.sizes.contains((
      width: board.layout.width,
      height: board.layout.height,
    ));
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
                for (final size in board.sizes)
                  _SizeTile(
                    size: size,
                    selected:
                        size.width == board.layout.width &&
                        size.height == board.layout.height,
                    onTap: () => board.setSize(size.width, size.height),
                    onDelete: () => board.removeSize(size),
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
  });

  final LayoutSize size;
  final bool selected;
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
              width: 56,
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
