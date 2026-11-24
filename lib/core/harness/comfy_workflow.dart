import 'dart:convert';
import 'dart:math' as math;

import '../../l10n/l10n.dart';
import 'comfyui.dart';

// 读、改「导出 (API)」格式的工作流:模型加载器、各种 LoRA 加载器。都返回新的一份,不改原来的。
//
// LoRA 加载器的写法各家不同,按输入的样子认,不按节点名认:
// - 一个输入的值是 {on, lora, strength(, strengthTwo)}:rgthree 的 Power Lora Loader(lora_1、lora_2…);
// - 名字里带 lora、值是文件名的输入(lora_name、lora_name_1、lora_01…):官方 LoraLoader /
//   LoraLoaderModelOnly、pysssss、Nunchaku、rgthree Lora Loader Stack、Efficiency LoRA Stacker、
//   CR LoRA Stack 等。同一个尾号的数字输入里名字带 strength / weight / wt / str 的是权重,
//   带 switch / on / enable 的是开关(CR LoRA Stack 的 "On" / "Off")。
// 值是 None 的槽位是空的,不列出来。

/// 「导出 (API)」格式的工作流:节点编号 → 节点。
typedef ComfyWorkflow = Map<String, Object?>;

/// 工作流里的一个模型加载器:哪个节点的哪个输入,现在是什么。
typedef ModelSlot = ({String node, String type, String key, String value});

/// 工作流里的一个 LoRA:[key] 是它在节点里的输入名(Power Lora Loader 是 lora_1 这种)。
/// [canToggle] 为假的没有开关,停用只能把权重调成 0。
typedef LoraSlot = ({
  String node,
  String type,
  String key,
  String name,
  double strength,
  bool on,
  bool canToggle,
});

/// 加 LoRA 时新插的节点。
const _addedLoraType = 'LoraLoaderModelOnly';

const _modelKeys = ['ckpt_name', 'unet_name'];
final _strengthKey = RegExp('strength|weight|wt|str', caseSensitive: false);
final _switchKey = RegExp(
  r'^(switch|on|enabled?|toggle)',
  caseSensitive: false,
);
final _modelFile = RegExp(
  r'\.(safetensors|ckpt|pt|pth|bin|gguf|sft)$',
  caseSensitive: false,
);

ComfyWorkflow _copy(ComfyWorkflow wf) =>
    jsonDecode(jsonEncode(wf)) as ComfyWorkflow;

int _byId(String a, String b) {
  final x = int.tryParse(a), y = int.tryParse(b);
  return x != null && y != null ? x.compareTo(y) : a.compareTo(b);
}

Iterable<(String, String, Map<String, Object?>)> _nodes(
  ComfyWorkflow wf,
) sync* {
  for (final id in wf.keys.toList()..sort(_byId)) {
    final node = wf[id];
    if (node is! Map) continue;
    final inputs = node['inputs'];
    yield (
      id,
      '${node['class_type']}',
      inputs is Map ? inputs.cast<String, Object?>() : <String, Object?>{},
    );
  }
}

/// 输入名最后的数字(lora_name_1 → 1,lora_01 → 01),没有是空串。
String _tail(String key) => RegExp(r'\d+$').stringMatch(key) ?? '';

/// 文本里的一条 LoRA 标签,例如 `<lora:moss/tool/lora_dmd2:0.75>`;
/// 不写权重时按 1 算(Lora Manager 这类节点用一整串文本装好几个 LoRA)。
final _loraTag = RegExp(r'<lora:([^:>]+)(?::([-+]?\d*\.?\d+))?>');

/// 写回文本时用的权重写法:0.75 还是 0.75,0.5 写成 0.5(不带尾零),1 写成 1。
String _strengthText(double v) {
  var text = v.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  return text;
}

