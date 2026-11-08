part of 'comfy_runner.dart';

/// 换哪台 ComfyUI、哪个工作流,改工作流(LoRA),存好的 LoRA 配置。
extension ComfyFlows on ComfyRunner {
  ComfySettings get _settings => config.config.comfy;

  void _put(ComfySettings next) =>
      config.update(config.config.copyWith(comfy: next));

  /// 内置文生图的模型和 LoRA 能选的(连上之后读)。
  Future<Map<String, List<String>>> _readOptions(ComfyClient client) async => {
    _ckptOptions: await client.checkpoints(),
    _loraOptions: await client.options('LoraLoaderModelOnly', 'lora_name'),
  };

  List<String> get loraOptions => _options[_loraOptions] ?? const [];

  ComfyWorkflow? _parse(String text) {
    try {
      return parseApiWorkflow(text);
    } on ComfyException {
      return null;
    }
  }

  /// 眼前用的工作流。内置的要连上 ComfyUI、知道第一个模型才有。
  ComfyWorkflow? get workflow {
    final flow = _settings.flow;
    return flow == null ? _builtin : _parse(flow.text);
  }

  /// 眼前用的工作流叫什么(已翻译)。
  String get workflowName => _flowName(_settings.flow);

  String _flowName(ComfyFlow? flow) => flow == null
      ? tr(builtinWorkflowName)
      : flow.name.trim().isEmpty
      ? tr('未命名')
      : tr(flow.name);

  /// 下拉里的工作流:导入的那些;一个都没有时只有内置文生图(id 是 [builtinWorkflowId])。
  List<({String id, String name})> get flowChoices => _settings.flows.isEmpty
      ? [(id: builtinWorkflowId, name: tr(builtinWorkflowName))]
      : [for (final f in _settings.flows) (id: f.id, name: _flowName(f))];

  /// 眼前用的工作流的 id(内置文生图是 [builtinWorkflowId])。
  String get flowId => _settings.flow?.id ?? builtinWorkflowId;

  /// 换工作流。
  void selectFlow(String id) {
    if (id == flowId) return;
    _put(_settings.copyWith(flowId: id));
    _changed();
  }

  /// 换一台 ComfyUI,马上测连接、重读名单。
  void selectServer(String id) {
    if (id == _settings.serverId) return;
    _put(_settings.copyWith(serverId: id));
    _status = null;
    _options = const {};
    _changed();
    unawaited(check(full: true));
  }

  /// 改工作流(LoRA),存进设置。内置的改过之后另存一份(名字照旧)并换过去。
  /// 改不了返回原因。
  String? edit(ComfyWorkflow Function(ComfyWorkflow) change) {
    final wf = workflow;
    if (wf == null) return tr('还没连上 ComfyUI');
    final ComfyWorkflow next;
    try {
      next = change(wf);
    } on ComfyException catch (e) {
      return e.message;
    }
    final flow =
        _settings.flow ??
        (
          id: '${DateTime.now().microsecondsSinceEpoch}',
          name: builtinWorkflowName,
          text: '',
        );
    _put(
      _settings
          .putFlow((id: flow.id, name: flow.name, text: jsonEncode(next)))
          .copyWith(flowId: flow.id),
    );
    _changed();
    return null;
  }

  /// 按名字换工作流(Agent 写的 `<comfy-workflow>`):先比工作流的名字,再比它用的模型
  /// (完整名字、去掉文件夹和后缀的名字,或只有一个包含它的)。返回换上的工作流名,或找不到的原因。
  ({String? flow, String? problem}) switchWorkflow(String wanted) {
    final w = wanted.trim().toLowerCase();
    if (w.isEmpty) return (flow: null, problem: tr('没说换成哪个'));
    final named = [
      for (final c in flowChoices)
        (id: c.id, names: [c.name.toLowerCase(), ..._modelsOf(c.id)]),
    ];
    final hits = [
      for (final c in named)
        if (c.names.any((n) => n == w || _short(n) == _short(w))) c.id,
    ];
    final loose = [
      for (final c in named)
        if (c.names.any((n) => n.contains(w))) c.id,
    ];
    final id = hits.firstOrNull ?? (loose.length == 1 ? loose.single : null);
    if (id == null) {
      return (
        flow: null,
        problem: loose.length > 1
            ? tr('「{0}」对得上好几个工作流', [wanted.trim()])
            : tr('没有用「{0}」的工作流', [wanted.trim()]),
      );
    }
    selectFlow(id);
    return (flow: workflowName, problem: null);
  }

