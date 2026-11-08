import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/harness/manga/manga.dart';

// 格里的人偶参考:每个出场角色画一个带明暗的关节人偶(头、躯干、胯、四肢),
// 按景别定大小和取景,按动作摆姿势,两个人时面对面;再画名牌、台词气泡和景别标签。
// 只是给人看站位和镜头的草图,不是解剖准确的人体。

/// 几种姿势,从动作文字里认(见 [poseOf])。
enum MangaPose { stand, point, wave, run, sit, fight, crouch, reach, think }

/// 动作里出现这些字就摆那个姿势;都没有是站着。
const _poseWords = <MangaPose, List<String>>{
  MangaPose.sit: ['坐'],
  MangaPose.crouch: ['蹲', '跪'],
  MangaPose.run: ['跑', '冲', '奔', '追'],
  MangaPose.fight: ['打', '踢', '拳', '砍', '挥剑', '战斗', '攻击'],
  MangaPose.point: ['指'],
  MangaPose.wave: ['挥手', '举手', '招手', '抬手', '扬手'],
  MangaPose.reach: ['抱', '拥', '伸手', '递', '拉'],
  MangaPose.think: ['托腮', '思考', '沉思', '捂'],
};

MangaPose poseOf(String action) {
  for (final MapEntry(key: pose, value: words) in _poseWords.entries) {
    if (words.any(action.contains)) return pose;
  }
  return MangaPose.stand;
}

/// 角色的颜色,按设定里的先后轮换。
const _palette = [
  Color(0xFF6E9BEA),
  Color(0xFFEC8E7D),
  Color(0xFF69BE93),
  Color(0xFFA78BE3),
  Color(0xFFE5B65C),
  Color(0xFF5CC3CF),
];

Color figureColor(List<MangaCharacter> all, String name) {
  final i = all.indexWhere((c) => c.name == name);
  return i < 0 ? const Color(0xFFB0B7C3) : _palette[i % _palette.length];
}

/// 四肢的角度(度,0 是朝下,正的往前/往外):肩、肘(相对上臂),髋、膝(相对大腿)。
typedef _Limbs = ({
  double armA,
  double elbowA,
  double armB,
  double elbowB,
  double legA,
  double kneeA,
  double legB,
  double kneeB,
});

_Limbs _limbs(MangaPose p) => switch (p) {
  MangaPose.stand => (
    armA: 12,
    elbowA: 8,
    armB: 12,
    elbowB: 8,
    legA: 4,
    kneeA: 0,
    legB: 4,
    kneeB: 0,
  ),
  MangaPose.point => (
    armA: 92,
    elbowA: 0,
    armB: 10,
    elbowB: 6,
    legA: 6,
    kneeA: 0,
    legB: 3,
    kneeB: 0,
  ),
  MangaPose.wave => (
    armA: 155,
    elbowA: 25,
    armB: 12,
    elbowB: 8,
    legA: 4,
    kneeA: 0,
    legB: 4,
    kneeB: 0,
  ),
  MangaPose.run => (
    armA: 55,
    elbowA: 70,
    armB: -45,
    elbowB: 60,
    legA: 45,
    kneeA: -75,
    legB: -30,
    kneeB: -55,
  ),
  MangaPose.sit => (
    armA: 25,
    elbowA: 40,
    armB: 20,
    elbowB: 35,
    legA: 88,
    kneeA: -88,
    legB: 84,
    kneeB: -84,
  ),
  MangaPose.fight => (
    armA: 85,
    elbowA: 8,
    armB: 45,
    elbowB: 100,
    legA: 22,
    kneeA: -10,
    legB: -22,
    kneeB: 0,
  ),
  MangaPose.crouch => (
    armA: 40,
    elbowA: 30,
    armB: 30,
    elbowB: 30,
    legA: 75,
    kneeA: -140,
    legB: 60,
    kneeB: -130,
  ),
  MangaPose.reach => (
    armA: 75,
    elbowA: 15,
    armB: 70,
    elbowB: 20,
    legA: 6,
    kneeA: 0,
    legB: 3,
    kneeB: 0,
  ),
  MangaPose.think => (
    armA: 20,
    elbowA: 140,
    armB: 15,
    elbowB: 70,
    legA: 4,
    kneeA: 0,
    legB: 4,
    kneeB: 0,
  ),
};

/// 朝向:正面(带一点侧转)、侧面、背面。
enum _View { front, side, back }

/// 一个人偶怎么画:脚底或头顶放在哪、全身多高、朝哪边、什么姿势。
typedef _Figure = ({
  double x,
  double y,
  bool fromFeet,
  double height,
  int facing,
  _View view,
  MangaPose pose,
  Color color,
  double head,
  double legs,
});

