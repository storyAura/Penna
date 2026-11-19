import 'dart:convert';

/// 角色的一套服装:名字和这套衣服的提示词。
typedef CharacterOutfit = ({String name, String prompt});

/// 一个角色的内容(不含编号、图、时间)。[prompt] 是「特征」(长相),
/// [clothing] 是默认的穿着,[outfits] 是另几套服装(JSON 里的 Clothing-2、Clothing-3…)。
typedef CharacterEntry = ({
  String name,
  String ip,
  String alias,
  String intro,
  String prompt,
  String clothing,
  List<CharacterOutfit> outfits,
});

/// 角色的标准 JSON 写法:导出、导入、Agent 存角色、存盘都用它。
/// Name、ip、Traits、Clothing 总是写;Alias、Intro、Clothing-N、Clothing-N-name 有才写。
Map<String, Object> characterToJson(CharacterEntry c) => {
  'Name': c.name,
  'ip': c.ip,
  if (c.alias.isNotEmpty) 'Alias': c.alias,
  if (c.intro.isNotEmpty) 'Intro': c.intro,
  'Traits': c.prompt,
  'Clothing': c.clothing,
  for (final (i, o) in c.outfits.indexed) ...{
    'Clothing-${i + 2}': o.prompt,
    if (o.name.isNotEmpty) 'Clothing-${i + 2}-name': o.name,
  },
};

final _outfitKey = RegExp(r'^clothing-(\d+)$');

/// 从一个 JSON 对象读出角色;键不分大小写,值是数组的拼成逗号隔开的一串。
/// 不是对象、没有名字或没有特征的返回 null。
CharacterEntry? characterFromJson(Object? json) {
  if (json is! Map) return null;
  final m = {
    for (final e in json.entries) '${e.key}'.trim().toLowerCase(): e.value,
  };
  String text(String key) => switch (m[key]) {
    final String v => v.trim(),
    final num v => '$v',
    final List v => v.whereType<String>().map((s) => s.trim()).join(', '),
    _ => '',
  };
  final slots = [
    for (final k in m.keys)
      if (_outfitKey.firstMatch(k) case final hit?)
        if (int.parse(hit[1]!) >= 2) int.parse(hit[1]!),
  ]..sort();
  final entry = (
    name: text('name'),
    ip: text('ip'),
    alias: text('alias'),
    intro: text('intro'),
    prompt: text('traits'),
    clothing: text('clothing'),
    outfits: List<CharacterOutfit>.unmodifiable([
      for (final n in slots)
        if ((name: text('clothing-$n-name'), prompt: text('clothing-$n'))
            case final o when o.name.isNotEmpty || o.prompt.isNotEmpty)
          o,
    ]),
  );
  return entry.name.isEmpty || entry.prompt.isEmpty ? null : entry;
}

/// 读一段 JSON 文字:一个角色对象、角色数组,或 {"characters": [...]};
/// 外面包着 ``` 代码块也认。读不出 JSON 抛 [FormatException],其中不合格的条目跳过。
List<CharacterEntry> parseCharacters(String text) {
  final body = text
      .trim()
      .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '');
  final json = jsonDecode(body);
  final list = switch (json) {
    final List l => l,
    {'characters': final List l} => l,
    final Map one => [one],
    _ => const [],
  };
  return [for (final c in list) ?characterFromJson(c)];
}

/// 导出成文件的那段文字:角色数组,缩进两格。
String exportCharacters(Iterable<CharacterEntry> cards) =>
    const JsonEncoder.withIndent('  ')
        .convert([for (final c in cards) characterToJson(c)]);
