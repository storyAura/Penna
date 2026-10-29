/// 查到的一个 Danbooru 标签:[tag] 是标准写法(下划线),[zh] 是中文含义(可能为空)。
typedef TagHit = ({String tag, String zh});

final _weight = RegExp(r':\s*[\d.]+\s*$');
final _separators = RegExp(r'[,,、;;\n]+');
final _ascii = RegExp(r'^[\x00-\x7f]+$');

/// 把提示词里的一个标签还原成 Danbooru 的标准写法:
/// 去掉权重和外层括号(`(long hair:1.2)`)、反斜杠转义(`\(`),空格换成下划线,小写。
String normalizeTag(String raw) {
  var t = raw.trim();
  // 一层层剥掉加权用的括号。标签自己的括号要留着:`ganyu (genshin impact)` 只有一头是括号;
  // `(o)_(o)` 两头都是,但去掉之后里面的括号就不成对了,所以也不剥。
  while (t.length > 1 &&
      (t.startsWith('(') && t.endsWith(')') ||
          t.startsWith('[') && t.endsWith(']') ||
          t.startsWith('{') && t.endsWith('}')) &&
      _paired(t.substring(1, t.length - 1))) {
    t = t.substring(1, t.length - 1).replaceFirst(_weight, '').trim();
  }
  // `((a, b))` 按逗号切开后,两头各剩半边括号。
  while (t.startsWith('(') && _depth(t) > 0) {
    t = t.substring(1).trim();
  }
  while (t.endsWith(')') && _depth(t) < 0) {
    t = t.substring(0, t.length - 1).trim();
  }
  return t
      .replaceAll(r'\(', '(')
      .replaceAll(r'\)', ')')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_');
}

/// 左圆括号比右圆括号多几个(转义过的 `\(` 不算)。
int _depth(String t) {
  final bare = t.replaceAll(r'\(', '').replaceAll(r'\)', '');
  return '('.allMatches(bare).length - ')'.allMatches(bare).length;
}

/// 里面的圆括号是不是成对的:数量相等,而且不会先出现右括号。
bool _paired(String t) {
  var depth = 0;
  for (final char in t.replaceAll(r'\(', '').replaceAll(r'\)', '').split('')) {
    if (char == '(') depth++;
    if (char == ')' && --depth < 0) return false;
  }
  return depth == 0;
}

/// 整组加权的写法:`(masterpiece, best quality:1.2)`。
final _weightedGroup = RegExp(r'\(([^()]*,[^()]*):\s*[\d.]+\s*\)');

/// 不是标签的东西:分区用的关键字,和 `<lora:xxx:1>` 这类写法。
bool _notATag(String piece) =>
    piece == 'BREAK' || piece == 'AND' || piece.startsWith('<');

/// 一条 Tag 式提示词里用到的标签(标准写法,去重,保持先后)。
/// 分段标注和中文对照要先去掉再传进来。
List<String> tagsIn(String prompt) {
  // 整组加权的先把外壳去掉,不然按逗号一切,括号和权重就落在两头的标签上了。
  final flat = prompt.replaceAllMapped(_weightedGroup, (m) => m[1]!);
  return {
    for (final piece in flat.split(_separators))
      if (piece.trim().isNotEmpty && !_notATag(piece.trim()))
        normalizeTag(piece),
  }.where((t) => t.isNotEmpty).toList();
}

/// 内置的 Danbooru 词库:常用的通用标签和角色标签,带使用次数和中文含义。
/// 数据来自 StoryAura/Danbooru-Dataset-csv,由 tool/make_tag_dict.py 精简而成。
class TagDictionary {
  /// [tsv] 每行是「标签 \t 使用次数 \t 中文含义」,按使用次数从多到少排好。
  TagDictionary.parse(String tsv)
    : _rows = List.unmodifiable([
        for (final line in tsv.split('\n'))
          if (line.isNotEmpty)
            switch (line.split('\t')) {
              [final tag, _, final zh, ...] => (tag: tag, zh: zh),
              final parts => (tag: parts.first, zh: ''),
            },
      ]) {
    _known = {for (final r in _rows) r.tag};
  }

  final List<TagHit> _rows;
  late final Set<String> _known;

  int get length => _rows.length;

  /// 全部标签和它们的中文含义(含日文等别的叫法,逗号隔开)。
  Iterable<TagHit> get all => _rows;

  /// 词库里有没有这个标签;写成空格、带权重、带转义的都认。
  bool has(String tag) => _known.contains(normalizeTag(tag));

  /// 按关键词找标签:[query] 用逗号隔开几个词,每个词各找 [perTerm] 个最常用的。
  /// 英文按标签名找,中文按中文含义找;完全对上的排最前。
  // ponytail: 只是按字面找,「猫耳」找不到「兽耳」;在线的 DanbooruSearch 才懂意思,
  // 这里只在连不上它的时候顶一下。
  List<TagHit> search(String query, {int perTerm = 8}) {
    final out = <String, TagHit>{};
    for (final raw in query.split(_separators)) {
      final term = raw.trim().toLowerCase();
      if (term.isEmpty) continue;
      final english = _ascii.hasMatch(term);
      final needle = english ? term.replaceAll(RegExp(r'\s+'), '_') : term;
      final exact = _rows.where((r) => english && r.tag == needle);
      final partial = _rows.where(
        (r) => english ? r.tag.contains(needle) : r.zh.contains(needle),
      );
      for (final hit in [...exact, ...partial.take(perTerm)].take(perTerm)) {
        out[hit.tag] = hit;
      }
    }
    return out.values.toList();
  }
}
