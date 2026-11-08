import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

void main() {
  testWidgets('200%缩放的小视口可滚到右侧操作,导航固定且放大窗口不丢输入', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = tempConfig()
      ..update(
        const AppConfig().putLlm(
          const LlmProfile(
            id: 'test',
            name: '测试',
            baseUrl: 'http://localhost',
            model: 'm',
          ),
        ),
      );
    final vm = StudioViewModel(
      config: config,
      streamChat: (_) => Stream.value('收到'),
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final size = media.size / 2;
          return MediaQuery(
            data: media.copyWith(
              size: size,
              devicePixelRatio: media.devicePixelRatio * 2,
            ),
            child: FittedBox(
              child: SizedBox.fromSize(size: size, child: child),
            ),
          );
        },
        home: AppShell(vm: vm, config: config, skills: tempSkills()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final nav = tester.getRect(find.byTooltip('设置'));
    final viewport = find.byKey(const ValueKey('desktop-content'));
    final bar = find.descendant(
      of: viewport,
      matching: find.byKey(const ValueKey('desktop-horizontal')),
    );
    final rect = tester.getRect(bar);
    await tester.dragFrom(
      rect.bottomLeft + const Offset(300, -6),
      const Offset(900, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final scroll = tester.widget<RawScrollbar>(bar).controller!;
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(tester.getRect(find.byTooltip('设置')), nav);

    final vertical = find.descendant(
      of: viewport,
      matching: find.byKey(const ValueKey('desktop-vertical')),
    );
    final verticalRect = tester.getRect(vertical);
    await tester.dragFrom(
      verticalRect.topRight + const Offset(-6, 200),
      const Offset(0, 600),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final verticalScroll = tester.widget<RawScrollbar>(vertical).controller!;
    expect(verticalScroll.offset, verticalScroll.position.maxScrollExtent);

    Finder inStudio(Finder finder) =>
        find.descendant(of: find.byType(StudioPage), matching: finder);
    final input = inStudio(
      find.byWidgetPredicate((w) => w is TextField && w.maxLines == 10),
    );
    await tester.enterText(input, '测试发送');
    await tester.tap(inStudio(find.byTooltip('发送')));
    await tester.pumpAndSettle();
    expect(vm.messages.first.text, '测试发送');
    await tester.enterText(input, '保留输入');
    tester.view.physicalSize = const Size(2880, 1800);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, '保留输入');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
