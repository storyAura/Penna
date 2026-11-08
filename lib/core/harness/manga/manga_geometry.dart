// 分格树的几何:算出各格的矩形、阅读顺序、能拖的格线,以及拖线、拆格、合并。
// 全部是整数微米;改动都返回新的 [MangaPage],不改原来的。
//
// 节点用路径指:根是空串,往下走 first 加 '0'、second 加 '1'。

import 'manga.dart';

/// 按 [axis] 把 [r] 切成两块:可用长度先扣一次沟宽,第一块取整,余数给第二块。
(MangaRect, MangaRect) splitRect(
  MangaRect r,
  MangaAxis axis,
  int ratio,
  int gap,
) {
  if (axis == MangaAxis.x) {
    final usable = r.w - gap;
    final a = usable * ratio ~/ 1000000;
    return (
      (x: r.x, y: r.y, w: a, h: r.h),
      (x: r.x + a + gap, y: r.y, w: usable - a, h: r.h),
    );
  }
  final usable = r.h - gap;
  final a = usable * ratio ~/ 1000000;
  return (
    (x: r.x, y: r.y, w: r.w, h: a),
    (x: r.x, y: r.y + a + gap, w: r.w, h: usable - a),
  );
}

/// 各格的矩形(页面坐标)。
Map<String, MangaRect> panelRects(MangaPage page) {
  final out = <String, MangaRect>{};
  void walk(MangaNode n, MangaRect r) {
    switch (n) {
      case MangaLeaf(:final panel):
        out[panel] = r;
      case MangaSplit(:final axis, :final ratio, :final first, :final second):
        final (a, b) = splitRect(r, axis, ratio, page.gap);
        walk(first, a);
        walk(second, b);
    }
  }

  walk(page.root, page.content);
  return out;
}

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

/// 一条能拖的格线:哪个切分节点、沿哪个方向、沟带在哪、它切的是哪块区域。
typedef MangaHandle = ({
  String path,
  MangaAxis axis,
  MangaRect gutter,
  MangaRect parent,
});

List<MangaHandle> handlesOf(MangaPage page) {
  final out = <MangaHandle>[];
  void walk(MangaNode n, MangaRect r, String path) {
    if (n is! MangaSplit) return;
    final (a, b) = splitRect(r, n.axis, n.ratio, page.gap);
    final gutter = n.axis == MangaAxis.x
        ? (x: a.x + a.w, y: r.y, w: b.x - a.x - a.w, h: r.h)
        : (x: r.x, y: a.y + a.h, w: r.w, h: b.y - a.y - a.h);
    out.add((path: path, axis: n.axis, gutter: gutter, parent: r));
    walk(n.first, a, '${path}0');
    walk(n.second, b, '${path}1');
  }

  walk(page.root, page.content, '');
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

/// 拖格线:[pos] 是鼠标在页面上沿切分方向的坐标(格线中心要去的地方)。
/// 先按两边子树的最小尺寸夹到合法区间,再换成比例;夹不出区间(放不下)返回 null。
MangaPage? dragSplit(MangaPage page, String path, int pos) {
  final handle = handlesOf(page).where((h) => h.path == path).firstOrNull;
  final node = nodeAt(page.root, path);
  if (handle == null || node is! MangaSplit) return null;
  final r = handle.parent;
  final x = node.axis == MangaAxis.x;
  final usable = (x ? r.w : r.h) - page.gap;
  final a = need(node.first, page.gap), b = need(node.second, page.gap);
  final lo = x ? a.w : a.h, hi = usable - (x ? b.w : b.h);
  if (usable <= 0 || lo > hi) return null;
  final want = pos - (x ? r.x : r.y) - page.gap ~/ 2;
  final first = want.clamp(lo, hi);
  // 往上取整:按比例算回来的长度不会比 lo 小(取整只会往下掉)。
  final ratio = ((first * 1000000 + usable - 1) ~/ usable).clamp(1, 999999);
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
  final r = panelRects(page)[panel];
  if (path == null || r == null) return null;
  final length = axis == MangaAxis.x ? r.w : r.h;
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
  final other = path.endsWith('0')
      ? (parent.second as MangaLeaf).panel
      : (parent.first as MangaLeaf).panel;
  final mine = page.panels[panel]!, theirs = page.panels[other]!;
  if (mine.locked || theirs.locked) return null;
  final keep = mine.isBlank && !theirs.isBlank ? theirs : mine;
  final drop = keep == mine ? other : panel;
  return page.copyWith(
    root: replaceAt(page.root, parentPath, (_) => MangaLeaf(keep.id)),
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
