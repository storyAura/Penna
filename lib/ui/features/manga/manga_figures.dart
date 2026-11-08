import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/harness/manga/manga.dart';
import '../../../core/harness/manga/manga_poses.dart';

// 格里的人偶参考:每个出场角色画一个素描风的关节人偶(白身体、细描边、蛋形头上画
// 脸的中线和眼线,关节处画小圆),按景别取景、按身高排高矮、按姿势摆关节、按朝向转身;
// 再画名牌、台词气泡和景别标签。关节角度按三维算再投到画面上,所以正面看坐着的人
// 大腿是缩短的,不是横着伸出去。只是看站位和镜头的草图,不是解剖准确的人体。

/// 角色的颜色(名牌、身体淡淡的底色),按设定里的先后轮换。
const _palette = [
  Color(0xFF4F7FDB),
  Color(0xFFE06A55),
  Color(0xFF3FA474),
  Color(0xFF8E6BD8),
  Color(0xFFD49A2E),
  Color(0xFF2FA7B5),
];

Color figureColor(List<MangaCharacter> all, String name) {
  final i = all.indexWhere((c) => c.name == name);
  return i < 0 ? const Color(0xFF8B93A1) : _palette[i % _palette.length];
}

const _ink = Color(0xFF3A3A3A);

/// 朝向:正面、斜侧、侧面、背面各转多少度(0 是正对镜头)。
double _yawOf(String view) => switch (view) {
  '斜侧' => 45,
  '侧面' => 90,
  '背面' => 180,
  _ => 15,
};

/// 景别 → 全身多高(格高的几倍)、从脚底排还是从头顶排、脚底或头顶的位置(格高的几成)、
/// 一个人占格宽的几成(排不下时缩小)。
({double body, bool fromFeet, double at, double width}) _framing(String f) =>
    switch (f) {
      '远景' => (body: 0.42, fromFeet: true, at: 0.9, width: 0.34),
      '中景' => (body: 1.7, fromFeet: false, at: 0.14, width: 0.34),
      '近景' => (body: 2.9, fromFeet: false, at: 0.12, width: 0.36),
      '特写' => (body: 5.6, fromFeet: false, at: 0.06, width: 0.3),
      _ => (body: 0.84, fromFeet: true, at: 0.96, width: 0.34),
    };

typedef _P3 = ({double x, double y, double z});

_P3 _add(_P3 a, _P3 b, [double k = 1]) =>
    (x: a.x + b.x * k, y: a.y + b.y * k, z: a.z + b.z * k);

double _rad(double deg) => deg * math.pi / 180;

/// 一节的方向:往前抬 f、往外张 o,[side] 是哪一侧(1 是 A 侧)。
_P3 _dir(double f, double o, int side) {
  final fr = _rad(f), orad = _rad(o);
  return (
    x: math.cos(fr) * math.sin(orad) * side,
    y: math.cos(fr) * math.cos(orad),
    z: math.sin(fr),
  );
}

/// 一个人偶怎么画:脚底或头顶放在哪、全身多高、朝哪边、转多少度、什么姿势、什么体型。
class FigureSpec {
  const FigureSpec({
    required this.anchor,
    required this.fromFeet,
    required this.height,
    required this.facing,
    required this.yaw,
    required this.pose,
    this.build = '',
    this.head = 1,
    this.legs = 1,
    this.color = const Color(0xFF8B93A1),
  });

  final Offset anchor;
  final bool fromFeet;
  final double height, yaw, head, legs;
  final int facing;
  final MangaPoseDef pose;
  final String build;
  final Color color;
}

