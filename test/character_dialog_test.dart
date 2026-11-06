import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/services/character_store.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/core/widgets.dart';
import 'package:penna/ui/features/characters/characters_page.dart';

void main() {
  testWidgets('角色保存失败保留编辑内容,解除写入阻碍后可原样重试', (tester) async {
    final dir = Directory.systemTemp.createTempSync('penna_character_dialog_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final blocked = Directory('${dir.path}/characters.json.tmp')..createSync();
    final store = CharacterStore(dir);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: Scaffold(body: CharactersPage(store: store, dict: null)),
      ),
    );
    await tester.tap(find.text('添加角色'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.descendant(
      of: find.byWidgetPredicate((w) => w is PennaField && w.label == label),
      matching: find.byType(TextField),
    );
    await tester.enterText(field('名字'), '保留草稿');
    await tester.enterText(field('提示词'), 'blue hair');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.cards, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('保存失败'), findsOneWidget);
    expect(tester.widget<TextField>(field('名字')).controller!.text, '保留草稿');
    expect(
      tester.widget<TextField>(field('提示词')).controller!.text,
      'blue hair',
    );

    blocked.deleteSync();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(store.cards.single.name, '保留草稿');
    expect(store.cards.single.prompt, 'blue hair');
  });
}
