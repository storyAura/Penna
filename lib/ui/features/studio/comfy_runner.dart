import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/harness/comfyui.dart';
import '../../../data/models/app_config.dart';
import '../../../data/services/comfy_images.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';

/// 出过的一张图:存在哪,用的哪条提示词。
typedef GeneratedImage = ({String path, String prompt, DateTime time});

/// 列表里最多留几张(文件都还在文件夹里)。
const _maxImages = 40;

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
