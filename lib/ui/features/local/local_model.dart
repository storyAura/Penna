import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../../../core/harness/attachment.dart';
import '../../../core/harness/local/caption_catalog.dart';
import '../../../core/harness/local/download.dart';
import '../../../core/harness/local/florence.dart';
import '../../../core/harness/local/llama_server.dart';
import '../../../core/harness/local/local_tools.dart';
import '../../../core/harness/local/model_scan.dart';
import '../../../core/harness/local/model_sources.dart';
import '../../../core/harness/local/tagger.dart';
import '../../../core/harness/providers/llm_http.dart';
import '../../../data/services/florence_engine.dart';
import '../../../data/services/onnx_model.dart';
import '../../../l10n/l10n.dart';

part 'local_agent.dart';
part 'local_caption.dart';
part 'local_llm.dart';
part 'local_tagger.dart';

/// 看图描述的一条要求:名字和正文。
typedef CaptionPrompt = ({String name, String text});

/// 看图写自然语言时默认的要求。
const defaultCaptionPrompt =
    'Describe this image in detail as a prompt for an image generation model: '
    'subject, appearance, clothing, pose, expression, background, composition, '
    'lighting and art style. Output only the description in English.';

/// 新装时给的几条要求,用户可以改、删、加。
const defaultCaptionPrompts = <CaptionPrompt>[
  (name: '详细描述', text: defaultCaptionPrompt),
  (
    name: '简短描述',
    text:
        'Describe this image in one or two sentences as a prompt for an image '
        'generation model. Output only the description in English.',
  ),
  (
    name: '标签',
    text:
        'List Danbooru-style tags for this image: lowercase, separated by '
        'commas, most important first. Output only the tags.',
  ),
];

/// 下载的进度:已有多少字节,总共多少(不知道时为 null)。
typedef Progress = ({int received, int? total});

typedef StreamChatFn = Stream<String> Function(LlmRequest request);

/// 本地反推页的状态:Tag 反推(打标模型,见 [LocalTagger])和 NL 反推(看图模型,见 [LocalCaption])。
/// 设置存在「文档\Penna\local.json」,模型和运行时在「文档\Penna\models」「runtime」下。
class LocalModel extends ChangeNotifier {
  /// [dir] 为 null 时只在内存里(测试用),也不能下载。
  LocalModel({
    this.dir,
    required this.streamChat,
    LlamaServer? server,
    Future<OnnxModel> Function(String path)? loadOnnx,
    String Function()? hfToken,
    this.autoFolders = const [],
  }) : server = server ?? LlamaServer(),
       hfToken = hfToken ?? (() => ''),
       _loadOnnx = loadOnnx ?? OnnxModel.load {
    // 服务自己退出了(崩了、被别的程序关了),界面跟着变回未启动。
    this.server.onExit = notifyListeners;
  }

  final Directory? dir;
  final StreamChatFn streamChat;
  final LlamaServer server;
  final Future<OnnxModel> Function(String path) _loadOnnx;

  /// HuggingFace 的 Token(存在设置的机密里);下要申请访问的模型时用。
  final String Function() hfToken;

  /// 不用添加也会找的文件夹(HuggingFace、ModelScope 的缓存,见 [cacheFolders])。
  final List<String> autoFolders;

  // —— 存盘的设置 ——
  /// 模型的下载来源(见 [modelSources]),和「自定义」时的地址。
  String source = 'huggingface';
  String customSource = '';

  /// llama.cpp 运行时先走 GitHub 加速;关着时先直连 GitHub,下不了再走加速。
  bool githubAccel = false;

  /// 选中的打标模型的 id(WD14 的就是仓库名,和以前存的对得上)。
  String taggerRepo = _defaultTagger.id;
  double general = _defaultTagger.general;
  double character = _defaultTagger.character;

  /// 自己选的 llama-server.exe;空串用下载的运行时。
  String exePath = '';
  String modelPath = '';
  String mmprojPath = '';
  int port = 8091;
  int context = 4096;
  int gpuLayers = -1;

