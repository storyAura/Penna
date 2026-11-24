import 'package:flutter/foundation.dart';

/// ComfyUI 默认的本机地址。
const comfyDefaultUrl = 'http://127.0.0.1:8188';

/// 新装时那一台(本机)的 id;它的 Key 沿用最早只有一台时的键名。
const comfyLocalId = 'local';

/// 内置文生图的 id:一个工作流都没导入时才用它(不存全文,用的时候按第一个模型现拼)。
const builtinWorkflowId = '';

/// 一台 ComfyUI 的 Key 在 `AppConfig.secrets` 里的键(给云端前面的反向代理用,本机的不用填)。
String comfyKeyName(String serverId) =>
    serverId == comfyLocalId ? 'comfy.key' : 'comfy.$serverId.key';

/// 一台 ComfyUI:本机的或云端的。
typedef ComfyServer = ({String id, String name, String url});

/// 导入的一个「导出 (API)」工作流。
typedef ComfyFlow = ({String id, String name, String text});

/// 一个 LoRA 在一套配置里的样子。
typedef LoraSetting = ({String name, double strength, bool on});

/// 存下来的一套 LoRA 配置;[server]、[flow] 是它属于哪台 ComfyUI 的哪个工作流
/// (各台的 LoRA 文件不同,各工作流的配置也互不相干)。
typedef LoraPreset = ({
  String server,
  String flow,
  String name,
  List<LoraSetting> loras,
});

/// [ComfySettings.loraPresetOf] 的键:哪台的哪个工作流。
String loraPresetKey(String server, String flow) => '$server|$flow';

/// 侧栏「画面大小」里存下的常用尺寸,新装时是这几个(SDXL 一类按一百万像素左右排的)。
const comfyDefaultSizes = <({int width, int height})>[
  (width: 1024, height: 1024),
  (width: 896, height: 1152),
  (width: 832, height: 1216),
  (width: 768, height: 1344),
  (width: 1152, height: 896),
  (width: 1216, height: 832),
  (width: 1344, height: 768),
];

/// 把 [list] 里第 [from] 个挪到第 [to] 个的位置(拖动排序用,[to] 是挪完之后的位置)。
List<T> moved<T>(List<T> list, int from, int to) {
  final out = [...list];
  final item = out.removeAt(from);
  out.insert(to.clamp(0, out.length), item);
  return out;
}

/// Agent 出图的画面方向:[orientationKeep] 照工作流里写的大小(一直以来的做法);
/// [orientationAuto] 让 Agent 按每张图的内容定横、竖或方;
/// [orientationLandscape]、[orientationPortrait] 只出横图、只出竖图。
const orientationKeep = 'keep';
const orientationAuto = 'auto';
const orientationLandscape = 'landscape';
const orientationPortrait = 'portrait';
const orientations = [
  orientationKeep,
  orientationAuto,
  orientationLandscape,
  orientationPortrait,
];

/// 把 [width]×[height] 摆成 [orientation] 要的方向(只出横图、只出竖图时对调宽高);
/// 方向已经对、或没限定方向时返回 null(不用动)。
({int width, int height})? orientedSize(
  String orientation,
  int width,
  int height,
) {
  final swap =
      orientation == orientationLandscape && height > width ||
      orientation == orientationPortrait && width > height;
  return swap ? (width: height, height: width) : null;
}

/// 「设置 → ComfyUI」:有哪几台 ComfyUI、哪几个工作流、存好的 LoRA 配置,出的图放哪。
@immutable
class ComfySettings {
  const ComfySettings({
    this.servers = const [(id: comfyLocalId, name: '本机', url: comfyDefaultUrl)],
    this.serverId = comfyLocalId,
    this.flows = const [],
    this.flowId = builtinWorkflowId,
    this.loraPresets = const [],
    this.loraPresetOf = const {},
    this.inputs = const {},
    this.imageDir = '',
    this.autoGenerate = true,
    this.orientation = orientationKeep,
    this.outputDirs = const {},
    this.sizes = comfyDefaultSizes,
    this.loraTexts = const {},
    this.loraOff = const {},
    this.loraOrder = const {},
  });

