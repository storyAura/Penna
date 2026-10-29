part of 'studio_view_model.dart';

/// 有的模型(DeepSeek 这类)不照 Skill 先 `<search-character>` / `<search-tags>`,
/// 凭记忆就写。两道补救:用户的话里提到了角色库里的角色,程序先替它查好、接在这条消息后面;
/// 系统提示最后再钉一条短的「先查再写」(模型对最后读到的话最上心)。
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

  /// 接在用户这条消息后面的查询结果;没有就是空串。
  String _autoLookupText(Map<String, List<CharacterHit>> found) => found.isEmpty
      ? ''
      : '【程序已按用户这句话里的名字查了角色库】下面这几个不用再查;'
            '和用户说的对不上的就不用管,别的角色照样先用 <search-character> 查。\n'
            '${formatCharacterResults(found, formOf: characterDict?.parentOf)}';

  /// 系统提示最后那一条:先查再写。关掉的 Skill 不提。
  String _lookupFirstPrompt(AppConfig cfg) {
    final people = !cfg.disabledSkills.contains('character-lib');
    final tags = !cfg.disabledSkills.contains('danbooru-tags');
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
}
