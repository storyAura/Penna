import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/manga/manga.dart';
import 'package:penna/core/harness/manga/manga_gacha.dart';
import 'package:penna/core/harness/manga/manga_geometry.dart';
import 'package:penna/core/harness/manga/manga_script.dart';
import 'package:penna/core/harness/manga/manga_styles.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/ui/features/archive/archive_page.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/manga/manga_board.dart';
import 'package:penna/ui/features/manga/manga_canvas.dart';
import 'package:penna/ui/features/manga/manga_figures.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

MangaPage _blank() => blankMangaPage('page-1', 'p');

/// 上下两格,中间一刀斜线(右头比左头低一成)。
MangaPage _slanted() => MangaPage(
  id: 'page-1',
  root: const MangaSplit(
    axis: MangaAxis.y,
    ratio: 400000,
    slant: 100000,
    first: MangaLeaf('top', bleed: true),
    second: MangaLeaf('bottom'),
  ),
  panels: const {
    'top': MangaPanel(id: 'top', cast: ['阿禾'], action: '指向远方'),
    'bottom': MangaPanel(id: 'bottom'),
  },
);

void main() {
  test('斜线:两格贴着同一条斜线,沟宽留着;点得中;拖线斜度不变;存了读回一样', () {
    final page = _slanted();
    final q = panelQuads(page);
    final top = q['top']!, bottom = q['bottom']!;
    // 上格的底边是斜的:右下比左下低。
    expect(top[2].y, greaterThan(top[3].y));
    // 下格的顶边和上格的底边平行,中间隔着沟宽。
    expect(bottom[0].y - top[3].y, 4000);
    expect(bottom[1].y - top[2].y, 4000);
    expect(quadContains(top, 74000, 30000), isTrue);
    expect(quadContains(bottom, 74000, 30000), isFalse);
    final dragged = dragSplit(page, '', 120000)!;
    expect((dragged.root as MangaSplit).slant, 100000);
    expect(
      jsonEncode(
        MangaPage.fromJson(jsonDecode(jsonEncode(page.toJson())))!.toJson(),
      ),
      jsonEncode(page.toJson()),
    );
  });

  test('出血格贴着版心边的顶点推到纸边外,不贴边的不动', () {
    final page = _slanted();
    final plain = panelQuads(page)['top']!;
    final bled = panelQuads(page, bleed: true)['top']!;
    expect(bled[0], (x: -3000, y: -3000));
    expect(bled[1].x, page.width + 3000);
    // 斜线那一边不贴版心边,不动。
    expect(bled[2].y, plain[2].y);
    expect(isBleed(page, 'top'), isTrue);
    expect(isBleed(setBleed(page, 'top', false), 'top'), isFalse);
  });

  test('几种版式:同一个种子抽出来一样;对话不斜不出血,动作有斜线和出血;格都不太窄', () {
    for (final MapEntry(key: name, value: style) in mangaStyles.entries) {
      final a = drawLayouts(_blank(), seed: 'x', style: style, count: 12);
      final b = drawLayouts(_blank(), seed: 'x', style: style, count: 12);
      expect(
        a.found.map((c) => c.key),
        b.found.map((c) => c.key),
        reason: name,
      );
      expect(a.found, isNotEmpty, reason: name);
      for (final c in a.found) {
        final page = _blank().copyWith(
          root: c.root,
          panels: {for (final id in leafIds(c.root)) id: MangaPanel(id: id)},
        );
        for (final q in panelQuads(page).values) {
          expect(spanOf(q).w, greaterThanOrEqualTo(mangaMinSide), reason: name);
          expect(spanOf(q).h, greaterThanOrEqualTo(mangaMinSide), reason: name);
        }
        expect(c.score, inInclusiveRange(0, 100));
      }
    }
    bool slants(MangaNode n) => switch (n) {
      MangaLeaf() => false,
      MangaSplit() => n.slant != 0 || slants(n.first) || slants(n.second),
    };
    bool bleeds(MangaNode n) => switch (n) {
      MangaLeaf(:final bleed) => bleed,
      MangaSplit() => bleeds(n.first) || bleeds(n.second),
    };
    final talk = drawLayouts(_blank(), seed: 'y', style: mangaStyles['对话']);
    expect(talk.found.any((c) => slants(c.root) || bleeds(c.root)), isFalse);
    final action = drawLayouts(_blank(), seed: 'y', style: mangaStyles['动作']);
    expect(action.found.any((c) => slants(c.root)), isTrue);
    expect(action.found.any((c) => bleeds(c.root)), isTrue);
    // 指定格数时只给那么多格的。
    final six = drawLayouts(
      _blank(),
      seed: 'z',
      style: mangaStyles['标准'],
      minPanels: 6,
      maxPanels: 6,
    );
    expect(six.found, isNotEmpty);
    expect(six.found.every((c) => c.count == 6), isTrue);
  });

  test('斜格交给区域控制写成多边形,出血格铺到画布边', () {
    final l = mangaToLayout(MangaProject(pages: [_slanted()]), 0);
    final frames = l.boxes.where((b) => b.layer == 'back').toList();
    expect(frames.first.shape, isNotNull);
    expect(frames.first.left, 0);
    expect(frames.first.top, 0);
    final person = l.boxes.firstWhere((b) => b.label == 'character');
    expect(person.bottom, lessThanOrEqualTo(frames.first.bottom));
    expect(
      mangaLayoutRequest(MangaProject(pages: [_slanted()]), 0, image: true),
      contains('人偶参考'),
    );
  });

  test('人偶:认得几种姿势;各种景别、角度、人数都画得出来', () {
    expect(poseOf('坐在长椅上'), MangaPose.sit);
    expect(poseOf('抬手指向门口'), MangaPose.point);
    expect(poseOf('拔腿就跑'), MangaPose.run);
    expect(poseOf('点头'), MangaPose.stand);
    const characters = [
      MangaCharacter(name: '阿禾', height: 174),
      MangaCharacter(name: '小岚', height: 137),
    ];
    for (final framing in ['', ...mangaFramings]) {
      for (final angle in ['', ...mangaAngles]) {
        for (final cast in const [
          ['阿禾'],
          ['阿禾', '小岚'],
          ['阿禾', '小岚', '路人'],
        ]) {
          final recorder = ui.PictureRecorder();
          paintPanelArt(
            Canvas(recorder),
            const Rect.fromLTWH(0, 0, 300, 400),
            MangaPanel(
              id: 'p',
              framing: framing,
              angle: angle,
              cast: cast,
              action: '挥手打招呼',
              lines: const [
                (speaker: '阿禾', text: '你好'),
                (speaker: '旁白', text: '那天下着雨'),
              ],
            ),
            characters,
            mm: 2,
          );
          recorder.endRecording().dispose();
        }
      }
    }
  });

  test('导出 PNG 的尺寸按纸张和 DPI 算', () async {
    final bytes = await mangaPng(_slanted(), dpi: 100);
    expect(bytes, isNotNull);
    final codec = await ui.instantiateImageCodec(bytes!);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, (148 * 100 / 25.4).round());
    expect(frame.image.height, (210 * 100 / 25.4).round());
  });

  test('系列:加、换、删都能撤销;存盘读回;旧版只有一部作品的读成一个系列', () async {
    final dir = Directory.systemTemp.createTempSync('penna_manga_series');
    addTearDown(() => dir.deleteSync(recursive: true));
    final board = MangaBoard(dir: dir)..setTitle('第一部');
    expect(board.addSeries(), isNull);
    expect(board.seriesIndex, 1);
    expect(board.seriesName(1), '系列 2');
    board.setTitle('第二部');
    board.showSeries(0);
    expect(board.project.title, '第一部');
    board.removeSeries(1);
    expect(board.shelf, hasLength(1));
    board.undo();
    expect(board.shelf, hasLength(2));
    board.flush();
    final again = MangaBoard(dir: dir);
    await again.load();
    expect(again.shelf.map((p) => p.title), ['第一部', '第二部']);
    File('${dir.path}/manga.json').writeAsStringSync(
      jsonEncode({
        'project': const MangaProject(pages: [])
            .copyWith(title: '旧的', pages: [_blank()])
            .toJson(),
        'page': 0,
      }),
    );
    final old = MangaBoard(dir: dir);
    await old.load();
    expect(old.shelf.single.title, '旧的');
  });

  testWidgets('档案库的「漫画」分区:列出存的作品,放回漫画分镜工作台', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final archive = ArchiveStore();
    final project = MangaProject(pages: [_slanted()], title: '门口');
    archive.add(
      text: jsonEncode(project.toJson()),
      title: '门口',
      category: '',
      kind: archiveManga,
    );
    MangaProject? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArchivePage(
            archive: archive,
            vm: StudioViewModel(
              config: tempConfig(),
              streamChat: (_) => const Stream.empty(),
            ),
            board: LayoutBoard(),
            onOpenStudio: () {},
            onOpenLayout: () {},
            onOpenManga: (p) {
              opened = p;
              return null;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('漫画'));
    await tester.pump();
    expect(find.text('门口'), findsWidgets);
    await tester.tap(find.text('放到漫画分镜工作台'));
    await tester.pump();
    expect(opened?.title, '门口');
    expect(opened?.pages.single.panels, hasLength(2));
  });
}
