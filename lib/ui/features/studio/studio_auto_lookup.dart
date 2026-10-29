part of 'studio_view_model.dart';

/// 有的模型(DeepSeek 这类)不照 Skill 先 `<search-character>` / `<search-tags>`,
/// 凭记忆就写。两道补救:用户的话里提到了角色库里的角色,程序先替它查好、接在这条消息后面;
/// 系统提示最后再钉一条短的「先查再写」(模型对最后读到的话最上心)。
/// 副聊天也用这里的:它自己没有查询的那段工具循环,查标签、查角色借主聊天的([lookupFor])。
extension StudioAutoLookup on StudioViewModel {
  /// 一条消息最多替模型查几个角色。
  static const _maxAuto = 3;

  /// [message] 里提到的角色(用户自己存的、内置的),名字 → 查到的结果。
  /// 关掉了「角色库」这个 Skill、或者一个也没认出来时是空的。
  Map<String, List<CharacterHit>> _mentioned(ChatMessage message) {
    if (config.config.disabledSkills.contains('character-lib')) return const {};
    final text = message.text;
    if (text.trim().isEmpty) return const {};
    final out = <String, List<CharacterHit>>{};
    // 用户自己存的排前面:同一个叫法也对上内置的时,结果里会叫模型先问是哪一个。
    for (final card in characters?.find(text) ?? const <CharacterCard>[]) {
      if (out.length < _maxAuto) out[card.name] = findCharacters(card.name);
    }
    final seen = {
      for (final hits in out.values)
        for (final h in hits) h.name,
    };
    for (final name in _mentions?.inText(text, limit: _maxAuto) ?? const []) {
      if (out.length >= _maxAuto || seen.contains(name)) continue;
      final hit = characterDict!.byName(name)!;
      final hits = characterDict!.withForms([hit], perHit: 6);
      out[name] = hits;
      seen.addAll(hits.map((h) => h.name));
    }
    return out;
  }

  /// [sent] 里最后一条用户消息([ask])提到的角色:查好的结果接在那条消息后面([text]),
  /// 回复上记一笔([note],没查就是 null)。
  ({ChatMessage? ask, String text, String? note}) autoLookupFor(
    List<ChatMessage> sent,
  ) {
    final ask = sent.where((m) => m.fromUser && !m.tool).lastOrNull;
    final found = ask == null
        ? const <String, List<CharacterHit>>{}
        : _mentioned(ask);
    if (found.isEmpty) return (ask: ask, text: '', note: null);
    return (
      ask: ask,
      text:
          '【程序已按用户这句话里的名字查了角色库】下面这几个不用再查;'
          '和用户说的对不上的就不用管,别的角色照样先用 <search-character> 查。\n'
          '${formatCharacterResults(found, formOf: characterDict?.parentOf)}',
      note: tr('已按名字查了角色库:{0}', [found.keys.join(tr('、'))]),
    );
  }

  /// 系统提示最后那一条:先查再写。关掉的 Skill、没接上的工具不提。
  String _lookupFirstPrompt(AppConfig cfg) {
    final people =
        !cfg.disabledSkills.contains('character-lib') &&
        (characters != null || characterDict != null);
    final tags =
        !cfg.disabledSkills.contains('danbooru-tags') && tagSearch != null;
    if (!people && !tags) return '';
    return [
      '【先查再写】查询由程序替你执行,你只要在回复里写出标签,程序查完会把结果交还给你,再接着写。'
          '不要说"我查不了",也不要凭记忆补。',
      if (people)
        '- 用户提到具体的角色(动漫、游戏、VTuber 里的,或他自己存的),而这一轮还没有它的'
            '【角色库查询结果】时:这条回复只写 <search-character>名字</search-character>'
            '(一个角色一个),不写 <draft>。',
      if (tags)
        '- 要写成 Danbooru 标签、或用到拿不准的标签时:先只写 <search-tags>关键词</search-tags>,'
            '拿到【标签搜索结果】再写 <draft>。',
    ].join('\n');
  }

  /// 给副聊天的那一条「先查再写」。
  String get lookupGuide => _lookupFirstPrompt(config.config);

  /// 几组关键词一起查标签:在线搜索一次就要十几秒,排着队查太久。
  /// 查不了的那组如实告诉模型,它会换个办法。
  Future<Map<String, TagSearchResult>> _findTags(List<String> asked) async {
    final found = await Future.wait([
      for (final query in asked)
        () async {
          try {
            return await tagSearch!(query);
          } on Object {
            return (hits: const <TagHit>[], source: '搜索失败');
          }
        }(),
    ]);
    return {for (final (i, query) in asked.indexed) query: found[i]};
  }

  /// 副聊天的回复里写了 `<search-tags>` / `<search-character>`:照主聊天的查法查好,
  /// 拼成交还给模型的那段话([text])和记在那一步上的一句([note])。没有要查的返回 null。
  Future<({String text, String note})?> lookupFor(String reply) async {
    final prose = splitNewSkill(reply).prose;
    final queries = tagSearch == null
        ? const <String>[]
        : splitTagSearch(prose).queries.take(_maxQueries).toList();
    final names = characters == null && characterDict == null
        ? const <String>[]
        : splitCharacterTags(prose).queries.take(_maxQueries).toList();
    if (queries.isEmpty && names.isEmpty) return null;
    final results = await _findTags(queries);
    final people = {for (final name in names) name: findCharacters(name)};
    return (
      text: [
        if (results.isNotEmpty) formatTagResults(results),
        if (people.isNotEmpty)
          formatCharacterResults(people, formOf: characterDict?.parentOf),
      ].join('\n\n'),
      note: [
        if (results.isNotEmpty)
          tr('查了 Danbooru 标签 · {0} 个', [
            results.values.expand((r) => r.hits).length,
          ]),
        if (people.isNotEmpty)
          tr('查了角色库 · {0} 个', [people.values.expand((h) => h).length]),
      ].join(' · '),
    );
  }
}
