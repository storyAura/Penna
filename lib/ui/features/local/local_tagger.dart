part of 'local_model.dart';

/// 按系列分好的一组。
typedef ModelGroup<T> = ({String series, List<T> items});

/// 列表顺序里系列那一项的 id。
String _groupId(String series) => 'series:$series';

/// 按系列分组;系列和组里的各行都按 [order] 排(没列的接在后面,保持原样)。
List<ModelGroup<T>> _grouped<T>(
  List<T> items,
  String Function(T) id,
  String Function(T) series,
  List<String> order,
) {
  final names = <String>[];
  for (final item in items) {
    if (!names.contains(series(item))) names.add(series(item));
  }
  return [
    for (final name in _ordered(names, _groupId, order))
      (
        series: name,
        items: _ordered(
          [
            for (final item in items)
              if (series(item) == name) item,
          ],
          id,
          order,
        ),
      ),
  ];
}

/// 拖动之后的新顺序:[group] 为 null 时是把第 [from] 组挪到第 [to] 组,
/// 否则是在第 [group] 组里把第 [from] 行挪到第 [to] 行。
List<String> _moved<T>(
  List<ModelGroup<T>> groups,
  String Function(T) id,
  int? group,
  int from,
  int to,
) {
  final names = [for (final g in groups) g.series];
  final rows = [
    for (final g in groups) [for (final item in g.items) id(item)],
  ];
  if (group == null) {
    names.insert(to, names.removeAt(from));
    rows.insert(to, rows.removeAt(from));
  } else {
    rows[group].insert(to, rows[group].removeAt(from));
  }
  return List.unmodifiable([
    for (final n in names) _groupId(n),
    for (final r in rows) ...r,
  ]);
}

/// 「Tag 反推」:打标模型清单(按系列分组、拖动排序)、选模型、调阈值、打标。
extension LocalTagger on LocalModel {
  /// 文件夹里找到、但不在清单里的打标模型,id 用这个开头接模型文件的路径。
  static const _local = 'local:';

  /// 能选的打标模型:清单里的,加上文件夹里找到的别的打标模型(按标签表认种类,阈值用常见的默认值)。
  List<TaggerModel> get taggers => [
    ...taggerModels,
    for (final d in _found.taggers)
      if (catalogTaggerFor(d) == null)
        if (_localKind(d) case final kind?)
          (
            id: '$_local$d',
            series: '本机',
            name: tr('[本机] {0}', [folderTitle(taggerDir(d))]),
            repo: '',
            note: d,
            kind: kind,
            files: const [],
            labels: taggerLabelFiles.entries
                .firstWhere((e) => e.value == kind)
                .key,
            size: 0,
            general: 0.35,
            character: 0.85,
            gated: false,
          ),
  ];

  /// 「名字.onnx」配同名 .csv 的(ComfyUI 的放法)是 WD;model.onnx 看旁边是哪种标签表。
  TaggerKind? _localKind(String model) =>
      fileName(model).toLowerCase() != taggerModelFile
      ? TaggerKind.wd
      : taggerLabelFiles.entries
            .where((e) => File(taggerLabelsAt(model, e.key)).existsSync())
            .firstOrNull
            ?.value;

  /// 打标模型按系列分好组,按用户拖好的顺序。
  List<ModelGroup<TaggerModel>> get taggerGroups =>
      _grouped(taggers, (m) => m.id, (m) => m.series, taggerOrder);

  /// 拖动排序:[group] 为 null 时挪的是整组。
  void moveTagger(int? group, int from, int to) => update(
    () => taggerOrder = _moved(taggerGroups, (m) => m.id, group, from, to),
  );

  TaggerModel get tagger =>
      taggers.where((m) => m.id == taggerRepo).firstOrNull ??
      taggerModels.firstWhere((m) => m.id.endsWith('wd-eva02-large-tagger-v3'));

  String _taggerFolder(TaggerModel m) =>
      '$_home${_sep}models${_sep}tagger$_sep'
      '${m.id.replaceAll(RegExp(r'[/:]'), '__')}';

  /// 要下载的文件(在自己的模型文件夹里只留文件名,外部权重 model.onnx.data 要和模型放在一起)。
  List<RemoteFile> taggerFiles(TaggerModel m) => [
    for (final f in m.files)
      (
        url: hfFileUrl(m.repo, f),
        path: '${_taggerFolder(m)}$_sep${fileName(f)}',
        size: null,
        sha256: null,
      ),
  ];

  /// 打标模型在文件夹里找到的模型文件;自己下载过的不算。
  String? foundTagger(TaggerModel m) => m.id.startsWith(_local)
      ? m.id.substring(_local.length)
      : _found.taggers.where((d) => catalogTaggerFor(d) == m.id).firstOrNull;

