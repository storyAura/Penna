import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';

/// PennaSoul 里一条记忆的种类:[soulRule] 是用户明说的约定(必须照办),
/// [soulLike] 是看出来的偏好(出点子、给建议时往上靠,[SoulEntry.hits] 越多越重)。
const soulRule = 'rule', soulLike = 'like';

/// PennaSoul 里的一条:编号、种类、一句话、被确认了几次、最后一次的时刻。
typedef SoulEntry = ({
  String id,
  String kind,
  String text,
  int hits,
  DateTime time,
});

/// 同一个角色被提到几次,就记成一条偏好。
const soulPromoteAt = 3;

/// 最多记多少条(偏好按分量淘汰,约定不淘汰)。
const soulMaxEntries = 60;

/// PennaSoul(2026-11-16 用户要求):跨对话记着用户的约定和偏好,像别家 AI 的记忆。
/// 分两种,照 mem0、ChatGPT 记忆的做法:用户明说的「约定」一字不差地照办,
/// 看出来的「偏好」按次数加权。平时不露面,每次请求带进系统提示;
/// Agent 写 `<soul-remember>` 记一条(回复下面出提示条,能撤销),
/// 程序自己数用户提到的角色,够 [soulPromoteAt] 次记成偏好。存在「文档\Penna\soul.json」。
class SoulStore extends ChangeNotifier {
  /// [file] 为 null 时只在内存里(测试用)。
  SoulStore([this.file]);

  final File? file;

  List<SoulEntry> _entries = const [];

  /// 用户提到各角色的次数(还没够数记成偏好的)。
  Map<String, int> _uses = const {};

  /// 全部记忆,约定在前,偏好按分量从重到轻。
  List<SoulEntry> get entries => _entries;

  var _seq = 0;

  String _newId() {
    final used = _entries.map((e) => e.id).toSet();
    while (true) {
      final id = 's${++_seq}';
      if (!used.contains(id)) return id;
    }
  }

  static String _key(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// 记一条;同样的话已经有了就加一次分量(种类改成新给的)。
  /// 返回记下的那条。
  SoulEntry remember(String kind, String text, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final same = _entries.where((e) => _key(e.text) == _key(text)).firstOrNull;
    final entry = (
      id: same?.id ?? _newId(),
      kind: kind == soulRule ? soulRule : soulLike,
      text: text.trim(),
      hits: (same?.hits ?? 0) + 1,
      time: at,
    );
    _set([
      for (final e in _entries)
        if (e.id != entry.id) e,
      entry,
    ]);
    return entry;
  }

  /// 删掉一条(用户撤销、取消约定)。
  void forget(String id) => _set(_entries.where((e) => e.id != id));

  /// 按原话找一条(回复里记过的,撤销时用);找不到是 null。
  SoulEntry? find(String text) =>
      _entries.where((e) => _key(e.text) == _key(text)).firstOrNull;

  /// 用户这句话提到了这几个角色:各记一次,够 [soulPromoteAt] 次的记成偏好
  /// (已经是偏好的加分量)。返回这次新记成偏好的。
  List<SoulEntry> noteCharacters(Iterable<String> names) {
    final uses = {..._uses};
    final added = <SoulEntry>[];
    for (final name in names.map((n) => n.trim()).where((n) => n.isNotEmpty)) {
      final text = '常用角色:$name';
      if (find(text) != null) {
        remember(soulLike, text);
        continue;
      }
      final n = (uses[name] ?? 0) + 1;
      if (n < soulPromoteAt) {
        uses[name] = n;
        continue;
      }
      uses.remove(name);
      added.add(remember(soulLike, text));
    }
    _uses = Map.unmodifiable(uses);
    _save();
    return added;
  }

  void _set(Iterable<SoulEntry> next) {
    final rules = [
      for (final e in next)
        if (e.kind == soulRule) e,
    ];
    final likes =
        [
          for (final e in next)
            if (e.kind != soulRule) e,
        ]..sort((a, b) {
          final byHits = b.hits.compareTo(a.hits);
          return byHits != 0 ? byHits : b.time.compareTo(a.time);
        });
    final room = (soulMaxEntries - rules.length).clamp(0, soulMaxEntries);
    _entries = List.unmodifiable([...rules, ...likes.take(room)]);
    notifyListeners();
    _save();
  }

  void _save() {
    final file = this.file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      // 先写临时文件再改名:写到一半断电也不会留下半个文件。
      final temp = File('${file.path}.tmp')
        ..writeAsStringSync(
          jsonEncode({
            'entries': [
              for (final e in _entries)
                {
                  'id': e.id,
                  'kind': e.kind,
                  'text': e.text,
                  'hits': e.hits,
                  'time': e.time.toIso8601String(),
                },
            ],
            'uses': _uses,
          }),
        );
      temp.renameSync(file.path);
    } on FileSystemException catch (e) {
      debugPrint(tr('PennaSoul 没存上:{0}', [e.message]));
    }
  }

  Future<void> load() async {
    final file = this.file;
    if (file == null || !file.existsSync()) return;
    try {
      final json = jsonDecode(await file.readAsString()) as Map;
      _entries = List.unmodifiable([
        for (final e in (json['entries'] as List).cast<Map>())
          (
            id: e['id'] as String,
            kind: e['kind'] == soulRule ? soulRule : soulLike,
            text: e['text'] as String,
            hits: (e['hits'] as num? ?? 1).toInt(),
            time: DateTime.tryParse('${e['time']}') ?? DateTime(2000),
          ),
      ]);
      _uses = Map.unmodifiable({
        if (json['uses'] case final Map uses)
          for (final MapEntry(:key, :value) in uses.entries)
            if (key is String && value is num) key: value.toInt(),
      });
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