/// 算好的关节(画面坐标)和每一点离镜头多近(大的近,用来排前后)。
class FigurePose {
  FigurePose(this.spec) {
    final p = spec.pose;
    final h = spec.height;
    final female = spec.build == '女', male = spec.build == '男';
    final sw = female ? 0.098 : (male ? 0.118 : 0.106);
    final hw = female ? 0.072 : 0.064;
    headR = 0.066 * spec.head;
    final lean = _rad(p.lean), tilt = _rad(p.tilt);
    final up = (
      x: math.sin(tilt),
      y: -math.cos(lean) * math.cos(tilt),
      z: math.sin(lean),
    );
    const hip = (x: 0.0, y: 0.0, z: 0.0);
    final shoulder = _add(hip, up, 0.3);
    final neck = _add(hip, up, 0.345);
    final head = _add(hip, up, 0.345 + headR);
    final pts = <String, _P3>{
      'hip': hip,
      'shoulder': shoulder,
      'neck': neck,
      'head': head,
      'crotch': (x: 0, y: 0.06, z: 0),
    };
    for (final (side, tag, arm, leg) in [
      (1, 'A', p.armA, p.legA),
      (-1, 'B', p.armB, p.legB),
    ]) {
      final s = _add(shoulder, (x: sw * side, y: 0.004, z: 0));
      final e = _add(s, _dir(arm.f1, arm.o1, side), 0.155);
      final w = _add(e, _dir(arm.f2, arm.o2, side), 0.145);
      final hand = _add(w, _dir(arm.f2, arm.o2, side), 0.045);
      final hp = _add(hip, (x: hw * side, y: 0.02, z: 0));
      final k = _add(hp, _dir(leg.f1, leg.o1, side), 0.235 * spec.legs);
      final a = _add(k, _dir(leg.f2, leg.o2, side), 0.225 * spec.legs);
      final toe = _add(a, (x: 0.0, y: 0.015, z: 0.06));
      pts.addAll({
        'shoulder$tag': s,
        'elbow$tag': e,
        'wrist$tag': w,
        'hand$tag': hand,
        'hip$tag': hp,
        'knee$tag': k,
        'ankle$tag': a,
        'toe$tag': toe,
      });
    }
    // 转身(朝向镜头转 yaw)、朝左时左右翻过来、整个人转 roll,再放到该在的地方。
    final yaw = _rad(spec.yaw);
    final roll = _rad(p.roll) * spec.facing;
    final cos = math.cos(yaw), sin = math.sin(yaw);
    Offset flat(_P3 q) {
      final x = (q.x * cos + q.z * sin) * spec.facing * h;
      final y = q.y * h;
      return Offset(
        x * math.cos(roll) - y * math.sin(roll),
        x * math.sin(roll) + y * math.cos(roll),
      );
    }

    final raw = {for (final e in pts.entries) e.key: flat(e.value)};
    depth = {
      for (final e in pts.entries) e.key: e.value.z * cos - e.value.x * sin,
    };
    final Offset shift;
    if (spec.fromFeet) {
      final lowest = raw.values.map((o) => o.dy).reduce(math.max);
      shift = Offset(spec.anchor.dx, spec.anchor.dy - lowest - 0.012 * h);
    } else {
      final top = raw['head']!.dy - headR * h;
      shift = Offset(spec.anchor.dx, spec.anchor.dy - top);
    }
    at = {for (final e in raw.entries) e.key: e.value + shift};
    var box = Rect.fromCircle(center: at['head']!, radius: headR * h);
    for (final o in at.values) {
      box = box.expandToInclude(Rect.fromCircle(center: o, radius: 0.04 * h));
    }
    bounds = box;
  }

  final FigureSpec spec;
  late final double headR;
  late final Map<String, Offset> at;
  late final Map<String, double> depth;
  late final Rect bounds;

  Offset get headCenter => at['head']!;
  Offset get headTop => headCenter - Offset(0, headR * spec.height);
}

/// 一节:a 到 b,两头的半径(像素)。画成锥形的胶囊。
Path _capsule(Offset a, Offset b, double ra, double rb) {
  final d = b - a;
  final len = d.distance;
  final path = Path()
    ..addOval(Rect.fromCircle(center: a, radius: ra))
    ..addOval(Rect.fromCircle(center: b, radius: rb));
  if (len < 0.5) return path;
  final n = Offset(-d.dy / len, d.dx / len);
  return path
    ..addPolygon([a + n * ra, b + n * rb, b - n * rb, a - n * ra], true);
}

/// 沿 a→b 方向的椭圆(手、脚)。
Path _ellipseAlong(Offset a, Offset b, double half) {
  final d = b - a;
  final c = (a + b) / 2;
  final angle = math.atan2(d.dy, d.dx);
  final m = Matrix4.identity()
    ..translateByDouble(c.dx, c.dy, 0, 1)
    ..rotateZ(angle);
  return (Path()..addOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: math.max(d.distance, half * 2),
          height: half * 2,
        ),
      ))
      .transform(m.storage);
}