/// 关节的位置(像素),先按头顶在原点算,再整体挪到该在的地方。
class _Joints {
  _Joints(_Figure f) {
    final h = f.height;
    final side = f.view == _View.side;
    final shoulderX = (side ? 0.045 : 0.105) * h;
    final hipX = (side ? 0.03 : 0.065) * h;
    headR = 0.065 * h * f.head;
    final l = _limbs(f.pose);
    // 领先的一侧(A)在朝向那边。侧面时胳膊腿都往前(朝向)摆;
    // 正面、背面时各往自己那一侧外面摆。
    final signA = f.facing, signB = side ? f.facing : -f.facing;
    Offset limb(Offset from, double angle, double length, int sign) {
      final a = angle * math.pi / 180;
      return from + Offset(math.sin(a) * sign, math.cos(a)) * length;
    }

    final headAt = Offset(0, headR);
    final neckAt = Offset(0, headR * 2 + 0.02 * h);
    final shoulderY = neckAt.dy + 0.025 * h;
    final hipY = shoulderY + 0.33 * h;
    final sA = Offset(shoulderX * f.facing, shoulderY);
    final sB = Offset(-shoulderX * f.facing, shoulderY);
    final hA = Offset(hipX * f.facing, hipY);
    final hB = Offset(-hipX * f.facing, hipY);
    final eA = limb(sA, l.armA, 0.155 * h, signA);
    final eB = limb(sB, l.armB, 0.155 * h, signB);
    final legLen = 0.235 * h * f.legs;
    final kA = limb(hA, l.legA, legLen, signA);
    final kB = limb(hB, l.legB, legLen, signB);
    final fA = limb(kA, l.legA + l.kneeA, legLen, signA);
    final fB = limb(kB, l.legB + l.kneeB, legLen, signB);
    final lowest = [fA.dy, fB.dy, kA.dy, kB.dy].reduce(math.max);
    // 全身的从脚底排(脚踩在 y 上),半身的从头顶排(头顶在 y 上)。
    final shift = f.fromFeet
        ? Offset(f.x, f.y - lowest - 0.012 * h)
        : Offset(f.x, f.y);
    head = headAt + shift;
    neck = neckAt + shift;
    shoulderA = sA + shift;
    shoulderB = sB + shift;
    hipA = hA + shift;
    hipB = hB + shift;
    elbowA = eA + shift;
    elbowB = eB + shift;
    handA = limb(eA, l.armA + l.elbowA, 0.15 * h, signA) + shift;
    handB = limb(eB, l.armB + l.elbowB, 0.15 * h, signB) + shift;
    kneeA = kA + shift;
    kneeB = kB + shift;
    footA = fA + shift;
    footB = fB + shift;
  }

  late final double headR;
  late final Offset head, neck, shoulderA, shoulderB, hipA, hipB;
  late final Offset elbowA, handA, elbowB, handB, kneeA, footA, kneeB, footB;
}

Color _shade(Color c, double amount) => Color.lerp(c, Colors.black, amount)!;
Color _light(Color c, double amount) => Color.lerp(c, Colors.white, amount)!;

/// 一节胳膊腿:深色描边、本色、亮面三层,看起来是圆柱。
void _segment(Canvas canvas, Offset a, Offset b, double width, Color color) {
  Paint stroke(Color c, double w) => Paint()
    ..color = c
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  canvas
    ..drawLine(a, b, stroke(_shade(color, 0.45), width + 1.4))
    ..drawLine(a, b, stroke(color, width));
  final lift = Offset(-width * 0.16, -width * 0.12);
  canvas.drawLine(
    a + lift,
    b + lift,
    stroke(_light(color, 0.35), width * 0.38),
  );
}

void _ball(Canvas canvas, Offset c, double r, Color color) {
  canvas
    ..drawCircle(c, r + 0.7, Paint()..color = _shade(color, 0.45))
    ..drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.45),
          colors: [_light(color, 0.45), color, _shade(color, 0.25)],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
}

