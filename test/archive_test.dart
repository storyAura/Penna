import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

void main() {
  group('档案库', () {
    test('元数据写入失败时换图和删除都保留原档案及原图', () async {
      final dir = Directory.systemTemp.createTempSync('penna_archive_failure_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/archive.json');
      final store = ArchiveStore(file)..add(text: 'keep');
      store.setImage(store.entries.single.id, Uint8List.fromList([1, 2, 3]));
      final original = store.entries.single;
      final saved = file.readAsStringSync();
      Directory('${file.path}.tmp').createSync();

      expect(
        store.setImage(original.id, Uint8List.fromList([4, 5, 6])),
        isFalse,
      );
      expect(store.entries.single, original);
      expect(File(original.image).readAsBytesSync(), [1, 2, 3]);
      expect(Directory('${dir.path}/archive').listSync(), hasLength(1));
      expect(store.remove(original.id), isFalse);
      expect(store.entries.single, original);
      expect(File(original.image).readAsBytesSync(), [1, 2, 3]);
      expect(file.readAsStringSync(), saved);
      expect(store.add(text: 'cannot save'), isNull);
      expect(store.entries.single, original);
      final reopened = ArchiveStore(file);
      await reopened.load();
      expect(reopened.entries.single, original);
    });

    test('拖着换顺序;换预览图存成文件,存盘读回还在,删条目时图跟着删', () async {
      final dir = Directory.systemTemp.createTempSync('penna_archive');
      final store = ArchiveStore(File('${dir.path}/archive.json'));
      for (final (i, t) in ['a', 'b', 'c'].indexed) {
        store.add(text: t, now: DateTime(2026, 1, 1, i));
      }
      String order() => store.entries.map((e) => e.text).join();
      expect(order(), 'cba');
      final a = store.entries.last.id, c = store.entries.first.id;
      store.move(a, c);
      expect(order(), 'acb');

      expect(store.setImage(a, Uint8List.fromList([1, 2, 3])), isTrue);
      final image = store.entries.first.image;
      expect(File(image).readAsBytesSync(), [1, 2, 3]);
      final again = ArchiveStore(File('${dir.path}/archive.json'));
      await again.load();
      expect(again.entries.map((e) => e.image).first, image);
      expect(again.entries.map((e) => e.text).join(), 'acb');

      expect(store.remove(a), isTrue);
      expect(File(image).existsSync(), isFalse);
      // 只在内存里的不存图。
      expect(ArchiveStore().setImage('x', Uint8List(1)), isFalse);
    });

    test('存一条带时间和分类;空的不存;分类没填归未分类;能删', () {
      final store = ArchiveStore();
      expect(store.add(text: '  '), isNull);
      final id = store.add(text: 'a fox', now: DateTime(2026, 10, 9, 8));
      expect(id, store.entries.single.id);
      store.add(
        text: '【主体】a cat',
        title: '猫',
        category: ' 动物 ',
        now: DateTime(2026, 10, 9, 9),
      );

      expect(store.entries.map((e) => e.title), ['猫', '']);
      expect(store.entries.first.time, DateTime(2026, 10, 9, 9));
      expect(store.categoriesOf(archivePrompt), ['动物', uncategorized]);

      store.remove(store.entries.first.id);
      expect(store.entries.single.text, 'a fox');
    });

    test('存盘后重新打开还在;读不了的文件改名留底', () async {
      final dir = Directory.systemTemp.createTempSync('penna_archive');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/archive.json');
      ArchiveStore(file).add(text: 'a fox', title: '狐', category: '动物');

      final reopened = ArchiveStore(file);
      await reopened.load();
      expect(reopened.entries.single.title, '狐');
      expect(reopened.entries.single.category, '动物');

      file.writeAsStringSync('{坏的');
      final broken = ArchiveStore(file);
      await broken.load();
      expect(broken.entries, isEmpty);
      expect(
        dir.listSync().map((f) => f.path),
        contains(contains('archive.json.bad-')),
      );
    });
  });

  testWidgets('工作区点保存 → 档案库里看得到,能按分类筛、放回成稿', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      blocks: const [(text: '【主体】a fox', pinned: false)],
    );
    addTearDown(vm.dispose);
    final archive = ArchiveStore()..add(text: 'old cat', category: '动物');
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(
          vm: vm,
          config: vm.config,
          skills: tempSkills(),
          archive: archive,
        ),
      ),
    );

    // 区域控制工作台也有「保存」:点工作台这一页的。
    await tester.tap(
      find.descendant(of: find.byType(StudioPage), matching: find.text('保存')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '可留空'), '狐狸');
    await tester.enterText(find.widgetWithText(TextField, '动物'), '写实');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(archive.entries.first.text, '【主体】a fox');
    expect(archive.entries.first.category, '写实');

    await tester.tap(find.byTooltip('档案库'));
    await tester.pumpAndSettle();
    expect(find.text('狐狸'), findsOneWidget);
    expect(find.text('old cat'), findsOneWidget);

    await tester.tap(find.widgetWithText(GestureDetector, '动物').first);
    await tester.pumpAndSettle();
    expect(find.text('狐狸'), findsNothing);

    await tester.tap(find.text('放回成稿'));
    await tester.pumpAndSettle();
    expect(vm.pending!.added, 'old cat');
  });
}
