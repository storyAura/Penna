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

/// 存下来的一套 LoRA 配置。
typedef LoraPreset = ({String name, List<LoraSetting> loras});

/// 「设置 → ComfyUI」:有哪几台 ComfyUI、哪几个工作流、存好的 LoRA 配置,出的图放哪。
@immutable
class ComfySettings {
  const ComfySettings({
    this.servers = const [(id: comfyLocalId, name: '本机', url: comfyDefaultUrl)],
    this.serverId = comfyLocalId,
    this.flows = const [],
    this.flowId = builtinWorkflowId,
    this.loraPresets = const [],
    this.imageDir = '',
    this.autoGenerate = true,
  });

  /// 读设置。旧版只有一个地址(`url`)和一个工作流(`workflow`、`workflowName`),照样读成列表。
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
      flowId:
          m['flowId'] as String? ??
          (oldFlow.trim().isNotEmpty ? 'imported' : builtinWorkflowId),
      loraPresets: List.unmodifiable([
        for (final p in m['loraPresets'] as List? ?? const [])
          if (p is Map && p['name'] is String)
            (
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
      imageDir: m['imageDir'] as String? ?? '',
      autoGenerate: m['autoGenerate'] as bool? ?? true,
    );
  }

  final List<ComfyServer> servers;

  /// 眼前用的那一台。
  final String serverId;

  final List<ComfyFlow> flows;

  /// 眼前用的工作流;[builtinWorkflowId] 是内置文生图。
  final String flowId;

  final List<LoraPreset> loraPresets;

  /// 出的图存在哪;空的是「文档\Penna\images」。
  final String imageDir;

  /// Agent 写了出图标签就直接出;关掉时回复下面出一个「出图」按钮,用户点了才出。
  final bool autoGenerate;

  /// 眼前那一台(id 对不上时用第一台)。
  ComfyServer get server =>
      servers.where((s) => s.id == serverId).firstOrNull ?? servers.first;

  /// 眼前的工作流;id 对不上时用第一个。一个都没导入时是 null(用内置文生图)。
  ComfyFlow? get flow =>
      flows.where((f) => f.id == flowId).firstOrNull ?? flows.firstOrNull;

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
          'name': p.name,
          'loras': [
            for (final l in p.loras)
              {'name': l.name, 'strength': l.strength, 'on': l.on},
          ],
        },
    ],
    'imageDir': imageDir,
    'autoGenerate': autoGenerate,
  };

  ComfySettings copyWith({
    List<ComfyServer>? servers,
    String? serverId,
    List<ComfyFlow>? flows,
    String? flowId,
    List<LoraPreset>? loraPresets,
    String? imageDir,
    bool? autoGenerate,
  }) => ComfySettings(
    servers: servers == null ? this.servers : List.unmodifiable(servers),
    serverId: serverId ?? this.serverId,
    flows: flows == null ? this.flows : List.unmodifiable(flows),
    flowId: flowId ?? this.flowId,
    loraPresets: loraPresets == null
        ? this.loraPresets
        : List.unmodifiable(loraPresets),
    imageDir: imageDir ?? this.imageDir,
    autoGenerate: autoGenerate ?? this.autoGenerate,
  );

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
    );
  }

  /// 新增或替换一个工作流(按 id)。
  ComfySettings putFlow(ComfyFlow flow) => copyWith(
    flows: flows.any((f) => f.id == flow.id)
        ? [for (final f in flows) f.id == flow.id ? flow : f]
        : [...flows, flow],
  );

  /// 删掉一个工作流;删的是眼前那个就换到剩下的第一个(都删了用内置文生图)。
  ComfySettings removeFlow(String id) {
    final rest = [
      for (final f in flows)
        if (f.id != id) f,
    ];
    return copyWith(
      flows: rest,
      flowId: flowId == id ? rest.firstOrNull?.id ?? builtinWorkflowId : flowId,
    );
  }

  /// 存一套 LoRA 配置;同名的换掉。
  ComfySettings putLoraPreset(LoraPreset preset) => copyWith(
    loraPresets: loraPresets.any((p) => p.name == preset.name)
        ? [for (final p in loraPresets) p.name == preset.name ? preset : p]
        : [...loraPresets, preset],
  );

  ComfySettings removeLoraPreset(String name) => copyWith(
    loraPresets: [
      for (final p in loraPresets)
        if (p.name != name) p,
    ],
  );
}
