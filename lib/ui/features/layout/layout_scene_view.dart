import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../../core/harness/layout.dart';
import '../../../l10n/l10n.dart';
import '../../core/theme.dart';
import 'layout_bodies.dart';
import 'layout_board.dart';
import 'layout_canvas.dart';

// 自由摄像机:像 Blender 的视口。主画布是镜头拍到的画面,镜头不动;
// 这里在场景外面随意转着看(体块、地面、镜头和它的视野),拖体块在地面上挪它,
// 镜头画面里的框跟着变。视口的镜头只在这里,不存盘、不交给 Agent。

/// 主画布和自由视图摆成上下还是左右:哪种让主画布(宽高比 [aspect])显示得更大就用哪种。
bool sceneStacked(double aspect, Size area) {
  final stacked = math.min(area.width / aspect, area.height / 2);
  final side = math.min(area.width / 2 / aspect, area.height);
  return stacked >= side;
}

/// 把主画布 [canvas] 和自由视图 [scene] 按画布比例摆成上下或左右两块。
class SceneSplit extends StatelessWidget {
  const SceneSplit({
    super.key,
    required this.aspect,
    required this.canvas,
    required this.scene,
  });

  final double aspect;
  final Widget canvas, scene;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final stacked = sceneStacked(aspect, c.biggest);
      return Flex(
        direction: stacked ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Expanded(child: canvas),
          Expanded(child: scene),
        ],
      );
    },
  );
}

/// 看整个场景的视口镜头:对着各块的体块和主镜头的中心,从主镜头左上方斜着看,
/// 远到全都装得下。
Camera fitSceneCamera(Layout l) {
  final main = CameraView(l.camera, l.width, l.height);
  final pts = [
    main.eye,
    for (final b in l.boxes)
      if (_inScene(b)) ...b.body!.corners,
  ];
  var lo = pts.first, hi = pts.first;
  for (final p in pts) {
    lo = (
      x: math.min(lo.x, p.x),
      y: math.min(lo.y, p.y),
      z: math.min(lo.z, p.z),
    );
    hi = (
      x: math.max(hi.x, p.x),
      y: math.max(hi.y, p.y),
      z: math.max(hi.z, p.z),
    );
  }
  final c = (x: (lo.x + hi.x) / 2, y: (lo.y + hi.y) / 2, z: (lo.z + hi.z) / 2);
  final radius = math.max(
    0.3,
    math.sqrt(
          math.pow(hi.x - lo.x, 2) +
              math.pow(hi.y - lo.y, 2) +
              math.pow(hi.z - lo.z, 2),
        ) /
        2,
  );
  const fov = 40.0;
  return Camera(
    orbit: l.camera.orbit - 40,
    pitch: 25,
    fov: fov,
    distance: radius / math.sin(fov / 2 * math.pi / 180) * 1.3,
    panX: c.x,
    panY: c.y,
    panZ: c.z - 1,
  );
}

/// 视口里 ([u], [v]) 那个像素的视线和水平面 y = [y] 的交点;视线和地面平行、
/// 或交点在镜头后面时为 null。
Vec3? hitGround(CameraView view, double u, double v, double y) {
  final far = view.unproject(u, v, 1);
  final dir = (
    x: far.x - view.eye.x,
    y: far.y - view.eye.y,
    z: far.z - view.eye.z,
  );
  if (dir.y.abs() < 1e-6) return null;
  final t = (y - view.eye.y) / dir.y;
  if (t <= 0) return null;
  return (x: view.eye.x + dir.x * t, y: y, z: view.eye.z + dir.z * t);
}

/// 视口里画不画这一块:有体块、用户没点眼睛关掉的都画。跑到主镜头外面的也画
/// (主画布上看不到它,只能在这里拖回来)。
bool _inScene(LayoutBox b) => b.body != null && b.hidden != true;