  /// 看图描述的几条要求(GGUF 模型用),和选中的是第几条。
  List<CaptionPrompt> captionPrompts = defaultCaptionPrompts;
  int promptIndex = 0;

  /// 用户加的模型文件夹:连同子文件夹一起找已有的模型,找到的直接用,不用再下。
  List<String> modelFolders = const [];

  /// 两个模型列表用户拖好的顺序(系列和模型的 id 的先后);没列的排在后面。
  List<String> taggerOrder = const [];
  List<String> captionOrder = const [];

  /// 各看图模型选的量化档(模型 id → 档名)。
  Map<String, String> quantPicks = const {};

  /// 选中的清单看图模型的 id;选的是自己的 GGUF 时为空串。
  String captionPick = '';

  /// Florence-2 用的指令。
  String florenceTask = florenceTaskLabels.keys.first;

  /// LLM 反推选的模型(最多 [maxLlmPicks] 个),一起跑、并排显示。
  List<LlmPick> llmPicks = const [];

  // —— 只在内存里的 ——
  Attachment? _image;
  final _downloads = <String, Progress>{};
  final _cancels = <String, DownloadCancel>{};
  OnnxModel? _tagger;
  String? _taggerFor;
  List<TagLabel> _labels = const [];
  bool _tagging = false;
  TagResult? _tags;

  /// 换图、换模型时加一;推理途中变了,那次的结果就不要了,免得挂到新图上。
  int _round = 0;

  /// 上次推理每个标签的把握;调阈值时拿它重新筛,不用再跑模型。
  List<double>? _scores;

  /// 上次打标的那张图有透明的地方。
  bool _transparent = false;
  bool _starting = false;
  bool _captioning = false;
  String _caption = '';
  FlorenceEngine? _florence;
  String? _florenceFor;

  /// LLM 反推各模型的结果。
  Map<LlmPick, LlmResult> _llmResults = const {};

  /// 换图时加一,作废还在路上的 LLM 反推(不跟 [_round]:换打标模型不该打断它)。
  int _llmRound = 0;

  Attachment? get image => _image;
  bool get tagging => _tagging;
  TagResult? get tags => _tags;
  bool get starting => _starting;
  bool get captioning => _captioning;
  String get caption => _caption;
  bool get serverRunning => server.running;

  FoundModels _found = noModels;
  bool _scanning = false;

  /// 上次在模型文件夹里扫到的东西。
  FoundModels get found => _found;
  bool get scanning => _scanning;

  /// 扫到了什么,给人看的一句话。
  String get foundSummary {
    if (_scanning) return tr('扫描中…');
    final f = _found;
    final counts = [
      if (f.taggers.isNotEmpty) tr('{0} 个打标模型', [f.taggers.length]),
      if (f.ggufs.isNotEmpty) tr('{0} 个 GGUF 模型', [f.ggufs.length]),
      if (f.florences.isNotEmpty) tr('{0} 个 Florence-2', [f.florences.length]),
      if (f.servers.isNotEmpty) 'llama-server',
    ];
    if (counts.isEmpty) return tr('没有找到可用的模型');
    return tr('找到 {0}{1}', [
      counts.join(tr('、')),
      f.truncated ? tr('(文件太多,只查了一部分)') : '',
    ]);
  }

  /// 正在下载的东西(按 [download] 时给的名字)和进度。
  Progress? progressOf(String key) => _downloads[key];
  bool get downloading => _downloads.isNotEmpty;

  String get _sep => Platform.pathSeparator;
  String get _home => dir?.path ?? '';

  RemoteFile get _runtimeZip => (
    url: llamaRuntimeUrl,
    path: '$_home${_sep}runtime$_sep$llamaRuntimeFile',
    size: llamaRuntimeSize,
    sha256: llamaRuntimeSha256,
  );

  Directory get _runtimeDir =>
      Directory('$_home${_sep}runtime${_sep}llama.cpp-$llamaCppTag');

