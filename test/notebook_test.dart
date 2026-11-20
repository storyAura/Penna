import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/services/notebook_store.dart';
import 'package:penna/ui/features/notebook/notebook_page.dart';

void main() {
  test('一个本子里放几条,各有名字和内容;改、删都只动那一条', () {
    final store = NotebookStore();
    final book = store.addBook('灵感');
    // 新本子自带一条空的。
    final a = store.books.single.notes.single.id;
    final b = store.addNote(book);
    store.updateNote(book, a, title: '光影', text: 'rim light');
    store.updateNote(book, b, text: 'low angle');

    final notes = store.books.single.notes;
    expect(store.books.single.name, '灵感');
    expect(notes.map((n) => n.title), ['光影', '']);
    expect(notes.map((n) => n.text), ['rim light', 'low angle']);

    store.removeNote(book, a);
    expect(store.books.single.notes.single.text, 'low angle');
    store.renameBook(book, '  ');
    expect(store.books.single.name, '灵感');
    store.removeBook(book);
    expect(store.books, isEmpty);
  });

  test('Agent 存一条:本子名带书名号也对上已有的本子', () {
    final store = NotebookStore()..addBook('风格');
    store.putNote('「风格」', '纪实', 'film grain');
    expect(store.books.single.notes.single.title, '纪实');
  });

  test('存进文件、读回来一样;读不了的文件留底', () async {
    final dir = Directory.systemTemp.createTempSync('penna-notes-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/notebooks.json');
    final store = NotebookStore(file);
    final book = store.addBook('角色');
    final note = store.books.single.notes.single.id;
    store.updateNote(book, note, title: '若叶睦', text: '灰发');

    final back = NotebookStore(file);
    await back.load();
    expect(back.books.single.name, '角色');
    expect(back.books.single.notes.single.title, '若叶睦');
    expect(back.books.single.notes.single.text, '灰发');

    file.writeAsStringSync('{坏的');
    final broken = NotebookStore(file);
    await broken.load();
    expect(broken.books, isEmpty);
    expect(
      dir.listSync().any((f) => f.path.contains('notebooks.json.bad-')),
      isTrue,
    );
  });

  testWidgets('页面上新建本子、加一条、打字就记下', (tester) async {
    final store = NotebookStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NotebookPage(store: store)),
      ),
    );
    await tester.tap(find.text('新建本子'));
    await tester.pumpAndSettle();
    expect(store.books, hasLength(1));
    // 新本子自带一条空的,直接能写。
    expect(store.books.single.notes, hasLength(1));

    await tester.enterText(find.byKey(const ValueKey('note-text-0')), 'a fox');
    await tester.enterText(find.byKey(const ValueKey('note-title-0')), '狐狸');
    expect(store.books.single.notes.single.text, 'a fox');
    expect(store.books.single.notes.single.title, '狐狸');

    await tester.tap(find.text('加一条'));
    await tester.pumpAndSettle();
    expect(store.books.single.notes, hasLength(2));
  });
}