  /// 一个工作流用的模型(小写)。内置的用 ComfyUI 里第一个模型。
  List<String> _modelsOf(String id) {
    final wf = id == builtinWorkflowId
        ? _builtin
        : _parse(_settings.flows.firstWhere((f) => f.id == id).text);
    return [for (final s in modelSlots(wf ?? const {})) s.value.toLowerCase()];
  }

  ComfyWorkflow? get _builtin {
    final first = (_options[_ckptOptions] ?? const <String>[]).firstOrNull;
    return first == null ? null : defaultWorkflow(first);
  }

  /// Agent 看的:每个工作流叫什么、用什么模型,眼前是哪个。
  String get flowsForAgent => [
    for (final c in flowChoices)
      '- ${c.name}${c.id == flowId ? '(眼前用的)' : ''}:'
          '${_modelsOf(c.id).isEmpty ? '模型未知' : _modelsOf(c.id).join('、')}',
  ].join('\n');

  /// 眼前用的那套 LoRA 配置;没用哪一套(或已删掉)是 null。
  LoraPreset? get loraPreset => _settings.loraPresets
      .where((p) => p.name == _settings.loraPreset)
      .firstOrNull;

  /// 眼前工作流的 LoRA 和用着的那套配置不一样了(要存才留得住)。
  bool get loraPresetChanged {
    final preset = loraPreset;
    final wf = workflow;
    return preset != null &&
        wf != null &&
        !listEquals(_lorasOf(wf), preset.loras);
  }

  List<LoraSetting> _lorasOf(ComfyWorkflow wf) => [
    for (final l in loraSlots(wf))
      (name: l.name, strength: l.strength, on: l.on),
  ];

  /// 把眼前工作流的 LoRA(开关、权重)存成一套配置并用上它;同名的换掉。
  String? saveLoraPreset(String name) {
    final wf = workflow;
    if (wf == null) return tr('还没连上 ComfyUI');
    if (name.trim().isEmpty) return tr('名字不能为空');
    _put(
      _settings
          .putLoraPreset((name: name.trim(), loras: _lorasOf(wf)))
          .copyWith(loraPreset: name.trim()),
    );
    _changed();
    return null;
  }

  /// 用一套配置:工作流里的 LoRA 换成和它一模一样(各套各是各的名单):
  /// 配置里有的照它开关、改权重,没有的加上,配置里没有的去掉。
  /// ponytail: 去掉的若是工作流自带的 LoraLoader(也接 CLIP),再加回来只作用于模型;
  /// 要原样还原就得把整份工作流存进配置。
  String? applyLoraPreset(LoraPreset preset) {
    final problem = edit((wf) {
      var next = wf;
      final wanted = {for (final l in preset.loras) l.name: l};
      // 去掉一个只动它自己那一项或那个节点,别的槽位的 node / key 不变,所以照旧表走。
      for (final slot in loraSlots(wf)) {
        final want = wanted.remove(slot.name);
        next = want == null
            ? removeLora(next, slot.node, slot.key)
            : setLora(
                next,
                slot.node,
                slot.key,
                strength: want.strength,
                on: want.on,
              );
      }
      for (final l in wanted.values) {
        next = addLora(next, l.name, l.strength);
        if (!l.on) {
          final added = loraSlots(next).last;
          next = setLora(next, added.node, added.key, on: false);
        }
      }
      return next;
    });
    if (problem != null) return problem;
    _put(_settings.copyWith(loraPreset: preset.name));
    _changed();
    return null;
  }

  void removeLoraPreset(String name) {
    _put(_settings.removeLoraPreset(name));
    _changed();
  }
}

/// 文件名去掉文件夹和后缀,小写。
String _short(String s) => s
    .split(RegExp(r'[\\/]'))
    .last
    .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')
    .toLowerCase();
