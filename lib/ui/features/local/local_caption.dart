part of 'local_model.dart';

/// 「NL 反推」列表里的一行:清单里的看图模型,或模型文件夹里找到的 GGUF(系列「本机」)。
typedef CaptionRow = ({
  String id,
  String series,
  CaptionModel? model,
  ({String model, String mmproj})? gguf,
});

/// 「NL 反推」:看图模型清单(选量化档、拖动排序),
/// 用 llama-server 跑 GGUF,或在程序里直接跑 Florence-2。
extension LocalCaption on LocalModel {
  /// 模型文件夹里找到的、不在清单里的 GGUF,配好同一个文件夹里的视觉组件。
  List<({String model, String mmproj})> get foundGgufs {
    final known = {
      for (final m in captionModels)
        for (final q in m.quants) fileName(q.file.path),
    };
    return [
      for (final g in _found.ggufs)
        if (!known.contains(fileName(g)))
          (model: g, mmproj: mmprojFor(g, _found.mmprojs, _found.gguf)),
    ];
  }

  /// 列表里的各行按系列分好组,按用户拖好的顺序。
  List<ModelGroup<CaptionRow>> get captionGroups => _grouped<CaptionRow>(
    [
      for (final m in captionModels)
        (id: m.id, series: m.series, model: m, gguf: null),
      for (final g in foundGgufs)
        (id: 'gguf:${g.model}', series: '本机', model: null, gguf: g),
    ],
    (r) => r.id,
    (r) => r.series,
    captionOrder,
  );

  /// 拖动排序:[group] 为 null 时挪的是整组。
  void moveCaption(int? group, int from, int to) => update(
    () => captionOrder = _moved(captionGroups, (r) => r.id, group, from, to),
  );

  // —— 看图描述的要求 ——

  /// 选中的那条要求。
  CaptionPrompt get currentPrompt =>
      captionPrompts[promptIndex.clamp(0, captionPrompts.length - 1)];

  void pickPrompt(int i) => update(() => promptIndex = i);

  /// 改选中的那条:名字或正文。
  void editPrompt({String? name, String? text}) {
    final i = promptIndex.clamp(0, captionPrompts.length - 1);
    final p = captionPrompts[i];
    update(
      () => captionPrompts = List.unmodifiable([
        ...captionPrompts.take(i),
        (name: name ?? p.name, text: text ?? p.text),
        ...captionPrompts.skip(i + 1),
      ]),
    );
  }

  /// 以选中的那条为底稿复制一份,选中新的。
  void addPrompt() => update(() {
    final p = currentPrompt;
    captionPrompts = List.unmodifiable([
      ...captionPrompts,
      (name: tr('{0} 副本', [p.name]), text: p.text),
    ]);
    promptIndex = captionPrompts.length - 1;
  });

  /// 删掉选中的那条;只剩一条时不删。
  void removePrompt() {
    if (captionPrompts.length < 2) return;
    final i = promptIndex.clamp(0, captionPrompts.length - 1);
    update(() {
      captionPrompts = List.unmodifiable([
        ...captionPrompts.take(i),
        ...captionPrompts.skip(i + 1),
      ]);
      promptIndex = (i - 1).clamp(0, captionPrompts.length - 1);
    });
  }

  /// 这个模型要用哪个量化档:用户选过的,否则推荐的那档。
  Quant quantOf(CaptionModel m) =>
      m.quants.where((q) => q.label == quantPicks[m.id]).firstOrNull ??
      m.quants.where((q) => q.recommended).firstOrNull ??
      m.quants.first;

  void pickQuant(CaptionModel m, String label) =>
      update(() => quantPicks = Map.unmodifiable({...quantPicks, m.id: label}));

  String _folderOf(CaptionModel m) =>
      '$_home${_sep}models${_sep}gguf$_sep${m.id}';

  RemoteFile _remote(CaptionModel m, ModelFile f) => (
    url: hfFileUrl(m.repo, f.path),
    path: '${_folderOf(m)}$_sep${fileName(f.path)}',
    size: f.size,
    sha256: f.sha256,
  );

  /// 要下载的文件:选中的量化档,加视觉组件(GGUF)或另外几个 ONNX 和分词器(Florence-2)。
  List<RemoteFile> captionFiles(CaptionModel m, [Quant? quant]) => [
    _remote(m, (quant ?? quantOf(m)).file),
    if (m.mmproj case final mm?) _remote(m, mm),
    for (final e in m.extra) _remote(m, e),
  ];

  /// 自己下载过这个模型(任何一档)。
  bool ownsCaption(CaptionModel m) =>
      m.quants.any((q) => ready(captionFiles(m, q)));

  /// 能用的文件:GGUF 是模型和视觉组件,Florence-2 是放着 ONNX 的文件夹(mmproj 为空串)。
  /// 自己下载的优先(选中的那档先看),其次是模型文件夹里找到的。都没有时为 null。
  ({String model, String mmproj})? captionPaths(CaptionModel m) {
    for (final q in [quantOf(m), ...m.quants]) {
      final files = captionFiles(m, q);
      if (!ready(files)) continue;
      return m.florence
          ? (model: _folderOf(m), mmproj: '')
          : (model: files[0].path, mmproj: files[1].path);
    }
    if (m.florence) {
      final found = findFlorence(m, _found);
      return found == null ? null : (model: found, mmproj: '');
    }
    return findCaption(m, _found, prefer: quantOf(m).label);
  }

  /// 选中的清单模型;选的是自己的 GGUF 时为 null。
  CaptionModel? get pickedCaption =>
      captionModels.where((m) => m.id == captionPick).firstOrNull;