/// 把一个文本里名为 [name] 的那条 LoRA 标签改成 [strength];[off] 为真时删掉它。
/// 别的标签、别的文字原样留着。
String _rewriteLoraTags(
  String text,
  String name, {
  double? strength,
  bool off = false,
}) {
  final out = text.replaceAllMapped(_loraTag, (m) {
    if (m.group(1)!.trim() != name.trim()) return m.group(0)!;
    if (off) return '';
    final s =
        strength ?? double.tryParse(m.group(2) ?? '') ?? 1;
    return '<lora:${m.group(1)}:${_strengthText(s)}>';
  });
  // 删掉一条之后别留下两个空格。
  return out.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}

/// 模型加载器(ckpt_name、unet_name)。
List<ModelSlot> modelSlots(ComfyWorkflow wf) => [
  for (final (id, type, inputs) in _nodes(wf))
    for (final key in _modelKeys)
      if (inputs[key] case final String value)
        (node: id, type: type, key: key, value: value),
];

final _fileKey = RegExp(r'^(ckpt_name|unet_name|clip_name\d*|vae_name)$');

/// 侧栏能换的模型文件(2026-11-23 用户要求开放):大模型(ckpt / unet)、
/// 文本编码器(clip_name、clip_name1…)、VAE,按节点编号排。
List<ModelSlot> fileSlots(ComfyWorkflow wf) => [
  for (final (id, type, inputs) in _nodes(wf))
    for (final key in inputs.keys)
      if (_fileKey.hasMatch(key) && inputs[key] is String)
        (node: id, type: type, key: key, value: inputs[key] as String),
];

/// 时长:标了 `Penna.Duration`(或节点标题就叫「时长」/ Duration)的数值节点,单位是秒;
/// 没有时是画面大小节点上没接线的 `length`(帧数)。都没有是 null。
({String node, String key, num value, bool frames})? durationSlot(
  ComfyWorkflow wf,
) {
  for (final (id, _, inputs) in _nodes(wf)) {
    final title = '${((wf[id] as Map)['_meta'] as Map?)?['title'] ?? ''}';
    final named =
        title.startsWith('Penna.Duration') ||
        const {'时长', 'duration'}.contains(title.trim().toLowerCase());
    if (inputs['value'] case final num v when named) {
      return (node: id, key: 'value', value: v, frames: false);
    }
  }
  for (final id in latentNodeIds(wf)) {
    if (_inputsOf(wf, id)['length'] case final num v) {
      return (node: id, key: 'length', value: v, frames: true);
    }
  }
  return null;
}

bool _isNested(Object? v) => v is Map && v['lora'] is String;