void _paintFigure(Canvas canvas, _Figure f) {
  final j = _Joints(f);
  final h = f.height;
  final c = f.color;
  final back = _shade(c, 0.18);
  // 后面那一侧的胳膊腿先画、颜色暗一点。
  _segment(canvas, j.hipB, j.kneeB, 0.075 * h, back);
  _segment(canvas, j.kneeB, j.footB, 0.06 * h, back);
  _segment(canvas, j.shoulderB, j.elbowB, 0.052 * h, back);
  _segment(canvas, j.elbowB, j.handB, 0.044 * h, back);
  _ball(canvas, j.handB, 0.028 * h, back);
  // 躯干:胸廓宽、腰收窄,中间一道分节线(关节人偶的样子);左亮右暗。
  final cx = (j.shoulderA.dx + j.shoulderB.dx) / 2;
  final sx = (j.shoulderA.dx - j.shoulderB.dx).abs() / 2;
  final top = j.shoulderA.dy - 0.015 * h;
  final chestY = j.shoulderA.dy + 0.19 * h;
  final waistY = (j.hipA.dy + j.hipB.dy) / 2 - 0.05 * h;
  final chestW = sx * 0.86, waistW = sx * 0.58;
  final torso = Path()
    ..moveTo(cx - sx, top)
    ..lineTo(cx + sx, top)
    ..quadraticBezierTo(cx + sx * 1.04, top + 0.09 * h, cx + chestW, chestY)
    ..quadraticBezierTo(
      cx + chestW * 0.9,
      chestY + 0.06 * h,
      cx + waistW,
      waistY,
    )
    ..lineTo(cx - waistW, waistY)
    ..quadraticBezierTo(
      cx - chestW * 0.9,
      chestY + 0.06 * h,
      cx - chestW,
      chestY,
    )
    ..quadraticBezierTo(cx - sx * 1.04, top + 0.09 * h, cx - sx, top)
    ..close();
  final box = torso.getBounds();
  canvas
    ..drawPath(
      torso,
      Paint()
        ..shader = LinearGradient(colors: [_light(c, 0.3), c, _shade(c, 0.22)])
            .createShader(box),
    )
    ..drawPath(
      torso,
      Paint()
        ..color = _shade(c, 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  canvas.drawArc(
    Rect.fromCenter(
      center: Offset(cx, chestY),
      width: chestW * 2,
      height: 0.05 * h,
    ),
    0,
    math.pi,
    false,
    Paint()
      ..color = _shade(c, 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
  // 胯。
  final pelvis = Rect.fromCenter(
    center: (j.hipA + j.hipB) / 2 + Offset(0, -0.015 * h),
    width: (j.hipA.dx - j.hipB.dx).abs() + 0.08 * h,
    height: 0.1 * h,
  );
  canvas
    ..drawOval(pelvis, Paint()..color = _shade(c, 0.08))
    ..drawOval(
      pelvis,
      Paint()
        ..color = _shade(c, 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  _segment(canvas, j.neck - Offset(0, 0.03 * h), j.neck, 0.04 * h, c);
  // 前面那一侧。
  _segment(canvas, j.hipA, j.kneeA, 0.075 * h, c);
  _segment(canvas, j.kneeA, j.footA, 0.06 * h, c);
  _ball(canvas, j.kneeA, 0.03 * h, c);
  _segment(canvas, j.shoulderA, j.elbowA, 0.052 * h, c);
  _segment(canvas, j.elbowA, j.handA, 0.044 * h, c);
  _ball(canvas, j.elbowA, 0.024 * h, c);
  _ball(canvas, j.handA, 0.028 * h, c);
  _head(canvas, j.head, j.headR, f);
}

/// 头:带高光的球,脸的朝向用十字线标出(背面不画)。
void _head(Canvas canvas, Offset center, double r, _Figure f) {
  _ball(canvas, center, r, f.color);
  if (f.view == _View.back) return;
  final line = Paint()
    ..color = _shade(f.color, 0.5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(0.8, r * 0.07);
  // 脸的中线往朝向偏:侧面偏得多,正面偏一点(四分之三侧)。
  final turn = f.view == _View.side ? 0.75 : 0.3;
  final mid = center.dx + r * turn * f.facing;
  final arc = Rect.fromCenter(
    center: Offset(mid, center.dy),
    width: r * (1 - turn) * 1.4 + 1,
    height: r * 2,
  );
  canvas
    ..save()
    ..clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)))
    ..drawArc(arc, -math.pi / 2, math.pi, false, line)
    ..drawLine(
      Offset(center.dx - r, center.dy + r * 0.15),
      Offset(center.dx + r, center.dy + r * 0.15),
      line,
    )
    ..restore();
}

/// 景别 → 全身多高(格高的几倍)、从脚底排还是从头顶排、头顶或脚底的位置(格高的几成)。
({double body, bool fromFeet, double at}) _framing(String framing) =>
    switch (framing) {
      '远景' => (body: 0.42, fromFeet: true, at: 0.9),
      '中景' => (body: 1.65, fromFeet: false, at: 0.13),
      '近景' => (body: 3.0, fromFeet: false, at: 0.1),
      '特写' => (body: 6.0, fromFeet: false, at: 0.05),
      _ => (body: 0.82, fromFeet: true, at: 0.96),
    };

/// 在格 [box](像素,格里正的那块)里画这格的人偶、名牌、气泡和标签。
/// 调用前要先按格的形状裁好。[mm] 是每毫米几像素,太小时(缩略图)不写字。
void paintPanelArt(
  Canvas canvas,
  Rect box,
  MangaPanel panel,
  List<MangaCharacter> characters, {
  required double mm,
  double inset = 0,
}) {
  final words = mm >= 1.2;
  final cast = panel.framing == '特写' && panel.cast.length > 1
      ? panel.cast.take(1).toList()
      : panel.cast.take(4).toList();
  final heads = <String, Offset>{};
  if (cast.isNotEmpty) {
    final frame = _framing(panel.framing);
    final tallest = cast
        .map(
          (n) =>
              characters.where((c) => c.name == n).firstOrNull?.height ?? 165,
        )
        .reduce(math.max);
    var body = box.height * frame.body;
    // 全身的几个人排不下时缩小。
    if (frame.fromFeet) {
      final room = box.width / (cast.length * 0.34);
      if (body > room) body = room;
    }
    final over = panel.angle == '过肩' && cast.length >= 2;
    final (head, legs) = switch (panel.angle) {
      '俯视' => (1.15, 0.8),
      '仰视' => (0.9, 1.15),
      _ => (1.0, 1.0),
    };
    for (final (i, name) in cast.indexed) {
      final c = characters.where((c) => c.name == name).firstOrNull;
      final k = (c?.height ?? 165) / tallest;
      final x = over
          ? box.left + box.width * (i == 0 ? 0.2 : 0.64)
          : box.left + box.width * (i + 1) / (cast.length + 1);
      final facing = cast.length == 1 ? 1 : (x < box.center.dx ? 1 : -1);
      final view = switch (panel.angle) {
        '背影' => _View.back,
        '侧面' => _View.side,
        _ when over && i == 0 => _View.back,
        _ => _View.front,
      };
      final size = body * k * (over && i == 0 ? 1.5 : 1);
      final y = frame.fromFeet
          ? box.top + box.height * frame.at
          : box.top + box.height * frame.at + body * (1 - k) * 0.9;
      final figure = (
        x: x,
        y: y,
        fromFeet: frame.fromFeet,
        height: size,
        facing: facing,
        view: view,
        pose: i == 0 ? poseOf(panel.action) : MangaPose.stand,
        color: figureColor(characters, name),
        head: head,
        legs: legs,
      );
      _paintFigure(canvas, figure);
      final j = _Joints(figure);
      heads[name] = j.head - Offset(0, j.headR);
      if (words) {
        _nameTag(
          canvas,
          j.head + Offset(j.headR * 0.9, -j.headR),
          name,
          figure.color,
          mm,
        );
      }
    }
  }
  if (words) {
    _bubbles(canvas, box, panel, heads, mm, inset);
    _label(canvas, box, panel, mm);
  }
}

void _nameTag(Canvas canvas, Offset at, String name, Color color, double mm) {
  final tp = TextPainter(
    text: TextSpan(
      text: name,
      style: TextStyle(
        fontSize: (2.2 * mm).clamp(8, 13),
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1F2937),
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: 30 * mm);
  final r = RRect.fromRectAndRadius(
    Rect.fromLTWH(at.dx, at.dy, tp.width + 8, tp.height + 3),
    const Radius.circular(8),
  );
  canvas
    ..drawRRect(r, Paint()..color = Colors.white)
    ..drawRRect(
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  tp.paint(canvas, Offset(at.dx + 4, at.dy + 1.5));
  tp.dispose();
}

/// 台词气泡:说话的人在格里就贴着他的头、尾巴指过去;旁白是方框,放在左上角。
void _bubbles(
  Canvas canvas,
  Rect box,
  MangaPanel panel,
  Map<String, Offset> heads,
  double mm,
  double inset,
) {
  final lines = panel.lines.take(3).toList();
  for (final (i, line) in lines.indexed) {
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
    final head = heads[line.speaker];
    var center = head == null || narration
        ? Offset(
            box.left + w / 2 + 2 * mm + (narration ? 0 : box.width * 0.3),
            box.top + h / 2 + 4 * mm + i * (h + mm),
          )
        : Offset(
            head.dx + (head.dx < box.center.dx ? w * 0.55 : -w * 0.55),
            head.dy - h * 0.7 - i * (h * 0.4),
          );
    center = Offset(
      center.dx.clamp(
        box.left + w / 2 + mm,
        math.max(box.left + w / 2 + mm, box.right - w / 2 - mm),
      ),
      center.dy.clamp(
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
      if (head != null) {
        final dir = (head - center);
        final side = Offset(-dir.dy, dir.dx) / dir.distance * (w * 0.08);
        final tail = Path()
          ..moveTo(center.dx + side.dx, center.dy + side.dy)
          ..lineTo(head.dx, head.dy)
          ..lineTo(center.dx - side.dx, center.dy - side.dy)
          ..close();
        canvas
          ..drawPath(tail, fill)
          ..drawPath(tail, edge);
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
