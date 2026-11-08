// 抽分格的版式:按几排(层)排,每排几格,有的格再上下分;格线可以斜,
// 贴着版心边的格可以出血。几种风格是几组参数,用户也能自己调。

import 'manga.dart';
import 'manga_gacha.dart';
import 'manga_geometry.dart';

/// 一组版式参数。层数是一页排几排;其余都是 0–100 的程度:
/// 横线、竖线斜多少,出血格多少,格里再分的多少,有没有一个特别大的格。
class MangaStyle {
  const MangaStyle({
    required this.tiersMin,
    required this.tiersMax,
    required this.slantH,
    required this.slantV,
    required this.bleed,
    required this.subdivide,
    required this.big,
  });

  final int tiersMin, tiersMax;
  final int slantH, slantV, bleed, subdivide, big;

  MangaStyle copyWith({
    int? tiersMin,
    int? tiersMax,
    int? slantH,
    int? slantV,
    int? bleed,
    int? subdivide,
    int? big,
  }) {
    final lo = (tiersMin ?? this.tiersMin).clamp(1, 6);
    return MangaStyle(
      tiersMin: lo,
      tiersMax: (tiersMax ?? this.tiersMax).clamp(lo, 6),
      slantH: (slantH ?? this.slantH).clamp(0, 100),
      slantV: (slantV ?? this.slantV).clamp(0, 100),
      bleed: (bleed ?? this.bleed).clamp(0, 100),
      subdivide: (subdivide ?? this.subdivide).clamp(0, 100),
      big: (big ?? this.big).clamp(0, 100),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MangaStyle &&
      other.tiersMin == tiersMin &&
      other.tiersMax == tiersMax &&
      other.slantH == slantH &&
      other.slantV == slantV &&
      other.bleed == bleed &&
      other.subdivide == subdivide &&
      other.big == big;

  @override
  int get hashCode =>
      Object.hash(tiersMin, tiersMax, slantH, slantV, bleed, subdivide, big);
}

/// 几种现成的风格(名字存的是中文原文,显示时翻译)。
const mangaStyles = <String, MangaStyle>{
  '对话': MangaStyle(
    tiersMin: 3,
    tiersMax: 4,
    slantH: 0,
    slantV: 0,
    bleed: 0,
    subdivide: 20,
    big: 10,
  ),
  '标准': MangaStyle(
    tiersMin: 2,
    tiersMax: 4,
    slantH: 25,
    slantV: 25,
    bleed: 20,
    subdivide: 20,
    big: 20,
  ),
  '动作': MangaStyle(
    tiersMin: 2,
    tiersMax: 3,
    slantH: 55,
    slantV: 55,
    bleed: 45,
    subdivide: 28,
    big: 35,
  ),
  '扉页': MangaStyle(
    tiersMin: 1,
    tiersMax: 3,
    slantH: 40,
    slantV: 40,
    bleed: 75,
    subdivide: 10,
    big: 70,
  ),
};

/// 斜线两头最多差多少(百万分比),程度 100 时。
const _slantSpan = 150000;

/// 斜一刀:程度越高越常斜、斜得越多;0 是直的。
int _slant(MangaStream s, int level) {
  if (level <= 0 || s.below(100) >= level * 3 ~/ 2) return 0;
  final most = _slantSpan * level ~/ 100;
  return s.below(2 * most + 1) - most;
}

/// 一串权重切成一串二分:第 i 块对剩下的那些,比例按权重。
MangaNode _chain(
  List<MangaNode> parts,
  List<int> weights,
  MangaAxis axis,
  MangaStream s,
  int slantLevel,
) {
  if (parts.length == 1) return parts.single;
  final rest = weights.skip(1).fold(0, (a, b) => a + b);
  final ratio = weights.first * 1000000 ~/ (weights.first + rest);
  return MangaSplit(
    axis: axis,
    ratio: ratio.clamp(1, 999999),
    slant: _slant(s, slantLevel),
    first: parts.first,
    second: _chain(parts.sublist(1), weights.sublist(1), axis, s, slantLevel),
  );
}

/// 按版式长一张分格(叶子是临时 id `n0`、`n1`…);[panels] 给了就只要正好这么多格。
/// 有格太窄、格数对不上返回 null(由调用方再抽一次)。
MangaNode? growTiers(
  MangaPage page,
  MangaStyle st,
  MangaStream s, {
  int? panels,
}) {
  var tMax = st.tiersMax, tMin = st.tiersMin;
  if (panels != null) {
    tMax = tMax < panels ? tMax : panels;
    final least = (panels + 5) ~/ 6;
    tMin = tMin > tMax ? tMax : tMin;
    if (tMin < least) tMin = least > tMax ? tMax : least;
  }
  final tiers = tMin + s.below(tMax - tMin + 1);
  final heights = [for (var i = 0; i < tiers; i++) 100 + s.below(61)];
  if (tiers > 1 && s.below(100) < st.big) {
    final b = s.below(tiers);
    heights[b] = heights[b] * (200 + st.big * 2) ~/ 100;
  }
  final total = heights.fold(0, (a, b) => a + b);
  var next = 0;
  final rows = <MangaNode>[];
  for (final h in heights) {
    final tall = h * 100 ~/ total > 45;
    final cols = 1 + s.weighted(tall ? [5, 3, 1] : [2, 5, 3]);
    final widths = [for (var c = 0; c < cols; c++) 100 + s.below(81)];
    if (cols > 1 && s.below(100) < st.big ~/ 2) {
      final b = s.below(cols);
      widths[b] *= 2;
    }
    final columns = <MangaNode>[];
    for (var c = 0; c < cols; c++) {
      if (s.below(100) < st.subdivide) {
        final stack = s.below(100) < st.subdivide ~/ 3 ? 3 : 2;
        columns.add(
          _chain(
            [for (var k = 0; k < stack; k++) MangaLeaf('n${next++}')],
            [for (var k = 0; k < stack; k++) 100 + s.below(61)],
            MangaAxis.y,
            s,
            st.slantH,
          ),
        );
      } else {
        columns.add(MangaLeaf('n${next++}'));
      }
    }
    rows.add(_chain(columns, widths, MangaAxis.x, s, st.slantV));
  }
  if (panels != null && next != panels) return null;
  final root = _chain(rows, heights, MangaAxis.y, s, st.slantH);
  final probe = page.copyWith(
    root: root,
    panels: {for (final id in leafIds(root)) id: MangaPanel(id: id)},
  );
  final quads = panelQuads(probe);
  for (final q in quads.values) {
    final span = spanOf(q);
    if (span.w < mangaMinSide || span.h < mangaMinSide) return null;
  }
  // 出血:贴着版心边的格,按程度铺到纸边。
  if (st.bleed <= 0) return root;
  final c = page.content;
  MangaNode bleed(MangaNode n) => switch (n) {
    MangaLeaf(:final panel) => () {
      final q = quads[panel]!;
      final edge = q.any(
        (p) => p.x <= c.x || p.y <= c.y || p.x >= c.x + c.w || p.y >= c.y + c.h,
      );
      return edge && s.below(150) < st.bleed
          ? MangaLeaf(panel, bleed: true)
          : n;
    }(),
    MangaSplit() => n.copyWith(first: bleed(n.first), second: bleed(n.second)),
  };
  return bleed(root);
}
