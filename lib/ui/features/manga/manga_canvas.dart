import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/manga/manga.dart';
import '../../../core/harness/manga/manga_geometry.dart';
import '../../core/theme.dart';
import 'manga_board.dart';
import 'manga_figures.dart';

/// 格里字的高度(mm),跟着纸张缩放。
const _fontMm = 3.2;

/// 左上角阅读顺序号的高度(像素);格里的字从它下面开始。
const _badgeHeight = 17.0;

/// 格线手柄离鼠标多近算抓到(像素),缩小了也抓得住。
const _handlePx = 6.0;

/// 页面 → 画面的换算:每微米几像素,和纸张左上角在画面上的位置。
class _View {
  _View(Size size, MangaPage page, double pad)
    : scale = math.max(
        1e-9,
        math.min(
          (size.width - 2 * pad) / page.width,
          (size.height - 2 * pad) / page.height,
        ),
      ) {
    origin = Offset(
      (size.width - page.width * scale) / 2,
      (size.height - page.height * scale) / 2,
    );
  }

  final double scale;
  late final Offset origin;

  Offset point(MangaPoint p) =>
      Offset(origin.dx + p.x * scale, origin.dy + p.y * scale);

  Path path(MangaQuad q) =>
      Path()..addPolygon([for (final p in q) point(p)], true);

  /// 格里面那块正的矩形(不压到斜边)。
  Rect inner(MangaQuad q) => Rect.fromLTRB(
    point((x: math.max(q[0].x, q[3].x), y: 0)).dx,
    point((x: 0, y: math.max(q[0].y, q[1].y))).dy,
    point((x: math.min(q[1].x, q[2].x), y: 0)).dx,
    point((x: 0, y: math.min(q[3].y, q[2].y))).dy,
  );

  /// 画面上的点 → 页面坐标(微米)。
  (int, int) toPage(Offset p) => (
    ((p.dx - origin.dx) / scale).round(),
    ((p.dy - origin.dy) / scale).round(),
  );
}

/// 画一页分镜:纸、格框,格里是人偶草图([figures])或文字;[overlays] 时再画
/// 选中框和阅读顺序,[flow] 时画阅读动线(导出、缩略图不画这些)。纸总是白的。
class MangaPainter extends CustomPainter {
  MangaPainter({
    required this.page,
    this.characters = const [],
    this.selected,
    this.overlays = true,
    this.figures = true,
    this.text = true,
    this.flow = false,
    this.pad = 16,
    this.hoverHandle,
    this.selectedFigure,
  });

  final MangaPage page;
  final List<MangaCharacter> characters;
  final String? selected;
  final bool overlays, figures, text, flow;
  final double pad;
  final String? hoverHandle;

  /// 选中的人偶(描虚框)。
  final ({String panel, String name})? selectedFigure;

