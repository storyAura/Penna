import 'package:flutter/foundation.dart';

import 'mcp_server.dart';
import '../../l10n/l10n.dart';

export 'mcp_server.dart';

/// 区域控制交出去的 summary.caption 最前面默认加的质量词(属性栏里能改)。
const defaultLayoutQuality =
    'best quality, highres, newest, year 2026, 8k resolution, masterpiece, ultra-detailed';

/// 一个可勾选的选项(Skill 或工具)。
@immutable
class Option {
  const Option(this.id, this.label, this.hint);

  final String id;
  final String label;
  final String hint;
}

const builtinSkills = [
  Option('writer', '写提示词', '从一个想法写出完整的正面提示词'),
  Option('local-edit', '局部修改', '只改指定的地方,其余原样不动'),
  Option('reverse-polish', '整理反推', '把反推出的 Tag 或描述整理成能出图的提示词'),
  Option('theme-expand', '同题变体', '同一个主题再出 3~5 条不同的写法'),
  Option('paraphrase', '意译', '换一种语言重写提示词,保留结构,不逐字翻'),
  Option('skill-creator', '写 Skill', '聊着写出一个新 Skill,自动加入 Skills'),
  Option('danbooru-tags', '转标签', '把提示词改写成 Danbooru 标签,用到的标签都先查词库'),
  Option('image-remix', '照图写', '用户给了图,要照着它写、或照着它改几处'),
  Option('grilling', '画面规划', '用户只给了大概想法时,写词前先一问一答把画面定下来'),
  Option('storyboard', '分镜', '把故事或情节拆成一组镜头,每个镜头一条能单独出图的提示词'),
  Option('character-lib', '角色库', '用户提到某个具体角色时先查它的触发词和特征;要存角色时也用'),
  Option('moss-layout', '区域控制', '要按位置安排画面(画框、bbox、转成 MOSS-Image 布局 JSON)时写布局'),
  Option('comic-page', '漫画分格', '一张图里排几格漫画:分格、气泡与台词归属、跨格一致,也能排成区域控制布局'),
  Option('local-reverse', '本地反推', '用户要用 Tag 反推、或点名用本机的某个模型反推图片时,调用本地模型'),
];

/// 聊天框上方的快捷操作:点一下把 [prompt] 接在输入框末尾。
typedef QuickAction = ({String label, String prompt});

const defaultQuickActions = <QuickAction>[
  (label: '转成自然语言', prompt: '将提示词转换成自然语言'),
  (label: '转成 Tag', prompt: '将提示词转换成 Tag'),
];

const builtinTools = [
  Option('ask_user', 'ask_user', '结构化澄清'),
  Option('context_memory', 'context_memory', '会话笔记 / 释放旧回复'),
  Option('load_skill', 'load_skill', '按需加载 Skill'),
  Option('reverse_image', 'reverse_image', '触发 Tag 或自然语言反推'),
  Option('translate_mt', 'translate_mt', '机翻(多引擎)'),
  Option('translate_llm', 'translate_llm', 'LLM 意译'),
  Option('search_tags', 'search_tags', 'Danbooru 类 Tag 检索'),
  Option('related_tags', 'related_tags', '相关 Tag'),
  Option('prompt_library', 'prompt_library', '词库增删改查'),
  Option('view_reference', 'view_reference', '查看参考图与批注(只读)'),
];

@immutable
class MtField {
  const MtField(this.id, this.label, {this.secret = false});

  final String id;
  final String label;
  final bool secret;
}

@immutable
class MtEngine {
  const MtEngine(this.id, this.label, this.fields);

  final String id;
  final String label;
  final List<MtField> fields;

  String keyOf(MtField field) => 'mt.$id.${field.id}';
}