bool _isFlatName(String key, Object? v) =>
    v is String &&
    key.toLowerCase().contains('lora') &&
    (_modelFile.hasMatch(v) || v.contains('/') || v.contains(r'\'));

/// 同一个尾号的权重输入。
List<String> _strengthKeysFor(String key, Map<String, Object?> inputs) => [
  for (final k in inputs.keys)
    if (k != key &&
        inputs[k] is num &&
        _strengthKey.hasMatch(k) &&
        _tail(k) == _tail(key))
      k,
];

String? _switchKeyFor(String key, Map<String, Object?> inputs) {
  for (final k in inputs.keys) {
    final v = inputs[k];
    if (_switchKey.hasMatch(k) &&
        _tail(k) == _tail(key) &&
        (v is bool || v == 'On' || v == 'Off')) {
      return k;
    }
  }
  return null;
}

/// 权重有好几个(模型、CLIP)时显示哪一个:带 model 的,或者叫 strength 的。
double _mainStrength(List<String> keys, Map<String, Object?> inputs) {
  if (keys.isEmpty) return 1;
  final main = keys.firstWhere(
    (k) => k.toLowerCase().contains('model'),
    orElse: () => keys.first,
  );
  return (inputs[main] as num).toDouble();
}

/// 工作流里的全部 LoRA,按节点编号排。
List<LoraSlot> loraSlots(ComfyWorkflow wf) => [
  for (final (id, type, inputs) in _nodes(wf))
    if (type.toLowerCase().contains('lora'))
      for (final key in inputs.keys)
        if (inputs[key] case final Map v when _isNested(v)) ...[
          if ('${v['lora']}' != 'None' && '${v['lora']}'.isNotEmpty)
            (
              node: id,
              type: type,
              key: key,
              name: '${v['lora']}',
              strength: (v['strength'] as num? ?? 1).toDouble(),
              on: v['on'] != false,
              canToggle: true,
            ),
        ] else if (_isFlatName(key, inputs[key]))
          (
            node: id,
            type: type,
            key: key,
            name: inputs[key] as String,
            strength: _mainStrength(_strengthKeysFor(key, inputs), inputs),
            on: switch (_switchKeyFor(key, inputs)) {
              final k? => inputs[k] == true || inputs[k] == 'On',
              null => true,
            },
            canToggle: _switchKeyFor(key, inputs) != null,
          ),
  // 用一整串文本装 LoRA 的节点(Lora Manager 的「LoRA Text Loader」等):
  // 不按节点名认,只要输入里有 <lora:名字:权重> 就算,一条标签一个 LoRA。
  for (final (id, type, inputs) in _nodes(wf))
    for (final key in inputs.keys)
      if (inputs[key] case final String text when _loraTag.hasMatch(text))
        for (final m in _loraTag.allMatches(text))
          (
            node: id,
            type: type,
            key: key,
            name: m.group(1)!.trim(),
            strength: double.tryParse(m.group(2) ?? '') ?? 1,
            on: true,
            canToggle: false,
          ),
];

Map<String, Object?> _inputsOf(ComfyWorkflow wf, String node) {
  final n = wf[node];
  if (n is! Map || n['inputs'] is! Map) {
    throw ComfyException(tr('工作流里没有这个节点了'));
  }
  return (n['inputs'] as Map).cast<String, Object?>();
}

/// 换模型:[node] 那个加载器的 [key] 改成 [value]。
ComfyWorkflow setModel(
  ComfyWorkflow wf,
  String node,
  String key,
  String value,
) {
  final out = _copy(wf);
  _inputsOf(out, node)[key] = value;
  return out;
}

/// 改 [node] 的一个输入(模型名、采样器参数)。
ComfyWorkflow setInput(
  ComfyWorkflow wf,
  String node,
  String key,
  Object value,
) {
  final out = _copy(wf);
  _inputsOf(out, node)[key] = value;
  return out;
}

/// 画面大小(Latent):第一个空白画布节点的宽高;没有是 null。
ComfySize? latentSize(ComfyWorkflow wf) {
  final id = latentNodeIds(wf).firstOrNull;
  if (id == null) return null;
  final inputs = _inputsOf(wf, id);
  return (
    width: (inputs['width'] as num).toInt(),
    height: (inputs['height'] as num).toInt(),
  );
}

/// 改画面大小:所有空白画布节点(标了 `Penna.Latent` 的只改它)换成 [size](取 8 的倍数)。
ComfyWorkflow setLatentSize(ComfyWorkflow wf, ComfySize size) {
  final ids = latentNodeIds(wf);
  if (ids.isEmpty) throw ComfyException(tr('工作流里找不到设画面大小的节点'));
  final out = _copy(wf);
  for (final id in ids) {
    _inputsOf(out, id)
      ..['width'] = snapLatent(size.width)
      ..['height'] = snapLatent(size.height);
  }
  return out;
}

/// 采样器能改的参数(没接线的才算)。
const samplerKeys = ['steps', 'cfg', 'sampler_name', 'scheduler', 'denoise'];

/// 工作流里的采样器(有 steps 的节点):编号、类型、能改的参数现在的值。
List<({String node, String type, Map<String, Object?> values})> samplerSlots(
  ComfyWorkflow wf,
) => [
  for (final (id, type, inputs) in _nodes(wf))
    if (inputs['steps'] is num)
      (
        node: id,
        type: type,
        values: {
          for (final k in samplerKeys)
            if (inputs[k] is num || inputs[k] is String) k: inputs[k],
        },
      ),
];

/// Agent 写的 `<comfy-set>` 里的键(左边)对应工作流里的输入名。
const _setKeys = {
  'steps': 'steps',
  'cfg': 'cfg',
  'denoise': 'denoise',
  'sampler': 'sampler_name',
  'sampler_name': 'sampler_name',
  'scheduler': 'scheduler',
};

/// 照 Agent 写的 `<comfy-set>size=832x1216 steps=30</comfy-set>` 改工作流:
/// size 可以写宽x高,也可以写比例(3:4,面积照现在的、取 64 的倍数);
/// 采样器参数改排第一的采样器。返回改好的和改了哪些(给人看的)。
/// 一项都认不出时抛 [ComfyException]。
// ponytail: 有好几个采样器(高清修复)时只改第一个;要改别的再加 `#编号`。
({ComfyWorkflow workflow, List<String> changed}) applyComfySet(
  ComfyWorkflow wf,
  String spec,
) {
  var out = wf;
  final changed = <String>[];
  final pairs = RegExp(r'([A-Za-z_]+)\s*[=:]\s*([^\s,,;;]+)');
  for (final m in pairs.allMatches(spec)) {
    final key = m[1]!.toLowerCase(), value = m[2]!;
    if (key == 'size' || key == 'ratio') {
      final size = _sizeOf(value, latentSize(out));
      if (size == null) continue;
      out = setLatentSize(out, size);
      final now = latentSize(out)!;
      changed.add('${now.width}×${now.height}');
      continue;
    }
    if (key == 'duration' || key == 'length') {
      final slot = durationSlot(out);
      final n = num.tryParse(value.replaceFirst(RegExp(r's$'), ''));
      if (slot == null || n == null || n <= 0) continue;
      out = setInput(out, slot.node, slot.key, slot.frames ? n.round() : n);
      changed.add('$key=$value');
      continue;
    }
    final input = _setKeys[key];
    final sampler = samplerSlots(out).firstOrNull;
    if (input == null || sampler == null) continue;
    final old = sampler.values[input];
    final Object? v = old is num ? num.tryParse(value) : value;
    if (v == null || old == null) continue;
    out = setInput(out, sampler.node, input, v);
    changed.add('$input=$value');
  }
  if (changed.isEmpty) throw ComfyException(tr('没认出要改的出图参数'));
  return (workflow: out, changed: changed);
}

/// `832x1216` 或比例 `3:4`(按 [now] 的面积换算成 64 的倍数)。
ComfySize? _sizeOf(String v, ComfySize? now) {
  final exact = RegExp(r'^(\d+)\s*[x×*]\s*(\d+)$').firstMatch(v);
  if (exact != null) {
    return (width: int.parse(exact[1]!), height: int.parse(exact[2]!));
  }
  final ratio = RegExp(r'^(\d+(?:\.\d+)?)[:/](\d+(?:\.\d+)?)$').firstMatch(v);
  if (ratio == null) return null;
  final a = double.parse(ratio[1]!), b = double.parse(ratio[2]!);
  if (a <= 0 || b <= 0) return null;
  final area = now == null ? 1024 * 1024 : now.width * now.height;
  int by64(double x) => ((x / 64).round() * 64).clamp(256, 4096);
  return (
    width: by64(math.sqrt(area * a / b)),
    height: by64(math.sqrt(area * b / a)),
  );
}

/// 改一个 LoRA 的权重、开关(给了哪个改哪个)。几个权重(模型、CLIP)一起改。
/// 文本标签形式的要用 [name] 指出改哪一条(一个文本里可能装着好几个 LoRA)。
ComfyWorkflow setLora(
  ComfyWorkflow wf,
  String node,
  String key, {
  double? strength,
  bool? on,
  String? name,
}) {
  final out = _copy(wf);
  final inputs = _inputsOf(out, node);
  final v = inputs[key];
  // 文本标签:<lora:名字:权重> 那一串
  if (v is String && _loraTag.hasMatch(v)) {
    if (name == null) return out;
    inputs[key] = _rewriteLoraTags(v, name, strength: strength, off: on == false);
    return out;
  }
  if (v is Map) {
    if (strength != null) {
      v['strength'] = strength;
      if (v.containsKey('strengthTwo')) v['strengthTwo'] = strength;
    }
    if (on != null) v['on'] = on;
    return out;
  }
  if (strength != null) {
    for (final k in _strengthKeysFor(key, inputs)) {
      inputs[k] = strength;
    }
  }
  if (on != null) {
    final k = _switchKeyFor(key, inputs);
    if (k != null) inputs[k] = inputs[k] is bool ? on : (on ? 'On' : 'Off');
  }
  return out;
}

/// 拖动 LoRA 换顺序:第 [from] 个挪到第 [to] 个([to] 是挪完之后的位置)。
/// 各槽位(节点、输入)不动,名字、权重、开关按新的先后重新填一遍。
// ponytail: 挪进没有开关的槽位时,关着的 LoRA 会变成开着(那种加载器没有开关可关)。
ComfyWorkflow moveLora(ComfyWorkflow wf, int from, int to) {
  final slots = loraSlots(wf);
  final order = [...slots];
  order.insert(to.clamp(0, slots.length - 1), order.removeAt(from));
  var out = _copy(wf);
  for (final (i, slot) in slots.indexed) {
    final want = order[i];
    final inputs = _inputsOf(out, slot.node);
    if (inputs[slot.key] case final Map nested) {
      nested['lora'] = want.name;
    } else {
      inputs[slot.key] = want.name;
    }
    out = setLora(
      out,
      slot.node,
      slot.key,
      strength: want.strength,
      on: want.on,
    );
  }
  return out;
}

String _nextId(ComfyWorkflow wf) =>
    '${wf.keys.map(int.tryParse).nonNulls.fold(0, (a, b) => a > b ? a : b) + 1}';

/// 把接在 [from] 上的线都改接到 [to](不动 [except] 这个节点)。
void _rewire(
  ComfyWorkflow wf,
  List<Object?> from,
  List<Object?> to,
  String except,
) {
  for (final (id, _, inputs) in _nodes(wf)) {
    if (id == except) continue;
    for (final k in inputs.keys.toList()) {
      final v = inputs[k];
      if (v is List &&
          v.length == 2 &&
          '${v[0]}' == from[0] &&
          v[1] == from[1]) {
        inputs[k] = [to[0], to[1]];
      }
    }
  }
}

/// 一段文字里的 LoRA 标签(名字、权重);没有标签就是空的。
List<({String name, double strength})> parseLoraTags(String text) => [
  for (final m in _loraTag.allMatches(text))
    (
      name: m.group(1)!.trim(),
      strength: double.tryParse(m.group(2) ?? '') ?? 1,
    ),
];

/// 工作流里有没有写着 `{{lora}}` 的框。
/// 有的话，LoRA 就由「设置里存的那段语法」决定，工作流别的节点一概不动。
bool usesLoraMark(ComfyWorkflow wf) => _nodes(wf).any(
  (n) => n.$3.values.any((v) => v is String && v.contains(comfyLoraMark)),
);

/// 工作流里「装 LoRA 语法」的那个文本框。
///
/// 依次找:
/// 1. 内容写着 `{{lora}}` 的(约定写法，出图时按设置里的语法替换);
/// 2. 接在某个名字带 lora 的输入(比如 LoraManager 的 `lora_syntax`)上的文本节点;
/// 3. 内容里已经有 `<lora:…>` 标签的文本框。
///
/// 找不到就没法在侧栏里编辑(返回 null)。
({String node, String key})? loraTextSlot(ComfyWorkflow wf) {
  for (final (id, _, inputs) in _nodes(wf)) {
    for (final key in inputs.keys) {
      final v = inputs[key];
      if (v is String && v.contains(comfyLoraMark)) return (node: id, key: key);
    }
  }
  for (final (_, _, inputs) in _nodes(wf)) {
    for (final key in inputs.keys) {
      if (!key.toLowerCase().contains('lora')) continue;
      final link = inputs[key];
      if (link is! List || link.length != 2) continue;
      final target = wf['${link[0]}'];
      if (target is! Map) continue;
      final targetInputs = target['inputs'];
      if (targetInputs is! Map) continue;
      for (final k in const ['text', 'value', 'string']) {
        if (targetInputs[k] is String) {
          return (node: '${link[0]}', key: k);
        }
      }
    }
  }
  for (final (id, _, inputs) in _nodes(wf)) {
    for (final key in inputs.keys) {
      final v = inputs[key];
      if (v is String && _loraTag.hasMatch(v)) return (node: id, key: key);
    }
  }
  return null;
}

/// 读一个节点某个输入的文字(没有就是空串)。
String nodeText(ComfyWorkflow wf, String node, String key) {
  final n = wf[node];
  if (n is! Map) return '';
  final inputs = n['inputs'];
  if (inputs is! Map) return '';
  final v = inputs[key];
  return v is String ? v : '';
}

/// 改一个节点的文字输入(不动别的东西)。
ComfyWorkflow setNodeText(
  ComfyWorkflow wf,
  String node,
  String key,
  String value,
) {
  final out = _copy(wf);
  _inputsOf(out, node)[key] = value;
  return out;
}

/// 名字的比较用键:去掉目录、后缀，小写。
String _bareName(String s) {
  final base = s.split(RegExp(r'[\\/]')).last;
  return base.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), '').toLowerCase();
}

