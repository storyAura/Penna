import 'dart:convert';

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

/// 模型加载器(ckpt_name、unet_name)。
List<ModelSlot> modelSlots(ComfyWorkflow wf) => [
  for (final (id, type, inputs) in _nodes(wf))
    for (final key in _modelKeys)
      if (inputs[key] case final String value)
        (node: id, type: type, key: key, value: value),
];

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

/// 改一个 LoRA 的权重、开关(给了哪个改哪个)。几个权重(模型、CLIP)一起改。
ComfyWorkflow setLora(
  ComfyWorkflow wf,
  String node,
  String key, {
  double? strength,
  bool? on,
}) {
  final out = _copy(wf);
  final inputs = _inputsOf(out, node);
  final v = inputs[key];
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

/// 加一个 LoRA。工作流里有 Power Lora Loader 就加在它里面;
/// 没有就在模型加载器后面插一个 LoraLoaderModelOnly,原来接模型的线都改接到它上面。
ComfyWorkflow addLora(ComfyWorkflow wf, String name, double strength) {
  final out = _copy(wf);
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

/// 去掉一个 LoRA:Power Lora Loader 里的删掉那一项;只有这一个 LoRA 的节点整个拿掉,
/// 接在它输出上的线改接回它的输入(模型、CLIP);Stack 类的槽位改成 None。
ComfyWorkflow removeLora(ComfyWorkflow wf, String node, String key) {
  final out = _copy(wf);
  final inputs = _inputsOf(out, node);
  if (inputs[key] is Map) {
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
