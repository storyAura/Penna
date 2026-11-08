import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';

/// 档案库里的一条:用户主动存下来的一份成稿([kind] 是 [archivePrompt]),
/// 或区域控制工作台上的一份布局([kind] 是 [archiveLayout],[text] 是 `Layout.toJson` 的 JSON)。
/// [image] 是用户上传的预览图(WebP 文件的路径),没有就是空串。
typedef ArchiveEntry = ({
  String id,
  DateTime time,
  String category,
  String title,
  String text,
  String kind,
  String image,
});

/// 档案库的分区:成稿、区域控制的布局、漫画分镜(一整部作品,`MangaProject.toJson` 的 JSON)。
const archivePrompt = 'prompt',
    archiveLayout = 'layout',
    archiveManga = 'manga';

/// 没填分类时归到这里。
const uncategorized = '未分类';

/// 档案库:用户点「保存」存下来的成稿,带时间和分类。存在「文档\Penna\archive.json」,
/// 预览图在旁边的 archive 文件夹里。顺序就是显示的顺序:新存的在最前,用户能拖着换。
class ArchiveStore extends ChangeNotifier {
  /// [file] 为 null 时只在内存里(测试用)。
  ArchiveStore([this.file]);

  final File? file;

  List<ArchiveEntry> _entries = const [];

  /// 显示的顺序(新存的在前,拖过的照拖完的)。
  List<ArchiveEntry> get entries => _entries;

  /// [kind] 这个分区里用过的分类,按最近用到的先后。
  List<String> categoriesOf(String kind) => {
    for (final e in _entries)
      if (e.kind == kind) e.category,
  }.toList();

  /// 存一条,返回它的 id;[text] 是空的就不存,返回 null。分类没填归「未分类」。
  String? add({
    required String text,
    String title = '',
    String category = '',
    String kind = archivePrompt,
    DateTime? now,
  }) {
    if (text.trim().isEmpty) return null;
    final time = now ?? DateTime.now();
    final id = '${time.microsecondsSinceEpoch}';
    _set([
      (
        id: id,
        time: time,
        category: category.trim().isEmpty ? uncategorized : category.trim(),
        title: title.trim(),
        text: text,
        kind: kind,
        image: '',
      ),
      ..._entries,
    ]);
    return id;
  }

  void remove(String id) {
    for (final e in _entries.where((e) => e.id == id)) {
      _deleteImage(e.image);
    }
    _set(_entries.where((e) => e.id != id));
  }

  /// 把 [id] 挪到 [before] 前面(拖着换顺序)。
  void move(String id, String before) {
    final moving = _entries.where((e) => e.id == id).firstOrNull;
    if (moving == null || id == before) return;
    final rest = _entries.where((e) => e.id != id).toList();
    final at = rest.indexWhere((e) => e.id == before);
    if (at < 0) return;
    _set([...rest.take(at), moving, ...rest.skip(at)]);
  }

  /// 换上一张预览图([webp] 是已经转好的 WebP)。只在内存里时不存图,返回 false。
  bool setImage(String id, Uint8List webp) {
    final file = this.file;
    final old = _entries.where((e) => e.id == id).firstOrNull;
    if (file == null || old == null) return false;
    final sep = Platform.pathSeparator;
    try {
      // 文件名带着时刻:换图之后路径不同,界面不会还显示旧图。
      final image = File(
        '${file.parent.path}${sep}archive$sep$id-'
        '${DateTime.now().microsecondsSinceEpoch}.webp',
      );
      image.parent.createSync(recursive: true);
      image.writeAsBytesSync(webp, flush: true);
      _deleteImage(old.image);
      _set([
        for (final e in _entries)
          e.id == id
              ? (
                  id: e.id,
                  time: e.time,
                  category: e.category,
                  title: e.title,
                  text: e.text,
                  kind: e.kind,
                  image: image.path,
                )
              : e,
      ]);
      return true;
    } on FileSystemException catch (e) {
      debugPrint(tr('预览图没存上:{0}', [e.message]));
      return false;
    }
  }

  void _deleteImage(String path) {
    if (path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException {
      // 删不掉就留着,不碍事。
    }
  }

  void _set(Iterable<ArchiveEntry> next) {
    _entries = List.unmodifiable(next);
    notifyListeners();
    _save();
  }

  // ponytail: 每次改动都把整个文件重写一遍;存到几千条嫌慢时再改成追加或换数据库。
  void _save() {
    final file = this.file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      // 先写临时文件再改名:写到一半断电也不会留下半个文件。
      final temp = File('${file.path}.tmp')
        ..writeAsStringSync(
          jsonEncode([
            for (final e in _entries)
              {
                'id': e.id,
                'time': e.time.toIso8601String(),
                'category': e.category,
                'title': e.title,
                'text': e.text,
                'kind': e.kind,
                if (e.image.isNotEmpty) 'image': e.image,
              },
          ]),
        );
      temp.renameSync(file.path);
    } on FileSystemException catch (e) {
      debugPrint(tr('档案库没存上:{0}', [e.message]));
    }
  }

  Future<void> load() async {
    final file = this.file;
    if (file == null || !file.existsSync()) return;
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      _entries = List.unmodifiable([
        for (final e in list.cast<Map<String, dynamic>>())
          (
            id: e['id'] as String,
            time: DateTime.parse(e['time'] as String),
            category: e['category'] as String? ?? uncategorized,
            title: e['title'] as String? ?? '',
            text: e['text'] as String,
            kind: e['kind'] as String? ?? archivePrompt,
            image: e['image'] as String? ?? '',
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