/// 全部机翻引擎;没有字段的是免费、无需凭据的。
const mtEngines = [
  MtEngine('google_free', 'Google 网页接口', []),
  MtEngine('mymemory', 'MyMemory', []),
  MtEngine('google', 'Google Cloud', [MtField('key', 'API Key', secret: true)]),
  MtEngine('ali', '阿里翻译', [
    MtField('id', 'AccessKey ID'),
    MtField('secret', 'AccessKey Secret', secret: true),
  ]),
  MtEngine('baidu', '百度翻译', [
    MtField('appid', 'APP ID'),
    MtField('secret', '密钥', secret: true),
  ]),
];

const defaultMtOrder = ['google_free', 'mymemory', 'google', 'ali', 'baidu'];
const defaultMtEnabled = {'google_free', 'mymemory'};
const minMtAttempts = 1;
const maxMtAttempts = 10;
const minMtTimeoutSeconds = 3;
const maxMtTimeoutSeconds = 120;
const defaultMtAttempts = 3;
const defaultMtTimeoutSeconds = 25;

/// 区域控制的画布宽高取它的倍数(MOSS-Image 要 16);1 是不对齐。
const defaultLayoutSnap = 16;
const minLayoutSnap = 1;
const maxLayoutSnap = 256;

/// 「界面大小」能选的倍数。
const uiScales = [1.0, 1.25, 1.5, 1.75, 2.0];
const minUiScale = 1.0;
const maxUiScale = 2.0;

/// 把存下来的顺序整理成"每个已知引擎恰好出现一次":丢掉不认识的,补上漏掉的。
List<String> normalizeMtOrder(Iterable<String> saved) {
  final known = {for (final e in mtEngines) e.id};
  final kept = <String>{...saved.where(known.contains)};
  return List.unmodifiable([
    ...kept,
    ...defaultMtOrder.where((id) => !kept.contains(id)),
  ]);
}

String llmSecretKey(String llmId) => 'llm.$llmId.key';

/// HuggingFace 的 Token:下要申请访问的本地模型时用。
const hfTokenSecret = 'hf.token';

const protocolOpenAi = 'openai';
const protocolGoogle = 'google';

const defaultBaseUrls = {
  protocolOpenAi: 'https://api.openai.com/v1',
  protocolGoogle: 'https://generativelanguage.googleapis.com/v1beta',
};

/// 一个模型接口(OpenAI 或 Google 协议)。Key 不在这里,见 [AppConfig.secrets]。
@immutable
class LlmProfile {
  const LlmProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    this.protocol = protocolOpenAi,
    this.enabled = true,
  });

  factory LlmProfile.fromJson(Map<String, dynamic> j) => LlmProfile(
    id: j['id'] as String,
    name: j['name'] as String,
    baseUrl: j['baseUrl'] as String,
    model: j['model'] as String,
    protocol: j['protocol'] == protocolGoogle ? protocolGoogle : protocolOpenAi,
    enabled: j['enabled'] as bool? ?? true,
  );

  final String id;
  final String name;
  final String baseUrl;

  /// 模型名称。一个接口可以填好几个,用逗号隔开,按先后顺序使用(见 [models])。
  final String model;
  final String protocol;

  /// 这个接口要用的模型,按先后顺序;前一个失败了换下一个。
  List<String> get models => [
    for (final m in model.split(RegExp(r'[,,\n]')))
      if (m.trim().isNotEmpty) m.trim(),
  ];

  /// 关掉的模型不参与任何用途。
  final bool enabled;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'model': model,
    'protocol': protocol,
    'enabled': enabled,
  };

  LlmProfile copyWith({
    String? name,
    String? baseUrl,
    String? model,
    String? protocol,
    bool? enabled,
  }) => LlmProfile(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    protocol: protocol ?? this.protocol,
    enabled: enabled ?? this.enabled,
  );
}

/// Preset = 系统提示 + 工具白名单。Skills 对所有 Preset 生效,见 [AppConfig.disabledSkills]。
@immutable
class AgentPreset {
  const AgentPreset({
    required this.id,
    required this.name,
    required this.systemPrompt,
    required this.tools,
    this.temperature = 0.7,
    this.topP = 1,
  });