/// 画一个人偶。[selected] 时外面描一圈虚框。
void paintFigure(Canvas canvas, FigurePose f, {bool selected = false}) {
  final s = f.spec, h = s.height, at = f.at;
  final line = math.max(0.7, h * 0.0045);
  final ink = Paint()..color = _ink;
  final body = Paint()..color = Color.lerp(Colors.white, s.color, 0.12)!;
  final thin = Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = line;
  // 身体上的结构线(中线、胸线、胯线、关节)淡一点,轮廓才是主体。
  final detail = Paint()
    ..color = _ink.withValues(alpha: 0.45)
    ..style = PaintingStyle.stroke
    ..strokeWidth = line * 0.8;
  final slim = s.build == '女' ? 0.9 : (s.build == '男' ? 1.08 : 1.0);

  // 一组胳膊或腿:先整组描边(放大一圈的深色),再整组填白,关节处的线不会断开。
  void limb(String t, bool arm) {
    final parts = arm
        ? [
            ('shoulder$t', 'elbow$t', 0.026, 0.02),
            ('elbow$t', 'wrist$t', 0.019, 0.014),
          ]
        : [
            ('hip$t', 'knee$t', 0.042, 0.029),
            ('knee$t', 'ankle$t', 0.027, 0.018),
          ];
    final (endA, endB, endR) = arm
        ? ('wrist$t', 'hand$t', 0.017)
        : ('ankle$t', 'toe$t', 0.014);
    for (final (a, b, ra, rb) in parts) {
      canvas.drawPath(
        _capsule(at[a]!, at[b]!, ra * h * slim + line, rb * h * slim + line),
        ink,
      );
    }
    canvas.drawPath(
      _ellipseAlong(at[endA]!, at[endB]!, endR * h * slim + line),
      ink,
    );
    for (final (a, b, ra, rb) in parts) {
      canvas.drawPath(
        _capsule(at[a]!, at[b]!, ra * h * slim, rb * h * slim),
        body,
      );
    }
    canvas.drawPath(_ellipseAlong(at[endA]!, at[endB]!, endR * h * slim), body);
    // 关节的小圆(木头人偶的样子),肩关节跟着胳膊画,不被胳膊盖掉一半。
    for (final (j, r)
        in arm
            ? [('shoulder$t', 0.017), ('elbow$t', 0.012), ('wrist$t', 0.009)]
            : [('knee$t', 0.016), ('ankle$t', 0.011)]) {
      canvas.drawCircle(at[j]!, r * h * slim, detail);
    }
  }

  void torso() {
    final yaw = _rad(s.yaw);
    final c = math.cos(yaw).abs(), sn = math.sin(yaw).abs();
    double wide(double w, double d) => (w * c + d * sn) * h * slim;
    final hip = at['hip']!, top = at['shoulder']!;
    final axis = top - hip;
    final len = math.max(axis.distance, 1.0);
    final n = Offset(-axis.dy / len, axis.dx / len);
    Offset p(double t) => hip + axis * t;
    final female = s.build == '女';
    final levels = [
      (-0.18, wide(0.03, 0.03)),
      (0.0, wide(female ? 0.096 : 0.088, 0.065)),
      (0.42, wide(female ? 0.06 : 0.074, 0.05)),
      (0.72, wide(female ? 0.09 : 0.1, 0.065)),
      (1.0, wide(female ? 0.098 : 0.11, 0.05)),
      (1.1, wide(0.032, 0.032)),
    ];
    final left = [for (final (t, w) in levels) p(t) - n * w];
    final right = [for (final (t, w) in levels) p(t) + n * w];
    // 脖子先画,躯干盖在下面那截上。
    canvas
      ..drawPath(
        _capsule(
          at['shoulder']!,
          at['neck']!,
          0.022 * h + line,
          0.02 * h + line,
        ),
        ink,
      )
      ..drawPath(
        _capsule(at['shoulder']!, at['neck']!, 0.022 * h, 0.02 * h),
        body,
      );
    final path = Path()..moveTo(left.first.dx, left.first.dy);
    void smooth(List<Offset> pts) {
      for (var i = 1; i < pts.length; i++) {
        final mid = (pts[i - 1] + pts[i]) / 2;
        path.quadraticBezierTo(pts[i - 1].dx, pts[i - 1].dy, mid.dx, mid.dy);
      }
      path.lineTo(pts.last.dx, pts.last.dy);
    }

    smooth(left);
    path.lineTo(right.last.dx, right.last.dy);
    smooth(right.reversed.toList());
    path.close();
    canvas
      ..drawPath(path, body)
      ..drawPath(path, thin);
    // 看得到正面时画身体的中线、胸线和胯线。
    if (c > 0.3) {
      final off = n * (math.sin(yaw) * s.facing * wide(0.05, 0));
      canvas.drawLine(p(1.0) + off, p(0.05) + off * 0.7, detail);
      final chest = p(0.62);
      if (female) {
        for (final side in [-1.0, 1.0]) {
          canvas.drawArc(
            Rect.fromCircle(
              center: chest + n * (wide(0.042, 0) * side) + off * 0.6,
              radius: wide(0.034, 0),
            ),
            0.15 * math.pi,
            0.7 * math.pi,
            false,
            detail,
          );
        }
      } else {
        canvas.drawLine(
          chest - n * wide(0.05, 0),
          chest + n * wide(0.05, 0),
          detail,
        );
      }
      final a = p(0.12) - n * wide(0.08, 0), b = p(0.12) + n * wide(0.08, 0);
      final low = p(-0.12);
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(low.dx, low.dy, b.dx, b.dy),
        detail,
      );
    }
  }

  void head() {
    final c = f.headCenter;
    final turn = _rad(s.yaw + s.pose.headTurn);
    final rx =
        (0.05 * math.cos(turn).abs() + 0.058 * math.sin(turn).abs()) *
        h *
        s.head;
    final ry = f.headR * h;
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(_rad(s.pose.headTilt * 0.4 + s.pose.roll) * s.facing);
    final egg = Path()
      ..moveTo(0, -ry)
      ..cubicTo(rx * 0.6, -ry, rx, -ry * 0.55, rx, -ry * 0.05)
      ..cubicTo(rx, ry * 0.45, rx * 0.5, ry, 0, ry)
      ..cubicTo(-rx * 0.5, ry, -rx, ry * 0.45, -rx, -ry * 0.05)
      ..cubicTo(-rx, -ry * 0.55, -rx * 0.6, -ry, 0, -ry)
      ..close();
    canvas
      ..drawPath(egg, body)
      ..drawPath(egg, thin);
    // 脸的中线和眼线;背过去时看不到脸,不画。
    if (math.cos(turn) > -0.15) {
      final ox = math.sin(turn) * rx * 0.85 * s.facing;
      final eye = ry * (0.08 + s.pose.headTilt / 300);
      canvas
        ..save()
        ..clipPath(egg)
        ..drawPath(
          Path()
            ..moveTo(ox * 0.3, -ry)
            ..quadraticBezierTo(ox * 1.15, 0, ox * 0.55, ry * 0.97),
          detail,
        )
        ..drawPath(
          Path()
            ..moveTo(-rx, eye)
            ..quadraticBezierTo(ox * 0.4, eye + ry * 0.2, rx, eye),
          detail,
        )
        ..restore();
    }
    canvas.restore();
  }

  // 按离镜头远近排:远的先画。
  double depthOf(List<String> keys) =>
      keys.map((k) => f.depth[k]!).reduce((a, b) => a + b) / keys.length;
  final parts = <(double, VoidCallback)>[
    (depthOf(['shoulderA', 'elbowA', 'wristA']), () => limb('A', true)),
    (depthOf(['shoulderB', 'elbowB', 'wristB']), () => limb('B', true)),
    (depthOf(['hipA', 'kneeA', 'ankleA']) - 0.02, () => limb('A', false)),
    (depthOf(['hipB', 'kneeB', 'ankleB']) - 0.02, () => limb('B', false)),
    (0.0, torso),
    (f.depth['head']! + 0.005, head),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  for (final (_, draw) in parts) {
    draw();
  }
  if (selected) _dashed(canvas, f.bounds.inflate(4));
}

