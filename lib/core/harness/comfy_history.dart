part of 'comfyui.dart';

/// ComfyUI 出过的一张图:哪一单(历史里没有的是空串)、文件(给 /view 用)、
/// 当时的正面提示词、出完的时刻,和本机硬盘上的路径(读的是输出文件夹时才有)。
typedef ComfyShot = ({
  String id,
  Map<String, Object?> file,
  String prompt,
  DateTime? time,
  String? path,
});

/// 一张图在输出文件夹里的哪一层:`''` 是 output 最外层,子文件夹用 `/` 隔开。
String shotFolder(ComfyShot s) =>
    '${s.file['subfolder'] ?? ''}'.replaceAll('\\', '/');

String _shotKey(ComfyShot s) =>
    '${s.file['type'] ?? 'output'}/${shotFolder(s)}/${s.file['filename']}';

/// 读 `/history` 的结果:每一单出的图,新的在前。
/// 一单是 `{prompt: [序号, id, 工作流, …], outputs: {…}, status: {messages: [[事件, {timestamp}]…]}}`。
List<ComfyShot> parseHistory(Object? json) {
  if (json is! Map) return const [];
  final shots = <ComfyShot>[];
  // 返回的顺序是先跑的在前:倒过来一单一单读,同一单里的几张照原来的先后。
  for (final MapEntry(key: id, value: entry)
      in json.entries.toList().reversed) {
    if (entry is! Map) continue;
    final p = entry['prompt'];
    final wf = p is List && p.length > 2 && p[2] is Map
        ? (p[2] as Map).cast<String, Object?>()
        : null;
    final prompt = wf == null ? '' : positivePromptOf(wf);
    DateTime? time;
    final status = entry['status'];
    for (final m in status is Map ? status['messages'] as List? ?? [] : []) {
      if (m is List && m.length > 1 && m[1] is Map) {
        final at = (m[1] as Map)['timestamp'];
        if (at is int) time = DateTime.fromMillisecondsSinceEpoch(at);
      }
    }
    for (final f in pickOutputImages(entry['outputs'])) {
      shots.add((id: '$id', file: f, prompt: prompt, time: time, path: null));
    }
  }
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  // 有时刻的再按时刻排(排序不保证稳定,同一时刻的按原来的先后)。
  final ordered = shots.indexed.toList()
    ..sort((a, b) {
      final byTime = (b.$2.time ?? epoch).compareTo(a.$2.time ?? epoch);
      // 同一时刻(同一单的几张)保持原来的先后。
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return [for (final (_, s) in ordered) s];
}

/// 读 `/internal/files/output` 的结果(输出文件夹最外层的文件名,新改的在前;
/// 新版本的名字后面带 ` [output]`),只留图片,换成给 /view 用的文件。
List<Map<String, Object?>> parseOutputFiles(Object? json) => [
  if (json is List)
    for (final e in json)
      if (e is String)
        if (e.replaceFirst(RegExp(r' \[output\]$'), '') case final name
            when imageMimes.containsKey(
              name.substring(name.lastIndexOf('.') + 1).toLowerCase(),
            ))
          {'filename': name, 'subfolder': '', 'type': 'output'},
];

/// 输出文件夹里的图(本机硬盘上读的,或 `/internal/files/output` 列的)配上出图历史:
/// 历史里有的补上路径(时刻没有时用文件的),历史没记着的接上(没有提示词);
/// 再按时刻排,新的在前,没有时刻的排在最后。
List<ComfyShot> mergeShots(List<ComfyShot> history, List<ComfyShot> files) {
  final byKey = {for (final f in files) _shotKey(f): f};
  final seen = <String>{};
  final all = [
    for (final h in history)
      if (byKey[_shotKey(h)] case final f?)
        (
          id: h.id,
          file: h.file,
          prompt: h.prompt,
          time: h.time ?? f.time,
          path: f.path,
        )
      else
        h,
    for (final f in files)
      if (!history.any((h) => _shotKey(h) == _shotKey(f)) &&
          seen.add(_shotKey(f)))
        f,
  ];
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  final ordered = all.indexed.toList()
    ..sort((a, b) {
      final ta = a.$2.time, tb = b.$2.time;
      if ((ta == null) != (tb == null)) return ta == null ? 1 : -1;
      final byTime = (tb ?? epoch).compareTo(ta ?? epoch);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return [for (final (_, s) in ordered) s];
}

/// `/internal/files/output` 列出的文件换成图(没有时刻和路径)。
List<ComfyShot> shotsOfFiles(List<Map<String, Object?>> files) => [
  for (final f in files) (id: '', file: f, prompt: '', time: null, path: null),
];

/// 本机 ComfyUI 的输出文件夹:照 `/system_stats` 里的启动参数找
/// (`--output-directory`,或 `--base-directory` / main.py 所在文件夹下的 output);
/// 找不出绝对路径(便携版用相对路径启动)时是 null。
String? localOutputDir(Object? stats) {
  final system = stats is Map ? stats['system'] : null;
  final argv = system is Map ? system['argv'] : null;
  if (argv is! List || argv.isEmpty) return null;
  final args = [for (final a in argv) '$a'];
  String? after(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final out = after('--output-directory');
  if (out != null) return File(out).isAbsolute ? out : null;
  final base = after('--base-directory') ?? File(args.first).parent.path;
  if (!File(base).isAbsolute) return null;
  return '$base${Platform.pathSeparator}output';
}

/// 一次最多从硬盘上列多少张(新改的在前)。
const _maxDiskShots = 20000;

/// 列出输出文件夹(连子文件夹)里的图,新改的在前;在 isolate 里读,不卡界面。
/// 文件夹不在了返回空的。
Future<List<ComfyShot>> listOutputFolder(String dir) => Isolate.run(() {
  // 去掉末尾的斜杠,下面按长度切出相对路径。
  final root = Directory(dir.replaceFirst(RegExp(r'[\\/]+$'), ''));
  if (!root.existsSync()) return const <ComfyShot>[];
  final found = <(File, DateTime)>[];
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final name = e.uri.pathSegments.last;
    final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
    if (!imageMimes.containsKey(ext)) continue;
    found.add((e, e.statSync().modified));
  }
  found.sort((a, b) => b.$2.compareTo(a.$2));
  final prefix = root.path.length + 1;
  return [
    for (final (f, at) in found.take(_maxDiskShots))
      if (f.path.substring(prefix).replaceAll('\\', '/') case final rel)
        (
          id: '',
          file: <String, Object?>{
            'filename': rel.substring(rel.lastIndexOf('/') + 1),
            'subfolder': rel.contains('/')
                ? rel.substring(0, rel.lastIndexOf('/'))
                : '',
            'type': 'output',
          },
          prompt: '',
          time: at,
          path: f.path,
        ),
  ];
});