  factory AgentPreset.fromJson(Map<String, dynamic> j) => AgentPreset(
    id: j['id'] as String,
    name: j['name'] as String,
    systemPrompt: j['systemPrompt'] as String,
    tools: {...(j['tools'] as List).cast<String>()},
    temperature: ((j['temperature'] as num?) ?? 0.7).clamp(0, 2).toDouble(),
    topP: ((j['topP'] as num?) ?? 1).clamp(0.1, 1).toDouble(),
  );

  final String id;
  final String name;
  final String systemPrompt;
  final Set<String> tools;
  final double temperature;

  /// 只在累计概率排在前这么多的词里选;1 是不限制(不发给模型)。
  final double topP;

  /// 界面上显示的名字;名字被清空时给个占位,免得出现点不到的空白项。
  /// 界面上显示的名字:内置 Preset 的名字按界面语言翻译,自己起的原样。
  String get displayName => name.trim().isEmpty ? tr('未命名') : tr(name);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'systemPrompt': systemPrompt,
    'tools': tools.toList(),
    'temperature': temperature,
    'topP': topP,
  };

  AgentPreset copyWith({
    String? id,
    String? name,
    String? systemPrompt,
    Set<String>? tools,
    double? temperature,
    double? topP,
  }) => AgentPreset(
    id: id ?? this.id,
    name: name ?? this.name,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    tools: tools ?? this.tools,
    temperature: temperature ?? this.temperature,
    topP: topP ?? this.topP,
  );
}

const _positiveOnly = '你只处理文生图的【正面】提示词,不写负面提示词,也不负责出图。回答用中文,提示词本身用英文。';

const _writerTools = {
  'ask_user',
  'context_memory',
  'load_skill',
  'reverse_image',
  'translate_mt',
  'translate_llm',
  'search_tags',
  'related_tags',
  'prompt_library',
  'view_reference',
};

/// 出厂默认用的 Preset,见 [AppConfig.activePresetId]。
const defaultPresetId = 'anime';

