import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/harness/comfy_workflow.dart';
import '../../../core/harness/comfyui.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/comfy_images.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';

/// 出过的一张图:存在哪,用的哪条提示词。
typedef GeneratedImage = ({String path, String prompt, DateTime time});

/// 列表里最多留几张(文件都还在文件夹里)。
const _maxImages = 40;

/// 连接情况:连上了吗、一问一答多少毫秒、ComfyUI 的版本;连不上时 [error] 是原因。
typedef ComfyStatus = ({bool connected, int ms, String version, String? error});

/// 内置文生图的名字(存进设置的是原文,显示时翻译)。
const builtinWorkflowName = '内置 · 文生图';

/// LoRA 的可选名单在 [ComfyRunner] 里的键。
const _loraOptions = 'LoraLoaderModelOnly/lora_name';

/// 两次测连接至少隔多久(两个页面的侧栏都会来问)。
const _checkGap = Duration(seconds: 5);

/// 用 ComfyUI 出图:把最终提示词交给它,出的图存进「设置 → ComfyUI」里的图片位置。
/// 只在内存里记这次运行出过的图,存档案库时拿最新的一张做预览图。
class ComfyRunner extends ChangeNotifier {
  ComfyRunner(this.config);

  final ConfigService config;

  bool _running = false;
  String? _error;
  List<GeneratedImage> _images = const [];
  ComfyProgress? _progress;
  Object? _owner;
  ComfyStatus? _status;
  bool _checking = false;
  DateTime? _checkedAt;

  /// 「节点类型/输入名」→ 能选的文件名;[_optionsOf] 是读这份名单时的工作流全文。
  Map<String, List<String>> _options = const {};
  String? _optionsOf;

  /// 每次开始、停止加一,作废之前那次的结果。
  int _run = 0;

  bool get running => _running;

  /// 正在出的这张进行到哪了(0 到 1);还在排队、或听不到进度时是 null。
  ComfyProgress? get progress => _progress;

  /// 正在出的这张是谁要的(对话里那条回复的时刻;工作台的按钮是 null)。
  Object? get owner => _owner;

  /// 上一次出错的原因;成功或重新开始时清掉。
  String? get error => _error;

  /// 出过的图,新的在前。
  List<GeneratedImage> get images => _images;

  /// 最近一次测连接的结果;还没测过是 null。
  ComfyStatus? get status => _status;

  bool get checking => _checking;

  ComfyClient get _client => ComfyClient(
    config.config.comfy.url,
    key: config.config.secrets[comfyKeyName] ?? '',
  );

  /// 测连接(侧栏定时来问);[full] 时连带重读模型、LoRA 的名单。
  /// 工作流换了也重读。刚测过不久的不再测。
  Future<void> check({bool full = false}) async {
    final last = _checkedAt;
    if (_checking ||
        !full &&
            last != null &&
            DateTime.now().difference(last) < _checkGap &&
            _optionsOf == config.config.comfy.workflow) {
      return;
    }
    _checking = true;
    notifyListeners();
    final client = _client;
    try {
      final p = await client.ping();
      _status = (connected: true, ms: p.ms, version: p.version, error: null);
      final text = config.config.comfy.workflow;
      if (full || _optionsOf != text) {
        _options = await _readOptions(client, text);
        _optionsOf = text;
      }
    } on ComfyException catch (e) {
      _status = (connected: false, ms: 0, version: '', error: e.message);
    } on Object catch (e) {
      _status = (
        connected: false,
        ms: 0,
        version: '',
        error: tr('连接失败({0})', [e.runtimeType]),
      );
    } finally {
      _checking = false;
      _checkedAt = DateTime.now();
      notifyListeners();
    }
  }

  /// 工作流里每个模型加载器能选的模型,和 LoRA 能选的。
  Future<Map<String, List<String>>> _readOptions(
    ComfyClient client,
    String text,
  ) async {
    final wf = _parse(text);
    final slots = wf == null
        ? [(type: 'CheckpointLoaderSimple', key: 'ckpt_name')]
        : [for (final s in modelSlots(wf)) (type: s.type, key: s.key)];
    return {
      for (final s in slots)
        '${s.type}/${s.key}': await client.options(s.type, s.key),
      _loraOptions: await client.options('LoraLoaderModelOnly', 'lora_name'),
    };
  }

  /// [type] 节点的 [key] 能选哪些;还没读到是空的。
  List<String> optionsFor(String type, String key) =>
      _options['$type/$key'] ?? const [];

  List<String> get loraOptions => _options[_loraOptions] ?? const [];

