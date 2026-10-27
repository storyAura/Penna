import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

void main() {
  testWidgets('点「成稿汇总」弹出大窗口,看得到完整的最终提示词', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      blocks: const [(text: '【主体】a fox\n【场景】snow', pinned: false)],
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );

    await tester.tap(
      find.descendant(of: find.byType(StudioPage), matching: find.text('成稿汇总')),
    );
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text(vm.finalPrompt)),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
