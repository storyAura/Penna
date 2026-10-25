import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';

/// 角色的一套服装:名字和这套衣服的提示词。
typedef CharacterOutfit = ({String name, String prompt});

/// 角色库里用户自己存的一个角色:名字、提示词,和一张图([image] 是文件路径,没有就是空串)。
/// [alias] 是别的叫法(逗号隔开),[intro] 是简介,[outfits] 是另存的几套服装。
typedef CharacterCard = ({
  String id,
  String name,
  String alias,
  String intro,
  String prompt,
  List<CharacterOutfit> outfits,
  String image,
  DateTime time,
});

/// 一张要存进角色库的图:内容和扩展名(不带点)。
typedef CharacterImage = ({List<int> bytes, String ext});

/// 图片的大小上限(字节)。
const maxCharacterImageBytes = 20 * 1024 * 1024;

/// 角色库里用户自己的那部分:存在「文档\Penna\characters.json」,图片在旁边的 characters 文件夹里。
/// 和档案库是两回事:档案库存的是整条成稿,这里存的是能反复拿来用的角色。
class CharacterStore extends ChangeNotifier {
  /// [dir] 是「文档\Penna」;为 null 时只在内存里、图片不存(测试用)。
  CharacterStore([this.dir]);

  final Directory? dir;

  List<CharacterCard> _cards = const [];

  /// 显示的顺序(新加的在前,拖过的照拖完的)。
  List<CharacterCard> get cards => _cards;

  File? get _file => _fileOf('characters.json');

  /// 收藏另存一个文件:「我的」那份还是原来的列表格式,旧版本也读得了。
  File? get _favFile => _fileOf('character_favorites.json');

  File? _fileOf(String name) =>
      dir == null ? null : File('${dir!.path}${Platform.pathSeparator}$name');

  List<String> _favSeries = const [];
  List<String> _favCharacters = const [];

  /// 收藏的内置系列、内置角色(都按名字记),新收藏的在前。
  List<String> get favoriteSeries => _favSeries;
  List<String> get favoriteCharacters => _favCharacters;

  bool isFavoriteSeries(String name) => _favSeries.contains(name);
  bool isFavoriteCharacter(String name) => _favCharacters.contains(name);

  /// 收藏或取消收藏一个系列。
  void toggleSeries(String name) {
    _favSeries = _toggled(_favSeries, name);
    _favoritesChanged();
  }

  /// 收藏或取消收藏一个内置角色。
  void toggleCharacter(String name) {
    _favCharacters = _toggled(_favCharacters, name);
    _favoritesChanged();
  }

  static List<String> _toggled(List<String> list, String name) =>
      List.unmodifiable(
        list.contains(name) ? list.where((n) => n != name) : [name, ...list],
      );

  void _favoritesChanged() {
    notifyListeners();
    _write(_favFile, {
      'series': _favSeries,
      'characters': _favCharacters,
    }, tr('收藏没存上:{0}'));
  }

  String _key(String name) => name.trim().toLowerCase();

  /// 按名字或别名找:名字里有 [query],或 [query] 里提到了名字。不分大小写。
  List<CharacterCard> find(String query) {
    final q = _key(query);
    if (q.isEmpty) return const [];
    bool hit(String n) => n.isNotEmpty && (n.contains(q) || q.contains(n));
    return [
      for (final c in _cards)
        if (hit(_key(c.name)) || aliasesOf(c).map(_key).any(hit)) c,
    ];
  }

  /// [c] 的几个别名(中英文逗号、顿号都算分隔)。
  static List<String> aliasesOf(CharacterCard c) => [
    for (final a in c.alias.split(RegExp('[,,、]')))
      if (a.trim().isNotEmpty) a.trim(),
  ];

  /// 存一个角色。给了 [id] 就是改那一个;没给时同名的算同一个(换掉提示词),否则新增。
  /// [image]、[alias]、[intro]、[outfits] 不给就留着原来的。名字或提示词是空的不存,返回 null。
  CharacterCard? put({
    String? id,
    required String name,
    required String prompt,
    String? alias,
    String? intro,
    List<CharacterOutfit>? outfits,
    CharacterImage? image,
    DateTime? now,
  }) {
    if (name.trim().isEmpty || prompt.trim().isEmpty) return null;
    final time = now ?? DateTime.now();
    final old = _cards
        .where((c) => id == null ? _key(c.name) == _key(name) : c.id == id)
        .firstOrNull;
    final cardId = old?.id ?? '${time.microsecondsSinceEpoch}';
    final card = (
      id: cardId,
      name: name.trim(),
      alias: (alias ?? old?.alias ?? '').trim(),
      intro: (intro ?? old?.intro ?? '').trim(),
      prompt: prompt.trim(),
      outfits: outfits == null
          ? old?.outfits ?? const <CharacterOutfit>[]
          : _cleanOutfits(outfits),
      image: image == null
          ? old?.image ?? ''
          : _saveImage(cardId, image, time, replacing: old?.image ?? ''),
      time: time,
    );
    // 改的留在原位(用户可能拖着排过顺序),新加的放最前。
    _set(
      old == null
          ? [card, ..._cards]
          : [for (final c in _cards) c.id == cardId ? card : c],
    );
    return card;
  }

