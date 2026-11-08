import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/manga/manga.dart';
import 'package:penna/core/harness/manga/manga_gacha.dart';
import 'package:penna/core/harness/manga/manga_geometry.dart';
import 'package:penna/core/harness/manga/manga_script.dart';

/// 设计稿里的双格页:A5、四边留 10 mm、沟宽 4 mm、左右对半、日式。
MangaPage _two() => MangaPage(
  id: 'page-1',
  root: const MangaSplit(
    axis: MangaAxis.x,
    ratio: 500000,
    first: MangaLeaf('left'),
    second: MangaLeaf('right'),
  ),
  panels: const {
    'left': MangaPanel(id: 'left', action: '点头'),
    'right': MangaPanel(id: 'right', action: '抬手指向门口'),
  },
);

void main() {
  test('双格页:两格的位置、沟宽只扣一次;日式先读右格', () {
    final rects = panelRects(_two());
    expect(rects['left'], (x: 10000, y: 10000, w: 62000, h: 190000));
    expect(rects['right'], (x: 76000, y: 10000, w: 62000, h: 190000));
    expect(readingOrder(_two()), ['right', 'left']);
    expect(readingOrder(_two().copyWith(rtl: false)), ['left', 'right']);
  });

  test('存盘读回一样;树和格对不上、版本更新的读不了', () {
    final p = MangaProject(
      pages: [_two()],
      title: '门口',
      characters: const [MangaCharacter(name: '阿禾', look: '短发')],
      nextId: 9,
    );
    final text = jsonEncode(p.toJson());
    expect(jsonEncode(MangaProject.fromJson(jsonDecode(text))!.toJson()), text);
    final broken = jsonDecode(text) as Map<String, dynamic>;
    ((broken['pages'] as List).first as Map)['panels'] = [
      {'id': 'left'},
    ];
    expect(MangaProject.fromJson(broken), isNull);
    expect(MangaProject.fromJson({...p.toJson(), 'schemaVersion': 2}), isNull);
  });

  test('拖格线:夹在两边最短边之间,一格不会小于 15 mm', () {
    final page = _two();
    final far = dragSplit(page, '', 0)!;
    expect(panelRects(far)['left']!.w, greaterThanOrEqualTo(mangaMinSide));
    expect(panelRects(far)['left']!.w, lessThan(mangaMinSide + 10));
    final mid = dragSplit(page, '', 50000)!;
    expect(panelRects(mid)['left']!.w, closeTo(38000, 2));
    expect(dragSplit(page, '0', 0), isNull);
  });

  test('拆格、合并:内容跟着有内容的那格走', () {
    final split = splitPanel(_two(), 'left', MangaAxis.y, 'new')!;
    expect(split.panels['new']!.isBlank, isTrue);
    expect(mergeableWith(split, 'new'), 'left');
    final merged = mergePanel(split, 'new')!;
    expect(merged.panels.keys, unorderedEquals(['left', 'right']));
    expect(merged.panels['left']!.action, '点头');
    final locked = split.withPanel(
      split.panels['left']!.copyWith(locked: true),
    );
    expect(mergePanel(locked, 'new'), isNull);
  });

  test('抽分格:同一个种子抽出来一样,格数在范围里、不重复、没有太小的格', () {
    final page = _two();
    final a = drawLayouts(page, seed: 's1', minPanels: 3, maxPanels: 6);
    final b = drawLayouts(page, seed: 's1', minPanels: 3, maxPanels: 6);
    expect([for (final c in a.found) c.key], [for (final c in b.found) c.key]);
    expect(a.found, hasLength(8));
    expect(a.found.map((c) => c.key).toSet(), hasLength(8));
    final other = drawLayouts(page, seed: 's2', minPanels: 3, maxPanels: 6);
    expect(other.found.first.key, isNot(a.found.first.key));
    for (final c in a.found) {
      expect(c.count, inInclusiveRange(3, 6));
      final applied = applyLayout(page, c.root, ['x1', 'x2', 'x3', 'x4'])!;
      final rects = panelRects(applied.page);
      expect(rects, hasLength(c.count));
      for (final r in rects.values) {
        expect(r.w, greaterThanOrEqualTo(mangaMinSide));
        expect(r.h, greaterThanOrEqualTo(mangaMinSide));
      }
    }
    // 放不下就说放不下,不放宽。
    final tiny = page.copyWith(width: 60000, height: 60000);
    final none = drawLayouts(tiny, seed: 's1', minPanels: 9, maxPanels: 9);
    expect(none.found, isEmpty);
    expect(none.problem, contains('9'));
  });

  test('换分格:原来的内容按阅读顺序接上,有内容的格不丢', () {
    final draw = drawLayouts(_two(), seed: 'k', minPanels: 4, maxPanels: 4);
    final applied = applyLayout(_two(), draw.found.first.root, ['a', 'b'])!;
    final order = readingOrder(applied.page);
    expect(applied.used, 2);
    expect(applied.page.panels[order[0]]!.action, '抬手指向门口');
    expect(applied.page.panels[order[1]]!.action, '点头');
    // 格数比有内容的格少:放不下。
    final one = drawLayouts(_two(), seed: 'k', minPanels: 1, maxPanels: 1);
    expect(applyLayout(_two(), one.found.first.root, const []), isNull);
  });

  test('抽镜头:同一个种子一样,锁着的格不动', () {
    final page = _two().withPanel(
      _two().panels['left']!.copyWith(locked: true, framing: '特写'),
    );
    final a = drawShots(page, seed: 'z');
    expect(
      jsonEncode(a.toJson()),
      jsonEncode(drawShots(page, seed: 'z').toJson()),
    );
    expect(a.panels['left']!.framing, '特写');
    expect(mangaFramings, contains(a.panels['right']!.framing));
    expect(mangaAngles, contains(a.panels['right']!.angle));
  });

  test('Agent 的分镜:格数不同就重排,写到新页就加页,补角色;锁着的格不重排', () {
    final project = MangaProject(pages: [_two()], nextId: 10);
    final board = parseStoryboard('''```json
{"characters": [{"name": "阿禾", "look": "黑色短发"}],
 "pages": [
  {"page": 1, "note": "门口", "panels": [
    {"framing": "全景", "cast": ["阿禾"], "action": "推门", "emphasis": 80},
    {"framing": "近景", "lines": [{"speaker": "阿禾", "text": "走吧"}]},
    {"framing": "特写", "action": "手"}]},
  {"page": 2, "panels": [{"action": "街道"}]}
 ]}
```''')!;
    final r = applyStoryboard(project, board, current: 0, seed: 's');
    expect(r.problems, isEmpty);
    expect(r.project.pages, hasLength(2));
    expect(r.project.characters.single.look, '黑色短发');
    final page = r.project.pages.first;
    final order = readingOrder(page);
    expect(order, hasLength(3));
    expect(page.panels[order[0]]!.action, '推门');
    expect(page.panels[order[1]]!.lines.single.text, '走吧');
    expect(page.note, '门口');
    final locked = project.withPage(
      0,
      _two().withPanel(_two().panels['left']!.copyWith(locked: true)),
    );
    final stuck = applyStoryboard(locked, board, current: 0, seed: 's');
    expect(stuck.problems.single, contains('锁'));
    expect(parseStoryboard('{"pages": "不是列表"}'), isNull);
    expect(parseStoryboard('{"pages": [{"panels": [{"act'), isNull);
  });

  test('交给区域控制:每格一块,人物和台词在自己那格里,画布按纸张比例', () {
    final project = MangaProject(
      pages: [
        _two().withPanel(
          _two().panels['right']!.copyWith(
            cast: ['阿禾'],
            lines: [(speaker: '阿禾', text: '走吧')],
          ),
        ),
      ],
      characters: const [MangaCharacter(name: '阿禾', look: 'short hair')],
    );
    final l = mangaToLayout(project, 0);
    expect(l.height, 1216);
    expect(l.width % 16, 0);
    expect(l.canvas, 'multi_panel');
    expect(l.cast, {'阿禾': 'short hair'});
    final frames = l.boxes.where((b) => b.layer == 'back').toList();
    expect(frames.map((b) => b.name), ['第1格', '第2格']);
    // 第 1 格是右边那格(日式)。
    expect(frames.first.left, greaterThan(frames.last.left));
    for (final b in l.boxes.where((b) => b.layer != 'back')) {
      expect(b.left, greaterThanOrEqualTo(frames.first.left));
      expect(b.right, lessThanOrEqualTo(frames.first.right));
      expect(b.bottom, lessThanOrEqualTo(frames.first.bottom));
    }
    expect(l.boxes.firstWhere((b) => b.label == 'character').name, '阿禾·1');
    // 特写格不放人物块。
    final close = MangaProject(
      pages: [
        project.pages.first.withPanel(
          project.pages.first.panels['right']!.copyWith(framing: '特写'),
        ),
      ],
    );
    expect(
      mangaToLayout(close, 0).boxes.where((b) => b.label == 'character'),
      isEmpty,
    );
    expect(mangaBrief(project, 0), contains('阿禾「走吧」'));
  });
}
