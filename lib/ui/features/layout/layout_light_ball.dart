part of 'layout_camera.dart';

/// 灯光球:从镜头看主体,球按现在的灯照亮;每盏灯一个带序号的手柄,拖着改方向,
/// 拖出球边就翻到背面(背面的手柄是空心的)。
class _LightBall extends StatefulWidget {
  const _LightBall({
    required this.lighting,
    required this.camera,
    required this.selected,
    required this.onPick,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
  });

  final Lighting lighting;
  final Camera camera;
  final String? selected;
  final ValueChanged<String> onPick;
  final VoidCallback onStart, onEnd;
  final void Function(String id, ({double azimuth, double elevation}) to)
  onMove;

  @override
  State<_LightBall> createState() => _LightBallState();
}

class _LightBallState extends State<_LightBall> {
  ui.Image? _image;
  Object? _for;

  /// 正在拖的灯,和按下时它在正面(1)还是背面(-1)。
  String? _drag;
  int _front = 1;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// 球的像素在别的线程外算不值当(最多 256×256):灯或镜头变了就重算一张。
  void _render(int px) {
    final key = (widget.lighting, widget.camera, px);
    if (key == _for) return;
    _for = key;
    ui.decodeImageFromPixels(
      renderLitSphere(px, widget.lighting, widget.camera),
      px,
      px,
      ui.PixelFormat.rgba8888,
      (img) {
        if (!mounted || _for != key) return img.dispose();
        setState(() {
          _image?.dispose();
          _image = img;
        });
      },
    );
  }

  /// 各盏灯的手柄在球上的位置(相对球心,半径为 1;y 朝下)和在不在正面。
  List<(Light, Offset, bool)> get _handles => [
    for (final l in widget.lighting.lights)
      if (relDir(l, widget.lighting, widget.camera) case final r)
        (l, Offset(r.side, -r.up), r.front >= 0),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = math.min(box.maxWidth, 180.0);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        _render((size * dpr).round().clamp(32, 256));
        final radius = size / 2 - 1;
        final center = Offset(size / 2, size / 2);
        String? hit(Offset p) {
          String? best;
          var bestD = 14.0;
          for (final (l, at, front) in _handles) {
            // 正面的优先:背面的离得一样近时让给正面的。
            final d = (center + at * radius - p).distance + (front ? 0 : 4);
            if (d < bestD) {
              best = l.id;
              bestD = d;
            }
          }
          return best;
        }

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTapUp: (d) {
                final id = hit(d.localPosition);
                if (id != null) widget.onPick(id);
              },
              onPanStart: (d) {
                final id = hit(d.localPosition);
                if (id == null) return;
                _drag = id;
                _front = _handles.firstWhere((h) => h.$1.id == id).$3 ? 1 : -1;
                widget.onPick(id);
                widget.onStart();
              },
              onPanUpdate: (d) {
                final id = _drag;
                if (id == null) return;
                final p = (d.localPosition - center) / radius;
                final rel = ballPointToRel(p.dx, -p.dy, _front);
                widget.onMove(
                  id,
                  fromRel(
                    rel.side,
                    rel.up,
                    rel.front,
                    widget.lighting,
                    widget.camera,
                  ),
                );
              },
              onPanEnd: (_) => _endDrag(),
              onPanCancel: _endDrag,
              child: CustomPaint(
                painter: _BallPainter(
                  _image,
                  _handles,
                  widget.selected,
                  PennaColors.border,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _endDrag() {
    if (_drag == null) return;
    _drag = null;
    widget.onEnd();
  }
}

class _BallPainter extends CustomPainter {
  _BallPainter(this.image, this.handles, this.selected, this.rim);

  final ui.Image? image;
  final List<(Light, Offset, bool)> handles;
  final String? selected;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF2B2824));
    final img = image;
    if (img != null) {
      paintImage(
        canvas: canvas,
        rect: Offset.zero & size,
        image: img,
        filterQuality: FilterQuality.medium,
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = rim
        ..style = PaintingStyle.stroke,
    );
    // 背面的先画,正面的盖在上面。
    for (final (i, (l, at, front)) in [
      ...handles.indexed.where((h) => !h.$2.$3),
      ...handles.indexed.where((h) => h.$2.$3),
    ]) {
      final c = center + at * radius;
      final (r, g, b) = lightRgb(l);
      final color = Color.fromARGB(
        255,
        (r * 255).round(),
        (g * 255).round(),
        (b * 255).round(),
      );
      final big = l.id == selected;
      final rad = big ? 9.0 : 7.5;
      canvas.drawCircle(
        c,
        rad,
        Paint()..color = front ? color : color.withValues(alpha: 0.25),
      );
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..color = big ? Colors.white : const Color(0xFF1F2533)
          ..style = PaintingStyle.stroke
          ..strokeWidth = big ? 2.2 : 1.2,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: front && (r + g + b) > 1.8
                ? const Color(0xFF1F2533)
                : Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, c - Offset(label.width / 2, label.height / 2));
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(_BallPainter old) =>
      old.image != image ||
      old.selected != selected ||
      old.rim != rim ||
      !listEquals(
        [for (final h in old.handles) (h.$1, h.$2, h.$3)],
        [for (final h in handles) (h.$1, h.$2, h.$3)],
      );
}
