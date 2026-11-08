import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/manga/manga.dart';
import 'package:penna/core/harness/manga/manga_poses.dart';
import 'package:penna/core/harness/manga/manga_script.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/ui/features/manga/manga_board.dart';
import 'package:penna/ui/features/manga/manga_figure_editor.dart';
import 'package:penna/ui/features/manga/manga_figures.dart';
import 'package:penna/ui/features/manga/manga_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

const _two = [
  MangaCharacter(name: '阿禾', height: 174, build: '男'),
  MangaCharacter(name: '小岚', height: 150, build: '女'),
];

void main() {
  test('内置姿势:名字不重复、分类都认得;动作里长的词先认', () {
    final names = mangaPoses.map((p) => p.name).toList();
    expect(names.toSet(), hasLength(names.length));
    expect(mangaPoses.length, greaterThanOrEqualTo(30));
    expect(mangaPoses.every((p) => mangaPoseGroups.contains(p.group)), isTrue);
    expect(poseFromAction('坐在长椅上发呆').name, '坐椅子');
    expect(poseFromAction('双手叉腰').name, '叉腰');
    expect(poseFromAction('回头微笑').name, '回头');
    expect(poseFromAction('默默站着').name, '稍息');
    expect(poseNamed('不存在'), isNull);
  });

  test('每个姿势、每种朝向和体型都画得出来,外框不是空的', () {
    for (final pose in mangaPoses) {
      for (final yaw in [15.0, 45.0, 90.0, 180.0]) {
        for (final build in ['', '女', '男']) {
          final f = FigurePose(
            FigureSpec(
              anchor: const Offset(100, 300),
              fromFeet: true,
              height: 200,
              facing: -1,
              yaw: yaw,
              pose: pose,
              build: build,
            ),
          );
          expect(f.bounds.width, greaterThan(10), reason: pose.name);
          final recorder = ui.PictureRecorder();
          paintFigure(Canvas(recorder), f, selected: true);
          recorder.endRecording().dispose();
        }
      }
    }
    // 全身的脚踩在给的位置上。
    final stand = FigurePose(
      FigureSpec(
        anchor: const Offset(100, 300),
        fromFeet: true,
        height: 200,
        facing: 1,
        yaw: 15,
        pose: mangaPoses.first,
      ),
    );
    expect(stand.bounds.bottom, closeTo(300, 12));
    expect(stand.headTop.dy, lessThan(120));
  });

  test('排人偶:两个人的近景在窄格里不叠在一起,朝着对方;拖过的照拖到的地方', () {
    const box = Rect.fromLTWH(0, 0, 160, 300);
    const panel = MangaPanel(id: 'p', framing: '近景', cast: ['阿禾', '小岚']);
    final placed = layoutFigures(box, panel, _two);
    expect(placed, hasLength(2));
    final a = placed[0].pose, b = placed[1].pose;
    expect(a.headCenter.dx, lessThan(b.headCenter.dx));
    final overlap = a.bounds.intersect(b.bounds);
    expect(overlap.width < 0 || overlap.width < a.bounds.width * 0.35, isTrue);
    expect(a.spec.facing, 1);
    expect(b.spec.facing, -1);
    // 女生的体型、矮的人偶小一点。
    expect(b.spec.height, lessThan(a.spec.height));
    final moved = panel.withFigure(
      '小岚',
      const MangaFigure(x: 300, y: 500, pose: '叉腰', facing: 1, view: '背面'),
    );
    final again = layoutFigures(box, moved, _two)[1];
    expect(again.anchor, const Offset(48, 150));
    expect(again.pose.spec.pose.name, '叉腰');
    expect(again.pose.spec.yaw, 180);
  });

  test('人偶设定存盘读回一样;角色不出场了,它的设定不留', () {
    const f = MangaFigure(x: 120, y: 880, pose: '挥手', facing: -1, view: '侧面');
    final panel = const MangaPanel(id: 'p', cast: ['阿禾']).withFigure('阿禾', f);
    final back = MangaPanel.fromJson(jsonDecode(jsonEncode(panel.toJson())))!;
    expect(back.figureOf('阿禾').toJson(), f.toJson());
    expect(panel.copyWith(cast: ['小岚']).figures, isEmpty);
    expect(panel.withFigure('阿禾', const MangaFigure()).figures, isEmpty);
  });

  test('拖人偶:拖的时候只画,松手才算一步;锁着的格不动', () {
    final board = MangaBoard();
    final id = board.page.panels.keys.single;
    board.updatePanel(board.page.panels[id]!.copyWith(cast: ['阿禾']));
    board.moveFigure(id, '阿禾', 200, 700);
    expect(board.page.panels[id]!.figureOf('阿禾').x, isNull);
    expect(board.canvasPage.panels[id]!.figureOf('阿禾').x, 200);
    board.endFigureDrag();
    expect(board.page.panels[id]!.figureOf('阿禾').y, 700);
    board.undo();
    expect(board.page.panels[id]!.figureOf('阿禾').x, isNull);
    board.updatePanel(board.page.panels[id]!.copyWith(locked: true));
    board.setFigure(id, '阿禾', const MangaFigure(pose: '叉腰'));
    expect(board.page.panels[id]!.figureOf('阿禾').pose, '');
  });

  test('Agent 能在分镜里指定姿势;不认得的姿势名不收', () {
    final story = parseStoryboard(
      '{"pages": [{"page": 1, "panels": [{"cast": ["阿禾"], '
      '"poses": {"阿禾": "叉腰", "路人": "乱写的"}}]}]}',
    )!;
    expect(story.pages.single.panels.single.poses, {'阿禾': '叉腰'});
    final r = applyStoryboard(
      MangaProject.blank(),
      story,
      current: 0,
      seed: 's',
    );
    final panel = r.project.pages.single.panels.values.single;
    expect(panel.figureOf('阿禾').pose, '叉腰');
    expect(panelLine(panel), contains('姿势:阿禾=叉腰'));
  });

  testWidgets('点出场角色选中人偶,挑姿势、朝向、大小', (tester) async {
    tester.view.physicalSize = const Size(1900, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 0.8;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final board = MangaBoard()
      ..setCharacter(0, const MangaCharacter(name: '阿禾'), typing: false);
    final id = board.page.panels.keys.single;
    board.updatePanel(board.page.panels[id]!.copyWith(cast: ['阿禾']));
    board.select(id);
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
            onToLayout: (_, _, _, _, _) => null,
            onToStudio: (_, _) => null,
            onOpenSettings: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    final editor = find.byType(MangaFigureEditor);
    await tester.tap(find.descendant(of: editor, matching: find.text('阿禾')));
    await tester.pump();
    expect(board.selectedFigure, (panel: id, name: '阿禾'));
    await tester.tap(find.descendant(of: editor, matching: find.text('叉腰')));
    await tester.pump();
    expect(board.page.panels[id]!.figureOf('阿禾').pose, '叉腰');
    await tester.tap(find.descendant(of: editor, matching: find.text('朝左')));
    await tester.pump();
    expect(board.page.panels[id]!.figureOf('阿禾').facing, -1);
    await tester.tap(
      find.descendant(of: editor, matching: find.byIcon(Icons.add)),
    );
    await tester.pump();
    expect(board.page.panels[id]!.figureOf('阿禾').scale, 110);
  });
}
