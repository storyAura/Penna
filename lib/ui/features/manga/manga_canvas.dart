import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/harness/manga/manga.dart';
import '../../../core/harness/manga/manga_geometry.dart';
import '../../core/theme.dart';
import 'manga_board.dart';

/// 格里字的高度(mm),跟着纸张缩放。
const _fontMm = 3.2;

/// 左上角阅读顺序号的高度(像素);格里的字从它下面开始。
const _badgeHeight = 17.0;

/// 格线手柄在屏幕上至少这么宽(像素),缩小了也抓得住。
const _handlePx = 10.0;

/// 页面 → 画面的换算:每微米几像素,和纸张左上角在画面上的位置。
class _View {
  _View(Size size, MangaPage page, double pad)
    : scale = [
        (size.width - 2 * pad) / page.width,
        (size.height - 2 * pad) / page.height,
      ].reduce((a, b) => a < b ? a : b).clamp(1e-9, double.infinity),
      origin = Offset.zero {
    origin = Offset(
      (size.width - page.width * scale) / 2,
      (size.height - page.height * scale) / 2,
    );
  }

  final double scale;
  Offset origin;

  Rect rect(MangaRect r) => Rect.fromLTWH(
    origin.dx + r.x * scale,
    origin.dy + r.y * scale,
    r.w * scale,
    r.h * scale,
  );

  /// 画面上的点 → 页面坐标(微米)。
  (int, int) toPage(Offset p) => (
    ((p.dx - origin.dx) / scale).round(),
    ((p.dy - origin.dy) / scale).round(),
  );
}

/// 画一页分镜:纸、格框、格里的景别和台词;[overlays] 时再画选中框和阅读顺序
/// (导出、缩略图不画)。纸总是白的,深色模式下也一样。
class MangaPainter extends CustomPainter {
  MangaPainter({
    required this.page,
    this.selected,
    this.overlays = true,
    this.text = true,
    this.pad = 16,
    this.hoverHandle,
  });

  final MangaPage page;
  final String? selected;
  final bool overlays, text;
  final double pad;
  final String? hoverHandle;

  @override
  void paint(Canvas canvas, Size size) {
    final view = _View(size, page, pad);
    final paper = view.rect((x: 0, y: 0, w: page.width, h: page.height));
    if (pad > 0) {
      canvas.drawRect(
        paper.shift(const Offset(0, 2)),
        Paint()
          ..color = const Color(0x22000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawRect(paper, Paint()..color = Colors.white);
    final rects = panelRects(page);
    final order = readingOrder(page);
    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = (500 * view.scale).clamp(0.6, 3);
    for (final (i, id) in order.indexed) {
      final r = view.rect(rects[id]!);
      final panel = page.panels[id]!;
      if (text) _content(canvas, r, panel, view.scale);
      canvas.drawRect(r, border);
      if (!overlays) continue;
      _badge(canvas, r, i + 1, panel.locked);
      if (id == selected) {
        canvas.drawRect(
          r.deflate(1.5),
          Paint()
            ..color = PennaColors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    }
    if (overlays && hoverHandle != null) {
      for (final h in handlesOf(page)) {
        if (h.path != hoverHandle) continue;
        canvas.drawRect(
          view.rect(h.gutter).inflate(1),
          Paint()..color = PennaColors.primary.withValues(alpha: 0.35),
        );
      }
    }
  }

  /// 格里的字:景别·角度、出场、动作、台词,放不下的裁掉。
  void _content(Canvas canvas, Rect r, MangaPanel p, double scale) {
    if (p.isBlank) return;
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
    )..layout(maxWidth: (r.width - size * 1.2).clamp(1, double.infinity));
    canvas
      ..save()
      ..clipRect(r.deflate(1))
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
      old.selected != selected ||
      old.hoverHandle != hoverHandle ||
      old.overlays != overlays;
}

/// 画布:点格选中,按住格线拖着改大小(松手才算一步,Esc 取消)。
class MangaCanvas extends StatefulWidget {
  const MangaCanvas({super.key, required this.board});

  final MangaBoard board;

  @override
  State<MangaCanvas> createState() => _MangaCanvasState();
}

class _MangaCanvasState extends State<MangaCanvas> {
  final _focus = FocusNode();
  String? _hover, _dragging;

  MangaBoard get board => widget.board;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// [p] 落在哪条格线的手柄上。
  String? _handleAt(_View view, MangaPage page, Offset p) {
    for (final h in handlesOf(page)) {
      var r = view.rect(h.gutter);
      if (h.axis == MangaAxis.x && r.width < _handlePx) {
        r = Rect.fromCenter(
          center: r.center,
          width: _handlePx,
          height: r.height,
        );
      }
      if (h.axis == MangaAxis.y && r.height < _handlePx) {
        r = Rect.fromCenter(
          center: r.center,
          width: r.width,
          height: _handlePx,
        );
      }
      if (r.contains(p)) return h.path;
    }
    return null;
  }

  String? _panelAt(_View view, MangaPage page, Offset p) {
    for (final MapEntry(key: id, value: r) in panelRects(page).entries) {
      if (view.rect(r).contains(p)) return id;
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
              null => SystemMouseCursors.basic,
            },
            onHover: browsing
                ? null
                : (e) {
                    final h = _handleAt(view, page, e.localPosition);
                    if (h != _hover) setState(() => _hover = h);
                  },
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: browsing
                  ? null
                  : (d) {
                      _focus.requestFocus();
                      if (_handleAt(view, page, d.localPosition) == null) {
                        board.select(_panelAt(view, page, d.localPosition));
                      }
                    },
              onPanStart: browsing
                  ? null
                  : (d) {
                      _focus.requestFocus();
                      _dragging = _handleAt(view, page, d.localPosition);
                    },
              onPanUpdate: (d) {
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
                if (_dragging == null) return;
                _dragging = null;
                board.endDrag();
              },
              child: CustomPaint(
                size: box.biggest,
                painter: MangaPainter(
                  page: page,
                  selected: browsing ? null : board.selected,
                  hoverHandle: _dragging ?? _hover,
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
Future<Uint8List?> mangaPng(MangaPage page, {int dpi = 300}) async {
  final w = (page.width * dpi / 25400).round();
  final h = (page.height * dpi / 25400).round();
  final recorder = ui.PictureRecorder();
  MangaPainter(
    page: page,
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
