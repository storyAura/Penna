// 抽卡:按种子随机切出几种分格(候选),再按规则打分、去重、排好;
// 还有给每格抽景别和角度。同一个种子、同一份设置,每次抽出来都一样。
//
// 随机数不用 Dart 自带的 Random(各版本可能不同),用自己的协议:
// 键 = SHA-256(JSON [种子, 生成器版本, 范围, 第几次, 类别]),
// 第 k 个数 = SHA-256(键 ‖ k 的 8 字节大端) 的前 4 字节(大端)。

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../l10n/l10n.dart';
import 'manga.dart';
import 'manga_geometry.dart';

/// 生成规则的版本:改了抽法就换,旧种子的结果不冒充一样。
const mangaGeneratorVersion = 'rect-v1';

/// 一路随机数。[scope] 是这次作用在哪(页 id),[category] 区分分格、镜头,
/// 改镜头不会动到分格的随机数。
class MangaStream {
  MangaStream(String seed, String scope, int attempt, String category)
    : _key = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                seed,
                mangaGeneratorVersion,
                scope,
                attempt,
                category,
              ]),
            ),
          )
          .bytes;

  final List<int> _key;
  int _k = 0;

  int next32() {
    final k = _k++;
    final b = sha256.convert([
      ..._key,
      for (var s = 56; s >= 0; s -= 8) (k >> s) & 0xff,
    ]).bytes;
    return b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3];
  }

  /// 0 到 n-1,拒绝采样去掉取模的偏差。
  int below(int n) {
    if (n <= 1) return 0;
    const span = 0x100000000;
    final limit = span - span % n;
    while (true) {
      final v = next32();
      if (v < limit) return v % n;
    }
  }

  /// 按整数权重挑一个;全是 0 时返回 -1。
  int weighted(List<int> weights) {
    final total = weights.fold(0, (a, w) => a + (w > 0 ? w : 0));
    if (total == 0) return -1;
    var r = below(total);
    for (final (i, w) in weights.indexed) {
      if (w <= 0) continue;
      if (r < w) return i;
      r -= w;
    }
    return weights.length - 1;
  }
}

/// 一张候选分格:树(叶子是临时 id)、几格、得分(越高越好)、去重用的键、
/// 第几次抽到的、主要扣分原因。
typedef MangaCandidate = ({
  MangaNode root,
  int count,
  int score,
  String key,
  int attempt,
  List<String> notes,
});

/// 抽分格的结果:找到的候选(按得分排好)和没抽满的原因。
typedef MangaDraw = ({List<MangaCandidate> found, int wanted, String? problem});

/// 每页最多几格。
const mangaMaxPanels = 12;

/// 比例从这几档里挑(三七开、四六开……),不出 51% 这种看不出差别的。
const _ratioSteps = [
  300000,
  350000,
  400000,
  450000,
  500000,
  550000,
  600000,
  650000,
  700000,
];

/// 在 [page] 的版心里抽 [count] 张不同的分格,格数在 [minPanels]..[maxPanels]。
/// [emphasis] 是按阅读顺序每格的分量(0–100),有的话分量大的格该大;
/// 长度和格数对不上就不看它。最多试 [attempts] 次;抽不满就少给,
/// 一张都没有时 [MangaDraw.problem] 说为什么,不放宽条件。
MangaDraw drawLayouts(
  MangaPage page, {
  required String seed,
  required int minPanels,
  required int maxPanels,
  int count = 8,
  List<int> emphasis = const [],
  int attempts = 200,
}) {
  final lo = minPanels.clamp(1, mangaMaxPanels);
  final hi = maxPanels.clamp(lo, mangaMaxPanels);
  final found = <MangaCandidate>[];
  final keys = <String>{};
  var noRoom = 0;
  for (var attempt = 0; attempt < attempts && found.length < count; attempt++) {
    final s = MangaStream(seed, page.id, attempt, 'layout');
    final n = lo + s.below(hi - lo + 1);
    final root = _grow(page, n, s);
    if (root == null) {
      noRoom++;
      continue;
    }
    final probe = page.copyWith(
      root: root,
      panels: {for (final id in leafIds(root)) id: MangaPanel(id: id)},
    );
    final key = _keyOf(probe);
    if (!keys.add(key)) continue;
    final scored = _score(probe, emphasis);
    found.add((
      root: root,
      count: n,
      score: scored.score,
      key: key,
      attempt: attempt,
      notes: scored.notes,
    ));
  }
  found.sort(
    (a, b) => a.score != b.score ? b.score - a.score : a.key.compareTo(b.key),
  );
  return (
    found: List.unmodifiable(found),
    wanted: count,
    problem: found.isEmpty
        ? (noRoom > 0 ? tr('版心放不下 {0} 格(每格最短边 15 mm)', [lo]) : tr('没有抽到能用的分格'))
        : null,
  );
}