  /// 读设置。旧版只有一个地址(`url`)和一个工作流(`workflow`、`workflowName`),照样读成列表;
  /// 旧版的 LoRA 配置不分工作流,每个工作流各拿一份;不分服务器的算本机那台的
  /// (没有本机那台就算第一台)。
  factory ComfySettings.fromJson(Object? json) {
    final m = json is Map ? json : const {};
    final servers = <ComfyServer>[
      for (final s in m['servers'] as List? ?? const [])
        if (s is Map && s['id'] is String)
          (
            id: s['id'] as String,
            name: s['name'] as String? ?? '',
            url: s['url'] as String? ?? comfyDefaultUrl,
          ),
    ];
    final flows = <ComfyFlow>[
      for (final f in m['flows'] as List? ?? const [])
        if (f is Map && f['id'] is String && f['text'] is String)
          (
            id: f['id'] as String,
            name: f['name'] as String? ?? '',
            text: f['text'] as String,
          ),
    ];
    final oldFlow = m['workflow'] as String? ?? '';
    if (flows.isEmpty && oldFlow.trim().isNotEmpty) {
      flows.add((
        id: 'imported',
        name: m['workflowName'] as String? ?? '',
        text: oldFlow,
      ));
    }
    final flowId =
        m['flowId'] as String? ??
        (oldFlow.trim().isNotEmpty ? 'imported' : builtinWorkflowId);
    final flowIds = flows.isEmpty
        ? const [builtinWorkflowId]
        : [for (final f in flows) f.id];
    final current = flowIds.contains(flowId) ? flowId : flowIds.first;
    final legacy = servers.isEmpty || servers.any((s) => s.id == comfyLocalId)
        ? comfyLocalId
        : servers.first.id;
    return ComfySettings(
      servers: servers.isNotEmpty
          ? List.unmodifiable(servers)
          : [
              (
                id: comfyLocalId,
                name: '本机',
                url: m['url'] as String? ?? comfyDefaultUrl,
              ),
            ],
      serverId:
          m['serverId'] as String? ??
          (servers.isEmpty ? comfyLocalId : servers.first.id),
      flows: List.unmodifiable(flows),
      flowId: flowId,
      loraPresets: List.unmodifiable([
        for (final p in m['loraPresets'] as List? ?? const [])
          if (p is Map && p['name'] is String)
            for (final flow
                in p['flow'] is String ? [p['flow'] as String] : flowIds)
              (
                server: p['server'] as String? ?? legacy,
                flow: flow,
                name: p['name'] as String,
                loras: List<LoraSetting>.unmodifiable([
                  for (final l in p['loras'] as List? ?? const [])
                    if (l is Map && l['name'] is String)
                      (
                        name: l['name'] as String,
                        strength: (l['strength'] as num? ?? 1).toDouble(),
                        on: l['on'] != false,
                      ),
                ]),
              ),
      ]),
      loraPresetOf: Map.unmodifiable(switch (m['loraPresetOf']) {
        final Map of => {
          for (final MapEntry(:key, :value) in of.entries)
            if (key is String && value is String)
              key.contains('|') ? key : loraPresetKey(legacy, key): value,
        },
        // 旧版只记一个名字:算眼前那个工作流的。
        _ => {
          if (m['loraPreset'] case final String name when name.isNotEmpty)
            loraPresetKey(legacy, current): name,
        },
      }),
      inputs: Map.unmodifiable({
        if (m['inputs'] case final Map all)
          for (final MapEntry(key: flow, value: files) in all.entries)
            if (flow is String && files is Map)
              flow: Map<String, String>.unmodifiable({
                for (final MapEntry(:key, :value) in files.entries)
                  if (key is String && value is String) key: value,
              }),
      }),
      imageDir: m['imageDir'] as String? ?? '',
      autoGenerate: m['autoGenerate'] as bool? ?? true,
      orientation: orientations.contains(m['orientation'])
          ? m['orientation'] as String
          : orientationKeep,
      outputDirs: Map.unmodifiable({
        if (m['outputDirs'] case final Map dirs)
          for (final MapEntry(:key, :value) in dirs.entries)
            if (key is String && value is String && value.isNotEmpty)
              key: value,
      }),
      sizes: m['sizes'] is List
          ? List.unmodifiable([
              for (final v in m['sizes'] as List)
                if (v is List && v.length == 2 && v[0] is int && v[1] is int)
                  (width: v[0] as int, height: v[1] as int),
            ])
          : comfyDefaultSizes,
      loraTexts: Map.unmodifiable({
        if (m['loraTexts'] case final Map texts)
          for (final MapEntry(:key, :value) in texts.entries)
            if (key is String && value is String) key: value,
      }),
      loraOff: Map.unmodifiable({
        if (m['loraOff'] case final Map off)
          for (final MapEntry(:key, :value) in off.entries)
            if (key is String && value is List)
              key: List<LoraSetting>.unmodifiable([
                for (final l in value)
                  if (l is Map && l['name'] is String)
                    (
                      name: l['name'] as String,
                      strength: (l['strength'] as num? ?? 1).toDouble(),
                      on: false,
                    ),
              ]),
      }),
      loraOrder: Map.unmodifiable({
        if (m['loraOrder'] case final Map orderMap)
          for (final MapEntry(:key, :value) in orderMap.entries)
            if (key is String && value is List)
              key: List<String>.unmodifiable([for (final n in value) '$n']),
      }),
    );
  }

