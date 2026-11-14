// 界面多语言。原文就是简体中文:代码里写 tr('简体中文原文'),换了语言时按原文查表,
// 表里没有的照原文显示。纯 Dart,哪一层都能用(给用户看的报错也走它)。

import 'l10n_en.dart';
import 'l10n_ja.dart';
import 'l10n_zh_hant.dart';

/// 能选的语言:代码和它自己的名字(菜单里照原样显示,不翻译)。
const languages = [
  (code: 'zh-Hans', name: '简体中文'),
  (code: 'zh-Hant', name: '繁體中文'),
  (code: 'en', name: 'English'),
  (code: 'ja', name: '日本語'),
];

const _tables = <String, Map<String, String>>{
  'zh-Hant': zhHant,
  'en': en,
  'ja': ja,
};

var _language = 'zh-Hans';

/// 现在的界面语言。
String get currentLanguage => _language;

/// 换界面语言;认不得的代码当简体中文。换完调用方负责让界面重建。
void useLanguage(String code) =>
    _language = _tables.containsKey(code) ? code : 'zh-Hans';

/// 系统语言环境(`zh_CN.UTF-8`、`zh-Hant-TW`、`en-US` 这类)对应的界面语言:
/// 中文分简繁(台湾、香港、澳门和写明 Hant 的算繁体),日文用日文,其余都用英文。
String languageForLocale(String locale) {
  final l = locale.toLowerCase().replaceAll('_', '-');
  if (l.startsWith('zh')) {
    return RegExp(r'hant|-(tw|hk|mo)\b').hasMatch(l) ? 'zh-Hant' : 'zh-Hans';
  }
  if (l.startsWith('ja')) return 'ja';
  return 'en';
}

final _slot = RegExp(r'\{(\d+)\}');

/// 把简体中文原文 [zh] 换成当前语言。原文里的 `{0}`、`{1}` 按顺序填 [args]
/// (各语言的词序可以不同,所以不直接拼字符串)。
String tr(String zh, [List<Object?> args = const []]) {
  final text = _tables[_language]?[zh] ?? zh;
  if (args.isEmpty) return text;
  return text.replaceAllMapped(_slot, (m) {
    final i = int.parse(m[1]!);
    return i < args.length ? '${args[i]}' : m[0]!;
  });
}