  /// 去掉没写提示词的服装,其余去掉首尾空白。
  static List<CharacterOutfit> _cleanOutfits(List<CharacterOutfit> outfits) =>
      List.unmodifiable([
        for (final o in outfits)
          if (o.prompt.trim().isNotEmpty)
            (name: o.name.trim(), prompt: o.prompt.trim()),
      ]);

  /// 把 [id] 挪到 [before] 前面(拖着换顺序)。
  void move(String id, String before) {
    final moving = _cards.where((c) => c.id == id).firstOrNull;
    if (moving == null || id == before) return;
    final rest = _cards.where((c) => c.id != id).toList();
    final at = rest.indexWhere((c) => c.id == before);
    if (at < 0) return;
    _set([...rest.take(at), moving, ...rest.skip(at)]);
  }

  /// 只换图([webp] 是已经转好的 WebP),名字和提示词不动。
  void setImage(String id, List<int> webp) {
    final old = _cards.where((c) => c.id == id).firstOrNull;
    if (old == null) return;
    put(
      id: id,
      name: old.name,
      prompt: old.prompt,
      image: (bytes: webp, ext: 'webp'),
    );
  }

  void remove(String id) {
    for (final c in _cards.where((c) => c.id == id)) {
      _deleteImage(c.image);
    }
    _set(_cards.where((c) => c.id != id));
  }

  /// 把图写进 characters 文件夹,返回路径;存不了返回空串。
  /// 文件名带着时刻:换图之后路径不同,界面不会还显示旧图。
  String _saveImage(
    String id,
    CharacterImage image,
    DateTime time, {
    required String replacing,
  }) {
    final dir = this.dir;
    final ext = image.ext.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    if (dir == null ||
        ext.isEmpty ||
        image.bytes.isEmpty ||
        image.bytes.length > maxCharacterImageBytes) {
      return replacing;
    }
    try {
      final file = File(
        '${dir.path}${Platform.pathSeparator}characters'
        '${Platform.pathSeparator}$id-${time.microsecondsSinceEpoch}.$ext',
      );
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(image.bytes, flush: true);
      _deleteImage(replacing);
      return file.path;
    } on FileSystemException catch (e) {
      debugPrint(tr('角色的图没存上:{0}', [e.message]));
      return replacing;
    }
  }

  void _deleteImage(String path) {
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // 删不掉就留着,不碍事。
    }
  }

  void _set(Iterable<CharacterCard> next) {
    _cards = List.unmodifiable(next);
    notifyListeners();
    _save();
  }

  // ponytail: 每次改动都把整个文件重写一遍;存到几千个嫌慢时再改。
  void _save() => _write(_file, [
    for (final c in _cards)
      {
        'id': c.id,
        'name': c.name,
        if (c.alias.isNotEmpty) 'alias': c.alias,
        if (c.intro.isNotEmpty) 'intro': c.intro,
        'prompt': c.prompt,
        if (c.outfits.isNotEmpty)
          'outfits': [
            for (final o in c.outfits) {'name': o.name, 'prompt': o.prompt},
          ],
        'image': c.image,
        'time': c.time.toIso8601String(),
      },
  ], tr('角色库没存上:{0}'));

  /// 把 [json] 写进 [file];[failed] 是写不了时记进日志的话({0} 是原因)。
  void _write(File? file, Object json, String failed) {
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      // 先写临时文件再改名:写到一半断电也不会留下半个文件。
      File('${file.path}.tmp')
        ..writeAsStringSync(jsonEncode(json), flush: true)
        ..renameSync(file.path);
    } on FileSystemException catch (e) {
      debugPrint(failed.replaceAll('{0}', e.message));
    }
  }

  Future<void> load() async {
    await _read(_file, (json) {
      _cards = List.unmodifiable([
        for (final c in (json as List).cast<Map<String, dynamic>>())
          (
            id: c['id'] as String,
            name: c['name'] as String,
            alias: c['alias'] as String? ?? '',
            intro: c['intro'] as String? ?? '',
            prompt: c['prompt'] as String,
            outfits: List<CharacterOutfit>.unmodifiable([
              for (final o
                  in (c['outfits'] as List? ?? const [])
                      .cast<Map<String, dynamic>>())
                (name: o['name'] as String, prompt: o['prompt'] as String),
            ]),
            image: c['image'] as String? ?? '',
            time: DateTime.parse(c['time'] as String),
          ),
      ]);
    });
    await _read(_favFile, (json) {
      final map = json as Map<String, dynamic>;
      List<String> names(String key) =>
          List.unmodifiable((map[key] as List? ?? const []).cast<String>());
      _favSeries = names('series');
      _favCharacters = names('characters');
    });
    notifyListeners();
  }

  /// 读 [file] 交给 [use];读不了的文件留个底,不让下一次保存把它盖掉。
  Future<void> _read(File? file, void Function(Object? json) use) async {
    if (file == null || !file.existsSync()) return;
    try {
      use(jsonDecode(await file.readAsString()));
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