  final List<ComfyServer> servers;

  /// 眼前用的那一台。
  final String serverId;

  final List<ComfyFlow> flows;

  /// 眼前用的工作流;[builtinWorkflowId] 是内置文生图。
  final String flowId;

  /// 所有工作流的 LoRA 配置,同一台同一个工作流的按显示的先后排。
  final List<LoraPreset> loraPresets;

  /// 各台各工作流眼前用的那套 LoRA 配置的名字(键见 [loraPresetKey]);没有是没用哪一套。
  final Map<String, String> loraPresetOf;

  /// 各工作流要上传的文件(按工作流 id):节点编号 → 本机文件路径。
  /// 出图前传到 ComfyUI,填进那个加载图片 / 视频 / 音频的节点。
  final Map<String, Map<String, String>> inputs;

  /// 出的图存在哪;空的是「文档\Penna\images」。
  final String imageDir;

  /// Agent 写了出图标签就直接出;关掉时回复下面出一个「出图」按钮,用户点了才出。
  final bool autoGenerate;

  /// Agent 出图时画面是横是竖,见 [orientations]。
  final String orientation;

  /// 各台 ComfyUI 的输出文件夹(按服务器 id;档案库「图片」分区读它)。
  /// 没填的本机 ComfyUI 照它的启动参数自己找。
  final Map<String, String> outputDirs;

  /// 侧栏「画面大小」里存下的常用尺寸(各工作流共用)。
  final List<({int width, int height})> sizes;

  /// 最多存几个常用尺寸。
  static const maxSizes = 12;

  /// 每个工作流的 LoRA 语法(按工作流 id)。
  /// 工作流里那个写着 `{{lora}}` 的框，出图时会被替换成这段文字。
  final Map<String, String> loraTexts;

  /// 每个工作流里「关掉」的 LoRA(按工作流 id)。关掉的不在语法里，但记着名字和权重，
  /// 下次点开关能原样加回去。
  final Map<String, List<LoraSetting>> loraOff;

  /// 每个工作流的展示顺序(按工作流 id，存比较键)。关掉的行也留在原来的位置。
  final Map<String, List<String>> loraOrder;

  /// 工作流 [id] 存的 LoRA 语法;没存过是空串。
  String loraTextOf(String id) => loraTexts[id] ?? '';

  /// 工作流 [id] 里关掉的 LoRA。
  List<LoraSetting> loraOffOf(String id) => loraOff[id] ?? const [];

  /// 工作流 [id] 的展示顺序。
  List<String> loraOrderOf(String id) => loraOrder[id] ?? const [];

  /// 眼前那一台(id 对不上时用第一台)。
  ComfyServer get server =>
      servers.where((s) => s.id == serverId).firstOrNull ?? servers.first;

  /// 眼前的工作流;id 对不上时用第一个。一个都没导入时是 null(用内置文生图)。
  ComfyFlow? get flow =>
      flows.where((f) => f.id == flowId).firstOrNull ?? flows.firstOrNull;

  /// [server] 那台 [flow] 那个工作流的 LoRA 配置,按显示的先后。
  List<LoraPreset> presetsOf(String server, String flow) => [
    for (final p in loraPresets)
      if (p.server == server && p.flow == flow) p,
  ];

