import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';

/// 记事本里的一条:名字可以空着。
typedef Note = ({String id, String title, String text});

/// 一个本子:有名字,里面按先后放着几条。
typedef Notebook = ({String id, String name, List<Note> notes});

/// 记事本:用户随手记的东西,分成几个本子。存在「文档\Penna\notebooks.json」。
class NotebookStore extends ChangeNotifier {
  /// [file] 为 null 时只在内存里(测试用)。
  NotebookStore([this.file]);

  final File? file;

  List<Notebook> _books = const [];
  List<Notebook> get books => _books;

  var _seq = 0;
  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  /// 新建一个本子(排在最后),里面先放一条空的,返回它的 id。
  String addBook(String name) {
    final id = _newId();
    _set([
      ..._books,
      (
        id: id,
        name: name.trim(),
        notes: List.unmodifiable([(id: _newId(), title: '', text: '')]),
      ),
    ]);
    return id;
  }

  /// 改名;名字是空的不改。
  void renameBook(String id, String name) {
    if (name.trim().isEmpty) return;
    _edit(id, (b) => (id: b.id, name: name.trim(), notes: b.notes));
  }

  void removeBook(String id) => _set(_books.where((b) => b.id != id));

  /// 在本子最后加一条空的,返回它的 id。
  String addNote(String book) {
    final id = _newId();
    _edit(
      book,
      (b) => (
        id: b.id,
        name: b.name,
        notes: List.unmodifiable([...b.notes, (id: id, title: '', text: '')]),
      ),
    );
    return id;
  }

  /// 改一条的名字或内容(不给的那样不动)。
  void updateNote(String book, String note, {String? title, String? text}) {
    _edit(
      book,
      (b) => (
        id: b.id,
        name: b.name,
        notes: List.unmodifiable([
          for (final n in b.notes)
            n.id == note
                ? (id: n.id, title: title ?? n.title, text: text ?? n.text)
                : n,
        ]),
      ),
    );
  }

  /// Agent 存一条:按名字找本子(没有就新建),本子里有同名的条目就换内容,
  /// 没有(或 [title] 空着)就接在最后。名字比的时候不分大小写、不看首尾空白。
  void putNote(String bookName, String title, String text) {
    String key(String s) => s.trim().toLowerCase();
    final book =
        _books.where((b) => key(b.name) == key(bookName)).firstOrNull?.id ??
        addBook(bookName);
    final notes = _books.firstWhere((b) => b.id == book).notes;
    final same = title.trim().isEmpty
        ? null
        : notes.where((n) => key(n.title) == key(title)).firstOrNull;
    // 新建的本子自带一条空的:先用它。
    final blank = notes.where((n) => n.title.isEmpty && n.text.isEmpty);
    final id = same?.id ?? blank.firstOrNull?.id ?? addNote(book);
    updateNote(book, id, title: title.trim(), text: text);
  }

  void removeNote(String book, String note) => _edit(
    book,
    (b) => (
      id: b.id,
      name: b.name,
      notes: List.unmodifiable(b.notes.where((n) => n.id != note)),
    ),
  );

  void _edit(String id, Notebook Function(Notebook) change) =>
      _set([for (final b in _books) b.id == id ? change(b) : b]);

  void _set(Iterable<Notebook> next) {
    _books = List.unmodifiable(next);
    notifyListeners();
    _save();
  }

  // ponytail: 每打一个字都把整个文件重写一遍;记的东西多到打字发卡时再改成停笔后再存。
  void _save() {
    final file = this.file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      // 先写临时文件再改名:写到一半断电也不会留下半个文件。
      final temp = File('${file.path}.tmp')
        ..writeAsStringSync(
          jsonEncode([
            for (final b in _books)
              {
                'id': b.id,
                'name': b.name,
                'notes': [
                  for (final n in b.notes)
                    {'id': n.id, 'title': n.title, 'text': n.text},
                ],
              },
          ]),
        );
      temp.renameSync(file.path);
    } on FileSystemException catch (e) {
      debugPrint(tr('记事本没存上:{0}', [e.message]));
    }
  }

  Future<void> load() async {
    final file = this.file;
    if (file == null || !file.existsSync()) return;
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      _books = List.unmodifiable([
        for (final b in list.cast<Map<String, dynamic>>())
          (
            id: b['id'] as String,
            name: b['name'] as String? ?? '',
            notes: List<Note>.unmodifiable([
              for (final n
                  in (b['notes'] as List? ?? const [])
                      .cast<Map<String, dynamic>>())
                (
                  id: n['id'] as String,
                  title: n['title'] as String? ?? '',
                  text: n['text'] as String? ?? '',
                ),
            ]),
          ),
      ]);
      notifyListeners();
    } on Object {
      // 读不了的文件留个底再重新开始,不让下一次保存把它盖掉。
      try {
        file.renameSync(
          '${file.path}.bad-${DateTime.now().millisecondsSinceEpoch}',
        );
      } on FileSystemException {
        // 留底失败也不拦着程序启动。
      }
    }
  }
}
