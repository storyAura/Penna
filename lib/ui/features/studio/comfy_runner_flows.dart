part of 'comfy_runner.dart';

/// 换哪台 ComfyUI、哪个工作流,改工作流(LoRA),存好的 LoRA 配置。
extension ComfyFlows on ComfyRunner {
  ComfySettings get _settings => config.config.comfy;

  void _put(ComfySettings next) =>
      config.update(config.config.copyWith(comfy: next));

  /// 这台 ComfyUI 里的 LoRA 文件(连上之后读)。
  List<String> get loraOptions => loraNamesOf(_info);

  /// [type] 节点的 [key] 能选哪些(模型、采样器、调度器):这台 ComfyUI 的名单。
  /// 还没读到名单时现问一次。连不上返回空的。
  Future<List<String>> optionsFor(String type, String key) async {
    final known = _info[type]?[key];
    if (known != null) return known;
    try {
      return await _client.options(type, key);
    } on ComfyException {
      return const [];
    }
  }

  /// 还没读到名单时是 null,读到了是 [type] 节点 [key] 能选的(给界面标出这台没有的文件)。
  List<String>? knownOptions(String type, String key) =>
      _info.isEmpty ? null : _info[type]?[key] ?? const [];

  /// [id] 那个工作流在眼前这台 ComfyUI 上缺什么(没装的节点、没有的模型文件);
  /// 还没读到名单、或什么都不缺时是空的。
  List<String> problemsOf(String id) {
    if (_info.isEmpty || id == builtinWorkflowId) return const [];
    final flow = _settings.flows.where((f) => f.id == id).firstOrNull;
    if (flow == null) return const [];
    final cached = _problems[id];
    if (cached != null && cached.$1 == flow.text) return cached.$2;
    final wf = _parse(flow.text);
    final found = wf == null ? const <String>[] : workflowProblems(wf, _info);
    _problems[id] = (flow.text, found);
    return found;
  }

  /// Agent 写的 `<comfy-set>`:改画面大小、采样器参数,存进眼前的工作流。
  /// 返回改了哪些,或改不成的原因。
  ({List<String> changed, String? problem}) applySet(String spec) {
    var changed = const <String>[];
    final problem = edit((wf) {
      final done = applyComfySet(wf, spec);
      changed = done.changed;
      return done.workflow;
    });
    return (changed: changed, problem: problem);
  }

  /// Agent 看的:眼前工作流的画面大小和采样器参数。
  String get settingsForAgent {
    final wf = workflow;
    if (wf == null) return '';
    final size = latentSize(wf);
    final sampler = samplerSlots(wf).firstOrNull;
    final duration = durationSlot(wf);
    return [
      if (size != null) 'size=${size.width}x${size.height}',
      if (duration != null)
        duration.frames
            ? 'length=${duration.value}'
            : 'duration=${duration.value}',
      if (sampler != null)
        for (final MapEntry(:key, :value) in sampler.values.entries)
          '$key=$value',
    ].join(' ');
  }

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

  /// 换一台 ComfyUI,马上测连接、重读名单;那台给眼前这个工作流选过 LoRA 配置的,换上它。
  void selectServer(String id) {
    if (id == _settings.serverId) return;
    _put(_settings.copyWith(serverId: id));
    _status = null;
    _info = const {};
    _optionsOf = null;
    _problems.clear();
    if (loraPreset case final preset?) applyLoraPreset(preset);
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
    final first = _info['CheckpointLoaderSimple']?['ckpt_name']?.firstOrNull;
    return first == null ? null : defaultWorkflow(first);
  }

  /// Agent 看的:每个工作流叫什么、用什么模型,眼前是哪个。
  String get flowsForAgent => [
    for (final c in flowChoices)
      '- ${c.name}${c.id == flowId ? '(眼前用的)' : ''}:'
          '${_modelsOf(c.id).isEmpty ? '模型未知' : _modelsOf(c.id).join('、')}',
  ].join('\n');

  /// 眼前这台、这个工作流的 LoRA 配置(各台、各工作流各是各的),按显示的先后。
  List<LoraPreset> get loraPresets =>
      _settings.presetsOf(_settings.serverId, flowId);

  String get _presetKey => loraPresetKey(_settings.serverId, flowId);

