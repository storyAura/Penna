// 分格树的几何:算出各格的四边形、阅读顺序、能拖的格线,以及拖线、拆格、合并。
// 全部是整数微米;改动都返回新的 [MangaPage],不改原来的。
//
// 格线可以斜:一刀从起头那一边切到另一边,两头的位置可以不同([MangaSplit.slant]),
// 所以每格是一个凸四边形(左上、右上、右下、左下)。节点用路径指:
// 根是空串,往下走 first 加 '0'、second 加 '1'。

import 'manga.dart';

typedef MangaPoint = ({int x, int y});

/// 四边形:左上、右上、右下、左下。
typedef MangaQuad = List<MangaPoint>;

MangaPoint _lerp(MangaPoint a, MangaPoint b, int num, int den) => den == 0
    ? a
    : (x: a.x + (b.x - a.x) * num ~/ den, y: a.y + (b.y - a.y) * num ~/ den);

MangaQuad _quadOf(MangaRect r) => [
  (x: r.x, y: r.y),
  (x: r.x + r.w, y: r.y),
  (x: r.x + r.w, y: r.y + r.h),
  (x: r.x, y: r.y + r.h),
];

/// 四边形的外框。
MangaRect boundsOf(MangaQuad q) {
  final xs = q.map((p) => p.x), ys = q.map((p) => p.y);
  final x0 = xs.reduce((a, b) => a < b ? a : b);
  final y0 = ys.reduce((a, b) => a < b ? a : b);
  return (
    x: x0,
    y: y0,
    w: xs.reduce((a, b) => a > b ? a : b) - x0,
    h: ys.reduce((a, b) => a > b ? a : b) - y0,
  );
}

/// 四边形最窄处的宽和高(上下两边、左右两边取短的)。
({int w, int h}) spanOf(MangaQuad q) {
  final top = (q[1].x - q[0].x).abs(), bottom = (q[2].x - q[3].x).abs();
  final left = (q[3].y - q[0].y).abs(), right = (q[2].y - q[1].y).abs();
  return (w: top < bottom ? top : bottom, h: left < right ? left : right);
}

/// 面积(平方毫米,鞋带公式)。
int areaMm(MangaQuad q) {
  var twice = 0;
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4];
    twice += (a.x ~/ 100) * (b.y ~/ 100) - (b.x ~/ 100) * (a.y ~/ 100);
  }
  return twice.abs() ~/ 200;
}

/// 点在不在凸四边形里。
bool quadContains(MangaQuad q, int x, int y) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = q[i], b = q[(i + 1) % 4];
    final c = (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x);
    if (c == 0) continue;
    final s = c > 0 ? 1 : -1;
    if (sign == 0) sign = s;
    if (s != sign) return false;
  }
  return true;
}

/// 切一刀:沿起头那一边(横线是左边、竖线是上边)按 ratio、另一边按 ratio+slant,
/// 各扣一次沟宽。返回两块和切口(沟带中线的两头)。
({MangaQuad first, MangaQuad second, MangaPoint a, MangaPoint b}) cutQuad(
  MangaQuad q,
  MangaSplit s,
  int gap,
) {
  // 横线:沿左边 q0→q3 和右边 q1→q2 切;竖线:沿上边 q0→q1 和下边 q3→q2 切。
  final y = s.axis == MangaAxis.y;
  final (s0, e0, s1, e1) = y
      ? (q[0], q[3], q[1], q[2])
      : (q[0], q[1], q[3], q[2]);
  (MangaPoint, MangaPoint) at(MangaPoint from, MangaPoint to, int ratio) {
    final length = y ? to.y - from.y : to.x - from.x;
    final usable = length - gap;
    final a = usable * ratio ~/ 1000000;
    return (_lerp(from, to, a, length), _lerp(from, to, a + gap, length));
  }

  final (a0, b0) = at(s0, e0, s.ratio);
  final (a1, b1) = at(s1, e1, s.ratio + s.slant);
  final mid0 = (x: (a0.x + b0.x) ~/ 2, y: (a0.y + b0.y) ~/ 2);
  final mid1 = (x: (a1.x + b1.x) ~/ 2, y: (a1.y + b1.y) ~/ 2);
  return y
      ? (
          first: [q[0], q[1], a1, a0],
          second: [b0, b1, q[2], q[3]],
          a: mid0,
          b: mid1,
        )
      : (
          first: [q[0], a0, a1, q[3]],
          second: [b0, q[1], q[2], b1],
          a: mid0,
          b: mid1,
        );
}