  bool ready(List<RemoteFile> files) =>
      dir != null && files.every(isDownloaded);

  /// 要用的 llama-server:自己选的优先,其次是下载好的运行时,再次是文件夹里找到的。
  String? get serverExe => exePath.isNotEmpty
      ? exePath
      : (dir == null ? null : findServerExe(_runtimeDir)?.path) ??
            _found.servers.firstOrNull;

  // —— 模型文件夹 ——

  /// 加一个模型文件夹,扫完才返回。
  Future<void> addFolder(String path) async {
    if (modelFolders.contains(path)) return;
    update(() => modelFolders = List.unmodifiable([...modelFolders, path]));
    await rescan();
  }

  void removeFolder(String path) {
    update(
      () => modelFolders = List.unmodifiable(
        modelFolders.where((f) => f != path),
      ),
    );
    rescan();
  }

  /// 重新扫一遍模型文件夹。在别的 isolate 里扫,文件多也不卡界面。
  Future<void> rescan() async {
    final folders = modelFolders;
    final roots = [...folders, ...autoFolders];
    _scanning = true;
    notifyListeners();
    FoundModels result = noModels;
    try {
      result = await Isolate.run(() => scanModelFolders(roots));
    } on Object catch (e) {
      debugPrint(tr('扫描模型文件夹失败:{0}', [e.runtimeType]));
    }
    // 扫的时候文件夹又变了:以后面那次为准。
    if (!identical(folders, modelFolders)) return;
    _found = result;
    _scanning = false;
    notifyListeners();
  }

  // —— 改设置 ——

  /// 通知界面。扩展里不能直接调 notifyListeners(它是受保护的)。
  void _changed() => notifyListeners();

  void update(void Function() change) {
    change();
    notifyListeners();
    _save();
  }

  void setImage(Attachment? image) {
    _round++;
    _llmRound++;
    _image = image;
    _tags = null;
    _scores = null;
    _caption = '';
    _llmResults = const {};
    notifyListeners();
  }

  // —— 下载 ——

  /// 下 [f] 时依次试的地址:模型按「下载来源」,llama.cpp 运行时按「GitHub 加速」。
  /// [gated] 的要带 Token,只发给 HuggingFace 和它的加速站。
  List<String> _urlsOf(RemoteFile f, {bool gated = false}) {
    final urls = modelUrls(f.url, source, custom: customSource, gated: gated);
    return urls.length > 1 ? urls : downloadUrls(f, proxyFirst: githubAccel);
  }

  /// 依次下载 [files],进度记在 [key] 下。文件大小不全知道时,进度按 [estimate] 算。
  /// 失败时返回给用户看的原因。
  Future<String?> download(
    String key,
    List<RemoteFile> files, {
    Map<String, String> headers = const {},
    int? estimate,
  }) async {
    if (dir == null) return tr('没有存放的地方');
    if (_downloads.containsKey(key)) return tr('正在下载');
    final cancel = _cancels[key] = DownloadCancel();
    final sizes = [for (final f in files) f.size];
    final total = sizes.contains(null)
        ? estimate
        : sizes.fold<int>(0, (a, b) => a + b!);
    var before = 0;
    _downloads[key] = (received: 0, total: total);
    notifyListeners();
    String? problem;
    try {
      for (final f in files) {
        await downloadFile(
          f,
          cancel: cancel,
          headers: headers,
          urls: _urlsOf(f, gated: headers.isNotEmpty),
          onProgress: (got, all) {
            _downloads[key] = (
              received: before + got,
              total: total ?? (files.length == 1 ? all : null),
            );
            notifyListeners();
          },
        );
        before += File(f.path).lengthSync();
      }
    } on DownloadException catch (e) {
      problem = e.message;
    } on FileSystemException catch (e) {
      problem = tr('存不下来:{0}', [e.osError?.message ?? e.message]);
    }
    _downloads.remove(key);
    _cancels.remove(key);
    notifyListeners();
    return problem;
  }

