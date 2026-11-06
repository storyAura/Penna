import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/l10n/l10n.dart';
import 'package:penna/ui/core/look_switcher.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/core/widgets.dart';
import 'package:penna/ui/features/settings/settings_app_section.dart';

import 'fixtures.dart';

void main() {
  tearDown(() => applyLook(const AppConfig()));

  testWidgets('连续切换主题并在动画中卸载会释放所有截图', (tester) async {
    final alive = <ui.Image>{};
    var created = 0;
    final onCreate = ui.Image.onCreate;
    final onDispose = ui.Image.onDispose;
    ui.Image.onCreate = (image) {
      created++;
      alive.add(image);
      onCreate?.call(image);
    };
    ui.Image.onDispose = (image) {
      alive.remove(image);
      onDispose?.call(image);
    };
    addTearDown(() {
      ui.Image.onCreate = onCreate;
      ui.Image.onDispose = onDispose;
    });
    final config = tempConfig();
    await tester.pumpWidget(
      MaterialApp(
        home: LookSwitcher(
          config: config,
          child: Builder(builder: (_) => ColoredBox(color: PennaColors.bg)),
        ),
      ),
    );
    for (final mode in ['on', 'off', 'on']) {
      config.update(config.config.copyWith(darkTheme: mode));
      await tester.pump(const Duration(milliseconds: 40));
      expect(PennaColors.isDark, mode == 'on');
    }
    expect(created, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(alive, isEmpty);
    expect(tester.binding.transientCallbackCount, 0);
  });

  test('tr:查不到就用原文,{0} 按顺序填', () {
    useLanguage('xx');
    expect(currentLanguage, 'zh-Hans');
    expect(tr('取消'), '取消');
    expect(tr('第 {0} 页,共 {1} 页', [2, 5]), '第 2 页,共 5 页');
    useLanguage('en');
    expect(tr('取消'), 'Cancel');
  });

  test('界面大小:存盘读回,超出范围的截到 1~2 倍', () {
    const cfg = AppConfig(uiScale: 1.5);
    expect(AppConfig.fromJson(cfg.toJson()).uiScale, 1.5);
    expect(AppConfig.fromJson(const <String, dynamic>{}).uiScale, 1);
    expect(AppConfig.fromJson(<String, dynamic>{'uiScale': 9}).uiScale, 2);
  });

  testWidgets('界面放大、上面有标题栏时,右键菜单还是出在鼠标那里', (tester) async {
    late BuildContext ctx;
    // 测试窗口 800×600,按 400×300 排版再放大一倍,和「界面大小」200% 一样。
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 400,
            height: 300,
            child: Column(
              children: [
                const SizedBox(height: 32),
                Expanded(child: child!),
              ],
            ),
          ),
        ),
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    const at = Offset(300, 200);
    popMenu(ctx, at, ['改名']);
    await tester.pumpAndSettle();
    final menu = tester.getTopLeft(find.byType(PopupMenuItem<String>));
    expect((menu - at).distance, lessThan(40));
  });

  testWidgets('切到深色:换配色,旧画面盖着慢慢露出新画面', (tester) async {
    final config = tempConfig();
    await tester.pumpWidget(
      MaterialApp(
        home: LookSwitcher(
          config: config,
          child: Builder(builder: (_) => ColoredBox(color: PennaColors.bg)),
        ),
      ),
    );
    expect(PennaColors.isDark, isFalse);

    config.update(config.config.copyWith(darkTheme: 'on'));
    await tester.pump();
    expect(PennaColors.isDark, isTrue);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpAndSettle();
    expect(PennaColors.isDark, isTrue);

    config.update(config.config.copyWith(language: 'ja'));
    await tester.pump();
    expect(currentLanguage, 'ja');
  });

  testWidgets('跟随系统:系统换深浅色时跟着换,其他模式不跟', (tester) async {
    final config = tempConfig();
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: LookSwitcher(config: config, child: const SizedBox()),
      ),
    );
    expect(config.config.darkTheme, 'system');
    expect(PennaColors.isDark, isFalse);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(PennaColors.isDark, isTrue);

    config.update(config.config.copyWith(darkTheme: 'off'));
    await tester.pumpAndSettle();
    expect(PennaColors.isDark, isFalse);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(PennaColors.isDark, isFalse);
  });

  testWidgets('自定义时间段:到点就换,不用动设置', (tester) async {
    final config = tempConfig();
    var clock = DateTime(2026, 11, 3, 18, 59);
    await tester.pumpWidget(
      MaterialApp(
        home: LookSwitcher(
          config: config,
          now: () => clock,
          child: const SizedBox(),
        ),
      ),
    );
    config.update(config.config.copyWith(darkTheme: 'schedule'));
    await tester.pumpAndSettle();
    expect(PennaColors.isDark, isFalse);

    clock = DateTime(2026, 11, 3, 19);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(PennaColors.isDark, isTrue);
  });

  group('深色模式的设置', () {
    bool at(AppConfig c, int hour, [int minute = 0]) =>
        c.darkAt(systemDark: false, now: DateTime(2026, 11, 3, hour, minute));

    test('时间段跨半夜:19:00 到次日 07:00,结束那一分钟算浅色', () {
      const c = AppConfig(darkTheme: 'schedule', darkFrom: 1140, darkTo: 420);
      expect(at(c, 18, 59), isFalse);
      expect(at(c, 19), isTrue);
      expect(at(c, 0), isTrue);
      expect(at(c, 6, 59), isTrue);
      expect(at(c, 7), isFalse);
    });

    test('时间段在同一天:09:00 到 17:00', () {
      const c = AppConfig(darkTheme: 'schedule', darkFrom: 540, darkTo: 1020);
      expect(at(c, 8, 59), isFalse);
      expect(at(c, 9), isTrue);
      expect(at(c, 16, 59), isTrue);
      expect(at(c, 17), isFalse);
    });

    test('开始和结束相同时不变深色;其他模式不看时间', () {
      expect(
        at(const AppConfig(darkTheme: 'schedule', darkFrom: 60, darkTo: 60), 1),
        isFalse,
      );
      expect(at(const AppConfig(darkTheme: 'on'), 12), isTrue);
      expect(at(const AppConfig(darkTheme: 'off'), 23), isFalse);
      expect(
        const AppConfig().darkAt(systemDark: true, now: DateTime(2026)),
        isTrue,
      );
    });

    test('旧设置搬过来:开着的还开着,关着的还关着;新装跟随系统', () {
      AppConfig read(Map<String, dynamic> m) => AppConfig.fromJson(m);
      expect(read({'darkMode': true}).darkTheme, 'on');
      expect(read({'darkMode': false}).darkTheme, 'off');
      expect(read({}).darkTheme, 'system');

      const c = AppConfig(darkTheme: 'schedule', darkFrom: 1, darkTo: 2);
      final back = read(c.toJson());
      expect(back.darkTheme, 'schedule');
      expect(back.darkFrom, 1);
      expect(back.darkTo, 2);
      expect(read({'darkFrom': 99999}).darkFrom, 1439);
      expect(read({'darkTheme': 'auto'}).darkTheme, 'system');

      // 旧的正式版只认 darkMode:始终开启时它也要是深色。
      expect(const AppConfig(darkTheme: 'on').toJson()['darkMode'], isTrue);
      expect(c.toJson()['darkMode'], isFalse);
    });

    test('时间的写法:能读 7、7:30、07:30,读不了的给 null', () {
      expect(parseClock('7'), 420);
      expect(parseClock('7:30'), 450);
      expect(parseClock(' 07:30 '), 450);
      expect(parseClock('23:59'), 1439);
      expect(parseClock('24:00'), isNull);
      expect(parseClock('7:60'), isNull);
      expect(parseClock('7:3'), isNull);
      expect(parseClock(''), isNull);
      expect(clockText(450), '07:30');
    });
  });

  testWidgets('右键菜单:给了 onPaste 时空输入框也有「粘贴」,点了交给它', (tester) async {
    var pasted = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            contextMenuBuilder: (context, state) =>
                pennaTextMenu(context, state, onPaste: () => pasted++),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('粘贴'), findsOneWidget);
    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();
    expect(pasted, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('减少动画时主题立即切换,不运行扩散动画', (tester) async {
    final config = tempConfig();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: LookSwitcher(
          config: config,
          child: Builder(builder: (_) => ColoredBox(color: PennaColors.bg)),
        ),
      ),
    );

    config.update(config.config.copyWith(darkTheme: 'on'));
    await tester.pump();

    expect(PennaColors.isDark, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
