part of 'studio_view_model.dart';

/// 有的模型(DeepSeek 这类)不照 Skill 先 `<search-character>` / `<search-tags>`,
/// 凭记忆就写。两道补救:用户的话里提到了角色库里的角色,程序先替它查好、接在这条消息后面;
/// 系统提示最后再钉一条短的「先查再写」(模型对最后读到的话最上心)。
/// 副聊天也用这里的:它自己没有查询的那段工具循环,查标签、查角色借主聊天的([lookupFor])。
extension StudioAutoLookup on StudioViewModel {
  /// 一条消息最多替模型查几个角色。
  static const _maxAuto = 3;

  /// [message] 里提到的角色(用户自己存的、内置的),名字 → 查到的结果。
  /// 一个也没认出来时是空的。
  Map<String, List<CharacterHit>> _mentioned(ChatMessage message) {
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
    // 用户点了上一条回复里的选项:这句就是回答(用户反馈:选了「小葱(用户自存设定)」,
    // 又查出同名的两个,模型照着「先问是哪一个」又问了一遍)。
    final last = sent.take(sent.indexOf(ask!)).where((m) => !m.tool).lastOrNull;
    final answering =
        last != null && !last.fromUser && last.text.contains('<options');
    return (
      ask: ask,
      text:
          '【程序已按用户这句话里的名字查了角色库】下面这几个不用再查;'
          '和用户说的对不上的就不用管,别的角色照样先用 <search-character> 查。\n'
          '${answering ? '用户这句话是在回答你上一条用 <options> 问的问题:照用户选的写,同名的不要再问。\n' : ''}'
          '${formatCharacterResults(found, formOf: characterDict?.parentOf)}',
      note: tr('已按名字查了角色库:{0}', [found.keys.join(tr('、'))]),
    );
  }

  /// 系统提示最后那一条:先查再写。关掉的 Skill、没接上的工具不提。
  String _lookupFirstPrompt(AppConfig cfg) {
    final people = characters != null || characterDict != null;
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

  /// 系统提示里的【联网搜索】;关着或没有能搜的接口时不提。
  String get webSearchGuide =>
      webSearchChain(config.config).isEmpty ? '' : webSearchPrompt;

  /// 回复里要联网搜的东西;关着或没有能搜的接口时是空的。
  List<String> _webQueries(String prose) =>
      webSearchChain(config.config).isEmpty
      ? const []
      : splitToolTag(prose, webSearchTag).queries.take(_maxWebQueries).toList();

  bool wantsWebSearch(String reply) =>
      _webQueries(splitNewSkill(reply).prose).isNotEmpty;

  /// 联网搜索:用能搜的接口(不一定是写回复的这个)查好。一个接口搜不了就换下一个,
  /// 都不行的如实告诉模型。
  // ponytail: 用户点停止时这里不掐断,搜完的结果丢掉就是,最多多花一次搜索的钱。
  Future<Map<String, WebResult>> _searchWeb(List<String> asked) async {
    if (asked.isEmpty) return const {};
    final cfg = config.config;
    final chain = webSearchChain(cfg);
    final found = await Future.wait([
      for (final query in asked)
        () async {
          try {
            final text = await streamWithFailover(
              _requests(
                cfg,
                chain,
                cfg.activePreset,
                [
                  {'role': 'system', 'content': webSearchSystem},
                  {'role': 'user', 'content': query},
                ],
                piercing: '',
                webSearch: true,
              ),
              this.streamChat,
            ).join();
            return (text: text, failed: false);
          } on Object catch (e) {
            // 认不出的只报类型,原文可能带着 Key。
            return (
              text: e is LlmException ? e.message : '${e.runtimeType}',
              failed: true,
            );
          }
        }(),
    ]);
    return {for (final (i, query) in asked.indexed) query: found[i]};
  }

  /// 工具记录上列的那几行。
  List<String> _webDetails(Map<String, WebResult> results) => [
    for (final MapEntry(key: query, value: r) in results.entries)
      tr('「{0}」(联网):{1}', [
        query,
        r.failed
            ? tr('没搜到')
            : r.text.length > 80
            ? '${r.text.substring(0, 80)}…'
            : r.text,
      ]),
  ];

  /// 副聊天的回复里写了 `<search-tags>` / `<search-character>` / `<web-search>`:
  /// 照主聊天的查法查好,拼成交还给模型的那段话([text])和记在那一步上的一句([note])。
  /// 没有要查的返回 null。
  Future<({String text, String note})?> lookupFor(String reply) async {
    final prose = splitNewSkill(reply).prose;
    final queries = tagSearch == null
        ? const <String>[]
        : splitTagSearch(prose).queries.take(_maxQueries).toList();
    final names = characters == null && characterDict == null
        ? const <String>[]
        : splitCharacterTags(prose).queries.take(_maxQueries).toList();
    final webs = _webQueries(prose);
    if (queries.isEmpty && names.isEmpty && webs.isEmpty) return null;
    final (results, web) = await (_findTags(queries), _searchWeb(webs)).wait;
    final people = {for (final name in names) name: findCharacters(name)};
    return (
      text: [
        if (results.isNotEmpty) formatTagResults(results),
        if (people.isNotEmpty)
          formatCharacterResults(people, formOf: characterDict?.parentOf),
        if (web.isNotEmpty) formatWebResults(web),
      ].join('\n\n'),
      note: [
        if (web.isNotEmpty) tr('联网搜索 · {0} 次', [web.length]),
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