/// 视口里第 [i] 块体块投出来的外框;有角在视口镜头后面时为 null。
Rect? _bodyRect(Body body, CameraView view) {
  final pts = [for (final c in body.corners) view.project(c)];
  if (pts.contains(null)) return null;
  var r = Rect.fromLTWH(pts.first!.u, pts.first!.v, 0, 0);
  for (final p in pts) {
    r = r.expandToInclude(Rect.fromLTWH(p!.u, p.v, 0, 0));
  }
  return r;
}

/// 自由视图:左键拖空白处绕着转、拖体块在地面上挪它,右键或中键拖平移,滚轮推拉;
/// 右上角复位。
class SceneView extends StatefulWidget {
  const SceneView({super.key, required this.board});

  final LayoutBoard board;

  @override
  State<SceneView> createState() => _SceneViewState();
}

enum _SceneDrag { orbit, pan, body }

class _SceneViewState extends State<SceneView> {
  /// 视口的镜头;null 时照场景重新框一次。
  Camera? _cam;
  Size _size = Size.zero;
  _SceneDrag? _drag;
  Offset _last = Offset.zero;

  /// 拖体块时:按住的地方离体块中心差多少(水平面上),和那个水平面的高度。
  ({double dx, double dz, double y})? _grab;

  LayoutBoard get _board => widget.board;

  CameraView _view(Camera cam) => CameraView(
    cam,
    math.max(1, _size.width.round()),
    math.max(1, _size.height.round()),
  );

  /// 按在了哪块的体块上:离视口近的优先。
  int? _hitBody(Offset p, CameraView view) {
    int? best;
    var nearest = double.infinity;
    for (final (i, b) in _board.layout.boxes.indexed) {
      final body = b.body;
      if (body == null || !_inScene(b)) continue;
      final r = _bodyRect(body, view);
      if (r == null || !r.inflate(4).contains(p)) continue;
      final z = view.toCamera(body.center).z;
      if (z < nearest) (best, nearest) = (i, z);
    }
    return best;
  }

  void _down(PointerDownEvent e) {
    final cam = _cam ??= fitSceneCamera(_board.layout);
    final view = _view(cam);
    _last = e.localPosition;
    final pan =
        e.buttons & (kMiddleMouseButton | kSecondaryMouseButton) != 0 ||
        HardwareKeyboard.instance.isShiftPressed;
    final i = pan ? null : _hitBody(e.localPosition, view);
    if (i == null) {
      _drag = pan ? _SceneDrag.pan : _SceneDrag.orbit;
      return;
    }
    final body = _board.layout.boxes[i].body!;
    final hit = hitGround(view, e.localPosition.dx, e.localPosition.dy, body.y);
    if (hit == null) return;
    _drag = _SceneDrag.body;
    _grab = (dx: hit.x - body.x, dz: hit.z - body.z, y: body.y);
    // 选中会通知一次,标记放在它后面;拖动时挪的块靠选中跟着(重排后序号会变)。
    _board.select(i);
    _board.mark(tr('移动「{0}」的体块', [boxName(_board.layout.boxes[i], i)]));
  }

  void _move(PointerMoveEvent e) {
    final cam = _cam;
    if (cam == null || _drag == null) return;
    final d = e.localPosition - _last;
    _last = e.localPosition;
    switch (_drag!) {
      case _SceneDrag.orbit:
        setState(
          () => _cam = cam.copyWith(
            orbit: cam.orbit + d.dx * 0.4,
            pitch: (cam.pitch + d.dy * 0.4).clamp(-89.0, 89.0),
          ),
        );
      case _SceneDrag.pan:
        final view = _view(cam);
        final k = cam.distance / view.f;
        final t = cam.target;
        final to = (
          x: t.x - (view.right.x * d.dx + view.down.x * d.dy) * k,
          y: t.y - (view.right.y * d.dx + view.down.y * d.dy) * k,
          z: t.z - (view.right.z * d.dx + view.down.z * d.dy) * k,
        );
        setState(
          () => _cam = cam.copyWith(panX: to.x, panY: to.y, panZ: to.z - 1),
        );
      case _SceneDrag.body:
        final i = _board.selected, g = _grab;
        final body = i == null ? null : _board.layout.boxes[i].body;
        if (body == null || g == null) return;
        final hit = hitGround(
          _view(cam),
          e.localPosition.dx,
          e.localPosition.dy,
          g.y,
        );
        if (hit == null) return;
        _board.setBody(i!, body.copyWith(x: hit.x - g.dx, z: hit.z - g.dz));
    }
  }