const factoryPresets = [
  AgentPreset(
    id: defaultPresetId,
    name: '动漫风格',
    systemPrompt:
        '你是动漫插画提示词的写手。根据用户给的创作需求(一句话、关键词、角色设定或场景想法),'
        '主动构思并写出一段完整、具体、可直接用于出图的英文提示词。\n\n'
        '提示词写成一个连贯的英文段落,一般不超过 600 词,以 anime illustration of 开头,'
        '把需求扩写成画面清晰、细节完整的日系动漫插画。\n\n'
        '1. 确定性陈述:用肯定、精确的陈述句描写画面里有什么,如同在描述一张已经存在的图。'
        '不用 seems、appears、might、possibly、suggests 这类模糊词。'
        '用户没指定的细节由你补全,保持合理、统一,不与用户的需求冲突。\n\n'
        '2. 忠实需求:用户明确给出的元素(角色、服装、动作、场景、构图、光线等)完整保留,'
        '不删改、不替换。补充的细节只用来丰富画面,不改变用户的核心意图。\n\n'
        '3. 要写到的细节:\n'
        '- 人物与实体:外貌、发型发色、瞳色、五官、神态、衣着、姿势、动作和表情。'
        '用户指定了已有角色时,直接写出外观特征。\n'
        '- 物体与环境:场景(室内、室外、城市、自然等)、所有物体,以及它们彼此之间、与角色之间的空间关系。\n'
        '- 画面属性:视角(低角度、平视、俯视等)、景别、构图、景深、对焦、光线的方向与质感、'
        '镜头效果(如鱼眼畸变、镜头光晕)。\n'
        '- 画面中的文字:写明内容、位置、颜色、字体风格和大小。\n\n'
        '4. 不写的内容:\n'
        '- 主观评价与叙事:画面背后的含义、象征、故事或情绪评论,以及 beautiful、masterpiece、stunning 这类赞美词。\n'
        '- 额外的风格标签:除开头点明的动漫插画外,不再叠加艺术流派、渲染方式或绘画媒介,用户明确要求时除外。\n\n'
        '$_positiveOnly',
    tools: _writerTools,
    temperature: 0.9,
  ),
  AgentPreset(
    id: 'realistic',
    name: '真实风格',
    systemPrompt:
        '你是写实摄影提示词的写手。根据用户给的创作需求,写出一段可直接用于写实图像模型的英文提示词。\n\n'
        '提示词写成一个英文段落,90 到 130 词,以 Photograph of 或 '
        'This is a highly detailed photograph of 开头,按下面的顺序写。'
        '用户没提到的部分由你补全,保持合理、统一。\n\n'
        '1. 主体:是什么、数量、最显眼的特征。写人物时写明年龄段、体型、肤色、发色与发型,人物一律按成年人描写。\n'
        '2. 衣着与材质:用具体的面料和质感词(linen shirt、brushed steel、wet asphalt),写清每样东西的颜色和状态。\n'
        '3. 姿态:一个具体的动作或状态,以及视线的方向和表情。\n'
        '4. 环境:一句话交代场景,背景略微虚化。\n'
        '5. 光线:写明光源和它造成的效果(侧光、窗光、逆光),以及阴影落在哪里、是软是硬。\n'
        '6. 一处质感细节:织物的纹理、皮肤的质感、水珠、划痕、灰尘。\n'
        '7. 最后一句只写氛围,3 到 6 个词。\n\n'
        '规则:\n'
        '- 按照片来描写,不写成插画、动漫或 3D 渲染。\n'
        '- 不写画师名,不堆 masterpiece、8k、ultra detailed 这类质量词;用户没要求就不列相机参数。\n'
        '- 不写真人的姓名,不写"长得像某某"。\n'
        '- 衣着和物件写进段落里,不单独列成清单。\n'
        '- 用户指定的主体、年龄、衣着和场景原样保留。\n\n'
        '$_positiveOnly',
    tools: _writerTools,
    temperature: 0.9,
  ),
  AgentPreset(
    id: 'collab',
    name: '协同写词',
    systemPrompt:
        '你是 Penna 的提示词协作者。先弄清用户想要的画面,再给出完整的英文自然语言正面提示词;'
        '用户要求修改时只做最小必要改动,并说明改了哪里。$_positiveOnly',
    tools: _writerTools,
  ),
  AgentPreset(
    id: 'reverse',
    name: '反推润色',
    systemPrompt:
        '你负责把图片反推得到的 Tag 或自然语言描述,整理成干净、可直接出图的英文正面提示词:'
        '去重、合并同义、按主体→外观→场景→光影→镜头排序。$_positiveOnly',
    tools: {
      'ask_user',
      'context_memory',
      'load_skill',
      'reverse_image',
      'search_tags',
      'related_tags',
      'view_reference',
    },
    temperature: 0.4,
  ),
  AgentPreset(
    id: 'translate',
    name: '意译合稿',
    systemPrompt:
        '你负责提示词的意译:保留原文的结构和信息量,用地道的英文表达画面,而不是逐字翻译;'
        '同时给出中文对照,方便用户核对。$_positiveOnly',
    tools: {'ask_user', 'load_skill', 'translate_mt', 'translate_llm'},
    temperature: 0.3,
  ),
  AgentPreset(
    id: 'free',
    name: '自由改稿',
    systemPrompt:
        '你是提示词改稿助手。按用户的要求大胆改写、扩写或给出多个变体,每个变体单独成段并用一句话说明差异。$_positiveOnly',
    // 不带 local-edit:它要求"只做最小改动",和这个 Preset 的"大胆改写"相反。
    tools: {'ask_user', 'context_memory', 'load_skill', 'prompt_library'},
    temperature: 0.9,
  ),
];