/// 往一段语法里加一条;已经有同名的就只改权重。
String loraSyntaxAdd(String text, String name, double strength) {
  final has = parseLoraTags(text).any((e) => _bareName(e.name) == _bareName(name));
  if (has) return loraSyntaxSet(text, name, strength);
  final body = text.trim();
  final tag = '<lora:$name:${_strengthText(strength)}>';
  return body.isEmpty ? tag : '$body $tag';
}

/// 改一段语法里某一条的权重。
String loraSyntaxSet(String text, String name, double strength) {
  final parsed = parseLoraTags(text);
  // 名字写法可能不一样(带不带目录)，按比较键找出真正那一条的名字。
  final target = parsed
      .where((e) => _bareName(e.name) == _bareName(name))
      .map((e) => e.name)
      .firstOrNull;
  return _rewriteLoraTags(text, target ?? name, strength: strength);
}

/// 从一段语法里删掉一条。
String loraSyntaxRemove(String text, String name) {
  final parsed = parseLoraTags(text);
  final target = parsed
      .where((e) => _bareName(e.name) == _bareName(name))
      .map((e) => e.name)
      .firstOrNull;
  return _rewriteLoraTags(text, target ?? name, off: true);
}

/// 一条标准的 LoRA 标签:`<lora:名字:权重>`。
String loraTag(String name, double strength) =>
    '<lora:$name:${_strengthText(strength)}>';