/// 从一整格开始,切 n-1 刀;某一步无处可切返回 null。
MangaNode? _grow(MangaPage page, int n, MangaStream s) {
  MangaNode root = const MangaLeaf('n0');
  for (var i = 1; i < n; i++) {
    final probe = page.copyWith(
      root: root,
      panels: {for (final id in leafIds(root)) id: MangaPanel(id: id)},
    );
    final rects = panelRects(probe);
    final choices = <(String, MangaAxis, MangaRect)>[];
    final weights = <int>[];
    for (final MapEntry(key: id, value: r) in rects.entries) {
      for (final axis in MangaAxis.values) {
        final length = axis == MangaAxis.x ? r.w : r.h;
        if (length < 2 * mangaMinSide + page.gap) continue;
        // 大的格先切;高的格横着切(分出上下排),宽的格竖着切。
        // 第一刀偏向横切:漫画页大多是一排一排的。
        var w = r.w ~/ 1000 * (r.h ~/ 1000) ~/ 100 + 1;
        final tall = r.h >= r.w;
        if (axis == MangaAxis.y && tall || axis == MangaAxis.x && !tall) w *= 3;
        if (i == 1 && axis == MangaAxis.y) w *= 2;
        choices.add((id, axis, r));
        weights.add(w);
      }
    }
    final pick = s.weighted(weights);
    if (pick < 0) return null;
    final (id, axis, r) = choices[pick];
    final usable = (axis == MangaAxis.x ? r.w : r.h) - page.gap;
    final legal = [
      for (final step in _ratioSteps)
        if (usable * step ~/ 1000000 >= mangaMinSide &&
            usable - usable * step ~/ 1000000 >= mangaMinSide)
          step,
    ];
    final ratio = legal.isEmpty ? 500000 : legal[s.below(legal.length)];
    final path = pathOf(root, id)!;
    root = replaceAt(
      root,
      path,
      (leaf) => MangaSplit(
        axis: axis,
        ratio: ratio,
        first: leaf,
        second: MangaLeaf('n$i'),
      ),
    );
  }
  return root;
}

/// 去重的键:按阅读顺序各格的矩形,量到 0.1 mm(只用来比较,不改几何)。
String _keyOf(MangaPage page) {
  final rects = panelRects(page);
  return [
    for (final id in readingOrder(page))
      if (rects[id] case final r?)
        '${r.x ~/ 100},${r.y ~/ 100},${r.w ~/ 100},${r.h ~/ 100}',
  ].join('|');
}

/// 打分(整数):不要细长条、大小要有起伏、分量大的格要大、一排一排地读。
/// 这是经验规则,不保证叙事好坏;主要扣分原因写进 notes。
({int score, List<String> notes}) _score(MangaPage page, List<int> emphasis) {
  final rects = panelRects(page);
  final order = readingOrder(page);
  final notes = <String>[];
  // 最细长的那格:长边是短边的三倍以内满分,再长就扣。
  var worst = 100;
  for (final r in rects.values) {
    final long = r.w > r.h ? r.w : r.h, short = r.w > r.h ? r.h : r.w;
    final ratio = long * 100 ~/ short;
    if (ratio > worst) worst = ratio;
  }
  final thin = worst <= 300 ? 1000 : (1000 - (worst - 300) * 4).clamp(0, 1000);
  if (thin < 1000) notes.add(tr('有细长的格'));
  // 大小起伏:最大格是最小格的 1.8 到 6 倍最好;太平均像表格。
  final areas = [for (final r in rects.values) r.w ~/ 1000 * (r.h ~/ 1000)];
  final big = areas.reduce((a, b) => a > b ? a : b);
  final small = areas.reduce((a, b) => a < b ? a : b);
  final spread = small == 0 ? 1000 : big * 100 ~/ small;
  final rhythm = order.length == 1
      ? 1000
      : spread < 130
      ? 300
      : spread < 180
      ? 700
      : spread <= 600
      ? 1000
      : 600;
  if (rhythm < 1000 && spread < 180) notes.add(tr('格的大小太平均'));
  if (rhythm < 1000 && spread > 600) notes.add(tr('大小差得太多'));
  // 分量:分量最大的那格在面积里排第几(最大是满分)。
  var weight = 1000;
  if (emphasis.length == order.length && order.length > 1) {
    final top = emphasis.indexOf(emphasis.reduce((a, b) => a > b ? a : b));
    final mine = rects[order[top]]!;
    final area = mine.w ~/ 1000 * (mine.h ~/ 1000);
    final bigger = areas.where((a) => a > area).length;
    weight = 1000 - bigger * 1000 ~/ (order.length - 1);
    if (bigger > 0) notes.add(tr('重点格不够大'));
  }
  // 一排一排:第一刀是横切的好读。
  final root = page.root;
  final tiers = root is MangaSplit && root.axis == MangaAxis.x ? 600 : 1000;
  return (score: thin * 3 + rhythm * 2 + weight * 2 + tiers, notes: notes);
}