  /// 选中的是 Florence-2:在程序里直接跑,不用 llama-server。
  bool get florenceMode => pickedCaption?.florence ?? false;

  /// Florence-2 这次用的指令:用户选过的,它不认就用它的第一个。
  String florenceTaskOf(CaptionModel m) =>
      m.tasks.contains(florenceTask) ? florenceTask : m.tasks.first;

  /// 下载一个清单里的模型(选中的量化档),下好后就用它。
  Future<String?> downloadCaption(CaptionModel m) async {
    final problem = await download(m.id, captionFiles(m));
    if (problem == null) useCaption(m);
    return problem;
  }

  /// 删掉自己下载的这一档;视觉组件只在别的档也没了时才删(几档共用一个)。
  Future<String?> removeCaption(CaptionModel m) {
    final quant = quantOf(m);
    final others = m.quants.any(
      (q) => q.label != quant.label && isDownloaded(_remote(m, q.file)),
    );
    final files = captionFiles(m);
    return remove(others && !m.florence ? files.take(1).toList() : files);
  }

  /// 用这个清单模型;下载的、文件夹里找到的都行。没有能用的文件时返回 false。
  bool useCaption(CaptionModel m) {
    final paths = captionPaths(m);
    if (paths == null) return false;
    update(() {
      captionPick = m.id;
      if (!m.florence) {
        modelPath = paths.model;
        mmprojPath = paths.mmproj;
      }
    });
    return true;
  }

  /// 用模型文件夹里找到的、或自己选的 GGUF。
  void useGguf(String model, String mmproj) => update(() {
    captionPick = '';
    modelPath = model;
    mmprojPath = mmproj;
  });

  // —— llama-server ——

  /// 起 llama-server。失败时返回给用户看的原因。
  Future<String?> startServer() async {
    final exe = serverExe;
    if (exe == null) return tr('先下载运行时,或选一个 llama-server.exe');
    if (modelPath.isEmpty) return tr('先选一个模型');
    _starting = true;
    _changed();
    String? problem;
    try {
      await server.start((
        exe: exe,
        model: modelPath,
        mmproj: mmprojPath,
        port: port,
        context: context,
        gpuLayers: gpuLayers,
      ));
    } on LocalServerException catch (e) {
      problem = e.message;
    }
    _starting = false;
    _changed();
    return problem;
  }

  Future<void> stopServer() async {
    await server.stop();
    _starting = false;
    _changed();
  }

  // —— 看图写描述 ——

  /// 看图写一段描述:选的是 Florence-2 就在程序里跑,否则交给跑着的 llama-server。
  /// 失败时返回给用户看的原因。
  Future<String?> runCaption() async {
    final image = _image;
    if (image == null) return tr('先放一张图');
    if (_captioning) return tr('正在生成');
    final florence = florenceMode ? pickedCaption : null;
    final url = server.baseUrl;
    if (florence == null && url == null) return tr('先启动模型');
    _captioning = true;
    _caption = '';
    final round = _round;
    _changed();
    String? problem;
    try {
      if (florence != null) {
        problem = await _florenceCaption(florence, image, round);
      } else {
        await for (final piece in streamChat(
          LlmRequest(
            baseUrl: url!,
            model: 'local',
            apiKey: '',
            temperature: 0.3,
            messages: [
              {'role': 'user', 'content': currentPrompt.text},
            ],
            images: {
              0: [(mime: image.mime!, bytes: image.bytes!)],
            },
          ),
        )) {
          // 生成途中换了图:后面的字不是这张图的,停下不要了。
          if (round != _round) break;
          _caption += piece;
          _changed();
        }
      }
      if (problem == null && round == _round && _caption.trim().isEmpty) {
        problem = tr('模型没有返回内容');
      }
    } on LlmException catch (e) {
      problem = e.message;
    } on Object catch (e) {
      problem = tr('生成失败({0})', [e.runtimeType]);
    }
    if (round == _round) {
      _caption = _caption.trim();
    } else {
      problem = null;
    }
    _captioning = false;
    _changed();
    return problem;
  }

  /// Florence-2:第一次用时加载四个模型,之后留着;换了模型才重新加载。
  Future<String?> _florenceCaption(
    CaptionModel m,
    Attachment image,
    int round,
  ) async {
    final paths = captionPaths(m);
    if (paths == null) return tr('先下载这个模型');
    try {
      if (_florenceFor != paths.model) {
        _dropFlorence();
        _florence = await FlorenceEngine.load(paths.model);
        _florenceFor = paths.model;
      }
      final pixels = await decodeImage(
        image.bytes!,
        (_, _) => (width: florenceImageSize, height: florenceImageSize),
      );
      final text = await _florence!.caption(
        florencePixels(pixels.rgba, florenceImageSize),
        florenceTaskOf(m),
        stale: () => round != _round,
      );
      if (round == _round) _caption = text;
      return null;
    } on FlorenceException catch (e) {
      _dropFlorence();
      return e.message;
    }
  }

  void _dropFlorence() {
    final old = _florence;
    _florence = null;
    _florenceFor = null;
    old?.close().catchError((Object _) {});
  }
}

/// 按 [order] 排:列在里面的按它的先后,没列的(新出现的)接在后面,保持原来的先后。
List<T> _ordered<T>(List<T> items, String Function(T) id, List<String> order) {
  final rank = {for (final (i, k) in order.indexed) k: i};
  final keyed = [
    for (final (i, item) in items.indexed)
      (rank: rank[id(item)] ?? order.length + i, item: item),
  ]..sort((a, b) => a.rank.compareTo(b.rank));
  return [for (final k in keyed) k.item];
}
