import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/lighting.dart';
import 'package:penna/core/harness/local/caption_catalog.dart';
import 'package:penna/core/harness/local/model_sources.dart';
import 'package:penna/core/harness/local/tagger_catalog.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/l10n/l10n_en.dart';
import 'package:penna/l10n/l10n_ja.dart';
import 'package:penna/l10n/l10n_zh_hant.dart';

/// 代码里写的 tr('原文')(可以是几段相邻的字符串)。
final _call = RegExp(r"\btr\(\s*((?:'(?:[^'\\]|\\.)*'\s*)+)");
final _piece = RegExp(r"'((?:[^'\\]|\\.)*)'");
final _slot = RegExp(r'\{\d+\}');
final _han = RegExp(r'[一-鿿]');

String _unescape(String s) => s.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => switch (m[1]) {
    'n' => '\n',
    _ => m[1]!,
  },
);

Set<String> _keysInCode() => {
  for (final f in Directory('lib').listSync(recursive: true))
    if (f is File && f.path.endsWith('.dart') && !f.path.contains('l10n'))
      for (final call in _call.allMatches(f.readAsStringSync()))
        _piece.allMatches(call[1]!).map((p) => _unescape(p[1]!)).join(),
};

void main() {
  final tables = {'zh-Hant': zhHant, 'en': en, 'ja': ja};
  final keys = _keysInCode();

  test('代码里每一句 tr() 三种语言都有译文', () {
    expect(keys.length, greaterThan(500));
    for (final MapEntry(key: lang, value: table) in tables.entries) {
      final missing = keys.where((k) => !table.containsKey(k)).toList();
      expect(missing, isEmpty, reason: '$lang 缺:$missing');
    }
  });

  test('译文里的 {0} 这些占位符和原文一样', () {
    Set<String> slots(String s) => {for (final m in _slot.allMatches(s)) m[0]!};
    for (final MapEntry(key: lang, value: table) in tables.entries) {
      for (final MapEntry(key: zh, value: text) in table.entries) {
        expect(slots(text), slots(zh), reason: '$lang:$zh → $text');
      }
    }
  });

  test('清单和内置设置里显示时才翻译的文字也有译文', () {
    final texts = [
      for (final m in captionModels) ...[m.name, m.note],
      for (final m in taggerModels) m.note,
      '本机',
      ...modelSources.values,
      for (final o in [...builtinSkills, ...builtinTools]) ...[o.label, o.hint],
      for (final a in defaultQuickActions) ...[a.label, a.prompt],
      for (final e in mtEngines) ...[
        e.label,
        for (final f in e.fields) f.label,
      ],
      for (final p in factoryPresets) p.name,
      for (final p in lightPresets) p.name,
      for (final e in lightExtras) e.label,
      for (final r in lightRoleInfo.values) r.zh,
      uncategorized,
    ].where(_han.hasMatch);
    for (final MapEntry(key: lang, value: table) in tables.entries) {
      final missing = texts.where((t) => !table.containsKey(t)).toList();
      expect(missing, isEmpty, reason: '$lang 缺:$missing');
    }
  });
}