/// 全部用户设置。[secrets] 单独加密保存,不进 [toJson]。
@immutable
class AppConfig {
  const AppConfig({
    this.llms = const [],
    this.activeLlmId,
    this.polishLlmId,
    this.mtOrder = defaultMtOrder,
    this.mtEnabled = defaultMtEnabled,
    this.mtAttempts = defaultMtAttempts,
    this.mtTimeoutSeconds = defaultMtTimeoutSeconds,
    this.fields = const {},
    this.paraphrase = true,
    this.presets = factoryPresets,
    this.activePresetId = defaultPresetId,
    this.fontLatin = '',
    this.fontCjk = '',
    this.agentAvatar = '',
    this.userAvatar = '',
    this.language = 'zh-Hans',
    this.darkMode = false,
    this.uiScale = 1,
    this.disabledSkills = const {},
    this.tagSearchOnline = true,
    this.piercing = false,
    this.piercingPrompt = '',
    this.layoutQuality = defaultLayoutQuality,
    this.layoutSnap = defaultLayoutSnap,
    this.compressImages = true,
    this.autoApprove = false,
    this.characterPreviews = false,
    this.updateChannel = 'main',
    this.quickActions = defaultQuickActions,
    this.mcpServers = const [],
    this.secrets = const {},
  });

  factory AppConfig.fromJson(Object? json) {
    final m = json as Map<String, dynamic>;
    final presets = [
      for (final p in m['presets'] as List? ?? const [])
        AgentPreset.fromJson(p as Map<String, dynamic>),
    ];
    return AppConfig(
      llms: [
        for (final l in m['llms'] as List? ?? const [])
          LlmProfile.fromJson(l as Map<String, dynamic>),
      ],
      activeLlmId: m['activeLlmId'] as String?,
      polishLlmId: m['polishLlmId'] as String?,
      mtOrder: normalizeMtOrder((m['mtOrder'] as List? ?? const []).cast()),
      // 旧版配置没有 mtOrder:那时的开关还没接功能,直接换成新默认(免费引擎)。
      mtEnabled: m['mtOrder'] == null
          ? defaultMtEnabled
          : {...(m['mtEnabled'] as List? ?? const []).cast<String>()},
      mtAttempts: ((m['mtAttempts'] as num?) ?? defaultMtAttempts)
          .clamp(minMtAttempts, maxMtAttempts)
          .toInt(),
      mtTimeoutSeconds:
          ((m['mtTimeoutSeconds'] as num?) ?? defaultMtTimeoutSeconds)
              .clamp(minMtTimeoutSeconds, maxMtTimeoutSeconds)
              .toInt(),
      fields: {...(m['fields'] as Map? ?? const {}).cast<String, String>()},
      paraphrase: m['paraphrase'] as bool? ?? true,
      presets: presets.isEmpty ? factoryPresets : presets,
      activePresetId: m['activePresetId'] as String? ?? defaultPresetId,
      fontLatin: m['fontLatin'] as String? ?? '',
      fontCjk: m['fontCjk'] as String? ?? '',
      agentAvatar: m['agentAvatar'] as String? ?? '',
      userAvatar: m['userAvatar'] as String? ?? '',
      language: m['language'] as String? ?? 'zh-Hans',
      darkMode: m['darkMode'] as bool? ?? false,
      uiScale: ((m['uiScale'] as num?) ?? 1)
          .clamp(minUiScale, maxUiScale)
          .toDouble(),
      tagSearchOnline: m['tagSearchOnline'] as bool? ?? true,
      piercing: m['piercing'] as bool? ?? false,
      piercingPrompt: m['piercingPrompt'] as String? ?? '',
      layoutQuality: m['layoutQuality'] as String? ?? defaultLayoutQuality,
      layoutSnap: ((m['layoutSnap'] as num?) ?? defaultLayoutSnap)
          .clamp(minLayoutSnap, maxLayoutSnap)
          .toInt(),
      compressImages: m['compressImages'] as bool? ?? true,
      autoApprove: m['autoApprove'] as bool? ?? false,
      characterPreviews: m['characterPreviews'] as bool? ?? false,
      updateChannel: m['updateChannel'] == 'dev' ? 'dev' : 'main',
      // 旧配置里没有这一项才给默认的;用户删空了就是空的。
      quickActions: m['quickActions'] == null
          ? defaultQuickActions
          : List.unmodifiable([
              for (final a in (m['quickActions'] as List).cast<Map>())
                (
                  label: a['label'] as String? ?? '',
                  prompt: a['prompt'] as String? ?? '',
                ),
            ]),
      disabledSkills: {
        ...(m['disabledSkills'] as List? ?? const []).cast<String>(),
      },
      mcpServers: [
        for (final s in m['mcpServers'] as List? ?? const [])
          McpServer.fromJson(s as Map<String, dynamic>),
      ],
    );
  }