void _dashed(Canvas canvas, Rect box) {
  final dash = Paint()
    ..color = const Color(0xFF2563EB)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;
  for (final (a, b) in [
    (box.topLeft, box.topRight),
    (box.topRight, box.bottomRight),
    (box.bottomRight, box.bottomLeft),
    (box.bottomLeft, box.topLeft),
  ]) {
    final d = b - a;
    final len = d.distance;
    for (var t = 0.0; t < len; t += 8) {
      canvas.drawLine(
        a + d * (t / len),
        a + d * (math.min(t + 5, len) / len),
        dash,
      );
    }
  }
}

/// 排好的一个人偶:谁、算好的关节、放在哪(拖动从这里起算)。
typedef FigurePlacement = ({String name, FigurePose pose, Offset anchor});

/// 这一格的人偶怎么排(画和点选用同一份):按景别取景、按人数和格宽定大小、
/// 两人以上面对面;用户拖过、选过的([MangaPanel.figures])照用户的。
List<FigurePlacement> layoutFigures(
  Rect box,
  MangaPanel panel,
  List<MangaCharacter> characters,
) {
  final cast = panel.framing == '特写' && panel.cast.length > 1
      ? panel.cast.take(1).toList()
      : panel.cast.take(4).toList();
  if (cast.isEmpty || box.width <= 0 || box.height <= 0) return const [];
  final frame = _framing(panel.framing);
  MangaCharacter? character(String n) =>
      characters.where((c) => c.name == n).firstOrNull;
  final tallest = cast.map((n) => character(n)?.height ?? 165).reduce(math.max);
  // 一排排不下就缩小,两个人不叠在一起。
  final body = math.min(
    box.height * frame.body,
    box.width / (cast.length * frame.width),
  );
  final over = panel.angle == '过肩' && cast.length >= 2;
  final (head, legs) = switch (panel.angle) {
    '俯视' => (1.12, 0.84),
    '仰视' => (0.9, 1.14),
    _ => (1.0, 1.0),
  };
  final out = <FigurePlacement>[];
  for (final (i, name) in cast.indexed) {
    final c = character(name);
    final set = panel.figureOf(name);
    final k = (c?.height ?? 165) / tallest;
    final autoX = over
        ? box.left + box.width * (i == 0 ? 0.22 : 0.64)
        // 均匀铺开、两边留一点:两个人在 27% 和 73%,三个人在 19%、50%、81%。
        : box.left +
              box.width *
                  (0.5 + (i - (cast.length - 1) / 2) * 0.92 / cast.length);
    final autoY = frame.fromFeet
        ? box.top + box.height * frame.at
        : box.top + box.height * frame.at + body * (1 - k) * 0.9;
    final anchor = Offset(
      set.x == null ? autoX : box.left + box.width * set.x! / 1000,
      set.y == null ? autoY : box.top + box.height * set.y! / 1000,
    );
    final facing = set.facing != 0
        ? set.facing
        : cast.length == 1
        ? 1
        : (autoX < box.center.dx ? 1 : -1);
    final yaw = set.view.isNotEmpty
        ? _yawOf(set.view)
        : switch (panel.angle) {
            '背影' => 180.0,
            '侧面' => 90.0,
            _ when over && i == 0 => 155.0,
            _ => cast.length >= 2 ? 35.0 : 15.0,
          };
    final pose =
        poseNamed(set.pose) ??
        (i == 0 ? poseFromAction(panel.action) : mangaPoses.first);
    final spec = FigureSpec(
      anchor: anchor,
      fromFeet: frame.fromFeet,
      height: body * k * (over && i == 0 ? 1.45 : 1) * set.scale / 100,
      facing: facing,
      yaw: yaw,
      pose: pose,
      build: c?.build ?? '',
      head: head,
      legs: legs,
      color: figureColor(characters, name),
    );
    out.add((name: name, pose: FigurePose(spec), anchor: anchor));
  }
  return out;
}

