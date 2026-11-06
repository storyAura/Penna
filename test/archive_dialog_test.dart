import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/core/widgets.dart';
import 'package:penna/ui/features/studio/prompt_pane.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  testWidgets('档案写入失败保留名称分类,成功重试后再关闭窗口', (tester) async {
    final dir = Directory.systemTemp.createTempSync('penna_archive_dialog_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final archive = ArchiveStore(File('${dir.path}/archive.json'));
    addTearDown(archive.dispose);
    final blocked = Directory('${archive.file!.path}.tmp')..createSync();
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      blocks: const [(text: '【主体】a blue bird', pinned: false)],
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: Scaffold(
          body: PromptPane(vm: vm, archive: archive),
        ),
      ),
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is PennaField && w.label == label),
      matching: find.byType(TextField),
    );
    await tester.enterText(field('名称'), '待保存的名称');
    await tester.enterText(field('分类'), '待保存的分类');
    await tester.pump();
    final save = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('保存'),
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(archive.entries, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('保存失败'), findsOneWidget);
    expect(tester.widget<TextField>(field('名称')).controller!.text, '待保存的名称');
    expect(tester.widget<TextField>(field('分类')).controller!.text, '待保存的分类');

    blocked.deleteSync();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(archive.entries.single.title, '待保存的名称');
    expect(archive.entries.single.category, '待保存的分类');
    expect(archive.entries.single.text, vm.labeledPrompt);
    expect(archive.entries.single.kind, archivePrompt);
  });
}
