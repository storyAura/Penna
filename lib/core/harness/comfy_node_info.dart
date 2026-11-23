part of 'comfyui.dart';

/// 一台 ComfyUI 认得的节点:节点类型 → 下拉输入的名字 → 能选的值
/// (从 `/object_info` 精简来的,只留下拉;模型、LoRA、采样器的名单都在里面)。
typedef ComfyNodeInfo = Map<String, Map<String, List<String>>>;

/// 下拉输入能选的值:老写法 `[[名字…], {…}]`,新写法 `["COMBO", {options: [名字…]}]`。
/// 不是下拉是 null。
List<String>? _comboOf(Object? spec) {
  if (spec is! List || spec.isEmpty) return null;
  final names = spec[0] is List
      ? spec[0] as List
      : spec.length > 1 && spec[1] is Map
      ? (spec[1] as Map)['options']
      : null;
  // 动态下拉(COMFY_DYNAMICCOMBO_V3,SaveVideo 的 format)的选项是 {key, inputs}。
  return names is List
      ? [for (final n in names) n is Map ? '${n['key']}' : '$n']
      : null;
}

/// 读 `/object_info` 的结果(几 MB,在 isolate 里读)。
ComfyNodeInfo parseNodeInfo(Object? json) => {
  if (json is Map)
    for (final MapEntry(:key, :value) in json.entries)
      if (value is Map)
        '$key': {
          for (final group in const ['required', 'optional'])
            if ((value['input'] as Map?)?[group] case final Map inputs)
              for (final MapEntry(key: name, value: spec) in inputs.entries)
                '$name': ?_comboOf(spec),
        },
};

/// 文件名里的文件夹分隔统一成 `/`:Windows 上的 ComfyUI 写 `a\b.safetensors`,
/// Linux 上的写 `a/b.safetensors`。
String _slash(String name) => name.replaceAll('\\', '/');

/// 文件名(去掉文件夹)。
String _base(String name) => _slash(name).split('/').last;

/// [value] 在这台的 [options] 里叫什么:一字不差的、只差在文件夹分隔上的,
/// 或者文件夹不同、但这台只有一个同名文件的(本机放在 `Moss-base\`、云端放在 `MossImage/`)。
/// 都对不上是 null。
String? serverName(String value, List<String> options) {
  if (options.contains(value)) return value;
  final want = _slash(value);
  for (final o in options) {
    if (_slash(o) == want) return o;
  }
  final same = [
    for (final o in options)
      if (_base(o) == _base(value)) o,
  ];
  return same.length == 1 ? same.single : null;
}

/// 这台 ComfyUI 能选的 LoRA 文件。
List<String> loraNamesOf(ComfyNodeInfo info) =>
    info['LoraLoaderModelOnly']?['lora_name'] ??
    info['LoraLoader']?['lora_name'] ??
    const [];

/// [wf] 在这台 ComfyUI([info])上缺什么:没装的节点、下拉里没有的值(模型、LoRA 这类文件)。
/// 要上传的素材格子不算(出图时传上去);能对上的(见 [serverName])不算缺,出图时换成它的写法。
List<String> workflowProblems(Map<String, Object?> wf, ComfyNodeInfo info) {
  if (info.isEmpty) return const [];
  final uploads = {for (final s in uploadSlots(wf)) '${s.node}/${s.key}'};
  final loras = loraNamesOf(info);
  final out = <String>{};
  for (final MapEntry(key: id, value: node) in wf.entries) {
    if (node is! Map) continue;
    final type = '${node['class_type']}';
    final known = info[type];
    if (known == null) {
      out.add(tr('缺节点 {0}', [type]));
      continue;
    }
    for (final MapEntry(:key, :value) in _inputs(node).entries) {
      if (uploads.contains('$id/$key')) continue;
      // rgthree Power Lora Loader:{on, lora, strength}。
      if (value is Map && value['lora'] is String) {
        final name = value['lora'] as String;
        // 关着的不加载,不算缺。
        if (loras.isNotEmpty &&
            value['on'] != false &&
            name != 'None' &&
            serverName(name, loras) == null) {
          out.add(tr('缺 {0}', [name]));
        }
        continue;
      }
      final options = known[key];
      if (value is! String || options == null || options.isEmpty) continue;
      if (serverName(value, options) == null) {
        out.add(tr('缺 {0}', [value]));
      }
    }
  }
  return out.toList();
}

/// 下拉的值换成这台 ComfyUI 的写法(见 [serverName]),不改原来的。
/// 在 Windows 上做的工作流交给 Linux 云端时,模型名对不上就跑不了。
Map<String, Object?> adaptToServer(
  Map<String, Object?> wf,
  ComfyNodeInfo info,
) {
  if (info.isEmpty) return wf;
  final out = jsonDecode(jsonEncode(wf)) as Map<String, Object?>;
  final loras = loraNamesOf(info);
  for (final node in out.values) {
    if (node is! Map) continue;
    final known = info['${node['class_type']}'];
    if (known == null) continue;
    final inputs = _inputs(node);
    for (final MapEntry(:key, :value) in inputs.entries.toList()) {
      if (value is Map && value['lora'] is String) {
        final own = serverName(value['lora'] as String, loras);
        if (own != null) value['lora'] = own;
        continue;
      }
      if (value is! String) continue;
      final own = serverName(value, known[key] ?? const []);
      if (own != null) inputs[key] = own;
    }
  }
  return out;
}