  final List<LlmProfile> llms;

  /// [llms] 的先后就是使用顺序:排前面的先用,失败了换下一个。
  /// 这两个是"指定":Agent 对话 / 润色优先用哪个模型;null 表示直接按顺序。
  final String? activeLlmId;
  final String? polishLlmId;

  /// Agent 对话依次尝试的模型。
  List<LlmProfile> get agentChain => _llmChain(activeLlmId);

  /// 润色依次尝试的模型。
  List<LlmProfile> get polishChain => _llmChain(polishLlmId);

  List<LlmProfile> _llmChain(String? pinnedId) {
    final usable = llms.where((l) => l.enabled);
    return [
      ...usable.where((l) => l.id == pinnedId),
      ...usable.where((l) => l.id != pinnedId),
    ];
  }

  /// 启用的机翻引擎 id。
  final Set<String> mtEnabled;

  /// 全部引擎的优先顺序(含未启用的)。
  final List<String> mtOrder;

  /// 每个引擎最多尝试几次、单次等多久,都不行就换下一个。
  final int mtAttempts;
  final int mtTimeoutSeconds;

  /// 按优先顺序排好的已启用引擎。
  List<String> get mtChain => [
    for (final id in mtOrder)
      if (mtEnabled.contains(id)) id,
  ];

  /// 非机密的引擎字段(如 APP ID),键见 [MtEngine.keyOf]。
  final Map<String, String> fields;

  /// 是否启用 LLM 意译。
  final bool paraphrase;
  final List<AgentPreset> presets;
  final String activePresetId;

  /// 用户指定的英文 / 中文字体名;空串表示用内置字体。
  final String fontLatin;
  final String fontCjk;

  /// 对话里 Agent / 用户头像的图片路径;空串表示用默认头像。
  final String agentAvatar;
  final String userAvatar;

  /// 界面语言:zh-Hans、zh-Hant、en、ja(见 `l10n/l10n.dart`)。
  final String language;

  /// 深色模式。
  final bool darkMode;

  /// 界面整体放大几倍(高分屏上嫌小时调),1 是原样。
  final double uiScale;

  /// 成稿每段下面的对照译文(〔译〕)和机翻用什么语言,跟着界面语言走:
  /// 'zh'(简体)、'zh-Hant'、'ja';英文界面不要对照,为 null。
  String? get glossLanguage => switch (language) {
    'en' => null,
    'zh-Hant' => 'zh-Hant',
    'ja' => 'ja',
    _ => 'zh',
  };

  /// 被用户关掉的 Skill。不在这里面的都是开着的,对所有 Preset 生效;
  /// 所以新导入、新写出来的 Skill 默认就能用。
  final Set<String> disabledSkills;

  /// 查 Danbooru 标签时先问在线的 DanbooruSearch;关掉就只查内置词库。
  final bool tagSearchOnline;

  /// 穿甲弹:开着时 [piercingPrompt] 放在每次请求的系统提示最前面,所有 Preset 都带。
  final bool piercing;
  final String piercingPrompt;

  /// 区域控制交出去的 JSON 里 summary.caption 最前面的质量词;空串是不加。
  final String layoutQuality;

  /// 区域控制的画布宽高对齐到它的倍数(见 [defaultLayoutSnap])。
  final int layoutSnap;

  /// 要注入的穿甲弹文字;关着或没填为空串。
  String get piercingText => piercing ? piercingPrompt.trim() : '';

  /// 对话里附上的大图先缩小、转成 WebP 再发。
  final bool compressImages;

