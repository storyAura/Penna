import 'dart:io';

import 'caption_catalog.dart';
import 'florence.dart';
import 'llama_server.dart';
import 'tagger.dart';

// 在用户指定的文件夹(连同子文件夹)里找已经有的模型,免得同一个模型反复下载。
// 认得 BooruDatasetTagManagerPlus(Models\SmilingWolf\wd-...\)、
// NLapt(模型目录\<id>\xxx.gguf)和 HuggingFace 缓存(models--作者--名字\snapshots\<哈希>\)的放法。

/// 扫到的东西,都是完整路径。
typedef FoundModels = ({
  /// 放着 model.onnx 和一种标签表的文件夹(打标模型,见 [taggerLabelFiles])。
  List<String> taggers,

  /// 模型本体 .gguf(名字里带 mmproj 的算视觉组件,不在这里)。
  List<String> ggufs,

  /// 视觉组件 .gguf。
  List<String> mmprojs,

  /// llama-server.exe。
  List<String> servers,

  /// 放着 Florence-2 四个 ONNX 的文件夹(分词器在它或它的上一层)。
  List<String> florences,

  /// 文件太多,没扫完就停了。
  bool truncated,
});

const noModels = (
  taggers: <String>[],
  ggufs: <String>[],
  mmprojs: <String>[],
  servers: <String>[],
  florences: <String>[],
  truncated: false,
);

/// 这些文件夹里不会有模型,还常常很大,不进去。
const _skipDirs = {
  '.git',
  'node_modules',
  r'$recycle.bin',
  'system volume information',
  '__pycache__',
};

String fileName(String path) => path.split(RegExp(r'[\\/]')).last;

bool isMmproj(String path) => fileName(path).toLowerCase().contains('mmproj');

/// 在 [roots] 里一层层往下找,最深 [maxDepth] 层,最多看 [maxEntries] 个条目。
/// 读不了的文件夹跳过。同步执行,要在别的 isolate 里调。
FoundModels scanModelFolders(
  List<String> roots, {
  int maxDepth = 8,
  int maxEntries = 200000,
}) {
  final taggers = <String>[], ggufs = <String>[], mmprojs = <String>[];
  final servers = <String>[], florences = <String>[];
  var seen = 0;
  var truncated = false;
  final queue = <(Directory, int)>[for (final r in roots) (Directory(r), 0)];
  while (queue.isNotEmpty) {
    final (dir, depth) = queue.removeAt(0);
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    final files = <String>{};
    for (final e in entries) {
      if (++seen > maxEntries) {
        truncated = true;
        break;
      }
      // HuggingFace 缓存里的文件常常是链接:指向文件的照常算,指向文件夹的不跟进去,免得绕圈。
      final type = e is Link
          ? FileSystemEntity.typeSync(e.path)
          : e is Directory
          ? FileSystemEntityType.directory
          : FileSystemEntityType.file;
      final name = fileName(e.path).toLowerCase();
      if (type == FileSystemEntityType.directory) {
        if (e is! Link && depth < maxDepth && !_skipDirs.contains(name)) {
          queue.add((Directory(e.path), depth + 1));
        }
      } else if (type == FileSystemEntityType.file) {
        files.add(name);
        if (name.endsWith('.gguf')) {
          (isMmproj(name) ? mmprojs : ggufs).add(e.path);
        } else if (name == llamaServerFileName) {
          servers.add(e.path);
        }
      }
    }
    if (files.contains(taggerModelFile) &&
        taggerLabelFiles.keys.any(files.contains)) {
      taggers.add(dir.path);
    }
    if (florenceOnnx.every(files.contains) &&
        (files.contains(florenceTokenizer) ||
            File(
              '${dir.parent.path}${Platform.pathSeparator}$florenceTokenizer',
            ).existsSync())) {
      florences.add(dir.path);
    }
    if (truncated) break;
  }
  return (
    taggers: taggers,
    ggufs: ggufs,
    mmprojs: mmprojs,
    servers: servers,
    florences: florences,
    truncated: truncated,
  );
}