/// 用候选 [root](叶子是临时 id)换掉 [page] 的分格:按阅读顺序把原来的格接到新格上,
/// 内容跟着走;新格多出来就补留白,少了先丢后面的留白格。有内容的格放不下返回 null。
/// [newIds] 至少要有候选格数那么多个,用掉几个由返回的 used 说。
({MangaPage page, int used})? applyLayout(
  MangaPage page,
  MangaNode root,
  List<String> newIds,
) {
  final kept = [for (final id in readingOrder(page)) page.panels[id]!];
  final want = leafIds(root).length;
  while (kept.length > want) {
    final i = kept.lastIndexWhere((p) => p.isBlank && !p.locked);
    if (i < 0) return null;
    kept.removeAt(i);
  }
  var used = 0;
  while (kept.length < want) {
    kept.add(MangaPanel(id: newIds[used++]));
  }
  // 候选的临时 id 按阅读顺序对上原来的格。
  final probe = page.copyWith(
    root: root,
    panels: {for (final id in leafIds(root)) id: MangaPanel(id: id)},
  );
  final rename = {
    for (final (i, id) in readingOrder(probe).indexed) id: kept[i].id,
  };
  MangaNode renamed(MangaNode n) => switch (n) {
    MangaLeaf(:final panel) => MangaLeaf(rename[panel]!),
    MangaSplit() => n.copyWith(
      first: renamed(n.first),
      second: renamed(n.second),
    ),
  };
  return (
    page: page.copyWith(
      root: renamed(root),
      panels: {for (final p in kept) p.id: p},
    ),
    used: used,
  );
}

/// 景别:由远到近。
const mangaFramings = ['远景', '全景', '中景', '近景', '特写'];

/// 镜头角度。
const mangaAngles = ['平视', '俯视', '仰视', '侧面', '背影', '过肩'];

/// 给没锁的格抽景别和角度(第 [attempt] 次)。一页开头偏远景交代环境,
/// 分量大的格偏近景特写,宽格偏远景,小格偏特写;和上一格同景别的少抽。
MangaPage drawShots(MangaPage page, {required String seed, int attempt = 0}) {
  final s = MangaStream(seed, page.id, attempt, 'shot');
  final rects = panelRects(page);
  final c = page.content;
  final total = c.w ~/ 1000 * (c.h ~/ 1000);
  var panels = page.panels;
  String? last;
  for (final (i, id) in readingOrder(page).indexed) {
    final p = panels[id]!;
    if (p.locked) {
      last = p.framing;
      continue;
    }
    final r = rects[id]!;
    final share = r.w ~/ 1000 * (r.h ~/ 1000) * 100 ~/ total;
    final w = [2, 3, 4, 3, 2];
    if (i == 0) {
      w[0] += 4;
      w[1] += 3;
    }
    if (r.w * 10 > r.h * 16) {
      w[0] += 3;
      w[1] += 2;
    }
    if (share < 15) {
      w[3] += 3;
      w[4] += 3;
    }
    if (p.emphasis >= 70) {
      w[3] += 2;
      w[4] += 3;
    }
    final same = mangaFramings.indexOf(last ?? '');
    if (same >= 0) w[same] = w[same] ~/ 4;
    final framing = mangaFramings[s.weighted(w)];
    final angles = [6, 2, 2, 2, 1, p.cast.length >= 2 ? 3 : 0];
    final angle = mangaAngles[s.weighted(angles)];
    panels = {...panels, id: p.copyWith(framing: framing, angle: angle)};
    last = framing;
  }
  return page.copyWith(panels: panels);
}