  /// 要用的模型和标签表:自己下载的优先,其次是文件夹里找到的。都没有时为 null。
  ({String model, String labels})? taggerPaths(TaggerModel m) {
    if (m.files.isNotEmpty && ready(taggerFiles(m))) {
      final folder = _taggerFolder(m);
      return (
        model: '$folder$_sep${fileName(m.files.first)}',
        labels: '$folder$_sep${fileName(m.labels)}',
      );
    }
    final found = foundTagger(m);
    return found == null
        ? null
        : (model: found, labels: taggerLabelsAt(found, fileName(m.labels)));
  }

  /// 下载一个打标模型。要申请访问的模型得先在设置里填 HuggingFace Token。
  Future<String?> downloadTagger(TaggerModel m) {
    final token = hfToken().trim();
    if (m.gated && token.isEmpty) {
      return Future.value(tr('这个模型要先在 HuggingFace 申请访问,并在「设置 → 本地反推」填 Token'));
    }
    return download(
      m.id,
      taggerFiles(m),
      headers: m.gated ? {'Authorization': 'Bearer $token'} : const {},
      estimate: m.size,
    );
  }

  /// 换打标模型:阈值换成它的推荐值,已加载的模型放掉。
  void pickTagger(String id) {
    // 推理途中不换:正在用的模型会被关掉。
    if (id == taggerRepo || _tagging) return;
    _round++;
    update(() {
      taggerRepo = id;
      general = tagger.general;
      character = tagger.character;
      _tags = null;
      _scores = null;
    });
    _dropTagger();
  }

  /// 调阈值:上次推理的结果按新阈值重新筛。
  void setThresholds({double? general, double? character}) => update(() {
    this.general = general ?? this.general;
    this.character = character ?? this.character;
    _refilter();
  });

  void _refilter() {
    final scores = _scores;
    final m = tagger;
    _tags = scores == null
        ? null
        : decodeTags(
            scores,
            _labels,
            general: general,
            // OppaiOracle 只有一个阈值,也没有角色这一类。
            character: m.kind == TaggerKind.oppai ? general : character,
            logits: const {
              TaggerKind.pixai10,
              TaggerKind.clV1,
              TaggerKind.clV2,
            }.contains(m.kind),
            // 透明图贴到灰底上以后,模型会说「灰背景」,那不是图本来的。
            skip: m.kind == TaggerKind.oppai && _transparent
                ? const {'gray_background'}
                : const {},
          );
  }

  /// 用选中的打标模型给当前的图打标。失败时返回给用户看的原因。
  Future<String?> runTagger() async {
    final image = _image;
    if (image == null) return tr('先放一张图');
    if (_tagging) return tr('正在推理');
    final m = tagger;
    final paths = taggerPaths(m);
    if (paths == null) return tr('先下载模型');
    _tagging = true;
    final round = _round;
    _changed();
    String? problem;
    try {
      if (_taggerFor != m.id) {
        _dropTagger();
        _labels = parseLabels(m.kind, await File(paths.labels).readAsString());
        _tagger = await _loadOnnx(paths.model);
        _taggerFor = m.id;
      }
      final model = _tagger!;
      final pixelsIn = model.inputs.first;
      final layout = inputLayout(
        pixelsIn.shape,
        fallback: taggerFallbackSize(m),
      );
      final decoded = await decodeImage(
        image.bytes!,
        (w, h) => taggerImageSize(m.kind, w, h, layout.size),
      );
      final input = prepareTaggerInput(
        m.kind,
        decoded.rgba,
        decoded.width,
        decoded.height,
        size: layout.size,
        nchw: layout.nchw,
      );
      final mask = model.inputs
          .where((i) => i.name.toLowerCase() == 'padding_mask')
          .firstOrNull;
      final scores = await model.run({
        model.inputs
                .where((i) => i.name.toLowerCase() == 'pixel_values')
                .firstOrNull
                ?.name ??
            pixelsIn.name: (
          data: input.pixels,
          shape: input.shape,
        ),
        if (mask != null && input.mask != null)
          mask.name: (data: input.mask!, shape: [1, layout.size, layout.size]),
      });
      // 推理途中换了图:这次的结果不是眼前这张图的。
      if (round == _round) {
        _scores = scores;
        _transparent = input.transparent;
        _refilter();
      }
    } on OnnxException catch (e) {
      problem = e.message;
      _dropTagger();
    } on FormatException {
      problem = tr('标签表读不了');
      _dropTagger();
    } on FileSystemException catch (e) {
      problem = tr('读不了模型文件:{0}', [e.osError?.message ?? e.message]);
    } on Object catch (e) {
      problem = tr('推理失败({0})', [e.runtimeType]);
    }
    _tagging = false;
    _changed();
    return round == _round ? problem : null;
  }

  void _dropTagger() {
    final old = _tagger;
    _tagger = null;
    _taggerFor = null;
    old?.close().catchError((Object _) {});
  }
}