  void cancelDownload(String key) => _cancels[key]?.cancel();

  /// 删掉下载好的文件(连同没下完的)。删不了时返回给用户看的原因。
  Future<String?> remove(List<RemoteFile> files) async {
    final paths = {for (final f in files) f.path};
    if (server.running &&
        (paths.contains(modelPath) || paths.contains(mmprojPath))) {
      return tr('这个模型正在用,先停止服务');
    }
    if (_tagging && paths.any((p) => p.endsWith(taggerModelFile))) {
      return tr('正在推理');
    }
    if (paths.any((p) => p.endsWith(taggerModelFile))) _dropTagger();
    if (paths.any((p) => _florenceFor != null && p.startsWith(_florenceFor!))) {
      _dropFlorence();
    }
    String? problem;
    try {
      for (final path in paths) {
        for (final file in [File(path), File('$path.part')]) {
          if (file.existsSync()) await file.delete();
        }
      }
    } on FileSystemException catch (e) {
      problem = tr('删不掉:{0}', [e.osError?.message ?? e.message]);
    }
    // 选着的模型删掉了就不再指着它。
    if (paths.contains(modelPath) || paths.contains(mmprojPath)) {
      update(() {
        if (paths.contains(modelPath)) modelPath = '';
        if (paths.contains(mmprojPath)) mmprojPath = '';
      });
    } else {
      notifyListeners();
    }
    return problem;
  }

  /// 下载并解开 llama.cpp 运行时。
  Future<String?> downloadRuntime() async {
    // 固定下的是 Windows 的 Vulkan 版(见 llama_server.dart 的 llamaRuntimeUrl),
    // 别的平台没有对应的包,得自己装 llama.cpp 再指过来。
    if (!Platform.isWindows) {
      return tr('这个平台请自行下载 llama.cpp 运行时,再用「选择 llama-server」指过来');
    }
    final zip = _runtimeZip;
    final problem = await download('runtime', [zip]);
    if (problem != null) return problem;
    // 先解到旁边的临时文件夹,全解完才换上:解到一半失败时不会留下缺文件的运行时。
    // 解压放到另一个 isolate 里,界面不卡。
    final target = _runtimeDir.path;
    final temp = '$target.tmp';
    try {
      final from = zip.path;
      await Isolate.run(() => _extractInto(from, temp, target));
      await File(zip.path).delete();
    } on Object catch (e) {
      // 下好的压缩包留着,再点一次直接重新解压。
      return tr('运行时解压失败({0})', [e.runtimeType]);
    }
    notifyListeners();
    return serverExe == null ? tr('运行时里没找到 llama-server.exe') : null;
  }

  // —— 存盘 ——

  File? get _file => dir == null ? null : File('$_home${_sep}local.json');

  Map<String, Object> toJson() => {
    'source': source,
    'customSource': customSource,
    'githubAccel': githubAccel,
    'taggerRepo': taggerRepo,
    'general': general,
    'character': character,
    'exePath': exePath,
    'modelPath': modelPath,
    'mmprojPath': mmprojPath,
    'port': port,
    'context': context,
    'gpuLayers': gpuLayers,
    'captionPrompts': [
      for (final p in captionPrompts) {'name': p.name, 'text': p.text},
    ],
    'promptIndex': promptIndex,
    'modelFolders': modelFolders,
    'taggerOrder': taggerOrder,
    'captionOrder': captionOrder,
    'quantPicks': quantPicks,
    'captionPick': captionPick,
    'florenceTask': florenceTask,
    'llmPicks': [
      for (final p in llmPicks) {'llm': p.llm, 'model': p.model},
    ],
  };

