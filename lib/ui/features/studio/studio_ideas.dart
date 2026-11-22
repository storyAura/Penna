part of 'studio_view_model.dart';

/// 每批点子最多几条。
const _ideaCount = 4;

/// Preset 正文最多带多少字给模型参考画风。
const _ideaPresetMax = 4000;

/// PennaSoul 的偏好最多带几条给模型。
const _ideaLikes = 8;

/// 记着最近出过的点子最多几条(叫模型别重复)。
const _ideaPastMax = 24;

/// 这么多批点子里有一批带上一个常用角色(2026-11-23 用户要求:按提到的次数加权随机抽,
/// 比例写死;更早的 11-21 反馈:以前每批都抽角色,点子被角色占满)。
const ideaCastChance = 0.3;

/// 出点子用的常用角色:[ideaCastChance] 的机会抽一个,提到次数越多越容易抽中;
/// 这批不带角色或没有常用角色时是 null。
String? pickIdeaCast(List<({String name, int count})> cast, Random random) {
  if (cast.isEmpty || random.nextDouble() >= ideaCastChance) return null;
  var ticket = random.nextInt(cast.fold(0, (a, c) => a + c.count));
  for (final c in cast) {
    ticket -= c.count;
    if (ticket < 0) return c.name;
  }
  return cast.last.name;
}

/// 每条点子随机给一个方向,免得一批批都是「给某某画一套衣服」。
const _ideaAngles = [
  '季节或天气',
  '节日或纪念日',
  '一件日常小事',
  '某个职业或身份',
  '一处具体的地点',
  '一天里的某个时段和光线',
  '一种情绪或关系',
  '一样道具或食物',
  '一段旅行或出行',
  '动物或植物',
  '一种运动或爱好',
  '一个意外的瞬间',
];

/// 新对话的空白处摆几条创作点子:用 Agent 的模型现想,点一条填进输入框。
/// 点子的类型照眼前的 Preset 来(2026-11-16 用户要求:写视频的 Preset 出视频的点子),
/// 往 PennaSoul 记着的偏好上靠。对话里一有话就作废,下一场新对话重想;换了 Preset 也重想。
/// 2026-11-21 用户反馈点子被角色占满、不跟 Preset、老重复:常用角色按 [pickIdeaCast]
/// 偶尔带一个(最多一条),名字照界面语言;每条随机给一个方向,出过的叫模型别重复。
/// PennaSoul 没开时偏好和常用角色都不用。
// ponytail: 出过的点子只记在这次运行里,重启后从头记。
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
    if (!_ideasOn) return;
    final preset = config.config.activePresetId;
    if ((_ideas != null || _ideasBusy) && _ideasFor != preset) forgetIdeas();
    if (_ideas != null || _ideasBusy) return;
    _ideasBusy = true;
    _ideasFor = preset;
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
    final random = Random();
    var found = const <String>[];
    try {
      final reply = await streamWithFailover(
        _requests(cfg, _usable(cfg.agentChain), preset, [
          {
            'role': 'system',
            'content': _ideasPrompt(
              cfg.language,
              preset.systemPrompt,
              soulOn ? soul!.entries : const [],
            ),
          },
          {
            'role': 'user',
            'content': _ideasAsk(
              _ideaCast(cfg.language, random),
              (_ideaAngles.toList()..shuffle(random)).take(_ideaCount).toList(),
              _pastIdeas,
            ),
          },
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
    final past = [..._pastIdeas, ...found];
    _pastIdeas = List.unmodifiable(
      past.skip((past.length - _ideaPastMax).clamp(0, past.length)),
    );
    _changed();
  }

  /// 拿来出点子的角色:PennaSoul 的常用角色里按次数抽的那一个([pickIdeaCast]),
  /// 名字照界面语言写。这批没抽到就不点名角色。
  List<String> _ideaCast(String language, Random random) {
    if (!soulOn) return const [];
    final name = pickIdeaCast(soul!.cast, random);
    return name == null ? const [] : [_ideaName(name, language)];
  }

  /// 显示给模型的角色名:自己存的照原名;内置的挑界面语言的那个别名,
  /// 英文界面用英文名(去掉括号里的作品)。
  String _ideaName(String name, String language) {
    final hit = characterDict?.byName(name);
    if (hit == null) return name;
    final english = name
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s*\(.*\)$'), '');
    if (language == 'en') return english;
    final kana = RegExp('[぀-ヿ]');
    final han = RegExp('[㐀-鿿]');
    final aliases = [
      for (final a in hit.alias.split(RegExp('[,,]')))
        if (a.trim().isNotEmpty) a.trim(),
    ];
    final pick = language == 'ja'
        ? aliases.where(kana.hasMatch).firstOrNull ??
              aliases.where(han.hasMatch).firstOrNull
        : aliases
              .where((a) => han.hasMatch(a) && !kana.hasMatch(a))
              .firstOrNull;
    return pick ?? english;
  }

  String _ideasAsk(List<String> cast, List<String> angles, List<String> past) =>
      [
        '这批 $_ideaCount 条各从一个方向想(按顺序):${angles.join('、')}。',
        if (cast.isEmpty)
          '不要点名具体的作品角色,写画面里是什么样的人或东西就行。'
        else
          '其中一条画用户常画的 ${cast.join('、')}(名字照写),其余的不点名具体角色。',
        if (past.isNotEmpty) '前面已经出过下面这些,不要重复,题材、句式和开头都要换:\n${past.join('\n')}',
      ].join('\n');

  String _ideasPrompt(String language, String preset, List<SoulEntry> memory) {
    final what = manga != null
        ? '一篇短漫画:谁、发生了什么、一个情节转折'
        : layoutOnly
        ? '一张多人或多物的画面:谁在哪、在做什么'
        : '一张画:主体、在做什么、在哪里';
    final lang = switch (language) {
      'en' => '英文',
      'ja' => '日文',
      'zh-Hant' => '繁体中文',
      _ => '简体中文',
    };
    final style = preset.trim();
    final likes = [
      for (final e in memory)
        if (e.kind == soulLike) e,
    ].take(_ideaLikes);
    return [
      '你给提示词工作台的用户出创作点子,点子要贴着用户这会儿用的 Preset。',
      if (style.isNotEmpty)
        '【用户当前的 Preset】点子是什么、题材和画风都照它的用途来:'
            '它写视频提示词,点子就是一段视频(谁、做什么动作、镜头怎么走);写写实摄影就是一张照片;'
            '写插画就是一幅插画;它专写某类题材就出那类题材。不要照它的输出格式写:\n'
            '${style.length > _ideaPresetMax ? style.substring(0, _ideaPresetMax) : style}',
      if (likes.isNotEmpty)
        '【用户明说过的偏好】有一两条往这些上靠就够了,别条条都一样:\n'
            '${likes.map((e) => '- ${e.text}').join('\n')}',
      '写 $_ideaCount 条,没有 Preset 指明别的用途时每条是$what。'
          '不要赛博朋克、全息、霓虹、未来科技、机甲、太空这类科幻元素,除非 Preset 本来就写这类。'
          '每条一行,不超过 30 个字,具体、有画面感;四条的句式各不相同,不要都用「给…画…」「用…画…」开头。'
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
