import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../../../core/harness/local/download.dart';
import '../../../data/services/skill_store.dart' show safeZipPath;
import '../../../l10n/l10n.dart';
import 'pose_download.dart';

export 'pose_download.dart' show PoseSource;

/// 一个视角:[angle] 是 front / diag / side / above / below,[path] 是图片的完整路径。
typedef PoseView = ({String angle, String path});

/// 图集里的一个姿势。[tags] 照原样(`people:2`、`sensitive:suggestive_series` 这类)。
typedef Pose = ({
  String id,
  String category,
  List<String> tags,
  String description,
  List<PoseView> views,
});

/// 作者标出的「性感 / 双人」系列,默认藏起来(图集说明里的请求)。
bool isSuggestive(Pose p) => p.tags.contains('sensitive:suggestive_series');

/// 读 poses.json;[root] 是图集所在的文件夹,图片路径照它拼成完整的。
/// 格式不对时抛 [FormatException]。
List<Pose> parsePoses(Map<String, dynamic> json, String root) {
  final poses = json['poses'];
  if (poses is! List) throw const FormatException('poses');
  String full(Object? rel) {
    final path = safeZipPath('$rel');
    if (path == null || path.isEmpty) throw const FormatException('path');
    return '$root${Platform.pathSeparator}'
        '${path.replaceAll('/', Platform.pathSeparator)}';
  }

  return List.unmodifiable([
    for (final p in poses.cast<Map<String, dynamic>>())
      (
        id: '${p['id']}',
        category: '${p['category']}',
        tags: List<String>.unmodifiable([
          for (final t in p['tags'] as List? ?? const []) '$t',
        ]),
        description: '${p['descriptionZh'] ?? ''}',
        views: List<PoseView>.unmodifiable([
          for (final v in (p['views'] as List).cast<Map<String, dynamic>>())
            (angle: '${v['angle']}', path: full(v['path'])),
        ]),
      ),
  ]);
}

/// 姿势图库:不随软件带,用户下载或导入后放在「文档\Penna\poses\」。
class PoseLibrary extends ChangeNotifier {
  /// [home] 为 null 时只在内存里(测试里不给),什么都装不上。
  PoseLibrary([this.home]);

  final Directory? home;

  String? get _dir =>
      home == null ? null : '${home!.path}${Platform.pathSeparator}poses';

  List<Pose> _poses = const [];
  List<Pose> get poses => _poses;
  bool get installed => _poses.isNotEmpty;

  /// 正在下载或导入;[progress] 是下载进度(0 到 1,不知道时为 null)。
  bool _busy = false;
  bool get busy => _busy;
  double? _progress;
  double? get progress => _progress;

  Future<void> load() async {
    final dir = _dir;
    if (dir == null) return;
    final index = File('$dir${Platform.pathSeparator}poses.json');
    if (!index.existsSync()) return;
    try {
      _poses = parsePoses(
        jsonDecode(await index.readAsString()) as Map<String, dynamic>,
        dir,
      );
    } on Object catch (e) {
      // 下载来的东西坏了:当成没装,用户重新导入就好。
      debugPrint(tr('姿势图库读不了:{0}', [e.runtimeType]));
      _poses = const [];
    }
    notifyListeners();
  }

  /// 从 [zip] 装上图集(盖掉原来的);出错返回给用户看的一句话。
  Future<String?> importZip(String zip) async {
    final dir = _dir;
    if (dir == null || _busy) return null;
    _set(busy: true);
    try {
      final problem = await Isolate.run(() => _unpack(zip, dir));
      if (problem != null) return _problemText(problem);
      await load();
      return installed ? null : tr('图集里没有能用的姿势');
    } on Object catch (e) {
      debugPrint('pose import: $e');
      return tr('导入失败({0})', [e.runtimeType]);
    } finally {
      _set(busy: false);
    }
  }

  /// 从 [source] 下载再装上(盖掉原来的)。返回给用户看的一句话:
  /// 出错时说原因;魔搭上有几张下不到时也说,装还是装上。全都好时是 null。
  Future<String?> download(PoseSource source) async {
    final dir = _dir;
    if (dir == null || _busy) return null;
    if (source == PoseSource.modelscope) return _downloadLoose(dir);
    final zip = '$dir.zip';
    _set(busy: true);
    try {
      const file = (
        url: poseZipUrl,
        path: '',
        size: poseZipSize,
        sha256: poseZipSha256,
      );
      await downloadFile(
        (url: file.url, path: zip, size: file.size, sha256: file.sha256),
        urls: downloadUrls(file, proxyFirst: source == PoseSource.githubAccel),
        onProgress: _onProgress,
      );
    } on DownloadException catch (e) {
      _set(busy: false);
      return e.message;
    }
    _set(busy: false);
    final problem = await importZip(zip);
    if (problem == null) await File(zip).delete();
    return problem;
  }

