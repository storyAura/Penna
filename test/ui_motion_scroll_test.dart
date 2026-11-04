import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/scroll_strip.dart';
import 'package:penna/ui/core/smooth_scroll.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/chat_tabs.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

Future<ScrollController> _strip(
  WidgetTester tester,
  ScrollController parent,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: parent,
          children: [
            ScrollStrip(
              visible: 2,
              bar: false,
              children: List.generate(
                10,
                (_) => const SizedBox(width: 100, height: 32),
              ),
            ),
            const SizedBox(height: 1500),
          ],
        ),
      ),
    ),
  );
  return tester
      .widget<Scrollbar>(
        find.descendant(
          of: find.byType(ScrollStrip),
          matching: find.byType(Scrollbar),
        ),
      )
      .controller!;
}

void main() {
  testWidgets('横向条只为显示出来的按钮提供一次键盘焦点', (tester) async {
    final visited = <int>[];
    var reachedEnd = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                autofocus: true,
                onPressed: () {},
                child: const Text('开始'),
              ),
              ScrollStrip(
                visible: 2,
                children: [
                  for (var i = 0; i < 3; i++)
                    TextButton(
                      onPressed: () {},
                      onFocusChange: (focused) {
                        if (focused) visited.add(i);
                      },
                      child: Text('按钮 $i'),
                    ),
                ],
              ),
              TextButton(
                onPressed: () {},
                onFocusChange: (focused) => reachedEnd = focused,
                child: const Text('结束'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && !reachedEnd; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }

    expect(reachedEnd, isTrue);
    expect(visited, [0, 1, 2]);
  });

  testWidgets('横向按钮条的一次水平滚轮只滚一次', (tester) async {
    final parent = ScrollController();
    addTearDown(parent.dispose);
    final strip = await _strip(tester, parent);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ScrollStrip)),
        scrollDelta: const Offset(100, 0),
      ),
    );
    await tester.pump();

    expect(strip.offset, 100);
    expect(parent.offset, 0);
  });

  testWidgets('按钮条把纵向滚轮转为横滚后,父列表不再重复滚动', (tester) async {
    final parent = ScrollController();
    addTearDown(parent.dispose);
    final strip = await _strip(tester, parent);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ScrollStrip)),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pump();

    expect(strip.offset, 100);
    expect(parent.offset, 0);
  });

  testWidgets('按钮条已滚到尽头时,纵向滚轮仍能交给父列表', (tester) async {
    final parent = ScrollController();
    addTearDown(parent.dispose);
    final strip = await _strip(tester, parent);
    strip.jumpTo(strip.position.maxScrollExtent);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ScrollStrip)),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pump();

    expect(strip.offset, strip.position.maxScrollExtent);
    expect(parent.offset, 100);
  });

  testWidgets('对话标签的一次水平滚轮只滚一次', (tester) async {
    final vm =
        StudioViewModel(
          config: tempConfig(),
          streamChat: (_) => const Stream.empty(),
        )..restore({
          'chatId': '0',
          'chats': [
            for (var i = 1; i < 12; i++)
              {
                'id': '$i',
                'messages': [
                  ChatMessage(
                    fromUser: true,
                    text: '第 $i 场对话',
                    time: DateTime(2026, 11, 4),
                  ).toJson(),
                ],
              },
          ],
        });
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 300, child: ChatTabs(vm: vm)),
          ),
        ),
      ),
    );
    final scroll = tester.widget<Scrollbar>(find.byType(Scrollbar)).controller!;

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ListView)),
        scrollDelta: const Offset(100, 0),
      ),
    );
    await tester.pump();

    expect(scroll.offset, 100);
  });

  testWidgets('减少动画时滚轮立即到位', (tester) async {
    final scroll = SmoothScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ListView(
          controller: scroll,
          children: const [SizedBox(height: 2000)],
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(ListView)),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pump();

    expect(scroll.offset, 120);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('普通滚轮仍平滑移动,连续滚动累加到目标', (tester) async {
    final scroll = SmoothScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: scroll,
          children: const [SizedBox(height: 2000)],
        ),
      ),
    );
    final at = tester.getCenter(find.byType(ListView));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(scroll.offset, greaterThan(0));
    expect(scroll.offset, lessThan(120));

    await tester.sendEventToBinding(
      PointerScrollEvent(position: at, scrollDelta: const Offset(0, 120)),
    );
    await tester.pumpAndSettle();

    expect(scroll.offset, 240);
  });

  testWidgets('切页暂停后台打字动画,返回时恢复', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = tempConfig()
      ..update(
        const AppConfig().putLlm(
          const LlmProfile(
            id: 'a',
            name: '测试模型',
            baseUrl: 'http://localhost/v1',
            model: 'm',
          ),
        ),
      );
    final reply = StreamController<String>();
    final vm = StudioViewModel(config: config, streamChat: (_) => reply.stream);
    addTearDown(() async {
      vm.dispose();
      await reply.close();
    });
    expect(vm.send('等待回复'), isNull);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: config, skills: tempSkills()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(vm.isStreaming, isTrue);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.tap(find.byTooltip('工作台'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(vm.isStreaming, isTrue);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });

  testWidgets('减少动画时切换页面和导航选中态立即完成', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );

    await tester.tap(find.byTooltip('设置'));
    await tester.pump();

    expect(tester.binding.transientCallbackCount, 0);
  });
}