/// 这个文件夹是不是清单里的那个打标模型:路径里有一层的名字以模型名结尾
/// (wd-vit-tagger-v3、SmilingWolf__wd-vit-tagger-v3、models--SmilingWolf--wd-vit-tagger-v3)。
String? catalogTaggerFor(String dir) {
  for (final m in taggerModels) {
    // 文件在仓库的子文件夹里的(cl_tagger_1_02/、V1_onnx/):最后一层要是它,上一层对上仓库。
    final at = m.files.first.lastIndexOf('/');
    if (at < 0) {
      if (inRepoFolder(dir, m.repo)) return m.id;
      continue;
    }
    final sub = m.files.first.substring(0, at).toLowerCase();
    final cut = dir.lastIndexOf(RegExp(r'[\\/]'));
    if (cut > 0 &&
        fileName(dir).toLowerCase() == sub &&
        inRepoFolder(dir.substring(0, cut), m.repo)) {
      return m.id;
    }
  }
  return null;
}

/// 打标模型的标签表文件名 → 它是哪一种(清单外的模型靠它认种类)。
/// selected_tags.csv 三种模型都用,默认按 WD 的读法。
const taggerLabelFiles = {
  taggerLabelsFile: TaggerKind.wd,
  'tags.json': TaggerKind.pixai10,
  'tag_mapping.json': TaggerKind.clV1,
  'model_vocabulary.json': TaggerKind.clV2,
};

/// [dir] 的路径里有一层是 [repo] 的模型名(或 [id]),允许前面带「作者__」「models--作者--」。
bool inRepoFolder(String dir, String repo, [String? id]) {
  final base = repo.split('/').last.toLowerCase();
  bool hit(String s) =>
      s == base ||
      s == id ||
      s.endsWith(base) && '-_ '.contains(s[s.length - base.length - 1]);
  return dir.toLowerCase().split(RegExp(r'[\\/]')).any(hit);
}

final _hash = RegExp(r'^[0-9a-f]{16,}$');

/// 给扫到的文件夹起个能看的名字:跳过缓存里的哈希和 snapshots 那几层。
String folderTitle(String dir) {
  for (final s in dir.split(RegExp(r'[\\/]')).reversed) {
    final low = s.toLowerCase();
    if (s.isEmpty || low == 'snapshots' || _hash.hasMatch(low)) continue;
    return low.startsWith('models--') ? s.split('--').last : s;
  }
  return dir;
}

String _parent(String path) {
  final cut = path.lastIndexOf(RegExp(r'[\\/]'));
  return cut < 0 ? '' : path.substring(0, cut);
}

/// 给模型本体配一个视觉组件:同一个文件夹里的优先。没有就是空串。
String mmprojFor(String gguf, List<String> mmprojs) =>
    mmprojs.where((p) => _parent(p) == _parent(gguf)).firstOrNull ?? '';

/// 清单里的 GGUF 看图模型在扫到的文件里有没有:任何一个量化档的文件名对上就算,
/// [prefer] 那一档优先;视觉组件按文件名找,同一个文件夹里的优先。
({String model, String mmproj})? findCaption(
  CaptionModel m,
  FoundModels f, {
  String? prefer,
}) {
  final mmproj = m.mmproj;
  if (m.florence || mmproj == null) return null;
  final names = [
    for (final q in m.quants)
      if (q.label == prefer) fileName(q.file.path),
    for (final q in m.quants) fileName(q.file.path),
  ];
  final model = names
      .map((n) => f.ggufs.where((p) => fileName(p) == n).firstOrNull)
      .nonNulls
      .firstOrNull;
  final pairs = f.mmprojs
      .where((p) => fileName(p) == fileName(mmproj.path))
      .toList();
  if (model == null || pairs.isEmpty) return null;
  final same = pairs.where((p) => _parent(p) == _parent(model)).firstOrNull;
  return (model: model, mmproj: same ?? pairs.first);
}

/// 清单里的 Florence-2 在扫到的文件夹里有没有:路径里有它的模型名或 NLapt 的 id。
String? findFlorence(CaptionModel m, FoundModels f) => m.florence
    ? f.florences.where((d) => inRepoFolder(d, m.repo, m.id)).firstOrNull
    : null;