  void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(toJson()));
    } on FileSystemException catch (e) {
      debugPrint(tr('本地反推的设置没存上:{0}', [e.message]));
    }
  }

  Future<void> load() async {
    final file = _file;
    if (file != null && file.existsSync()) await _read(file);
    // 不等它扫完:文件夹大的话要好一会儿,不拦着程序启动。
    if (modelFolders.isNotEmpty || autoFolders.isNotEmpty) rescan();
  }

  Future<void> _read(File file) async {
    try {
      final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      source = j['source'] as String? ?? source;
      customSource = j['customSource'] as String? ?? '';
      githubAccel = j['githubAccel'] as bool? ?? false;
      taggerRepo = j['taggerRepo'] as String? ?? taggerRepo;
      general = (j['general'] as num?)?.toDouble() ?? general;
      character = (j['character'] as num?)?.toDouble() ?? character;
      exePath = j['exePath'] as String? ?? '';
      modelPath = j['modelPath'] as String? ?? '';
      mmprojPath = j['mmprojPath'] as String? ?? '';
      port = j['port'] as int? ?? port;
      context = j['context'] as int? ?? context;
      gpuLayers = j['gpuLayers'] as int? ?? gpuLayers;
      final prompts = [
        for (final p in j['captionPrompts'] as List? ?? const [])
          (name: (p as Map)['name'] as String, text: p['text'] as String),
      ];
      // 以前只有一条要求:改过的那条留着,接在默认的几条后面并选中它。
      final old = j['captionPrompt'] as String?;
      if (prompts.isEmpty && old != null && old != defaultCaptionPrompt) {
        prompts.addAll([...defaultCaptionPrompts, (name: '我的要求', text: old)]);
      }
      if (prompts.isNotEmpty) {
        captionPrompts = List.unmodifiable(prompts);
        promptIndex = (j['promptIndex'] as int? ?? prompts.length - 1).clamp(
          0,
          prompts.length - 1,
        );
      }
      modelFolders = List.unmodifiable([
        for (final f in j['modelFolders'] as List? ?? const []) f as String,
      ]);
      List<String> strings(String key) => List.unmodifiable([
        for (final v in j[key] as List? ?? const []) v as String,
      ]);
      taggerOrder = strings('taggerOrder');
      captionOrder = strings('captionOrder');
      quantPicks = Map.unmodifiable(
        (j['quantPicks'] as Map? ?? const {}).cast<String, String>(),
      );
      captionPick = j['captionPick'] as String? ?? '';
      florenceTask = j['florenceTask'] as String? ?? florenceTask;
      llmPicks = List.unmodifiable([
        for (final p in j['llmPicks'] as List? ?? const [])
          (llm: (p as Map)['llm'] as String, model: p['model'] as String),
      ]);
      notifyListeners();
    } on Object {
      // 读不了就用默认设置,不拦着程序启动。
    }
  }

  @override
  void dispose() {
    for (final c in _cancels.values) {
      c.cancel();
    }
    _dropTagger();
    _dropFlorence();
    server.stop();
    super.dispose();
  }
}

/// 读出图片的像素,缩成 [size] 按原图长宽算出的大小。透明度是没乘进颜色的。
Future<({Uint8List rgba, int width, int height})> decodeImage(
  Uint8List bytes,
  ({int width, int height}) Function(int width, int height) size,
) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final fit = size(descriptor.width, descriptor.height);
  final codec = await descriptor.instantiateCodec(
    targetWidth: fit.width,
    targetHeight: fit.height,
  );
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  if (data == null) throw OnnxException(tr('读不了这张图'));
  return (
    rgba: data.buffer.asUint8List(),
    width: fit.width,
    height: fit.height,
  );
}

/// 把 [zip] 解到 [temp],全解完再换成 [target]。
Future<void> _extractInto(String zip, String temp, String target) async {
  final dir = Directory(temp);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  await extractFileToDisk(zip, temp);
  final old = Directory(target);
  if (old.existsSync()) old.deleteSync(recursive: true);
  dir.renameSync(target);
}

/// 新装时默认选的打标模型。
final _defaultTagger = taggerModels.firstWhere(
  (m) => m.id == 'SmilingWolf/wd-eva02-large-tagger-v3',
);
