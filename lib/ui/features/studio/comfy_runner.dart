import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max, min;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/harness/attachment.dart';
import '../../../core/harness/comfy_workflow.dart';
import '../../../core/harness/comfyui.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/archive_store.dart';
import '../../../data/services/comfy_images.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';

part 'comfy_queue.dart';
part 'comfy_runner_flows.dart';

/// 建过的附件,按路径记着:每次重建都新建一个的话,图会重新读一遍、闪一下
/// (附件读出的内容按对象记,图片按内容判断是不是同一张)。这次运行出的图记的是原图。
// ponytail: 只增不减,一张图一个小对象,内容读一次留在内存里;出图上千张时再加上限。
final _attachments = <String, Attachment>{};

String _mimeOf(String name) =>
    imageMimes[name.substring(name.lastIndexOf('.') + 1).toLowerCase()] ??
    'image/png';

/// 出的图当成图片附件显示(点开看大图、复制),文件读不了时显示空的。
Attachment comfyImageAttachment(String path) =>
    _attachments[path] ??= Attachment.saved(
      name: File(path).uri.pathSegments.last,
      file: path,
      mime: _mimeOf(path),
    );

/// 用 ComfyUI 出过的图给档案库里 [id] 那一条做预览图(转成 WebP)。
Future<void> archivePreview(
  ArchiveStore archive,
  String? id,
  String? image,
) async {
  if (id == null || image == null) return;
  try {
    final webp = await toPreviewWebP(await File(image).readAsBytes());
    if (webp != null) archive.setImage(id, webp);
  } on FileSystemException catch (e) {
    debugPrint(tr('预览图没存上:{0}', [e.message]));
  }
}

/// 出过的一张图:存在哪,用的哪条提示词。
typedef GeneratedImage = ({String path, String prompt, DateTime time});

/// 列表里最多留几张(文件都还在文件夹里)。
const _maxImages = 40;

/// 连接情况:连上了吗、一问一答多少毫秒、ComfyUI 的版本;连不上时 [error] 是原因。
typedef ComfyStatus = ({bool connected, int ms, String version, String? error});

/// 内置文生图的名字(存进设置的是原文,显示时翻译)。
const builtinWorkflowName = '内置 · 文生图';

/// 两次测连接至少隔多久(两个页面的侧栏都会来问)。
const _checkGap = Duration(seconds: 5);

/// 用 ComfyUI 出图:把最终提示词交给它,出的图存进「设置 → ComfyUI」里的图片位置。
/// 记着出过的图(启动时从出图队列的记录里找回),存档案库时拿最新的一张做预览图。
class ComfyRunner extends ChangeNotifier {
  ComfyRunner(this.config) {
    unawaited(_loadJobs());
  }

  final ConfigService config;

  bool _running = false;
  String? _error;
  List<GeneratedImage> _images = const [];
  ComfyProgress? _progress;
  Object? _owner;
  ComfyStatus? _status;
  bool _checking = false;
  DateTime? _checkedAt;

  /// 这台 ComfyUI 的节点和下拉名单(模型、LoRA、采样器);[_optionsOf] 是读它时连的哪台。
  ComfyNodeInfo _info = const {};
  String? _optionsOf;

  /// 已经看过(或存过)眼前工作流的「地址|工作流 id」,同一台同一个只看一次。
  final _synced = <String>{};

  /// 各工作流在这台上缺什么(工作流 id → 当时的全文、缺的),换了名单就清掉。
  final _problems = <String, (String, List<String>)>{};

  /// 正在往回传图:传到哪了;没在传是 null。
  ComfyTransfer? _transfer;

  /// 每次开始、停止加一,作废之前那次的结果。
  int _run = 0;

  /// 出图队列(新的在前):排着的、正在出的、出完的([ComfyQueue])。
  List<ComfyJob> _jobs = const [];
  int _jobSeq = 0;

  /// 排着的单子出完时把结果交回去。
  final _waiters = <int, Completer<ComfyResult>>{};

  /// 排着写出图队列的那一串;还没写过是 null。
  Future<void>? _saving;

  /// 出图队列排着要写的都写完(关窗时等它,免得写到一半就退出)。
  /// 没写过时当场给一个做完的:不拿建这个对象时的那个(测试的假时钟里建的,真时钟里等不来)。
  Future<void> flushed() => _saving ?? Future.value();

  /// 出图队列,新的在前。
  List<ComfyJob> get jobs => _jobs;

  bool get running => _running;

  /// 正在出的这张进行到哪了(0 到 1);还在排队、或听不到进度时是 null。
  ComfyProgress? get progress => _progress;

  /// 跑完之后正在往回传图(云端的可能慢);没在传是 null。
  ComfyTransfer? get transfer => _transfer;

  /// 正在出的这张是谁要的(对话里那条回复的时刻;工作台的按钮是 null)。
  Object? get owner => _owner;

  /// 上一次出错的原因;成功或重新开始时清掉。
  String? get error => _error;

  /// 出过的图,新的在前。
  List<GeneratedImage> get images => _images;

  /// 最近一次测连接的结果;还没测过是 null。
  ComfyStatus? get status => _status;

  bool get checking => _checking;

  /// 扩展([ComfyFlows])里通知界面用它:`notifyListeners` 是受保护的。
  void _changed() => notifyListeners();

  /// 连眼前那台 ComfyUI(读历史、下图用)。
  ComfyClient get client => _client;

  ComfyClient get _client {
    final server = config.config.comfy.server;
    return ComfyClient(
      server.url,
      key: config.config.secrets[comfyKeyName(server.id)] ?? '',
    );
  }