  Map<String, Object?> toJson() => {
    'servers': [
      for (final s in servers) {'id': s.id, 'name': s.name, 'url': s.url},
    ],
    'serverId': serverId,
    'flows': [
      for (final f in flows) {'id': f.id, 'name': f.name, 'text': f.text},
    ],
    'flowId': flowId,
    'loraPresets': [
      for (final p in loraPresets)
        {
          'server': p.server,
          'flow': p.flow,
          'name': p.name,
          'loras': [
            for (final l in p.loras)
              {'name': l.name, 'strength': l.strength, 'on': l.on},
          ],
        },
    ],
    'loraPresetOf': loraPresetOf,
    if (inputs.isNotEmpty) 'inputs': inputs,
    'imageDir': imageDir,
    'autoGenerate': autoGenerate,
    'orientation': orientation,
    if (outputDirs.isNotEmpty) 'outputDirs': outputDirs,
    'sizes': [
      for (final s in sizes) [s.width, s.height],
    ],
    if (loraTexts.isNotEmpty) 'loraTexts': loraTexts,
    if (loraOff.isNotEmpty)
      'loraOff': {
        for (final MapEntry(:key, :value) in loraOff.entries)
          key: [
            for (final l in value) {'name': l.name, 'strength': l.strength},
          ],
      },
    if (loraOrder.isNotEmpty) 'loraOrder': loraOrder,
  };

  ComfySettings copyWith({
    List<ComfyServer>? servers,
    String? serverId,
    List<ComfyFlow>? flows,
    String? flowId,
    List<LoraPreset>? loraPresets,
    Map<String, String>? loraPresetOf,
    Map<String, Map<String, String>>? inputs,
    String? imageDir,
    bool? autoGenerate,
    String? orientation,
    Map<String, String>? outputDirs,
    List<({int width, int height})>? sizes,
    Map<String, String>? loraTexts,
    Map<String, List<LoraSetting>>? loraOff,
    Map<String, List<String>>? loraOrder,
  }) => ComfySettings(
    servers: servers == null ? this.servers : List.unmodifiable(servers),
    serverId: serverId ?? this.serverId,
    flows: flows == null ? this.flows : List.unmodifiable(flows),
    flowId: flowId ?? this.flowId,
    loraPresets: loraPresets == null
        ? this.loraPresets
        : List.unmodifiable(loraPresets),
    loraPresetOf: loraPresetOf == null
        ? this.loraPresetOf
        : Map.unmodifiable(loraPresetOf),
    inputs: inputs == null ? this.inputs : Map.unmodifiable(inputs),
    imageDir: imageDir ?? this.imageDir,
    autoGenerate: autoGenerate ?? this.autoGenerate,
    orientation: orientation ?? this.orientation,
    outputDirs: outputDirs == null
        ? this.outputDirs
        : Map.unmodifiable(outputDirs),
    sizes: sizes == null ? this.sizes : List.unmodifiable(sizes),
    loraTexts: loraTexts == null ? this.loraTexts : Map.unmodifiable(loraTexts),
    loraOff: loraOff == null ? this.loraOff : Map.unmodifiable(loraOff),
    loraOrder: loraOrder == null ? this.loraOrder : Map.unmodifiable(loraOrder),
  );

  /// 记下工作流 [flowId] 里关掉的 LoRA。
  ComfySettings putLoraOff(String flowId, List<LoraSetting> loras) {
    final next = {...loraOff};
    if (loras.isEmpty) {
      next.remove(flowId);
    } else {
      next[flowId] = List.unmodifiable(loras);
    }
    return copyWith(loraOff: next);
  }

  /// 记下工作流 [flowId] 的展示顺序。
  ComfySettings putLoraOrder(String flowId, List<String> keys) {
    final next = {...loraOrder};
    if (keys.isEmpty) {
      next.remove(flowId);
    } else {
      next[flowId] = List.unmodifiable(keys);
    }
    return copyWith(loraOrder: next);
  }

  /// 存一个工作流的 LoRA 语法;空串表示不存(回到没设置的样子)。
  ComfySettings putLoraText(String flowId, String text) {
    final next = {...loraTexts};
    if (text.trim().isEmpty) {
      next.remove(flowId);
    } else {
      next[flowId] = text.trim();
    }
    return copyWith(loraTexts: next);
  }

  /// 新增或替换一台(按 id)。
  ComfySettings putServer(ComfyServer server) => copyWith(
    servers: servers.any((s) => s.id == server.id)
        ? [for (final s in servers) s.id == server.id ? server : s]
        : [...servers, server],
  );