/// 在格 [box](像素,格里正的那块)里画这格的人偶、名牌、气泡和标签。
/// 调用前要先按格的形状裁好。[mm] 是每毫米几像素,太小时(缩略图)不写字;
/// [inset] 让气泡让开左上角的顺序号;[selected] 是选中的人偶。
void paintPanelArt(
  Canvas canvas,
  Rect box,
  MangaPanel panel,
  List<MangaCharacter> characters, {
  required double mm,
  double inset = 0,
  String? selected,
}) {
  final placed = layoutFigures(box, panel, characters);
  final figures = <String, FigurePose>{};
  // 前后:脚更靠下的离镜头近,后画。
  for (final p in [
    ...placed,
  ]..sort((a, b) => a.pose.bounds.bottom.compareTo(b.pose.bounds.bottom))) {
    paintFigure(canvas, p.pose, selected: p.name == selected);
    figures[p.name] = p.pose;
  }
  if (mm < 1.2) return;
  for (final p in placed) {
    _nameTag(canvas, box, p.pose, p.name, mm);
  }
  _bubbles(canvas, box, panel, figures, mm, inset);
  _label(canvas, box, panel, mm);
}

/// 名牌放在头的一侧(和气泡相反的那边),出不了格。
void _nameTag(Canvas canvas, Rect box, FigurePose f, String name, double mm) {
  final tp = TextPainter(
    text: TextSpan(
      text: name,
      style: TextStyle(
        fontSize: (2.1 * mm).clamp(8, 12),
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1F2937),
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: 30 * mm);
  final head = f.headCenter, r = f.headR * f.spec.height;
  final away = head.dx < box.center.dx ? -1 : 1;
  final x = (away > 0 ? head.dx + r * 0.9 : head.dx - r * 0.9 - tp.width - 8)
      .clamp(box.left + 2, math.max(box.left + 2, box.right - tp.width - 10))
      .toDouble();
  final y = (head.dy + r * 0.2)
      .clamp(box.top + 2, math.max(box.top + 2, box.bottom - tp.height - 6))
      .toDouble();
  final rect = RRect.fromRectAndRadius(
    Rect.fromLTWH(x, y, tp.width + 8, tp.height + 3),
    const Radius.circular(8),
  );
  canvas
    ..drawRRect(rect, Paint()..color = Colors.white)
    ..drawRRect(
      rect,
      Paint()
        ..color = f.spec.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  tp.paint(canvas, Offset(x + 4, y + 1.5));
  tp.dispose();
}

/// 台词气泡:说话的人在格里就放在他头的上方、偏格中间那边,尾巴指过去;
/// 旁白是方框,放在左上角。同一个人的几句往上叠。
void _bubbles(
  Canvas canvas,
  Rect box,
  MangaPanel panel,
  Map<String, FigurePose> figures,
  double mm,
  double inset,
) {
  final said = <String, int>{};
  var narrations = 0;
  for (final line in panel.lines.take(3)) {
    final narration = line.speaker.isEmpty || line.speaker == '旁白';
    final tp = TextPainter(
      text: TextSpan(
        text: line.text,
        style: TextStyle(
          fontSize: (2.4 * mm).clamp(8, 14),
          height: 1.25,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: math.max(20, box.width * 0.42));
    final w = tp.width + 4 * mm, h = tp.height + 3 * mm;
    final f = narration ? null : figures[line.speaker];
    final Offset wanted;
    if (f == null) {
      final k = narration ? narrations++ : 0;
      wanted = Offset(
        box.left + w / 2 + 2 * mm + (narration ? 0 : box.width * 0.3),
        box.top + inset + h / 2 + 2 * mm + k * (h + mm),
      );
    } else {
      final k = said[line.speaker] = (said[line.speaker] ?? -1) + 1;
      final head = f.headTop;
      final toward = head.dx < box.center.dx ? 1 : -1;
      wanted = Offset(
        head.dx + toward * (w * 0.45 + f.headR * f.spec.height * 0.6),
        head.dy - h * 0.55 - k * (h + mm),
      );
    }
    final center = Offset(
      wanted.dx.clamp(
        box.left + w / 2 + mm,
        math.max(box.left + w / 2 + mm, box.right - w / 2 - mm),
      ),
      wanted.dy.clamp(
        box.top + inset + h / 2 + mm,
        math.max(box.top + inset + h / 2 + mm, box.bottom - h / 2 - mm),
      ),
    );
    final rect = Rect.fromCenter(center: center, width: w, height: h);
    final fill = Paint()..color = Colors.white;
    final edge = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    if (narration) {
      canvas
        ..drawRect(rect, fill)
        ..drawRect(rect, edge);
    } else {
      if (f != null) {
        final target = f.headTop + Offset(0, f.headR * f.spec.height * 0.5);
        final dir = target - center;
        if (dir.distance > 1) {
          final side = Offset(-dir.dy, dir.dx) / dir.distance * (w * 0.07);
          final tail = Path()
            ..moveTo(center.dx + side.dx, center.dy + side.dy)
            ..lineTo(target.dx, target.dy)
            ..lineTo(center.dx - side.dx, center.dy - side.dy)
            ..close();
          canvas
            ..drawPath(tail, fill)
            ..drawPath(tail, edge);
        }
      }
      canvas
        ..drawOval(rect, fill)
        ..drawOval(rect, edge);
    }
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }
}

/// 左下角一行小字:景别 · 角度,和动作。
void _label(Canvas canvas, Rect box, MangaPanel panel, double mm) {
  final shot = [
    panel.framing,
    panel.angle,
  ].where((s) => s.isNotEmpty).join(' · ');
  final text = [shot, panel.action].where((s) => s.isNotEmpty).join('  ');
  if (text.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: (2.1 * mm).clamp(8, 12), color: Colors.white),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: math.max(10, box.width - 4 * mm));
  final r = Rect.fromLTWH(
    box.left + mm,
    box.bottom - tp.height - 2.2 * mm,
    tp.width + 2 * mm,
    tp.height + 1.2 * mm,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(r, const Radius.circular(3)),
    Paint()..color = const Color(0xCC374151),
  );
  tp.paint(canvas, Offset(r.left + mm, r.top + 0.6 * mm));
  tp.dispose();
}