  void _up(PointerEvent _) {
    if (_drag == _SceneDrag.body) _board.mark(null);
    _drag = null;
    _grab = null;
  }

  void _scroll(PointerSignalEvent e) {
    final cam = _cam;
    if (e is! PointerScrollEvent || cam == null) return;
    setState(
      () => _cam = cam.copyWith(
        distance: (cam.distance * math.exp(e.scrollDelta.dy * 0.0015)).clamp(
          0.05,
          200.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PennaColors.card,
          border: Border.all(color: PennaColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, c) {
                  _size = c.biggest;
                  final cam = _cam ??= fitSceneCamera(_board.layout);
                  return Listener(
                    onPointerDown: _down,
                    onPointerMove: _move,
                    onPointerUp: _up,
                    onPointerCancel: _up,
                    onPointerSignal: _scroll,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        _board,
                        _board.shadePreview,
                      ]),
                      builder: (context, _) => CustomPaint(
                        size: c.biggest,
                        painter: _ScenePainter(
                          layout: _board.layout,
                          cam: cam,
                          selected: _board.selected,
                          grid: PennaColors.border,
                          text: PennaColors.slate500,
                          lit:
                              _board.layout.lighting.enabled &&
                              _board.shadePreview.value,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 10,
              top: 8,
              child: IgnorePointer(
                child: Text(
                  tr('自由摄像机'),
                  style: TextStyle(fontSize: 11, color: PennaColors.slate500),
                ),
              ),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: IconButton(
                tooltip: tr('复位'),
                iconSize: 16,
                icon: const Icon(Icons.center_focus_strong),
                onPressed: () => setState(() => _cam = null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 视口画面:地面网格、各块的体块(带序号)、主镜头和它看出去的视野。
class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.layout,
    required this.cam,
    required this.selected,
    required this.grid,
    required this.text,
    required this.lit,
  });

  final Layout layout;
  final Camera cam;
  final int? selected;
  final Color grid, text;

  /// 光影预览:按灯光给看得到的面上明暗(灯的方位照主镜头算,看得到哪几面照视口)。
  final bool lit;

  static const _eyeColor = Color(0xFFF59E0B);

  @override
  void paint(Canvas canvas, Size size) {
    final view = CameraView(
      cam,
      math.max(1, size.width.round()),
      math.max(1, size.height.round()),
    );
    Offset? at(Vec3 p) {
      final q = view.project(p);
      return q == null ? null : Offset(q.u, q.v);
    }

    void line(Vec3 a, Vec3 b, Paint paint, {int steps = 1}) {
      // 分成几段画,一头在视口镜头后面时只画看得到的那几段。
      for (var k = 0; k < steps; k++) {
        Vec3 lerp(double t) => (
          x: a.x + (b.x - a.x) * t,
          y: a.y + (b.y - a.y) * t,
          z: a.z + (b.z - a.z) * t,
        );
        final p = at(lerp(k / steps)), q = at(lerp((k + 1) / steps));
        if (p != null && q != null) canvas.drawLine(p, q, paint);
      }
    }

    canvas.clipRect(Offset.zero & size);
    final bodies = [
      for (final (i, b) in layout.boxes.indexed)
        if (_inScene(b)) (i, b.body!),
    ];
    _paintGround(bodies, line);
    // 远的先画,近的盖在上面。
    final order = [...bodies]
      ..sort(
        (a, b) => view
            .toCamera(b.$2.center)
            .z
            .compareTo(view.toCamera(a.$2.center).z),
      );
    for (final (i, body) in order) {
      // 在主镜头外面的(主画布上看不到)画淡一点。
      final color = layout.boxes[i].offscreen
          ? Color.lerp(layoutBodyColor(i), grid, 0.6)!
          : layoutBodyColor(i);
      paintBody(
        canvas,
        body,
        layout.boxes[i].shape,
        at,
        color,
        width: i == selected ? 2.4 : 1.2,
        lit: lit ? layout : null,
        eye: view.eye,
      );
      final top = at((x: body.x, y: body.y - body.h / 2, z: body.z));
      if (top != null) _label(canvas, '${i + 1}', top, layoutBoxColor(i));
    }
    _paintCamera(line, at, canvas);
  }

  /// 地面:各块底下那个水平面(世界 y 向下,取最低的底面),铺一片网格。
  void _paintGround(
    List<(int, Body)> bodies,
    void Function(Vec3, Vec3, Paint, {int steps}) line,
  ) {
    final ground = bodies.isEmpty
        ? 0.3
        : bodies.map((b) => b.$2.y + b.$2.h / 2).reduce(math.max);
    final t = cam.target;
    final reach = math.max(1.0, cam.distance);
    final step = math.pow(10, (math.log(reach) / math.ln10).floor() - 1) * 2.0;
    final half = (reach / step).ceil() * step;
    final paint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final cx = (t.x / step).round() * step, cz = (t.z / step).round() * step;
    for (var k = -half; k <= half + 1e-9; k += step) {
      line(
        (x: cx + k, y: ground, z: cz - half),
        (x: cx + k, y: ground, z: cz + half),
        paint,
        steps: 24,
      );
      line(
        (x: cx - half, y: ground, z: cz + k),
        (x: cx + half, y: ground, z: cz + k),
        paint,
        steps: 24,
      );
    }
  }

  /// 主镜头:一个黄点,四条线连到它拍到的那块画面(取在各块里最远的那一层)。
  void _paintCamera(
    void Function(Vec3, Vec3, Paint, {int steps}) line,
    Offset? Function(Vec3) at,
    Canvas canvas,
  ) {
    final main = CameraView(layout.camera, layout.width, layout.height);
    final far = [
      for (final b in layout.boxes)
        if (b.body != null && !b.offscreen) main.toCamera(b.body!.center).z,
    ].fold(layout.camera.distance, math.max).clamp(0.3, 20.0);
    final w = layout.width.toDouble(), h = layout.height.toDouble();
    final frame = [
      main.unproject(0, 0, far),
      main.unproject(w, 0, far),
      main.unproject(w, h, far),
      main.unproject(0, h, far),
    ];
    final ray = Paint()
      ..color = _eyeColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final edge = Paint()
      ..color = _eyeColor
      ..strokeWidth = 1.6;
    for (final (k, c) in frame.indexed) {
      line(main.eye, c, ray, steps: 12);
      line(c, frame[(k + 1) % 4], edge, steps: 12);
    }
    final eye = at(main.eye);
    if (eye != null) {
      canvas
        ..drawCircle(eye, 5.5, Paint()..color = _eyeColor)
        ..drawCircle(
          eye,
          5.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    }
  }

  void _label(Canvas canvas, String s, Offset at, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromCenter(
      center: at - Offset(0, tp.height / 2 + 4),
      width: tp.width + 8,
      height: tp.height + 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(3)),
      Paint()..color = color,
    );
    tp.paint(canvas, r.topLeft + const Offset(4, 1));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.layout != layout ||
      old.cam != cam ||
      old.selected != selected ||
      old.grid != grid ||
      old.lit != lit;
}
