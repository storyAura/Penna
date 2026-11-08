import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/manga/manga.dart';
import 'package:penna/core/harness/manga/manga_geometry.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/manga/manga_board.dart';
import 'package:penna/ui/features/manga/manga_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

const _storyboard =
    '好的,排了一页。<storyboard>{"characters": [{"name": "阿禾", "look": "黑色短发"}], '
    '"pages": [{"page": 1, "panels": ['
    '{"framing": "全景", "cast": ["阿禾"], "action": "推门", "emphasis": 80},'
    '{"framing": "近景", "lines": [{"speaker": "阿禾", "text": "走吧"}]},'
    '{"framing": "特写", "action": "手"}]}]}</storyboard>';

void main() {
  test('撤销重做;连着打字合成一步', () {
    final board = MangaBoard();
    board.setTitle('门');
    board.setTitle('门口');
    expect(board.project.title, '门口');
    board.undo();
    expect(board.project.title, '');
    board.redo();
    expect(board.project.title, '门口');
    board.select(board.page.panels.keys.single);
    expect(board.splitSelected(MangaAxis.y), isNull);
    expect(board.page.panels, hasLength(2));
    board.undo();
    expect(board.page.panels, hasLength(1));
  });

  test('抽分格:看候选不改作品,用了才换,能撤销', () {
    final board = MangaBoard();
    final before = board.page;
    board.drawLayout();
    expect(board.draw!.found, isNotEmpty);
    expect(board.previewing, 0);
    expect(identical(board.page, before), isTrue);
    expect(readingOrder(board.shown).length, board.draw!.found.first.count);
    board.applyPreview();
    expect(board.draw, isNull);
    expect(readingOrder(board.page).length, inInclusiveRange(1, 12));
    board.undo();
    expect(identical(board.page, before), isTrue);
  });

  test('拖格线:松手才算一步,Esc 取消', () {
    final board = MangaBoard();
    board.select(board.page.panels.keys.single);
    board.splitSelected(MangaAxis.x);
    final ratio = (board.page.root as MangaSplit).ratio;
    board.dragTo('', 40000);
    expect((board.page.root as MangaSplit).ratio, ratio);
    expect((board.canvasPage.root as MangaSplit).ratio, isNot(ratio));
    board.cancelDrag();
    expect((board.canvasPage.root as MangaSplit).ratio, ratio);
    board.dragTo('', 40000);
    board.endDrag();
    expect((board.page.root as MangaSplit).ratio, isNot(ratio));
  });

  test('存盘读回;读不了的改名留底', () async {
    final dir = Directory.systemTemp.createTempSync('penna_manga');
    addTearDown(() => dir.deleteSync(recursive: true));
    final board = MangaBoard(dir: dir)..setTitle('门口');
    board.addPage();
    board.flush();
    final again = MangaBoard(dir: dir);
    await again.load();
    expect(again.project.title, '门口');
    expect(again.project.pages, hasLength(2));
    expect(again.pageIndex, 1);
    File('${dir.path}/manga.json').writeAsStringSync('{坏的');
    final broken = MangaBoard(dir: dir);
    await broken.load();
    expect(broken.project.pages, hasLength(1));
    expect(
      dir.listSync().where((f) => f.path.contains('manga.json.bad-')),
      hasLength(1),
    );
  });

  test('分镜 Agent:系统提示带着作品,回复里的分镜放上画板,不碰成稿', () async {
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final board = MangaBoard()..setTitle('门口');
    final seen = <LlmRequest>[];
    final vm = StudioViewModel(
      config: service,
      streamChat: (req) {
        seen.add(req);
        return Stream.value(_storyboard);
      },
      manga: board,
    );
    expect(vm.send('排第一页'), isNull);
    await pumpEventQueue();
    final system = seen.single.messages.first['content'] as String;
    expect(system, contains('漫画分镜工作台'));
    expect(system, contains('【作品】门口'));
    expect(system, isNot(contains('〔译〕')));
    expect(readingOrder(board.page), hasLength(3));
    expect(board.project.characters.single.name, '阿禾');
    expect(vm.messages.last.toolSummary, contains('第 1 页 · 3 格'));
    expect(vm.body, isEmpty);
  });

  test('交给区域控制:另起一个系列放上去,原来的页不动', () {
    final service = tempConfig();
    final layout = LayoutBoard();
    final chat = StudioViewModel(
      config: service,
      streamChat: (_) => const Stream.empty(),
      layout: layout,
      layoutOnly: true,
    );
    layout.replace(
      const Layout(boxes: [LayoutBox(left: 0, top: 0, right: 99, bottom: 99)]),
    );
    final mine = chat.body;
    expect(mine, isNotEmpty);
    final l = const Layout(
      width: 864,
      height: 1216,
      boxes: [LayoutBox(left: 1, top: 1, right: 400, bottom: 600, name: '第1格')],
    );
    expect(chat.receiveLayout(l, name: '门口 第 1 页'), isNull);
    expect(chat.seriesName(chat.series), '门口 第 1 页');
    expect(layout.layout.boxes.single.name, '第1格');
    expect(chat.pages.first.blocks.map((b) => b.text).join(), mine);
  });

  testWidgets('分镜工作台能画出来:点一格看本格,抽分格出候选', (tester) async {
    tester.view.physicalSize = const Size(1900, 1100);
    tester.view.devicePixelRatio = 1;
    // 测试字体比真字体宽,对话栏顶栏放不下:缩小一点。
    tester.platformDispatcher.textScaleFactorTestValue = 0.8;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final board = MangaBoard();
    final chat = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      manga: board,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MangaWorkbench(
            board: board,
            chat: chat,
            config: chat.config,
            archive: ArchiveStore(),
            onToLayout: (_, _, _, _) => null,
            onToStudio: (_, _) => null,
            onOpenSettings: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('抽分格'));
    await tester.pump();
    expect(find.text('用这张'), findsOneWidget);
    await tester.tap(find.text('用这张'));
    await tester.pump();
    expect(board.draw, isNull);
    expect(readingOrder(board.page).length, greaterThanOrEqualTo(3));
    board.select(readingOrder(board.page).first);
    await tester.pump();
    expect(find.text('第 1 格'), findsOneWidget);
    await tester.tap(find.text('中景'));
    await tester.pump();
    expect(board.selectedPanel!.framing, '中景');
  });
}