/// 把一段语法收拢成标准写法(`<lora:名字:权重>` 用空格隔开)。
/// 认不出任何标签时原样返回(可能用户正在输入)。
String loraSyntaxNormalize(String text) {
  final parsed = parseLoraTags(text);
  if (parsed.isEmpty) return text.trim();
  return [
    for (final e in parsed) '<lora:${e.name}:${_strengthText(e.strength)}>',
  ].join(' ');
}

/// 工作流用文本标签(`<lora:名字:权重>`)装 LoRA 吗。
/// 是的话，加 LoRA 只写文件名(和 Lora Manager 自己写的一致)。
bool usesLoraTags(ComfyWorkflow wf) => _nodes(wf).any(
  (n) => n.$3.values.any((v) => v is String && _loraTag.hasMatch(v)),
);

/// 加一个 LoRA。工作流用文本装 LoRA 时追加一条 `<lora:名字:权重>`;
/// 有 Power Lora Loader 就加在它里面;
/// 没有就在模型加载器后面插一个 LoraLoaderModelOnly,原来接模型的线都改接到它上面。
ComfyWorkflow addLora(ComfyWorkflow wf, String name, double strength) {
  final out = _copy(wf);
  // 有「装 LoRA 语法的文本节点」时一律写进那段文本，绝不新增 LoraLoaderModelOnly：
  // 那边要的是带目录和后缀的完整文件名，裸名字插进去 ComfyUI 会直接拒收。
  final slot = loraTextSlot(wf);
  if (slot != null) {
    final current = nodeText(out, slot.node, slot.key);
    if (!current.contains(comfyLoraMark)) {
      _inputsOf(out, slot.node)[slot.key] = loraSyntaxAdd(
        current,
        name,
        strength,
      );
      return out;
    }
  }
  // 文本标签形式的:直接追加在那串文本后面,别混进一个新节点,
  // 否则同一个工作流里两种写法并存,面板上会多出一份。
  for (final (_, _, inputs) in _nodes(out)) {
    for (final key in inputs.keys) {
      final v = inputs[key];
      if (v is String && _loraTag.hasMatch(v)) {
        inputs[key] =
            '${v.trimRight()} <lora:$name:${_strengthText(strength)}>'.trim();
        return out;
      }
    }
  }
  for (final (_, type, inputs) in _nodes(out)) {
    final nested = inputs.entries.where((e) => _isNested(e.value)).toList();
    if (nested.isEmpty && !type.toLowerCase().contains('power lora')) continue;
    final n =
        nested
            .map((e) => int.tryParse(_tail(e.key)) ?? 0)
            .fold(0, (a, b) => a > b ? a : b) +
        1;
    final two = nested.any((e) => (e.value as Map).containsKey('strengthTwo'));
    inputs['lora_$n'] = {
      'on': true,
      'lora': name,
      'strength': strength,
      if (two) 'strengthTwo': strength,
    };
    return out;
  }
  final source = modelSlots(out).firstOrNull;
  if (source == null) throw ComfyException(tr('工作流里找不到模型加载器,加不了 LoRA'));
  final id = _nextId(out);
  _rewire(out, [source.node, 0], [id, 0], id);
  out[id] = {
    'class_type': _addedLoraType,
    'inputs': {
      'lora_name': name,
      'strength_model': strength,
      'model': [source.node, 0],
    },
  };
  return out;
}

/// 去掉一个 LoRA:文本标签形式删掉那一条标签;Power Lora Loader 里的删掉那一项;
/// 只有这一个 LoRA 的节点整个拿掉,接在它输出上的线改接回它的输入(模型、CLIP);
/// Stack 类的槽位改成 None。
ComfyWorkflow removeLora(
  ComfyWorkflow wf,
  String node,
  String key, {
  String? name,
}) {
  final out = _copy(wf);
  final inputs = _inputsOf(out, node);
  final v = inputs[key];
  if (v is String && _loraTag.hasMatch(v)) {
    if (name == null) return out;
    inputs[key] = _rewriteLoraTags(v, name, off: true);
    return out;
  }
  if (v is Map) {
    inputs.remove(key);
    return out;
  }
  final single = loraSlots({node: out[node]}).length == 1 && _tail(key).isEmpty;
  if (!single) {
    inputs[key] = 'None';
    return out;
  }
  // LoraLoader 的输出:0 是模型,1 是 CLIP;仅模型的只有 0。
  for (final (slot, input) in [(0, 'model'), (1, 'clip')]) {
    final link = inputs[input];
    if (link is List && link.length == 2) {
      _rewire(out, [node, slot], link, node);
    }
  }
  out.remove(node);
  return out;
}
