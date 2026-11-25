import '../../l10n/l10n.dart';
import 'comfyui.dart';

// 把 ComfyUI 普通保存的工作流(画布格式:nodes、links、groups)转成「导出 (API)」格式。
// 照官方前端 graphToPrompt 的规则:
// - 只要从存图节点(SaveImage、PreviewImage)往回接得上的节点;没接上的残留节点、
//   静音(mode 2)、绕过(mode 4)的节点、Reroute、说明卡片都不写进去;
// - 连线穿过 Reroute、被绕过的节点(按类型找能递过去的输入)和 KJNodes 的 GetNode → 同名
//   SetNode,接到静音节点上的输入去掉;
// - 控件按名字取(widgets_values_named),control_after_generate 这类不进 API;
//   没有按名字存的旧文件,按输入表里控件的先后对上(跳过紧跟在数字后面的 randomize 这类);
// - rgthree 的 Power Lora Loader 只写出带 lora 的那几项(lora_1、lora_2…)。
//
// 组名协议:组标题第一个词是 `Penna.角色` 这样的记号。
// 组里的节点按官方规则(节点框的中心落在组框里)算;`_meta.title` 写成那个记号,
// `Penna.Prompt.positive` 组里的文字框换成 {{prompt}},`Penna.Latent` 组里的节点出图时换成画板尺寸。
// ponytail: 一个节点落在两个组里时取先列出的组,没做冲突确认;子图(subgraph)不支持;
// 自定义节点按控件名照搬,动态控件除了 Power Lora Loader 都没专门处理,ComfyUI 校验不过时会报出来。

/// 组标题里的记号:`Penna.Prompt.positive`、`Penna.Sampler#hires`。
final _token = RegExp(r'^Penna(\.[A-Za-z][A-Za-z0-9_]*)+(#[A-Za-z0-9_]+)?$');

/// 不进 API 的控件(官方前端里 serialize 为假)。
const _controlWidgets = {'control_after_generate', 'control_before_generate'};
const _controlValues = {'fixed', 'increment', 'decrement', 'randomize'};

/// 只在画布上、不执行的节点。
const _virtualTypes = {
  'Reroute',
  'Note',
  'MarkdownNote',
  'PrimitiveNode',
  'PrimitiveString',
  'SetNode',
  'GetNode',
};

/// 官方前端节点标题栏的高度:节点的 pos 是内容区左上角,框要往上加这么多。
const _titleHeight = 30.0;

typedef _Json = Map<String, Object?>;

/// 组标题里的记号(第一个词);不是记号是 null。
String? groupToken(String title) {
  final first = title.trim().split(RegExp(r'\s+')).first;
  return _token.hasMatch(first) ? first : null;
}

/// 是不是画布格式的工作流(普通保存的)。
bool isCanvasWorkflow(Object? json) =>
    json is Map && json['nodes'] is List && json['links'] is List;

/// 画布格式转 API 格式。转不了时抛 [ComfyException]。
Map<String, Object?> canvasToApi(Map<String, Object?> json) {
  final nodes = <String, _Json>{
    for (final n in json['nodes'] as List)
      if (n is Map && n['id'] != null) '${n['id']}': n.cast<String, Object?>(),
  };
  if (json['definitions'] is Map &&
      (json['definitions'] as Map)['subgraphs'] is List &&
      ((json['definitions'] as Map)['subgraphs'] as List).isNotEmpty) {
    throw ComfyException(tr('暂不支持带子图的工作流,请在 ComfyUI 里用「导出 (API)」'));
  }
  // 连线:编号 → (从哪个节点, 第几个输出)。
  final links = <Object?, (String, int)>{
    for (final l in json['links'] as List)
      if (l is List && l.length > 2)
        l[0]: ('${l[1]}', (l[2] as num).toInt())
      else if (l is Map)
        l['id']: ('${l['origin_id']}', (l['origin_slot'] as num).toInt()),
  };
  final groups = _groupsOf(json, nodes);
  // KJNodes 的 SetNode / GetNode:按名字隔空接线,GetNode 取同名 SetNode 的输入。
  final setters = <String, _Json>{
    for (final n in nodes.values)
      if (n['type'] == 'SetNode') _firstWidget(n): n,
  };

  List<Object?>? resolve(Object? linkId, [int depth = 0]) {
    final link = links[linkId];
    if (link == null || depth > 64) return null;
    final (id, slot) = link;
    final node = nodes[id];
    if (node == null) return null;
    final type = '${node['type']}';
    if (type == 'Reroute' || type == 'SetNode') {
      return resolve(_inputsOf(node).firstOrNull?['link'], depth + 1);
    }
    if (type == 'GetNode') {
      final set = setters[_firstWidget(node)];
      return set == null
          ? null
          : resolve(_inputsOf(set).firstOrNull?['link'], depth + 1);
    }
    if (_virtualTypes.contains(type) || node['mode'] == 2) return null;
    if (node['mode'] == 4) return resolve(_bypassInput(node, slot), depth + 1);
    return [id, slot];
  }

  // 从存图节点往回找要执行的节点。
  final outputs = [
    for (final MapEntry(key: id, value: n) in nodes.entries)
      if (_runs(n) &&
          (comfyOutputType.hasMatch('${n['type']}') ||
              (groups[id]?.startsWith('Penna.Output') ?? false)))
        id,
  ];
  if (outputs.isEmpty) {
    throw ComfyException(tr('工作流里没有保存图像的节点'));
  }
  final keep = <String>{};
  final todo = [...outputs];
  while (todo.isNotEmpty) {
    final id = todo.removeLast();
    if (!keep.add(id)) continue;
    for (final input in _inputsOf(nodes[id]!)) {
      final from = resolve(input['link']);
      if (from != null) todo.add('${from[0]}');
    }
  }

  return {
    for (final id in keep.toList()..sort(_byId))
      id: _apiNode(nodes[id]!, groups[id], resolve),
  };
}

