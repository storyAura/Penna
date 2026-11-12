part of 'studio_view_model.dart';

/// 每批点子最多几条。
const _ideaCount = 4;

/// 内置角色从图最多的前这么多个里抽:大家认得的。
const _ideaPopular = 2000;

/// Preset 正文最多带多少字给模型参考画风。
const _ideaPresetMax = 4000;

/// 新对话的空白处摆几条创作点子:用 Agent 的模型现想,点一条填进输入框。
/// 对话里一有话就作废,下一场新对话重想。
extension StudioIdeas on StudioViewModel {
  /// 眼前的点子;还没要或正在要时是 null,要过但没要到是空的。
  List<String>? get ideaList => _ideas;
  bool get ideasBusy => _ideasBusy;

  bool get _ideasOn =>
      ideas &&
      config.config.chatIdeas &&
      _usable(config.config.agentChain).isNotEmpty;

  /// 空对话显示时调:还没有点子就去要一份。可以在 build 里调,要到之前不通知。
  void wantIdeas() {
    if (!_ideasOn || _ideas != null || _ideasBusy) return;
    _ideasBusy = true;
    unawaited(_fetchIdeas(_ideasRun));
  }

  /// 对话里有话了:这份作废(正在要的也作废)。不通知,build 里也能调。
  void forgetIdeas() {
    if (_ideas == null && !_ideasBusy) return;
    _ideas = null;
    _ideasBusy = false;
    _ideasRun++;
  }

  /// 换一批。
  void refreshIdeas() {
    forgetIdeas();
    wantIdeas();
    _changed();
  }

  Future<void> _fetchIdeas(int run) async {
    final cfg = config.config;
    final preset = cfg.activePreset;
    var found = const <String>[];
    try {
      final reply = await streamWithFailover(
        _requests(cfg, _usable(cfg.agentChain), preset, [
          {
            'role': 'system',
            'content': _ideasPrompt(cfg.language, preset.systemPrompt),
          },
          {'role': 'user', 'content': _ideasAsk(_ideaCast(Random()))},
        ], piercing: ''),
        this.streamChat,
      ).join();
      found = parseIdeas(reply);
    } on Object catch (e) {
      // 只记类型:原文可能带着 Key。没要到就不摆,不打扰用户。
      debugPrint('对话建议没要到(${e.runtimeType})');
    }
    if (_disposed || run != _ideasRun) return;
    _ideasBusy = false;
    _ideas = found;
    _changed();
  }

  /// 程序替模型抽好这批用的角色:先从用户自己存的和收藏的里抽一半,
  /// 再从内置角色库的热门角色里补满 [_ideaCount] 个,不重复。
  List<String> _ideaCast(Random random) {
    final store = characters;
    final mine = <String>{
      if (store != null) ...[
        for (final c in store.cards) c.name.trim(),
        ...store.favoriteCharacters,
      ],
    }.where((n) => n.isNotEmpty).toList()..shuffle(random);
    final cast = <String>{...mine.take(_ideaCount ~/ 2).map(_ideaName)};
    final popular = characterDict?.all.take(_ideaPopular).toList() ?? const [];
    for (
      var tries = 0;
      cast.length < _ideaCount && popular.isNotEmpty && tries < 20;
      tries++
    ) {
      cast.add(_ideaName(popular[random.nextInt(popular.length)].name));
    }
    // 内置库也没有时,把自己的剩下的补上。
    cast.addAll(
      mine.skip(_ideaCount ~/ 2).take(_ideaCount - cast.length).map(_ideaName),
    );
    return cast.toList();
  }

  /// 显示给模型的角色名:内置的用第一个别名(中文名)加作品,没有别名就把下划线换成空格。
  String _ideaName(String name) {
    final hit = characterDict?.byName(name);
    if (hit == null) return name;
    final alias = hit.alias.split(RegExp('[,,]')).first.trim();
    final shown = alias.isNotEmpty ? alias : name.replaceAll('_', ' ');
    final series = hit.series.replaceAll('_', ' ').trim();
    return series.isEmpty ? shown : '$shown($series)';
  }

  String _ideasAsk(List<String> cast) => cast.isEmpty
      ? '角色你来挑,用知名的动漫、游戏角色,四条各不相同。'
      : '这批的角色已经抽好,每条用一个,按这个顺序:${cast.join('、')}。'
            '名字照写,括号里的作品名不用写进点子。';

  String _ideasPrompt(String language, String preset) {
    final what = manga != null
        ? '「用某角色画一篇什么漫画」,带一个情节转折'
        : layoutOnly
        ? '「让某角色和谁同框做什么」,写清谁在哪'
        : '「给某角色画什么」或「用某角色画什么」,带上服装、动作或场景';
    final lang = switch (language) {
      'en' => '英文',
      'ja' => '日文',
      'zh-Hant' => '繁体中文',
      _ => '简体中文',
    };
    final style = preset.trim();
    return [
      if (style.isNotEmpty)
        '【用户当前的 Preset】下面是用户写词时用的设定,只拿来参考画风和题材取向,'
            '不要照它的输出格式写:\n'
            '${style.length > _ideaPresetMax ? style.substring(0, _ideaPresetMax) : style}',
      '你给文生图提示词工作台的用户出创作点子。写 $_ideaCount 条,句式是$what,'
          '例如「给芙莉莲画一套夏日浴衣」「用阿尼亚画她第一次上烹饪课」。'
          '点子要贴着角色本身:服装、表情、日常场景、和别人的互动、季节节日;画风和题材跟上面的 Preset 一致。'
          '不要赛博朋克、全息、霓虹、未来科技、机甲、太空这类科幻元素,除非角色本来就出自这类作品。'
          '每条一行,不超过 30 个字,具体、有画面感。'
          '只写点子本身,不编号,不加引号,不解释。用$lang写。',
    ].join('\n\n');
  }
}

/// 从模型的回复里取出点子:一行一条,去掉编号、项目符号和引号,太长的不要。
List<String> parseIdeas(String reply) => [
  for (final line
      in reply.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').split('\n'))
    if (line
            .replaceFirst(RegExp(r'^\s*(?:[-*•·]|\d+[.、)）])?\s*'), '')
            .replaceAll(RegExp(r'^["“「『]+|["”」』]+$'), '')
            .trim()
        case final idea when idea.isNotEmpty && idea.length <= 60)
      idea,
].take(_ideaCount).toList();