  /// 测连接(侧栏定时来问);[full] 时连带重读节点和模型、LoRA 的名单。
  /// 换了一台也重读。刚测过不久的不再测。测的中途换了一台,测完再测新的那台。
  Future<void> check({bool full = false}) async {
    final last = _checkedAt;
    final url = config.config.comfy.server.url;
    if (_checking ||
        !full &&
            last != null &&
            DateTime.now().difference(last) < _checkGap &&
            _optionsOf == url) {
      return;
    }
    _checking = true;
    notifyListeners();
    final client = _client;
    try {
      final p = await client.ping();
      _status = (connected: true, ms: p.ms, version: p.version, error: null);
      unawaited(_syncFlow(client, url));
      if (full || _optionsOf != url) {
        final info = await client.objectInfo();
        // 读的时候换了一台:这份名单不是眼前那台的,不要。
        if (config.config.comfy.server.url == url) {
          _info = info;
          _optionsOf = url;
          _problems.clear();
        }
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
    if (config.config.comfy.server.url != url) unawaited(check(full: true));
  }

  /// 现在存图的文件夹。
  String get imageDir {
    final dir = config.config.comfy.imageDir;
    return dir.isEmpty ? defaultImageDir(config.dir) : dir;
  }

  /// 存档案库时配的图:用这条提示词出的最新一张(空白差别不算),先找这次出的,
  /// 再找出图队列的记录(最多 100 单,比这次留着的 40 张远);没有时 [any] 为真就给最新的一张。
  /// 2026-11-25 用户反馈保存系列配图有的没配上、有的配错:以前只比这次的 40 张、一字不差才算,
  /// 单条保存还会拿别的提示词出的图凑数。
  String? latestFor(String prompt, {bool any = true}) {
    final want = _plain(prompt);
    final hit =
        _stills.where((i) => _plain(i.prompt) == want).firstOrNull?.path ??
        [
          for (final j in jobs)
            if (_plain(j.prompt) == want)
              for (final path in j.images)
                if (!isVideoFile(path) && File(path).existsSync()) path,
        ].firstOrNull;
    return hit ?? (any ? _stills.firstOrNull?.path : null);
  }

  static String _plain(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// 出过的图里不是视频的(视频做不了预览图)。
  Iterable<GeneratedImage> get _stills =>
      _images.where((i) => !isVideoFile(i.path));

  /// 用 [prompt] 出一张,返回出的图和出错的原因(停止了两个都是空的)。
  /// 只由队列([ComfyQueue.generate])调,同一时间只有一张。
  /// [owner] 记着是谁要的,出图时界面据此显示进度。
  Future<ComfyResult> _execute(
    String prompt, {
    Object? owner,
    ComfySize? size,
  }) async {
    const none = <GeneratedImage>[];
    final run = ++_run;
    _running = true;
    _error = null;
    _progress = null;
    _transfer = null;
    _owner = owner;
    notifyListeners();
    final client = _client;
    final comfy = config.config.comfy;
    var saved = <GeneratedImage>[];
    String? error;
    try {
      final out = await client.run(
        // 空的是内置文生图。
        comfy.flow?.text ?? '',
        prompt,
        size: size,
        uploads: comfy.inputs[comfy.flow?.id ?? builtinWorkflowId] ?? const {},
        info: _optionsOf == comfy.server.url ? _info : const {},
        // 工作流里写着 {{lora}} 的框换成这里存的语法;没存过就是空串。
        loraSyntax: config.config.comfy.loraTextOf(config.config.comfy.flowId),
        canceled: () => run != _run,
        onDownload: (t) {
          if (run != _run) return;
          _transfer = t;
          notifyListeners();
        },
        onProgress: (p) {
          if (run != _run) return;
          _progress = p;
          notifyListeners();
        },
      );
      if (run != _run) return (images: none, error: null);
      final now = DateTime.now();
      saved = [];
      // 云端出的原图另存进「下载\Penna\<时刻>」;本机的 ComfyUI 自己的 output 里就有。
      final downloads = comfy.cloudDownload && !isLocalComfy(comfy.server.url)
          ? (await downloadsDir()).path
          : null;
      for (final image in out) {
        final small = await _forDisk(image);
        final path = saveComfyImage(
          imageDir,
          small.name,
          small.bytes,
          now,
        ).path;
        // 这次运行里显示、复制的是传回来的原图;磁盘上的是压过的。视频不当图片附件。
        if (!isVideoFile(image.name)) {
          _attachments[path] = Attachment.image(
            name: image.name,
            mime: _mimeOf(image.name),
            bytes: image.bytes,
          );
        }
        saved.add((path: path, prompt: prompt, time: now));
        if (downloads != null) {
          try {
            saveCloudCopy(downloads, image.name, image.bytes, now);
          } on FileSystemException catch (e) {
            // 图已经存进 Penna 的文件夹了,这份没存上不算出图失败。
            debugPrint('云端的图没存进「下载」:${e.message}');
          }
        }
      }
      if (run != _run) return (images: none, error: null);
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
    _transfer = null;
    _owner = null;
    _error = error;
    notifyListeners();
    return (images: saved, error: error);
  }

  /// 存盘用的那份:转成 WebP(尺寸不变);转不了或没变小就存原图。
  Future<ComfyImage> _forDisk(ComfyImage image) async {
    if (isVideoFile(image.name)) return image;
    try {
      final webp = await toStoredWebP(image.bytes);
      if (webp != null && webp.length < image.bytes.length) {
        return (name: 'image.webp', bytes: webp);
      }
    } on Object catch (e) {
      debugPrint('出的图没压成 WebP,存原图:${e.runtimeType}');
    }
    return image;
  }

  /// 停止:ComfyUI 那边的单子在下一次问进度时撤掉。
  void stop() {
    if (!_running) return;
    _run++;
    _running = false;
    _transfer = null;
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