int _byId(String a, String b) {
  final x = int.tryParse(a), y = int.tryParse(b);
  return x != null && y != null ? x.compareTo(y) : a.compareTo(b);
}

bool _runs(_Json n) =>
    !_virtualTypes.contains('${n['type']}') && n['mode'] != 2 && n['mode'] != 4;

String _firstWidget(_Json node) => switch (node['widgets_values']) {
  [final v, ...] => '$v',
  _ => '',
};

List<_Json> _inputsOf(_Json node) => [
  for (final i in node['inputs'] as List? ?? const [])
    if (i is Map) i.cast<String, Object?>(),
];

/// 被绕过的节点第 [slot] 个输出由哪条输入递过去:同位置、同类型的优先,否则第一个同类型的。
Object? _bypassInput(_Json node, int slot) {
  final outs = node['outputs'] as List? ?? const [];
  final type = slot < outs.length ? (outs[slot] as Map)['type'] : null;
  final ins = _inputsOf(node);
  if (slot < ins.length && ins[slot]['type'] == type) return ins[slot]['link'];
  return ins.where((i) => i['type'] == type).firstOrNull?['link'];
}

/// 每个节点落在哪个记号组里(节点框中心在组框里;只看标题是记号的组)。
Map<String, String> _groupsOf(_Json json, Map<String, _Json> nodes) {
  final out = <String, String>{};
  for (final g in json['groups'] as List? ?? const []) {
    if (g is! Map) continue;
    final token = groupToken('${g['title'] ?? ''}');
    final b = g['bounding'];
    if (token == null || b is! List || b.length < 4) continue;
    final [x, y, w, h] = [for (final v in b.take(4)) (v as num).toDouble()];
    for (final MapEntry(key: id, value: n) in nodes.entries) {
      final pos = n['pos'], size = n['size'];
      if (out.containsKey(id) || !_isPair(pos) || !_isPair(size)) continue;
      final collapsed = (n['flags'] as Map?)?['collapsed'] == true;
      final cx = _at(pos, 0) + _at(size, 0) / 2;
      final cy = collapsed
          ? _at(pos, 1) - _titleHeight / 2
          : _at(pos, 1) - _titleHeight + (_at(size, 1) + _titleHeight) / 2;
      if (cx >= x && cx <= x + w && cy >= y && cy <= y + h) out[id] = token;
    }
  }
  return out;
}

bool _isPair(Object? v) =>
    v is List && v.length >= 2 && v[0] is num && v[1] is num ||
    v is Map && v['0'] is num && v['1'] is num;

double _at(Object? v, int i) =>
    ((v is List ? v[i] : (v as Map)['$i']) as num).toDouble();

_Json _apiNode(
  _Json node,
  String? token,
  List<Object?>? Function(Object?) resolve,
) {
  final type = '${node['type']}';
  final inputs = <String, Object?>{};
  final linked = <String>{};
  for (final input in _inputsOf(node)) {
    final name = '${input['name']}';
    final from = input['link'] == null ? null : resolve(input['link']);
    if (from != null) {
      inputs[name] = from;
      linked.add((input['widget'] as Map?)?['name'] as String? ?? name);
    }
  }
  for (final MapEntry(:key, :value) in _widgets(node, type).entries) {
    if (linked.contains(key)) continue;
    inputs[key] = value is List ? {'__value__': value} : value;
  }
  if (token == 'Penna.Prompt.positive' ||
      (token?.startsWith('Penna.Prompt.positive#') ?? false)) {
    for (final k in const ['text', 'text_g', 'text_l']) {
      if (inputs[k] is String) inputs[k] = comfyPromptMark;
    }
  }
  return {
    'class_type': type,
    'inputs': inputs,
    '_meta': {'title': token ?? '${node['title'] ?? type}'},
  };
}

/// 节点的控件值,按名字。
Map<String, Object?> _widgets(_Json node, String type) {
  final values = node['widgets_values'];
  if (type.contains('Power Lora Loader')) {
    var n = 0;
    return {
      if (values is List)
        for (final v in values)
          if (v is Map && v['lora'] is String) 'lora_${++n}': v,
    };
  }
  if (values is Map) return values.cast<String, Object?>();
  final named = node['widgets_values_named'];
  if (named is Map) {
    return {
      for (final MapEntry(:key, :value)
          in named.cast<String, Object?>().entries)
        if (!_controlWidgets.contains(key)) key: value,
    };
  }
  if (values is! List || values.isEmpty) return const {};
  // 旧文件没有按名字存:输入表里带 widget 的那几项就是控件的先后。
  final names = [
    for (final i in _inputsOf(node))
      if (i['widget'] is Map) '${(i['widget'] as Map)['name']}',
  ];
  if (names.isEmpty) {
    throw ComfyException(
      tr('「{0}」读不出控件名:请用新版 ComfyUI 重新保存,或用「导出 (API)」', [type]),
    );
  }
  final out = <String, Object?>{};
  var v = 0;
  for (final name in names) {
    if (v >= values.length) break;
    out[name] = values[v++];
    // 种子后面跟着的「生成后怎么变」不进 API。
    if (out[name] is num &&
        v < values.length &&
        _controlValues.contains(values[v])) {
      v++;
    }
  }
  return out;
}