  /// 成稿的待确认改动一出来就自动采纳,不用用户点。
  final bool autoApprove;

  /// 内置角色库要不要下载预览图。
  // ponytail: 只是个开关,预览图的仓库还没建;建好后角色库按它去下载、缓存。
  final bool characterPreviews;

  /// 检查更新看哪个通道:'main' 是正式版,'dev' 是测试版。
  final String updateChannel;

  /// 聊天框上方的快捷操作,先后就是显示顺序。
  final List<QuickAction> quickActions;
  final List<McpServer> mcpServers;
  final Map<String, String> secrets;

  Map<String, dynamic> toJson() => {
    'llms': [for (final l in llms) l.toJson()],
    'activeLlmId': activeLlmId,
    'polishLlmId': polishLlmId,
    'mtOrder': mtOrder,
    'mtEnabled': mtEnabled.toList(),
    'mtAttempts': mtAttempts,
    'mtTimeoutSeconds': mtTimeoutSeconds,
    'fields': fields,
    'paraphrase': paraphrase,
    'presets': [for (final p in presets) p.toJson()],
    'activePresetId': activePresetId,
    'fontLatin': fontLatin,
    'fontCjk': fontCjk,
    'agentAvatar': agentAvatar,
    'userAvatar': userAvatar,
    'language': language,
    'darkMode': darkMode,
    'uiScale': uiScale,
    'disabledSkills': disabledSkills.toList(),
    'tagSearchOnline': tagSearchOnline,
    'piercing': piercing,
    'piercingPrompt': piercingPrompt,
    'layoutQuality': layoutQuality,
    'layoutSnap': layoutSnap,
    'compressImages': compressImages,
    'autoApprove': autoApprove,
    'characterPreviews': characterPreviews,
    'updateChannel': updateChannel,
    'quickActions': [
      for (final a in quickActions) {'label': a.label, 'prompt': a.prompt},
    ],
    'mcpServers': [for (final s in mcpServers) s.toJson()],
  };

  /// 开关一个 Skill。
  AppConfig setSkill(String id, {required bool on}) => copyWith(
    disabledSkills: on
        ? ({...disabledSkills}..remove(id))
        : {...disabledSkills, id},
  );

  AgentPreset get activePreset => presets.firstWhere(
    (p) => p.id == activePresetId,
    orElse: () => presets.first,
  );

  String llmKey(String llmId) => secrets[llmSecretKey(llmId)] ?? '';

  AppConfig copyWith({
    List<LlmProfile>? llms,
    String? Function()? activeLlmId,
    String? Function()? polishLlmId,
    Set<String>? mtEnabled,
    List<String>? mtOrder,
    int? mtAttempts,
    int? mtTimeoutSeconds,
    Map<String, String>? fields,
    bool? paraphrase,
    List<AgentPreset>? presets,
    String? activePresetId,
    String? fontLatin,
    String? fontCjk,
    String? agentAvatar,
    String? userAvatar,
    String? language,
    bool? darkMode,
    double? uiScale,
    Set<String>? disabledSkills,
    bool? tagSearchOnline,
    bool? piercing,
    String? piercingPrompt,
    String? layoutQuality,
    int? layoutSnap,
    bool? compressImages,
    bool? autoApprove,
    bool? characterPreviews,
    String? updateChannel,
    List<QuickAction>? quickActions,
    List<McpServer>? mcpServers,
    Map<String, String>? secrets,
  }) => AppConfig(
    llms: llms ?? this.llms,
    activeLlmId: activeLlmId == null ? this.activeLlmId : activeLlmId(),
    polishLlmId: polishLlmId == null ? this.polishLlmId : polishLlmId(),
    mtEnabled: mtEnabled ?? this.mtEnabled,
    mtOrder: mtOrder ?? this.mtOrder,
    mtAttempts: mtAttempts ?? this.mtAttempts,
    mtTimeoutSeconds: mtTimeoutSeconds ?? this.mtTimeoutSeconds,
    fields: fields ?? this.fields,
    paraphrase: paraphrase ?? this.paraphrase,
    presets: presets ?? this.presets,
    activePresetId: activePresetId ?? this.activePresetId,
    fontLatin: fontLatin ?? this.fontLatin,
    fontCjk: fontCjk ?? this.fontCjk,
    agentAvatar: agentAvatar ?? this.agentAvatar,
    userAvatar: userAvatar ?? this.userAvatar,
    language: language ?? this.language,
    darkMode: darkMode ?? this.darkMode,
    uiScale: uiScale ?? this.uiScale,
    disabledSkills: disabledSkills ?? this.disabledSkills,
    tagSearchOnline: tagSearchOnline ?? this.tagSearchOnline,
    piercing: piercing ?? this.piercing,
    piercingPrompt: piercingPrompt ?? this.piercingPrompt,
    layoutQuality: layoutQuality ?? this.layoutQuality,
    layoutSnap: layoutSnap ?? this.layoutSnap,
    compressImages: compressImages ?? this.compressImages,
    autoApprove: autoApprove ?? this.autoApprove,
    characterPreviews: characterPreviews ?? this.characterPreviews,
    updateChannel: updateChannel ?? this.updateChannel,
    quickActions: quickActions ?? this.quickActions,
    mcpServers: mcpServers ?? this.mcpServers,
    secrets: secrets ?? this.secrets,
  );

