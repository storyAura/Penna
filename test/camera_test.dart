import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/layout_3d.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_camera.dart';
import 'package:penna/ui/features/layout/layout_canvas.dart';
import 'package:penna/ui/features/layout/layout_fullscreen.dart';
import 'package:penna/ui/features/studio/page_strip.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

const _w = 832, _h = 1216;
const Span _box = (left: 100.0, top: 300.0, right: 400.0, bottom: 1000.0);

void _near(Span? got, Span want, {double tol = 1.5}) {
  expect(got, isNotNull);
  expect(got!.left, closeTo(want.left, tol));
  expect(got.top, closeTo(want.top, tol));
  expect(got.right, closeTo(want.right, tol));
  expect(got.bottom, closeTo(want.bottom, tol));
}

LayoutBox _boxAt(int l, int t, int r, int b, {String name = ''}) =>
    LayoutBox(left: l, top: t, right: r, bottom: b, name: name);

void main() {
  group('摄像机和体块', () {
    final view = CameraView(const Camera(), _w, _h);

    test('立起来的体块在没转过的镜头里投回原来的框', () {
      for (final hint in [
        (distance: 0.5, depth: 0.5, yaw: 0.0),
        (distance: 3.0, depth: 1.5, yaw: 40.0),
      ]) {
        _near(projectBody(liftBody(_box, view, hint), view), _box);
      }
    });

    test('镜头平移时近的挪得比远的多', () {
      final near = liftBody(_box, view, (distance: 0.6, depth: 0.5, yaw: 0));
      final far = liftBody(_box, view, (distance: 3, depth: 0.5, yaw: 0));
      final turned = CameraView(const Camera(panX: 0.2), _w, _h);
      final a = projectBody(near, turned)!, b = projectBody(far, turned)!;
      expect(
        (a.left - _box.left).abs(),
        greaterThan((b.left - _box.left).abs()),
      );
    });

    test('框挪了、放大了,体块跟着调到投影正好是新框', () {
      const turned = Camera(orbit: 30, pitch: 20);
      final v = CameraView(turned, _w, _h);
      final body = liftBody(_box, v, (distance: 1.2, depth: 1, yaw: 10));
      const moved = (left: 160.0, top: 250.0, right: 520.0, bottom: 1100.0);
      _near(projectBody(fitBody(body, moved, v)!, v), moved, tol: 2);
    });

    test('俯视时把框拉高,体块不会被拉成伸到镜头后面的长棍', () {
      // 正面立起一个站着的人,再从很陡的俯视角度把它的框往下拉长一倍。
      final body = liftBody(_box, view, (distance: 1.2, depth: 0.5, yaw: 0));
      final v = CameraView(const Camera(pitch: 75), _w, _h);
      final p = projectBody(body, v)!;
      final taller = (
        left: p.left,
        top: p.top,
        right: p.right,
        bottom: p.bottom + (p.bottom - p.top),
      );
      final fitted = fitBody(body, taller, v)!;
      final q = projectBody(fitted, v)!;
      expect(q.bottom - q.top, greaterThan((p.bottom - p.top) * 1.5));
      for (final (a, b) in [
        (fitted.w, body.w),
        (fitted.h, body.h),
        (fitted.d, body.d),
      ]) {
        expect(a, inInclusiveRange(b / 4 - 1e-9, b * 4 + 1e-9));
      }
    });

    test('转到镜头后面的投不出来', () {
      final body = liftBody(_box, view, (distance: 1, depth: 0.5, yaw: 0));
      // 镜头推过主体,还朝前看:主体在它身后。
      final behind = CameraView(const Camera(panZ: 1.5, distance: 0.1), _w, _h);
      expect(projectBody(body, behind), isNull);
    });

    test('摄像机读写一圈不变,超出范围的收回来', () {
      const c = Camera(orbit: 120, pitch: -30, roll: 5, distance: 2, fov: 35);
      expect(Camera.fromJson(jsonDecode(jsonEncode(c.toJson()))), c);
      expect(const Camera().copyWith(orbit: 200).orbit, -160);
      expect(const Camera().copyWith(pitch: 120).pitch, 89);
      expect(Camera.fromJson('x'), const Camera());
    });
  });

  group('布局里的体块', () {
    test('体块和镜头跟着布局存下来,交出去的 JSON 里没有', () {
      final l = Layout(
        width: _w,
        height: _h,
        camera: const Camera(orbit: 30),
        boxes: [
          liftBox(_boxAt(100, 300, 400, 1000, name: '小红'), const Layout()),
        ],
      );
      final back = Layout.fromJson(
        jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>,
      );
      expect(back.camera, l.camera);
      expect(back.boxes.single.body!.z, closeTo(l.boxes.single.body!.z, 1e-3));
      expect(mossLayoutJson(l), isNot(contains('body')));
      expect(mossLayoutJson(l, draft: true), contains('"distance"'));
    });

    test('Agent 写的 body 读成每块的体块提示', () {
      final read = readMossLayout(
        '{"width": 832, "height": 1216, "items": ['
        '{"name": "甲", "label": "character", "bbox": [0, 0, 300, 900], '
        '"body": {"distance": 0.8, "depth": 0.5, "yaw": -30}},'
        '{"name": "乙", "bbox": [400, 100, 800, 500]}],'
        '"bbox_coord_space": "abs", "bbox_format": "xyxy"}',
        width: _w,
        height: _h,
        ownSize: true,
      )!;
      expect(read.hints.keys, [0]);
      expect(read.hints[0]!.distance, 0.8);
      expect(read.hints[0]!.yaw, -30);
    });

    test('文字块不立体块', () {
      final text = liftBox(
        const LayoutBox(
          left: 0,
          top: 0,
          right: 400,
          bottom: 100,
          label: 'text',
        ),
        const Layout(),
      );
      expect(text.body, isNull);
    });
  });

  group('画板转镜头', () {
    LayoutBoard board() => LayoutBoard()
      ..replace(
        Layout(
          width: _w,
          height: _h,
          boxes: [
            liftBox(
              _boxAt(100, 300, 400, 1000, name: '前').copyWith(layer: 'front'),
              const Layout(),
              (distance: 0.7, depth: 0.5, yaw: 0),
            ),
            liftBox(
              _boxAt(450, 200, 700, 800, name: '后').copyWith(layer: 'back'),
              const Layout(),
              (distance: 2.5, depth: 0.5, yaw: 0),
            ),
          ],
        ),
      );

    test('转回正面时框回到原处', () {
      final b = board();
      final before = [for (final x in b.layout.boxes) x.span];
      b.setCamera(const Camera(orbit: 35, pitch: 15));
      expect(b.layout.boxes.first.left, isNot(100));
      b.setCamera(const Camera());
      for (final (i, x) in b.layout.boxes.indexed) {
        _near(x.span, before[i]);
      }
    });

    test('绕到背后时前后对调', () {
      // 拉远一点再绕:离得太近时远景会落到镜头后面。
      final b = board()..setCamera(const Camera(orbit: 180, distance: 4));
      expect(b.layout.boxes.first.name, '后');
      expect(b.layout.boxes.first.layer, 'front');
      expect(b.layout.boxes.last.layer, 'back');
      expect(b.cameraMoved, isTrue);
    });

    test('Agent 没写 body 时沿用原来那块的', () {
      final b = board();
      final z = b.layout.boxes.last.body!.z;
      expect(
        b.apply(
          '{"width": 832, "height": 1216, "items": ['
          '{"name": "前", "bbox": [100, 300, 400, 1000]},'
          '{"name": "后", "bbox": [450, 200, 700, 800]}],'
          '"bbox_coord_space": "abs", "bbox_format": "xyxy"}',
        ),
        isTrue,
      );
      expect(b.layout.boxes.last.body!.z, closeTo(z, 1e-6));
      expect(b.guessedBodies, isFalse);
    });

    test('自己画的框先猜一个体块', () {
      final b = LayoutBoard()..addBox(_boxAt(10, 10, 200, 300));
      expect(b.layout.boxes.single.body!.guessed, isTrue);
      expect(b.guessedBodies, isTrue);
    });
  });

  test('区域控制的改动记进操作记录,能回滚', () {
    final board = LayoutBoard();
    final chat = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      layout: board,
      layoutOnly: true,
    );
    board.addBox(_boxAt(10, 10, 200, 300, name: '小红'));
    board.mark('移动「小红」');
    board.updateBox(
      0,
      board.layout.boxes.single.copyWith(left: 20, right: 210),
    );
    board.updateBox(
      0,
      board.layout.boxes.single.copyWith(left: 30, right: 220),
    );
    expect(chat.actions, hasLength(2));
    expect(chat.actions.first.text, startsWith('移动「小红」'));
    expect(chat.rollback(1), isNull);
    expect(board.layout.boxes, isEmpty);
  });

  testWidgets('3D 视图:右键拖画布转镜头,面板上的箭头一步一步调', (tester) async {
    final board = LayoutBoard()
      ..addBox(_boxAt(100, 300, 400, 1000, name: '小红'))
      ..setThreeD(true)
      // 不选中:选中时摄像机栏下面多出体块那一截,按钮会被挤出测试窗口。
      ..select(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 300,
                height: 500,
                child: LayoutCanvas(board: board),
              ),
              ListenableBuilder(
                listenable: board,
                builder: (context, _) => CameraPanel(board: board),
              ),
            ],
          ),
        ),
      ),
    );
    final at = tester.getCenter(find.byType(LayoutCanvas));
    final g = await tester.startGesture(at, buttons: kSecondaryMouseButton);
    await g.moveBy(const Offset(50, 0));
    await g.up();
    await tester.pump();
    expect(board.layout.camera.orbit, greaterThan(0));
    final orbit = board.layout.camera.orbit;
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pump();
    expect(board.layout.camera.orbit, closeTo(orbit + 15, 1e-9));
    // 交给 Agent 统一在画布上面那一个按钮,摄像机栏里没有了。
    expect(find.text('按视角改描述'), findsNothing);
    await tester.tap(find.byIcon(Icons.restart_alt).first);
    await tester.pump();
    expect(board.layout.camera.isDefault, isTrue);
    expect(tester.takeException(), isNull);
  });

  group('自由镜头和屏蔽', () {
    test('转头时镜头位置不动,走动时朝前挪', () {
      const c = Camera(orbit: 20, pitch: 10, distance: 1.5);
      final eye = CameraView(c, _w, _h).eye;
      final turned = CameraView(lookAround(c, 30, -15), _w, _h);
      expect(turned.eye.x, closeTo(eye.x, 1e-9));
      expect(turned.eye.y, closeTo(eye.y, 1e-9));
      expect(turned.eye.z, closeTo(eye.z, 1e-9));
      final ahead = CameraView(walk(c, forward: 0.5), _w, _h);
      final moved = ahead.toCamera(eye);
      expect(moved.z, closeTo(-0.5, 1e-9));
    });

    test('3D 视图里文字块默认屏蔽,点过眼睛就照用户的', () {
      final b = LayoutBoard()
        ..replace(
          const Layout(
            boxes: [
              LayoutBox(
                left: 0,
                top: 0,
                right: 400,
                bottom: 100,
                label: 'text',
                text: 'SPRING',
              ),
              LayoutBox(left: 100, top: 200, right: 300, bottom: 800),
            ],
          ),
        );
      expect([b.shown(0), b.shown(1)], [true, true]);
      b.setThreeD(true);
      expect([b.shown(0), b.shown(1)], [false, true]);
      b.setHidden(0, false);
      b.setHidden(1, true);
      expect([b.shown(0), b.shown(1)], [true, false]);
      b.setThreeD(false);
      expect(b.shown(1), isFalse);
      // 屏蔽只管画布,交出去的 JSON 照常带着。
      expect(b.json, contains('SPRING'));
    });

    testWidgets('小键盘切视角,Shift+` 开自由镜头后 WASD 走动', (tester) async {
      final board = LayoutBoard()
        ..addBox(_boxAt(100, 300, 400, 1000, name: '小红'))
        ..setThreeD(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 500,
              child: LayoutCanvas(board: board),
            ),
          ),
        ),
      );
      // 键盘要画布有焦点:点一下拿过来。
      await tester.tapAt(tester.getCenter(find.byType(LayoutCanvas)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);
      expect(board.layout.camera.orbit, -90);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(board.layout.camera.orbit, -180);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(board.layout.camera.isDefault, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backquote);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(board.freeCam, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      for (var k = 0; k < 10; k++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.pump(const Duration(milliseconds: 16));
      expect(board.layout.camera.panZ, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(board.freeCam, isFalse);
    });
  });

  test('转到镜头外看不见的块算屏蔽着;常用尺寸最多存 8 个', () {
    final b = LayoutBoard()
      ..addBox(_boxAt(100, 300, 400, 1000, name: '小红'))
      ..setThreeD(true);
    expect(b.shown(0), isTrue);
    // 镜头推过它、还朝前看:它在镜头后面。
    b.setCamera(const Camera(panZ: 1.5, distance: 0.1));
    expect(b.layout.boxes.single.offscreen, isTrue);
    expect(b.shown(0), isFalse);

    for (var i = 0; i < LayoutBoard.maxSizes + 2; i++) {
      b.setSize(512 + 16 * i, 512);
      b.saveSize();
    }
    expect(b.sizes, hasLength(LayoutBoard.maxSizes));
    expect(b.saveSize(), isFalse);
  });

  testWidgets('系列再多也只画眼前这个:箭头一个一个换,新建的系列跟着成为眼前这个', (tester) async {
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
    );
    // 系列没有个数上限。
    for (var i = 0; i < 24; i++) {
      expect(vm.addPage(newSeries: true), isNull);
    }
    expect(vm.series, isNot(vm.pages.first.series));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1600,
            child: ListenableBuilder(
              listenable: vm,
              builder: (context, _) => PageStrip(vm: vm),
            ),
          ),
        ),
      ),
    );
    // 眼前是第 25 个系列,别的不画。
    expect(find.text('系列 25'), findsOneWidget);
    expect(find.text('系列 1'), findsNothing);
    expect(find.text('25/25'), findsOneWidget);
    await tester.tap(find.byTooltip('上一个系列'));
    await tester.pump();
    expect(find.text('系列 24'), findsOneWidget);
    expect(find.text('系列 25'), findsNothing);
    expect(find.text('24/25'), findsOneWidget);
    // 新建一个:它成为眼前这个。
    expect(vm.addPage(newSeries: true), isNull);
    await tester.pump();
    expect(find.text('系列 26'), findsOneWidget);
    expect(find.text('26/26'), findsOneWidget);
  });

  testWidgets('一个系列页多、页签条窄时,系列框里的页签折行,不溢出', (tester) async {
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
    );
    for (var i = 0; i < 12; i++) {
      vm.addPage(toSeries: vm.series);
      vm.renamePage(vm.pages.length - 1, '很长的页名$i');
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: ListenableBuilder(
              listenable: vm,
              builder: (context, _) => PageStrip(vm: vm),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // 最后一页的页签还在条里,没被挤出右边。
    final last = tester.getRect(find.textContaining('很长的页名11'));
    expect(last.right, lessThanOrEqualTo(500));
  });

  testWidgets('选中一块后在摄像机栏里直接改它的体块,框跟着重新投出来', (tester) async {
    final board = LayoutBoard()
      ..addBox(_boxAt(100, 300, 400, 1000, name: '小红'))
      ..setThreeD(true)
      ..select(0);
    final before = board.layout.boxes.single;
    expect(before.body!.guessed, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 1200,
            child: ListenableBuilder(
              listenable: board,
              builder: (context, _) => CameraPanel(board: board),
            ),
          ),
        ),
      ),
    );
    expect(find.text('体块 · 小红'), findsOneWidget);
    // 「位置 X」那一行的右箭头:往右挪一步。名字和数值在里面一层的 Row,
    // 两个箭头在外面一层。
    final row = find
        .ancestor(of: find.text('位置 X'), matching: find.byType(Row))
        .at(1);
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
    );
    await tester.pump();
    final after = board.layout.boxes.single;
    expect(after.body!.x, closeTo(before.body!.x + 0.05, 1e-9));
    expect(after.body!.guessed, isFalse);
    expect(after.left, greaterThan(before.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('全屏摆放:画布铺满窗口,3D 时有摄像机栏,Esc 回去', (tester) async {
    final board = LayoutBoard()
      ..addBox(_boxAt(100, 300, 400, 1000, name: '小红'))
      ..setThreeD(true)
      ..select(null);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFullCanvas(
              context,
              board: board,
              onToggle3D: () => board.setThreeD(!board.threeD),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(LayoutCanvas), findsOneWidget);
    expect(find.byType(CameraPanel), findsOneWidget);
    expect(find.text('退出全屏'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LayoutCanvas), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
