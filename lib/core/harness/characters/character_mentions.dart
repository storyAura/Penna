import 'dart:math';

import '../tags/tag_dictionary.dart';
import 'character_dict.dart';

/// 从用户的一句话里认出提到了哪些内置角色,程序好替模型先查角色库
/// (有的模型不按 Skill 写的先 `<search-character>`,凭记忆就写了)。
///
/// 按叫法认:中日文别名(至少 [_minCjk] 个字),或英文的角色名、去掉括号的名字
/// (至少 [_minLatin] 个字母,按整词;英文别名太杂不收)。同一个叫法归图多的那个角色。
/// 普通的词不当人名:[tags] 里通用标签的名字和中文含义(「忍者」「死神」「unicorn」)
/// 不收;标签本身就是角色的(`ganyu_(genshin_impact)` 的「甘雨」)照收。
// ponytail: 只看前 [_scan] 个字,索引在第一次用时建(七万多个角色,一百来毫秒);
// 普通词表靠词库,词库里没有的普通词还是可能认错人,所以交给模型时写明"对不上就不用管"。
class CharacterMentions {
  CharacterMentions(this.dict, {this.tags});

  final CharacterDict dict;
  final TagDictionary? tags;

  late final Map<String, String> _index = () {
    final common = <String>{};
    for (final t in tags?.all ?? const <TagHit>[]) {
      final name = t.tag.replaceAll('_', ' ');
      if (dict.byName(name) != null) continue;
      common.add(name);
      // 含义里也混着英文(`ganyu (cosplay)` 那条写着 Ganyu):只收中日文的。
      for (final w in t.zh.split(_wordSeparators)) {
        if (_cjk.hasMatch(w)) common.add(w.toLowerCase());
      }
    }
    final map = <String, String>{};
    void put(String key, String name) {
      if (!common.contains(key)) map.putIfAbsent(key, () => name);
    }

    for (final r in dict.all) {
      final paren = r.name.indexOf(' (');
      for (final n in [r.name, if (paren > 0) r.name.substring(0, paren)]) {
        if (n.length >= _minLatin) put(n, r.name);
      }
      // 别名排在前面的是正经译名,后面混着 pixiv 式的标签(「雨天」「小猫」、CP 名「刻甘」),
      // 所以只认前几个;两个字的只认排第一的那个。
      for (final (i, a) in r.alias.split(', ').take(_aliasesUsed).indexed) {
        if (a.length >= (i == 0 ? _minCjk : _minCjk + 1) && _cjk.hasMatch(a)) {
          put(a.toLowerCase(), r.name);
        }
      }
    }
    return map;
  }();

  /// [text] 里提到的内置角色名,先提到的在前,最多 [limit] 个。
  /// 同一处取最长的那个叫法:「初音未来」不会再拆出「初音」。
  List<String> inText(String text, {int limit = 3}) {
    final found = <String>[];
    final head = (text.length > _scan ? text.substring(0, _scan) : text)
        .toLowerCase();
    // 中日文:从每个字起往后试,取对得上的最长那个,然后跳过它。
    for (var i = 0; i < head.length && found.length < limit; i++) {
      if (!_cjk.hasMatch(head[i])) continue;
      for (var n = min(_maxLength, head.length - i); n >= _minCjk; n--) {
        final name = _index[head.substring(i, i + n)];
        if (name != null) {
          if (!found.contains(name)) found.add(name);
          i += n - 1;
          break;
        }
      }
    }
    // 英文:按整词,几个词连起来试,同样取最长的。
    final words = head
        .replaceAll(_notLatin, ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    for (var i = 0; i < words.length && found.length < limit; i++) {
      for (var n = min(_maxWords, words.length - i); n >= 1; n--) {
        final name = _index[words.sublist(i, i + n).join(' ')];
        if (name != null) {
          if (!found.contains(name)) found.add(name);
          i += n - 1;
          break;
        }
      }
    }
    return found;
  }
}

const _minCjk = 2;
const _aliasesUsed = 3;
const _minLatin = 5;
const _maxLength = 16;
const _maxWords = 6;
const _scan = 2000;

/// 汉字、假名、韩文。
final _cjk = RegExp(r'[぀-ヿ㐀-鿿가-힯]');

/// 英文角色名里会出现的字符以外的都当分隔。
final _notLatin = RegExp(r"[^a-z0-9\s_\-.:!']");

final _wordSeparators = RegExp(r'[,，、;；/\s]+');
