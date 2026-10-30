part of 'local_model.dart';

// 给 Agent 调用的本地反推(`<reverse-image>`、`<download-model>`,见 `local_tools.dart`):
// 按名字找模型,装了就直接跑,没装就把装了的和能下载的列给它,让它问用户。
// 交给模型的话不翻译;给用户看的那一行记录要翻译。

/// 一次调用的结果:交还给模型的一段话,和列在回复上给用户看的一行。
typedef LocalToolResult = ({String text, String note});

extension LocalAgent on LocalModel {
  /// 跑一次 [call];[image] 是要反推的图(没有时为 null)。
  Future<LocalToolResult> runTool(LocalToolCall call, Attachment? image) async {
    try {
      return switch ((call.action, call.kind)) {
        (toolReverse, 'tag') => await _tagReverse(call.model, image),
        (toolReverse, _) => await _nlReverse(call.model, image),
        (_, 'runtime') => await _downloadRuntime(),
        (_, 'tag') => await _downloadTagger(call.model),
        _ => await _downloadCaption(call.model),
      };
    } on Object catch (e) {
      // 只报类型,原文可能带着路径或 Token。
      return (
        text: '本地工具出错了(${e.runtimeType}),告诉用户换个办法或去「本地反推」页手动试。',
        note: tr('本地反推出错({0})', [e.runtimeType]),
      );
    }
  }

