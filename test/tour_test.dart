import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/tour_spot.dart';
import 'package:penna/ui/features/tour/mascot_perch.dart';
import 'package:penna/ui/features/tour/pixel_mascot.dart';
import 'package:penna/ui/features/tour/tour_overlay.dart';
import 'package:penna/ui/features/tour/tour_steps.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

void main() {
  test('新装没看过教程,旧设置当作看过', () {
    expect(const AppConfig().tutorialSeen, isFalse);
    expect(AppConfig.fromJson(<String, dynamic>{}).tutorialSeen, isTrue);
    final seen = const AppConfig().copyWith(tutorialSeen: true);
    expect(AppConfig.fromJson(seen.toJson()).tutorialSeen, isTrue);
  });

  testWidgets('召唤出来的吉祥物:点她抱头说一句,过一会儿接着打瞌睡;透明的地方点不到她', (tester) async {
    // 图要真的解码,假时钟里等不到。
    await tester.runAsync(precacheMascot);
    final anchor = GlobalKey();
    var below = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => below++,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: SizedBox(key: anchor),
            ),
            Positioned.fill(child: MascotPerch(anchor: anchor)),
          ],
        ),
      ),
    );
    await tester.pump();
    final mascot = find.byType(PixelMascot);
    expect(tester.widget<PixelMascot>(mascot).look, MascotLook.doze);

    // 图的左上角是透明的:点穿到底下去。
    await tester.tapAt(tester.getTopLeft(mascot) + const Offset(1, 1));
    expect(below, 1);

    // 点她的裙子。
    final rect = tester.getRect(mascot);
    await tester.tapAt(
      rect.topLeft + Offset(rect.width * 0.5, rect.height * 0.55),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<PixelMascot>(mascot).look, MascotLook.cower);
    expect(below, 1);
    expect(find.textContaining(RegExp('干、干嘛|别、别戳|长不高|才不是在等你')), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 400)); // 气泡淡出
    expect(tester.widget<PixelMascot>(mascot).look, MascotLook.doze);
    expect(find.textContaining(RegExp('干、干嘛|别、别戳|长不高|才不是在等你')), findsNothing);
    // 停掉吉祥物的计时器,测试才能收尾。
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('吉祥物跟着对话:写回复时盯着看,写完比耶,出错慌张,之后醒着坐一会儿再睡', (tester) async {
    await tester.runAsync(precacheMascot);
    var reply = StreamController<String>();
    final vm = StudioViewModel(
      config: tempConfig()
        ..update(
          const AppConfig(
            llms: [
              LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x', model: 'm'),
            ],
          ),
        ),
      streamChat: (_) => reply.stream,
    );
    final anchor = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: SizedBox(key: anchor),
            ),
            Positioned.fill(
              child: MascotPerch(anchor: anchor, chat: vm),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    MascotLook look() =>
        tester.widget<PixelMascot>(find.byType(PixelMascot)).look;
    expect(look(), MascotLook.doze);

    vm.send('你好');
    await tester.pump();
    expect(look(), MascotLook.watch);
    reply.add('好');
    await reply.close();
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    expect(look(), MascotLook.peace);
    await tester.pump(const Duration(seconds: 4));
    expect(look(), MascotLook.sit);
    await tester.pump(const Duration(seconds: 30));
    expect(look(), MascotLook.doze);

    reply = StreamController<String>();
    vm.send('再来');
    await tester.pump();
    reply.addError(Exception('x'));
    await reply.close();
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
    expect(look(), MascotLook.panic);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('召唤出来时快捷操作那一排在最左边给她让位置', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(precacheMascot);
    final vm = sampleStudio();
    vm.config.update(vm.config.config.copyWith(mascot: true));
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );
    await tester.pump();
    final chip = tester.getRect(
      find
          .descendant(
            of: find.byType(StudioPage),
            matching: find.text(defaultQuickActions.first.label),
          )
          .first,
    );
    final perched = tester.getRect(find.byType(PixelMascot));
    // 快捷操作的按钮都在她的右边,不被她的腿盖住。
    expect(chip.left, greaterThan(perched.right - 8));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('第一次启动走教程:← → 翻页,Esc 跳过后记住', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = sampleStudio();
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          vm: vm,
          config: vm.config,
          skills: tempSkills(),
          showTutorial: true,
        ),
      ),
    );
    // 教程每帧量一次位置,pumpAndSettle 等不到。
    Future<void> settle() => tester.pump(const Duration(milliseconds: 400));
    await settle();
    expect(find.text('欢迎来到 Penna'), findsOneWidget);

    // 几页一直都建着:每一步要高亮的那块都找得到。
    for (final s in tourSteps) {
      if (s.spot case final id?) {
        expect(tourKey(id).currentContext, isNotNull, reason: id);
      }
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle();
    expect(find.text('侧栏'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle();
    expect(find.text('欢迎来到 Penna'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();
    expect(find.byType(TourOverlay), findsNothing);
    expect(vm.config.config.tutorialSeen, isTrue);
  });
}