  @override
  void paint(Canvas canvas, Size size) {
    final view = _View(size, page, pad);
    final paper = Rect.fromLTWH(
      view.origin.dx,
      view.origin.dy,
      page.width * view.scale,
      page.height * view.scale,
    );
    if (pad > 0) {
      canvas.drawRect(
        paper.shift(const Offset(0, 2)),
        Paint()
          ..color = const Color(0x22000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas
      ..drawRect(paper, Paint()..color = Colors.white)
      ..save()
      ..clipRect(paper);
    final quads = panelQuads(page);
    final outer = panelQuads(page, bleed: true);
    final order = readingOrder(page);
    final mm = 1000 * view.scale;
    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.miter
      ..strokeWidth = math.max(0.6, page.border * view.scale);
    for (final id in order) {
      final shape = view.path(outer[id]!);
      final box = view.inner(quads[id]!);
      final panel = page.panels[id]!;
      if (text && !panel.isBlank) {
        canvas
          ..save()
          ..clipPath(shape);
        figures
            ? paintPanelArt(
                canvas,
                box,
                panel,
                characters,
                mm: mm,
                // 让开左上角的阅读顺序号。
                inset: overlays ? _badgeHeight + 4 : 0,
                selected: selectedFigure?.panel == id
                    ? selectedFigure!.name
                    : null,
              )
            : _content(canvas, box, panel, view.scale);
        canvas.restore();
      }
      canvas.drawPath(shape, border);
    }
    canvas.restore();
    if (flow) _flow(canvas, view, quads, order);
    if (!overlays) return;
    for (final (i, id) in order.indexed) {
      _badge(canvas, view.inner(quads[id]!), i + 1, page.panels[id]!.locked);
      if (id == selected) {
        canvas.drawPath(
          view.path(quads[id]!),
          Paint()
            ..color = PennaColors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }
    for (final h in handlesOf(page)) {
      if (h.path != hoverHandle) continue;
      canvas.drawLine(
        view.point(h.a),
        view.point(h.b),
        Paint()
          ..color = PennaColors.primary.withValues(alpha: 0.45)
          ..strokeWidth = math.max(4, page.gap * view.scale)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// 阅读动线:按顺序连起各格的中心,虚线带箭头。
  void _flow(
    Canvas canvas,
    _View view,
    Map<String, MangaQuad> quads,
    List<String> order,
  ) {
    if (order.length < 2) return;
    final points = [
      for (final id in order)
        quads[id]!.map(view.point).reduce((a, b) => a + b) / 4,
    ];
    final line = Paint()
      ..color = const Color(0xFFF08A4B)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      final d = b - a;
      final length = d.distance;
      if (length < 1) continue;
      final unit = d / length;
      for (var t = 0.0; t < length - 10; t += 10) {
        canvas.drawLine(a + unit * t, a + unit * math.min(t + 6, length), line);
      }
      final tip = b - unit * 14;
      final side = Offset(-unit.dy, unit.dx) * 5;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx + unit.dx * 8, tip.dy + unit.dy * 8)
          ..lineTo(tip.dx + side.dx, tip.dy + side.dy)
          ..lineTo(tip.dx - side.dx, tip.dy - side.dy)
          ..close(),
        Paint()..color = line.color,
      );
      canvas.drawCircle(a, 3.5, Paint()..color = line.color);
    }
  }

  /// 文字模式:景别·角度、出场、动作、台词,放不下的裁掉。
  void _content(Canvas canvas, Rect r, MangaPanel p, double scale) {
    final size = _fontMm * 1000 * scale;
    TextSpan line(
      String s, {
      Color color = const Color(0xFF333333),
      bool bold = false,
    }) => TextSpan(
      text: '$s\n',
      style: TextStyle(
        fontSize: size,
        height: 1.35,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    );
    final shot = [p.framing, p.angle].where((s) => s.isNotEmpty).join(' · ');
    final painter = TextPainter(
      text: TextSpan(
        children: [
          if (shot.isNotEmpty)
            line(shot, color: const Color(0xFF6B7280), bold: true),
          if (p.cast.isNotEmpty)
            line(p.cast.join('、'), color: const Color(0xFF2563EB)),
          if (p.action.isNotEmpty) line(p.action),
          for (final l in p.lines)
            line(l.speaker.isEmpty ? '「${l.text}」' : '${l.speaker}「${l.text}」'),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(1, r.width - size * 1.2));
    canvas
      ..save()
      ..translate(
        r.left + size * 0.6,
        r.top + size * 0.5 + (overlays ? _badgeHeight + 2 : 0),
      );
    painter.paint(canvas, Offset.zero);
    canvas.restore();
    painter.dispose();
  }

  /// 左上角的阅读顺序号(锁着的再标一把锁)。
  void _badge(Canvas canvas, Rect r, int n, bool locked) {
    final label = TextPainter(
      text: TextSpan(
        text: locked ? '$n ${String.fromCharCode(Icons.lock.codePoint)}' : '$n',
        style: TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontFamilyFallback: [Icons.lock.fontFamily!],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromLTWH(
      r.left + 3,
      r.top + 3,
      label.width + 10,
      _badgeHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(9)),
      Paint()..color = PennaColors.primary,
    );
    label.paint(
      canvas,
      Offset(box.left + 5, box.top + (_badgeHeight - label.height) / 2),
    );
    label.dispose();
  }

  @override
  bool shouldRepaint(MangaPainter old) =>
      old.page != page ||
      old.characters != characters ||
      old.selected != selected ||
      old.hoverHandle != hoverHandle ||
      old.overlays != overlays ||
      old.figures != figures ||
      old.flow != flow ||
      old.selectedFigure != selectedFigure;
}

/// 点到线段的距离。
double _distance(Offset p, Offset a, Offset b) {
  final d = b - a;
  final l2 = d.dx * d.dx + d.dy * d.dy;
  if (l2 == 0) return (p - a).distance;
  final t = (((p - a).dx * d.dx + (p - a).dy * d.dy) / l2).clamp(0.0, 1.0);
  return (p - (a + d * t)).distance;
}

/// 画布:点格选中,按住格线拖着改大小(松手才算一步,Esc 取消)。
class MangaCanvas extends StatefulWidget {
  const MangaCanvas({super.key, required this.board});

  final MangaBoard board;

  @override
  State<MangaCanvas> createState() => _MangaCanvasState();
}

/// 抓着的人偶:哪一格、谁、开始时脚底(或头顶)在哪、鼠标在哪、格里那块正的矩形。
typedef _Grab = ({
  String panel,
  String name,
  Offset anchor,
  Offset from,
  Rect box,
});

class _MangaCanvasState extends State<MangaCanvas> {
  final _focus = FocusNode();
  String? _hover, _dragging;
  bool _overFigure = false;
  _Grab? _grab;

  MangaBoard get board => widget.board;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// [p] 落在哪条格线的手柄上(离沟带中线够近)。
  String? _handleAt(_View view, MangaPage page, Offset p) {
    final reach = math.max(_handlePx, page.gap * view.scale / 2 + 2);
    for (final h in handlesOf(page)) {
      if (_distance(p, view.point(h.a), view.point(h.b)) <= reach) {
        return h.path;
      }
    }
    return null;
  }

  String? _panelAt(_View view, MangaPage page, Offset p) {
    final (x, y) = view.toPage(p);
    for (final MapEntry(key: id, value: q) in panelQuads(page).entries) {
      if (quadContains(q, x, y)) return id;
    }
    return null;
  }

  /// [p] 点在哪个人偶上(只看它所在那一格里的部分);人偶关着时没有。
  _Grab? _figureAt(_View view, MangaPage page, Offset p) {
    if (!board.showFigures) return null;
    final id = _panelAt(view, page, p);
    final panel = id == null ? null : page.panels[id];
    if (panel == null) return null;
    final box = view.inner(panelQuads(page)[id]!);
    final placed = layoutFigures(box, panel, board.project.characters);
    for (final f in placed.reversed) {
      if (f.pose.bounds.contains(p)) {
        return (panel: id!, name: f.name, anchor: f.anchor, from: p, box: box);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ListenableBuilder(
      listenable: board,
      builder: (context, _) {
        final page = board.canvasPage;
        final view = _View(box.biggest, page, 16);
        final axis = _hover == null
            ? null
            : handlesOf(page).where((h) => h.path == _hover).firstOrNull?.axis;
        // 看着候选时只能看,不能点选、拖线。
        final browsing = board.previewing != null;
        return Focus(
          focusNode: _focus,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent &&
                e.logicalKey == LogicalKeyboardKey.escape &&
                _dragging != null) {
              _dragging = null;
              board.cancelDrag();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            cursor: switch (axis) {
              MangaAxis.x => SystemMouseCursors.resizeColumn,
              MangaAxis.y => SystemMouseCursors.resizeRow,
              null when _grab != null => SystemMouseCursors.grabbing,
              null when _overFigure => SystemMouseCursors.grab,
              null => SystemMouseCursors.basic,
            },
            onHover: browsing
                ? null
                : (e) {
                    final h = _handleAt(view, page, e.localPosition);
                    final over =
                        h == null &&
                        _figureAt(view, page, e.localPosition) != null;
                    if (h != _hover || over != _overFigure) {
                      setState(() {
                        _hover = h;
                        _overFigure = over;
                      });
                    }
                  },
            onExit: (_) => setState(() {
              _hover = null;
              _overFigure = false;
            }),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: browsing
                  ? null
                  : (d) {
                      _focus.requestFocus();
                      if (_handleAt(view, page, d.localPosition) != null) {
                        return;
                      }
                      final f = _figureAt(view, page, d.localPosition);
                      f == null
                          ? board.select(_panelAt(view, page, d.localPosition))
                          : board.selectFigure(f.panel, f.name);
                    },
              onPanStart: browsing
                  ? null
                  : (d) {
                      _focus.requestFocus();
                      _dragging = _handleAt(view, page, d.localPosition);
                      if (_dragging != null) return;
                      final f = _figureAt(view, page, d.localPosition);
                      if (f == null) return;
                      setState(() => _grab = f);
                      board.selectFigure(f.panel, f.name);
                    },
              onPanUpdate: (d) {
                final grab = _grab;
                if (grab != null) {
                  final at = grab.anchor + (d.localPosition - grab.from);
                  board.moveFigure(
                    grab.panel,
                    grab.name,
                    ((at.dx - grab.box.left) / grab.box.width * 1000).round(),
                    ((at.dy - grab.box.top) / grab.box.height * 1000).round(),
                  );
                  return;
                }
                final path = _dragging;
                if (path == null) return;
                final h = handlesOf(page)
                    .where((h) => h.path == path)
                    .firstOrNull;
                if (h == null) return;
                final (x, y) = view.toPage(d.localPosition);
                board.dragTo(path, h.axis == MangaAxis.x ? x : y);
              },
              onPanEnd: (_) {
                if (_grab != null) {
                  setState(() => _grab = null);
                  board.endFigureDrag();
                  return;
                }
                if (_dragging == null) return;
                _dragging = null;
                board.endDrag();
              },
              child: CustomPaint(
                size: box.biggest,
                painter: MangaPainter(
                  page: page,
                  characters: board.project.characters,
                  selected: browsing ? null : board.selected,
                  selectedFigure: browsing ? null : board.selectedFigure,
                  hoverHandle: _dragging ?? _hover,
                  figures: board.showFigures,
                  flow: board.showFlow,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// 一页导出成 PNG:按 [dpi] 换算成品尺寸的像素,不带选中框和阅读顺序号。
/// [figures] 时格里画人偶草图,不然写字。
Future<Uint8List?> mangaPng(
  MangaPage page, {
  List<MangaCharacter> characters = const [],
  bool figures = true,
  int dpi = 300,
}) async {
  final w = (page.width * dpi / 25400).round();
  final h = (page.height * dpi / 25400).round();
  final recorder = ui.PictureRecorder();
  MangaPainter(
    page: page,
    characters: characters,
    figures: figures,
    overlays: false,
    pad: 0,
  ).paint(Canvas(recorder), Size(w.toDouble(), h.toDouble()));
  final image = await recorder.endRecording().toImage(w, h);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