  void _onProgress(int got, int? total) {
    _progress = total == null || total == 0 ? null : got / total;
    notifyListeners();
  }

  /// 魔搭上是散的文件:下到临时文件夹,读得通再换掉原来的。
  Future<String?> _downloadLoose(String dir) async {
    _set(busy: true);
    final tmp = Directory('$dir.tmp');
    try {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
      final missing = await fetchLoosePack(
        looseBase,
        tmp.path,
        onProgress: (done, total) => _onProgress(done, total),
      );
      final index = File('${tmp.path}${Platform.pathSeparator}poses.json');
      final json = jsonDecode(await index.readAsString());
      if (parsePoses(json as Map<String, dynamic>, dir).isEmpty) {
        return tr('图集里没有能用的姿势');
      }
      _swapIn(tmp.path, dir);
      await load();
      return missing == 0 ? null : tr('已装好,有 {0} 张图下载不到', [missing]);
    } on DownloadException catch (e) {
      return e.message;
    } on Object catch (e) {
      debugPrint('pose download: $e');
      return tr('下载失败({0})', [e.runtimeType]);
    } finally {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
      _set(busy: false);
    }
  }

  /// 魔搭的下载地址前缀;测试里换成本机的假服务器。
  @visibleForTesting
  String looseBase = poseModelScopeBase;

  /// 删掉装好的图集。
  Future<void> remove() async {
    final dir = _dir;
    if (dir == null) return;
    final d = Directory(dir);
    if (d.existsSync()) await d.delete(recursive: true);
    _poses = const [];
    notifyListeners();
  }

  void _set({required bool busy}) {
    _busy = busy;
    _progress = null;
    notifyListeners();
  }
}

String _problemText(String code) => switch (code) {
  'zip' => tr('不是有效的 ZIP 压缩包'),
  'unsafe' => tr('压缩包里有不安全的路径,已拒绝导入'),
  'big' => tr('压缩包太大'),
  _ => tr('压缩包里没有能用的 poses.json'),
};

const _maxFiles = 5000;
const _maxBytes = 200 * 1024 * 1024;

/// 在后台把 [zip] 解到 [dir]:先校验全部路径,解到旁边的临时文件夹,最后才替换。
/// 出错返回代号(后台读不到界面语言,翻译在 [_problemText])。
String? _unpack(String zip, String dir) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(File(zip).readAsBytesSync());
  } on Object {
    return 'zip';
  }
  // 图集可能套了一层文件夹:以 poses.json 所在的那层为根。
  final files = [
    for (final f in archive.files)
      if (f.isFile && !f.isSymbolicLink) (path: safeZipPath(f.name), file: f),
  ];
  if (files.any((f) => f.path == null)) return 'unsafe';
  final index = files
      .map((f) => f.path!)
      .where((p) => p == 'poses.json' || p.endsWith('/poses.json'))
      .fold<String?>(null, (a, p) => a == null || p.length < a.length ? p : a);
  if (index == null) return 'index';
  final root = index.substring(0, index.length - 'poses.json'.length);
  final picked = [
    for (final f in files)
      if (f.path!.isNotEmpty && f.path!.startsWith(root)) f,
  ];
  final total = picked.fold<int>(0, (a, f) => a + f.file.size);
  if (picked.length > _maxFiles || total > _maxBytes) return 'big';
  // 索引读得通、有姿势才动手,不然原来装好的不能先删掉。
  try {
    final json = jsonDecode(
      utf8.decode(files.firstWhere((f) => f.path == index).file.content),
    );
    if (parsePoses(json as Map<String, dynamic>, dir).isEmpty) return 'index';
  } on Object {
    return 'index';
  }

  final tmp = Directory('$dir.tmp');
  if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  for (final f in picked) {
    final out = File(
      '${tmp.path}${Platform.pathSeparator}'
      '${f.path!.substring(root.length).replaceAll('/', Platform.pathSeparator)}',
    );
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(f.file.content);
  }
  _swapIn(tmp.path, dir);
  return null;
}

/// 用 [tmp] 换掉 [dir]。
void _swapIn(String tmp, String dir) {
  final old = Directory(dir);
  if (old.existsSync()) old.deleteSync(recursive: true);
  Directory(tmp).renameSync(dir);
}