  /// 眼前用的那套 LoRA 配置;没用哪一套(或已删掉)是 null。
  LoraPreset? get loraPreset => loraPresets
      .where((p) => p.name == _settings.loraPresetOf[_presetKey])
      .firstOrNull;

  /// 拖动眼前这个工作流的 LoRA 配置换顺序。
  void moveLoraPreset(int from, int to) {
    _put(_settings.moveLoraPreset(_settings.serverId, flowId, from, to));
    _changed();
  }

  /// 眼前这个工作流要上传素材的节点(见 [uploadSlots])。
  List<UploadSlot> get uploads =>
      workflow == null ? const [] : uploadSlots(workflow!);

  /// 眼前这个工作流各节点选好的文件:节点编号 → 本机路径。
  Map<String, String> get uploadFiles => _settings.inputs[flowId] ?? const {};

  /// 给 [node] 选一个要上传的文件(null 是不传,用工作流里原来写的)。
  void setUpload(String node, String? path) {
    _put(_settings.putInput(flowId, node, path));
    _changed();
  }

  /// 对话里附的图按先后填进眼前工作流的图片格子,多出来的格子清掉(留空的出图时跳过);
  /// 图存进「文档\Penna\comfy_inputs」,文件名取内容的哈希。返回填了几张(格子本来就是这几张时是 0)。
  // ponytail: 排着队还没出的单子出图时读的也是这时填好的格子。
  int fillUploads(List<Attachment> images) {
    final slots = [
      for (final s in uploads)
        if (s.kind == 'image') s,
    ];
    final files = [
      for (final a in images)
        if (a.bytes case final bytes? when bytes.isNotEmpty)
          _saveInput(bytes, a.mime),
    ];
    if (slots.isEmpty || files.isEmpty) return 0;
    var next = _settings;
    for (final (i, slot) in slots.indexed) {
      next = next.putInput(flowId, slot.node, files.elementAtOrNull(i));
    }
    if (mapEquals(next.inputs[flowId], _settings.inputs[flowId])) return 0;
    _put(next);
    _changed();
    return min(files.length, slots.length);
  }

  String _saveInput(Uint8List bytes, String? mime) {
    final ext = mime == 'image/jpeg' ? 'jpg' : mime?.split('/').last ?? 'png';
    final dir = Directory(
      '${config.dir.path}${Platform.pathSeparator}comfy_inputs',
    )..createSync(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      '${sha1.convert(bytes).toString().substring(0, 16)}.$ext',
    );
    if (!file.existsSync()) file.writeAsBytesSync(bytes, flush: true);
    return file.path;
  }

  /// 侧栏「画面大小」存下的常用尺寸。
  List<ComfySize> get sizes => _settings.sizes;

  /// 存下 [size];存满 [ComfySettings.maxSizes] 个时不存,返回 false。
  bool saveSize(ComfySize size) {
    if (sizes.contains(size)) return true;
    if (sizes.length >= ComfySettings.maxSizes) return false;
    _put(_settings.copyWith(sizes: [...sizes, size]));
    _changed();
    return true;
  }

  void removeSize(ComfySize size) {
    _put(
      _settings.copyWith(
        sizes: [
          for (final s in sizes)
            if (s != size) s,
        ],
      ),
    );
    _changed();
  }

  /// 侧栏下拉里拖动工作流换顺序(设置里的列表跟着变)。
  void moveFlow(int from, int to) {
    if (_settings.flows.isEmpty) return;
    _put(_settings.moveFlow(from, to));
    _changed();
  }

  /// 记下眼前这台、这个工作流用的是哪一套。
  void _useLoraPreset(String name) => _put(
    _settings.copyWith(
      loraPresetOf: {..._settings.loraPresetOf, _presetKey: name},
    ),
  );

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
      _settings.putLoraPreset((
        server: _settings.serverId,
        flow: flowId,
        name: name.trim(),
        loras: _lorasOf(wf),
      )),
    );
    _useLoraPreset(name.trim());
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
    _useLoraPreset(preset.name);
    _changed();
    return null;
  }

  void removeLoraPreset(String name) {
    _put(_settings.removeLoraPreset(_settings.serverId, flowId, name));
    _changed();
  }
}

/// 文件名去掉文件夹和后缀,小写。
String _short(String s) => s
    .split(RegExp(r'[\\/]'))
    .last
    .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')
    .toLowerCase();