/// 各格的四边形(页面坐标)。[bleed] 时出血格贴着版心边的顶点推到纸边外 3 mm。
Map<String, MangaQuad> panelQuads(MangaPage page, {bool bleed = false}) {
  final out = <String, MangaQuad>{};
  final c = page.content;
  MangaPoint push(MangaPoint p) => (
    x: p.x <= c.x
        ? -3000
        : p.x >= c.x + c.w
        ? page.width + 3000
        : p.x,
    y: p.y <= c.y
        ? -3000
        : p.y >= c.y + c.h
        ? page.height + 3000
        : p.y,
  );
  void walk(MangaNode n, MangaQuad q) {
    switch (n) {
      case MangaLeaf(:final panel, bleed: final b):
        out[panel] = bleed && b ? [for (final p in q) push(p)] : q;
      case MangaSplit(:final first, :final second):
        final cut = cutQuad(q, n, page.gap);
        walk(first, cut.first);
        walk(second, cut.second);
    }
  }

  walk(page.root, _quadOf(c));
  return out;
}

/// 各格的外框(页面坐标,不算出血)。
Map<String, MangaRect> panelRects(MangaPage page) => {
  for (final MapEntry(:key, :value) in panelQuads(page).entries)
    key: boundsOf(value),
};

/// 阅读顺序:上下分先上后下;左右分日式先右后左、西式先左后右。
List<String> readingOrder(MangaPage page) {
  List<String> walk(MangaNode n) => switch (n) {
    MangaLeaf(:final panel) => [panel],
    MangaSplit(:final axis, :final first, :final second) =>
      axis == MangaAxis.x && page.rtl
          ? [...walk(second), ...walk(first)]
          : [...walk(first), ...walk(second)],
  };
  return walk(page.root);
}

/// 一棵子树至少要多宽多高:左右分是两边宽度加沟宽、高取大的;上下分反过来。
({int w, int h}) need(MangaNode n, int gap) => switch (n) {
  MangaLeaf() => (w: mangaMinSide, h: mangaMinSide),
  MangaSplit(:final axis, :final first, :final second) => () {
    final a = need(first, gap), b = need(second, gap);
    return axis == MangaAxis.x
        ? (w: a.w + gap + b.w, h: a.h > b.h ? a.h : b.h)
        : (w: a.w > b.w ? a.w : b.w, h: a.h + gap + b.h);
  }(),
};

/// 一条能拖的格线:哪个切分节点、沿哪个方向、沟带中线的两头、它切的那块。
typedef MangaHandle = ({
  String path,
  MangaAxis axis,
  MangaPoint a,
  MangaPoint b,
  MangaQuad parent,
});

List<MangaHandle> handlesOf(MangaPage page) {
  final out = <MangaHandle>[];
  void walk(MangaNode n, MangaQuad q, String path) {
    if (n is! MangaSplit) return;
    final cut = cutQuad(q, n, page.gap);
    out.add((path: path, axis: n.axis, a: cut.a, b: cut.b, parent: q));
    walk(n.first, cut.first, '${path}0');
    walk(n.second, cut.second, '${path}1');
  }

  walk(page.root, _quadOf(page.content), '');
  return out;
}

MangaNode? nodeAt(MangaNode root, String path) {
  MangaNode n = root;
  for (final step in path.split('')) {
    if (n is! MangaSplit) return null;
    n = step == '0' ? n.first : n.second;
  }
  return n;
}

/// 把 [path] 处的节点换成 [f] 的结果。
MangaNode replaceAt(
  MangaNode root,
  String path,
  MangaNode Function(MangaNode) f,
) {
  if (path.isEmpty) return f(root);
  if (root is! MangaSplit) return root;
  final rest = path.substring(1);
  return path[0] == '0'
      ? root.copyWith(first: replaceAt(root.first, rest, f))
      : root.copyWith(second: replaceAt(root.second, rest, f));
}

/// 格 [panel] 那片叶子的路径;没有是 null。
String? pathOf(MangaNode root, String panel, [String at = '']) =>
    switch (root) {
      MangaLeaf(panel: final p) => p == panel ? at : null,
      MangaSplit(:final first, :final second) =>
        pathOf(first, panel, '${at}0') ?? pathOf(second, panel, '${at}1'),
    };

/// [split] 在 [q] 里能取的比例区间(两头都要放得下两边子树),放不下是 null。
({int lo, int hi})? ratioRange(MangaQuad q, MangaSplit split, int gap) {
  final y = split.axis == MangaAxis.y;
  final a = need(split.first, gap), b = need(split.second, gap);
  final needA = y ? a.h : a.w, needB = y ? b.h : b.w;
  var lo = 1, hi = 999999;
  // 起头那一边、另一边各自的长度;另一边的位置多了 slant。
  final edges = y
      ? [(q[3].y - q[0].y, 0), (q[2].y - q[1].y, split.slant)]
      : [(q[1].x - q[0].x, 0), (q[2].x - q[3].x, split.slant)];
  for (final (length, offset) in edges) {
    final usable = length - gap;
    if (usable <= 0) return null;
    final from = (needA * 1000000 + usable - 1) ~/ usable - offset;
    final to = 1000000 - (needB * 1000000 + usable - 1) ~/ usable - offset;
    if (from > lo) lo = from;
    if (to < hi) hi = to;
  }
  return lo > hi ? null : (lo: lo, hi: hi);
}

