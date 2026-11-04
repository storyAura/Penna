import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/l10n/l10n.dart';
import 'package:penna/ui/core/look_switcher.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/core/widgets.dart';

import 'fixtures.dart';

void main() {
  tearDown(() => applyLook(const AppConfig()));

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

    config.update(config.config.copyWith(darkMode: true));
    await tester.pump();
    expect(PennaColors.isDark, isTrue);
    expect(find.byType(CustomPaint), findsWidgets);

    await tester.pumpAndSettle();
    expect(PennaColors.isDark, isTrue);

    config.update(config.config.copyWith(language: 'ja'));
    await tester.pump();
    expect(currentLanguage, 'ja');
  });

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

    config.update(config.config.copyWith(darkMode: true));
    await tester.pump();

    expect(PennaColors.isDark, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