  ComfyWorkflow? _parse(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return parseApiWorkflow(text);
    } on ComfyException {
      return null;
    }
  }

  /// 眼前用的工作流。内置的要连上 ComfyUI、知道第一个模型才有。
  ComfyWorkflow? get workflow {
    final text = config.config.comfy.workflow;
    if (text.trim().isNotEmpty) return _parse(text);
    final first = optionsFor('CheckpointLoaderSimple', 'ckpt_name').firstOrNull;
    return first == null ? null : defaultWorkflow(first);
  }

  /// 眼前用的工作流叫什么(已翻译)。
  String get workflowName {
    final c = config.config.comfy;
    return tr(c.workflow.trim().isEmpty ? builtinWorkflowName : c.workflowName);
  }

  /// 改工作流(换模型、改 LoRA),存进设置。内置的改过之后存成一份,名字照旧。
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
    final c = config.config.comfy;
    final text = jsonEncode(next);
    config.update(
      config.config.copyWith(
        comfy: c.copyWith(
          workflow: text,
          workflowName: c.workflow.trim().isEmpty
              ? builtinWorkflowName
              : c.workflowName,
        ),
      ),
    );
    // 只改了值,加载器还是那几个:名单不用重读。
    _optionsOf = text;
    notifyListeners();
    return null;
  }

  /// 按名字换模型(Agent 写的 `<comfy-model>`):在工作流的模型加载器能选的里找,
  /// 完整名字、去掉文件夹和后缀的名字对上,或只有一个包含它的。返回换上的文件名,或找不到的原因。
  ({String? model, String? problem}) switchModel(String wanted) {
    final wf = workflow;
    if (wf == null) return (model: null, problem: tr('还没连上 ComfyUI'));
    String short(String s) => s
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')
        .toLowerCase();
    final w = wanted.trim().toLowerCase();
    for (final slot in modelSlots(wf)) {
      final names = optionsFor(slot.type, slot.key);
      final hit =
          names.where((n) => n.toLowerCase() == w).firstOrNull ??
          names.where((n) => short(n) == short(w)).firstOrNull ??
          switch (names.where((n) => n.toLowerCase().contains(w)).toList()) {
            [final only] => only,
            _ => null,
          };
      if (hit == null) continue;
      final problem = edit((wf) => setModel(wf, slot.node, slot.key, hit));
      return (model: problem == null ? hit : null, problem: problem);
    }
    return (model: null, problem: tr('ComfyUI 里没有「{0}」', [wanted.trim()]));
  }

  /// 现在存图的文件夹。
  String get imageDir {
    final dir = config.config.comfy.imageDir;
    return dir.isEmpty ? defaultImageDir(config.dir) : dir;
  }

  /// 存档案库时配的图:用这条提示词出的最新一张;没有时 [any] 为真就给最新的一张。
  // ponytail: 改了几个字再存也配最新的一张,可能是别的页出的;配错了在档案库里换图。
  String? latestFor(String prompt, {bool any = true}) =>
      _images.where((i) => i.prompt == prompt).firstOrNull?.path ??
      (any ? _images.firstOrNull?.path : null);

  /// 用 [prompt] 出图,返回出的图和出错的原因(停止了两个都是空的)。
  /// 已经在出图时不出,报原因。[owner] 记着是谁要的,出图时界面据此显示进度。
  Future<({List<GeneratedImage> images, String? error})> generate(
    String prompt, {
    Object? owner,
  }) async {
    const none = <GeneratedImage>[];
    if (_running) return (images: none, error: tr('正在出另一张图'));
    if (prompt.trim().isEmpty) {
      return (images: none, error: tr('没有可出图的提示词'));
    }
    final run = ++_run;
    _running = true;
    _error = null;
    _progress = null;
    _owner = owner;
    notifyListeners();
    final settings = config.config.comfy;
    final client = ComfyClient(
      settings.url,
      key: config.config.secrets[comfyKeyName] ?? '',
    );
    var saved = <GeneratedImage>[];
    String? error;
    try {
      final out = await client.run(
        settings.workflow,
        prompt,
        canceled: () => run != _run,
        onProgress: (p) {
          if (run != _run) return;
          _progress = p;
          notifyListeners();
        },
      );
      if (run != _run) return (images: none, error: null);
      final now = DateTime.now();
      saved = [
        for (final image in out)
          (
            path: saveComfyImage(imageDir, image.name, image.bytes, now).path,
            prompt: prompt,
            time: now,
          ),
      ];
      _images = List.unmodifiable(
        [...saved.reversed, ..._images].take(_maxImages),
      );
    } on ComfyException catch (e) {
      if (!e.canceled) error = e.message;
    } on FileSystemException catch (e) {
      error = tr('图片没存上:{0}', [e.message]);
    } on Object catch (e) {
      // 没料到的错误只报类型,原文可能带着地址里的 Key。
      error = tr('出图失败({0})', [e.runtimeType]);
    }
    if (run != _run) return (images: none, error: null);
    _running = false;
    _owner = null;
    _error = error;
    notifyListeners();
    return (images: saved, error: error);
  }

  /// 停止:ComfyUI 那边的单子在下一次问进度时撤掉。
  void stop() {
    if (!_running) return;
    _run++;
    _running = false;
    _owner = null;
    notifyListeners();
  }

  /// 换存图的位置并把已有的图搬过去;返回搬了几张。
  Future<int> moveTo(String dir) async {
    final from = imageDir;
    final moved = await moveComfyImages(from, dir);
    // 搬过去的图跟着换路径(重名没搬的那张原处还在,不换)。
    _images = List.unmodifiable([
      for (final i in _images)
        if (File(i.path).existsSync())
          i
        else
          (
            path:
                '$dir${Platform.pathSeparator}${File(i.path).uri.pathSegments.last}',
            prompt: i.prompt,
            time: i.time,
          ),
    ]);
    config.update(
      config.config.copyWith(
        comfy: config.config.comfy.copyWith(imageDir: dir),
      ),
    );
    notifyListeners();
    return moved;
  }
}