  AppConfig setSecret(String key, String value) =>
      copyWith(secrets: {...secrets, key: value});

  AppConfig setField(String key, String value) =>
      copyWith(fields: {...fields, key: value});

  /// 新增(排到最后)或替换一个模型。
  AppConfig putLlm(LlmProfile llm) {
    final exists = llms.any((l) => l.id == llm.id);
    return copyWith(
      llms: exists
          ? [for (final l in llms) l.id == llm.id ? llm : l]
          : [...llms, llm],
    );
  }

  /// 把第 [from] 个模型挪到第 [to] 位。
  AppConfig moveLlm(int from, int to) {
    final next = [...llms];
    next.insert(to, next.removeAt(from));
    return copyWith(llms: next);
  }

  /// 删除模型及其 Key;指定了它的用途改回按顺序。
  AppConfig removeLlm(String id) => copyWith(
    llms: [
      for (final l in llms)
        if (l.id != id) l,
    ],
    activeLlmId: () => activeLlmId == id ? null : activeLlmId,
    polishLlmId: () => polishLlmId == id ? null : polishLlmId,
    secrets: {...secrets}..remove(llmSecretKey(id)),
  );

  AppConfig putPreset(AgentPreset preset) => copyWith(
    presets: [for (final p in presets) p.id == preset.id ? preset : p],
  );
}

bool isFactoryPreset(String id) => factoryPresets.any((p) => p.id == id);

extension McpEditing on AppConfig {
  /// 新增或替换一个 MCP 服务。
  AppConfig putMcp(McpServer server) => copyWith(
    mcpServers: mcpServers.any((s) => s.id == server.id)
        ? [for (final s in mcpServers) s.id == server.id ? server : s]
        : [...mcpServers, server],
  );

  /// 删除 MCP 服务及其令牌、环境变量。
  AppConfig removeMcp(String id) => copyWith(
    mcpServers: [
      for (final s in mcpServers)
        if (s.id != id) s,
    ],
    secrets: {...secrets}
      ..remove(mcpTokenKey(id))
      ..remove(mcpEnvKey(id)),
  );
}

extension PresetEditing on AppConfig {
  /// 新增一个 Preset 并设为当前。
  AppConfig addPreset(AgentPreset preset) =>
      copyWith(presets: [...presets, preset], activePresetId: preset.id);

  /// 删除 Preset;至少保留一个,删的是当前的就改用第一个。
  AppConfig removePreset(String id) {
    final rest = [
      for (final p in presets)
        if (p.id != id) p,
    ];
    if (rest.isEmpty) return this;
    return copyWith(
      presets: rest,
      activePresetId: activePresetId == id ? rest.first.id : activePresetId,
    );
  }
}