  /// 删掉一台;至少留一台。删的是眼前那台就换到第一台。
  ComfySettings removeServer(String id) {
    final rest = [
      for (final s in servers)
        if (s.id != id) s,
    ];
    if (rest.isEmpty) return this;
    return copyWith(
      servers: rest,
      serverId: serverId == id ? rest.first.id : serverId,
      loraPresets: [
        for (final p in loraPresets)
          if (p.server != id) p,
      ],
      loraPresetOf: {
        for (final MapEntry(:key, :value) in loraPresetOf.entries)
          if (!key.startsWith('$id|')) key: value,
      },
    );
  }

  /// 新增或替换一个工作流(按 id)。
  ComfySettings putFlow(ComfyFlow flow) => copyWith(
    flows: flows.any((f) => f.id == flow.id)
        ? [for (final f in flows) f.id == flow.id ? flow : f]
        : [...flows, flow],
  );

  /// 删掉一个工作流(连同它的 LoRA 配置和要上传的文件);
  /// 删的是眼前那个就换到剩下的第一个(都删了用内置文生图)。
  ComfySettings removeFlow(String id) {
    final rest = [
      for (final f in flows)
        if (f.id != id) f,
    ];
    return copyWith(
      flows: rest,
      flowId: flowId == id ? rest.firstOrNull?.id ?? builtinWorkflowId : flowId,
      loraPresets: [
        for (final p in loraPresets)
          if (p.flow != id) p,
      ],
      loraPresetOf: {
        for (final MapEntry(:key, :value) in loraPresetOf.entries)
          if (!key.endsWith('|$id')) key: value,
      },
      inputs: {...inputs}..remove(id),
    );
  }

  /// 复制一个工作流,放在它下面:全文、LoRA 配置、要上传的文件都跟着复制。
  ComfySettings copyFlow(
    String id, {
    required String newId,
    required String name,
  }) {
    final i = flows.indexWhere((f) => f.id == id);
    if (i < 0) return this;
    return copyWith(
      flows: [...flows]
        ..insert(i + 1, (id: newId, name: name, text: flows[i].text)),
      loraPresets: [
        ...loraPresets,
        for (final p in loraPresets)
          if (p.flow == id)
            (server: p.server, flow: newId, name: p.name, loras: p.loras),
      ],
      loraPresetOf: {
        ...loraPresetOf,
        for (final MapEntry(:key, :value) in loraPresetOf.entries)
          if (key.endsWith('|$id'))
            '${key.substring(0, key.length - id.length)}$newId': value,
      },
      inputs: {...inputs, newId: ?inputs[id]},
    );
  }

  /// 拖动工作流换顺序。
  ComfySettings moveFlow(int from, int to) =>
      copyWith(flows: moved(flows, from, to));

  /// 存一套 LoRA 配置;同一台同一个工作流里同名的换掉。
  ComfySettings putLoraPreset(LoraPreset preset) {
    bool same(LoraPreset p) =>
        p.server == preset.server &&
        p.flow == preset.flow &&
        p.name == preset.name;
    return copyWith(
      loraPresets: loraPresets.any(same)
          ? [for (final p in loraPresets) same(p) ? preset : p]
          : [...loraPresets, preset],
    );
  }

  ComfySettings removeLoraPreset(String server, String flow, String name) {
    final key = loraPresetKey(server, flow);
    return copyWith(
      loraPresets: [
        for (final p in loraPresets)
          if (p.server != server || p.flow != flow || p.name != name) p,
      ],
      loraPresetOf: loraPresetOf[key] == name
          ? ({...loraPresetOf}..remove(key))
          : null,
    );
  }

  /// 拖动 [server] 那台 [flow] 那个工作流的 LoRA 配置换顺序
  /// ([from]、[to] 是它自己那几套里的位置)。
  ComfySettings moveLoraPreset(String server, String flow, int from, int to) {
    final own = moved(presetsOf(server, flow), from, to);
    return copyWith(
      loraPresets: [
        for (final p in loraPresets)
          if (p.server != server || p.flow != flow) p,
        ...own,
      ],
    );
  }

  /// [flow] 那个工作流的 [node] 要上传的文件换成 [path](null 是不传,用工作流里原来写的)。
  ComfySettings putInput(String flow, String node, String? path) {
    final files = {...?inputs[flow]};
    path == null ? files.remove(node) : files[node] = path;
    return copyWith(inputs: {...inputs, flow: Map.unmodifiable(files)});
  }
}