/// 拖格线:[pos] 是鼠标在页面上沿切分方向的坐标,格线的中点挪过去(斜度不变)。
/// 先夹到合法区间再换成比例;夹不出区间(放不下)返回 null。
MangaPage? dragSplit(MangaPage page, String path, int pos) {
  final handle = handlesOf(page).where((h) => h.path == path).firstOrNull;
  final node = nodeAt(page.root, path);
  if (handle == null || node is! MangaSplit) return null;
  final range = ratioRange(handle.parent, node, page.gap);
  if (range == null) return null;
  final box = boundsOf(handle.parent);
  final x = node.axis == MangaAxis.x;
  final usable = (x ? box.w : box.h) - page.gap;
  if (usable <= 0) return null;
  final want = pos - (x ? box.x : box.y) - page.gap ~/ 2;
  final ratio = (want * 1000000 ~/ usable - node.slant ~/ 2).clamp(
    range.lo,
    range.hi,
  );
  return page.copyWith(
    root: replaceAt(page.root, path, (_) => node.copyWith(ratio: ratio)),
  );
}

/// 把格 [panel] 对半拆成两格,新的一格叫 [newId]、是留白。放不下返回 null。
MangaPage? splitPanel(
  MangaPage page,
  String panel,
  MangaAxis axis,
  String newId,
) {
  final path = pathOf(page.root, panel);
  final q = panelQuads(page)[panel];
  if (path == null || q == null) return null;
  final span = spanOf(q);
  final length = axis == MangaAxis.x ? span.w : span.h;
  if (length < 2 * mangaMinSide + page.gap) return null;
  return page.copyWith(
    root: replaceAt(
      page.root,
      path,
      (leaf) => MangaSplit(
        axis: axis,
        ratio: 500000,
        first: leaf,
        second: MangaLeaf(newId),
      ),
    ),
    panels: {
      ...page.panels,
      newId: MangaPanel(id: newId),
    },
  );
}

/// 格 [panel] 和它的兄弟格合并(两格必须是同一刀切出来的两片叶子)。
/// 留下的是有内容的那一格(两格都有内容时留 [panel]),另一格去掉。
/// 不能合并(兄弟不是一格、有锁)返回 null。
MangaPage? mergePanel(MangaPage page, String panel) {
  final path = pathOf(page.root, panel);
  if (path == null || path.isEmpty) return null;
  final parentPath = path.substring(0, path.length - 1);
  final parent = nodeAt(page.root, parentPath);
  if (parent is! MangaSplit ||
      parent.first is! MangaLeaf ||
      parent.second is! MangaLeaf) {
    return null;
  }
  final first = parent.first as MangaLeaf, second = parent.second as MangaLeaf;
  final other = path.endsWith('0') ? second.panel : first.panel;
  final mine = page.panels[panel]!, theirs = page.panels[other]!;
  if (mine.locked || theirs.locked) return null;
  final keep = mine.isBlank && !theirs.isBlank ? theirs : mine;
  final drop = keep == mine ? other : panel;
  return page.copyWith(
    root: replaceAt(
      page.root,
      parentPath,
      (_) => MangaLeaf(keep.id, bleed: first.bleed || second.bleed),
    ),
    panels: {...page.panels}..remove(drop),
  );
}

/// 能和 [panel] 合并的兄弟格;没有是 null。
String? mergeableWith(MangaPage page, String panel) {
  final path = pathOf(page.root, panel);
  if (path == null || path.isEmpty) return null;
  final parent = nodeAt(page.root, path.substring(0, path.length - 1));
  if (parent is! MangaSplit) return null;
  final other = path.endsWith('0') ? parent.second : parent.first;
  return other is MangaLeaf ? other.panel : null;
}

/// 换掉格 [panel] 那片叶子的出血。
MangaPage setBleed(MangaPage page, String panel, bool bleed) {
  final path = pathOf(page.root, panel);
  if (path == null) return page;
  return page.copyWith(
    root: replaceAt(page.root, path, (_) => MangaLeaf(panel, bleed: bleed)),
  );
}

/// 格 [panel] 是不是出血格。
bool isBleed(MangaPage page, String panel) {
  final path = pathOf(page.root, panel);
  final n = path == null ? null : nodeAt(page.root, path);
  return n is MangaLeaf && n.bleed;
}