  /// 告诉 Agent 本机有哪些反推模型:装了的、当前选中的、能下载的。
  String get agentPrompt {
    final tags = [for (final m in taggers) (m, taggerPaths(m) != null)];
    final nls = [for (final m in captionModels) (m, captionPaths(m) != null)];
    String names(Iterable<String> list) => list.isEmpty ? '没有' : list.join('、');
    return '【本地反推】本机能跑的反推模型。'
        '打标模型(出 Danbooru 标签,<reverse-image kind="tag">):'
        '当前选中「${tagger.name}」;已装:${names([for (final (m, ok) in tags)
          if (ok) m.name])};没装、可以下载:${names([for (final (m, ok) in tags)
          if (!ok && m.files.isNotEmpty) m.name])}。\n'
        '看图模型(写自然语言描述,<reverse-image kind="nl">):'
        '当前选中「${pickedCaption?.name ?? (modelPath.isEmpty ? '没有' : fileName(modelPath))}」;'
        '已装:${names([for (final (m, ok) in nls)
          if (ok) m.name])};没装、可以下载:${names([for (final (m, ok) in nls)
          if (!ok) m.name])};'
        'llama.cpp 运行时(Florence-2 以外的看图模型要它):${serverExe == null ? '没装' : '已装'}。';
  }

  // —— 反推 ——

  Future<LocalToolResult> _tagReverse(String query, Attachment? image) async {
    final m = query.isEmpty
        ? tagger
        : _match(query, taggers, (m) => m.id, (m) => m.name);
    if (m == null) return _notFound('打标模型', query, taggers, (m) => m.name);
    if (taggerPaths(m) == null) {
      return _missing(m.name, 'tag', m.size, [
        for (final o in taggers)
          if (taggerPaths(o) != null) o.name,
      ], gated: m.gated && hfToken().trim().isEmpty);
    }
    if (image == null) return _noImage;
    if (_tagging) return _busy;
    setImage(image);
    pickTagger(m.id);
    final problem = await runTagger();
    final t = _tags;
    if (problem != null || t == null) {
      return _failed(m.name, problem ?? '没有结果');
    }
    String join(List<TagScore> list) =>
        list.isEmpty ? '无' : list.map((s) => s.tag).join(', ');
    return (
      text:
          '<reverse-results>\n用「${m.name}」反推出的 Danbooru 标签(按把握从高到低):\n'
          '角色:${join(t.characters)}\n通用:${join(t.general)}\n'
          '分级:${t.rating ?? '无'}\n</reverse-results>'
          // 用户反馈:认出了丰川祥子和三角初华,转成自然语言后只剩「蓝发少女」。
          '${t.characters.isEmpty ? '' : '\n认出的角色要写进提示词:写标签就把上面的角色标签原样放最前;'
                    '写成句子也要点名(用角色名和作品,比如 "Togawa Sakiko from BanG Dream!"),'
                    '后面用名字指代谁在做什么,不要只写成「蓝发少女」这种外貌描述。'}',
      note: tr('Tag 反推 · {0} · {1} 个标签', [
        m.name,
        t.characters.length + t.general.length,
      ]),
    );
  }

  Future<LocalToolResult> _nlReverse(String query, Attachment? image) async {
    final m = query.isEmpty
        ? pickedCaption
        : _match(query, captionModels, (m) => m.id, (m) => m.name);
    if (query.isNotEmpty && m == null) {
      return _notFound('看图模型', query, captionModels, (m) => m.name);
    }
    if (m == null && modelPath.isEmpty) {
      return (
        text: '用户还没选看图模型。照【本地反推】里列的,用 <options> 问他用哪一个。',
        note: tr('还没选看图模型'),
      );
    }
    if (m != null && captionPaths(m) == null) {
      return _missing(
        m.name,
        'nl',
        captionFiles(m).fold<int>(0, (a, f) => a + (f.size ?? 0)),
        [
          for (final o in captionModels)
            if (captionPaths(o) != null) o.name,
        ],
      );
    }
    if (image == null) return _noImage;
    if (_captioning || _starting) return _busy;
    if (m != null) useCaption(m);
    if (!florenceMode) {
      if (serverExe == null) {
        return (
          text:
              'Florence-2 以外的看图模型要 llama.cpp 运行时,它还没装(下载约 ${_mb(llamaRuntimeSize)})。'
              '用 <options> 问用户要不要下载;他同意后输出 <download-model kind="runtime"></download-model>,'
              '下好后再反推。',
          note: tr('llama.cpp 运行时还没装'),
        );
      }
      // 跑着的服务装的是别的模型:换成这一个要重启。
      if (server.running && server.spec?.model != modelPath) {
        await stopServer();
      }
      if (!server.running) {
        final problem = await startServer();
        if (problem != null) return _failed(_captionName, problem);
      }
    }
    setImage(image);
    final problem = await runCaption();
    if (problem != null) return _failed(_captionName, problem);
    return (
      text:
          '<reverse-results>\n用「$_captionName」看图写出的描述:\n$_caption\n</reverse-results>',
      note: tr('NL 反推 · {0}', [_captionName]),
    );
  }

  String get _captionName => pickedCaption?.name ?? fileName(modelPath);

  // —— 下载 ——

  Future<LocalToolResult> _downloadTagger(String query) async {
    final m = _match(query, taggers, (m) => m.id, (m) => m.name);
    if (m == null) return _notFound('打标模型', query, taggers, (m) => m.name);
    if (taggerPaths(m) != null) return _ready(m.name, 'tag');
    return _downloaded(m.name, 'tag', await downloadTagger(m));
  }

  Future<LocalToolResult> _downloadCaption(String query) async {
    final m = _match(query, captionModels, (m) => m.id, (m) => m.name);
    if (m == null) {
      return _notFound('看图模型', query, captionModels, (m) => m.name);
    }
    if (captionPaths(m) != null) return _ready(m.name, 'nl');
    return _downloaded(m.name, 'nl', await downloadCaption(m));
  }

  Future<LocalToolResult> _downloadRuntime() async {
    if (serverExe != null) {
      return (text: 'llama.cpp 运行时已经装好了,可以直接反推。', note: tr('运行时已装好'));
    }
    final problem = await downloadRuntime();
    return problem == null
        ? (text: 'llama.cpp 运行时下好了,现在可以反推了。', note: tr('已下载 llama.cpp 运行时'))
        : _failed('llama.cpp 运行时', problem);
  }

  // —— 几种回话 ——

  LocalToolResult _missing(
    String name,
    String kind,
    int size,
    List<String> installed, {
    bool gated = false,
  }) => (
    text:
        '「$name」本机还没装(下载约 ${_mb(size)})。'
        '本机已装的同类模型:${installed.isEmpty ? '没有' : installed.join('、')}。'
        '${gated ? '这个模型要先在 HuggingFace 申请访问,并在「设置 → 本地反推」填 Token,告诉用户这一点。' : ''}'
        '不要自己决定:用 <options> 问用户是下载它,还是改用已装的哪一个'
        '(选项写成"下载 $name"和"用 某某",已装的一个一项)。'
        '他选下载时输出 <download-model kind="$kind">$name</download-model>;'
        '选已装的就用那个模型反推。',
    note: tr('「{0}」还没装', [name]),
  );

  LocalToolResult _notFound<T>(
    String what,
    String query,
    List<T> all,
    String Function(T) name,
  ) => (
    text:
        '没有叫「$query」的$what。能用的名字:${all.map(name).join('、')}。'
        '对不上用户说的就用 <options> 问他是哪一个。',
    note: tr('没找到「{0}」', [query]),
  );

  LocalToolResult get _noImage =>
      (text: '没有图可以反推:用户没在对话里发图,「本地反推」页上也没放图。请用户先发一张图。', note: tr('没有可以反推的图'));

  LocalToolResult get _busy =>
      (text: '本地模型正在忙(在推理或启动),告诉用户稍等一会儿再说一次。', note: tr('本地模型正在忙'));

  LocalToolResult _failed(String name, String problem) => (
    text: '用「$name」没跑成:$problem。照实告诉用户,不要编结果。',
    note: tr('「{0}」没跑成:{1}', [name, problem]),
  );

  LocalToolResult _ready(String name, String kind) => (
    text:
        '「$name」已经装好了,直接用 <reverse-image kind="$kind">$name</reverse-image> 反推。',
    note: tr('「{0}」已装好', [name]),
  );

  LocalToolResult _downloaded(String name, String kind, String? problem) =>
      problem == null
      ? (
          text:
              '「$name」下好了。现在用 <reverse-image kind="$kind">$name</reverse-image> 反推用户的图。',
          note: tr('已下载「{0}」', [name]),
        )
      : _failed(name, problem);
}

/// 按名字找:先找名字或 id 一模一样的,再找包含它的(不分大小写)。
T? _match<T>(
  String query,
  List<T> all,
  String Function(T) id,
  String Function(T) name,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return null;
  bool same(T m) => name(m).toLowerCase() == q || id(m).toLowerCase() == q;
  bool near(T m) =>
      name(m).toLowerCase().contains(q) || id(m).toLowerCase().contains(q);
  return all.where(same).firstOrNull ?? all.where(near).firstOrNull;
}

String _mb(int bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(1)} GB'
    : '${(bytes / (1 << 20)).round()} MB';
