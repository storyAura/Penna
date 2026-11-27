import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 用户的「下载」文件夹(Windows 认系统设置里挪过的位置);取不到时用 主目录\Downloads。
Future<Directory> downloadsDir() async {
  final got = await getDownloadsDirectory();
  if (got != null) return got;
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  return Directory('$home${Platform.pathSeparator}Downloads');
}

/// ComfyUI 出的图的文件名都以它开头;换位置时只搬这些,文件夹里别的东西不碰。
const comfyImagePrefix = 'Penna-';

/// 出的图默认放在数据文件夹(「文档\Penna」)下的 images 里。
String defaultImageDir(Directory home) =>
    '${home.path}${Platform.pathSeparator}images';

/// 把一张图存进 [dir],文件名带着时刻;[name] 是 ComfyUI 里的文件名,只取它的后缀。
File saveComfyImage(String dir, String name, Uint8List bytes, DateTime time) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? 'png' : name.substring(dot + 1).toLowerCase();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${time.year}${two(time.month)}${two(time.day)}-'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  final sep = Platform.pathSeparator;
  Directory(dir).createSync(recursive: true);
  for (var n = 1; ; n++) {
    final file = File('$dir$sep$comfyImagePrefix$stamp-$n.$ext');
    if (file.existsSync()) continue;
    file.writeAsBytesSync(bytes, flush: true);
    return file;
  }
}

/// 云端原图的大文件夹:[picked]\Penna_Image,[picked] 空的是「下载」。
Future<String> cloudImageDir(String picked) async =>
    '${picked.isEmpty ? (await downloadsDir()).path : picked}'
    '${Platform.pathSeparator}Penna_Image';

/// 云端出的原图另存一份到 [root]\<yy_mm_dd>\,当天的图都在一个文件夹,
/// 文件名照 ComfyUI 的(2026-11-28 用户要求);重名加 (1)、(2)…
File saveCloudCopy(String root, String name, Uint8List bytes, DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  final sep = Platform.pathSeparator;
  final dir =
      '$root$sep${two(time.year % 100)}_${two(time.month)}_${two(time.day)}';
  Directory(dir).createSync(recursive: true);
  name = name.split(RegExp(r'[\/]')).last;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var file = File('$dir$sep$name');
  for (var n = 1; file.existsSync(); n++) {
    file = File('$dir$sep$stem ($n)$ext');
  }
  file.writeAsBytesSync(bytes, flush: true);
  return file;
}

/// 换存图的位置:把 [from] 里 Penna 出的图搬到 [to],返回搬了几张。
/// 跨盘时 rename 不行,就复制再删。重名的不盖掉,留在原处。
Future<int> moveComfyImages(String from, String to) async {
  final source = Directory(from);
  if (!source.existsSync() || _same(from, to)) return 0;
  await Directory(to).create(recursive: true);
  final sep = Platform.pathSeparator;
  var moved = 0;
  await for (final entity in source.list()) {
    final name = entity.uri.pathSegments.last;
    if (entity is! File || !name.startsWith(comfyImagePrefix)) continue;
    final target = File('$to$sep$name');
    if (target.existsSync()) continue;
    try {
      await entity.rename(target.path);
    } on FileSystemException {
      await entity.copy(target.path);
      await entity.delete();
    }
    moved++;
  }
  return moved;
}

/// 换云端原图的位置:把 [from] 里各天的文件夹连图搬进 [to],返回搬了几张。重名的留在原处。
Future<int> moveCloudImages(String from, String to) async {
  final source = Directory(from);
  if (!source.existsSync() || _same(from, to)) return 0;
  final sep = Platform.pathSeparator;
  var moved = 0;
  await for (final day in source.list()) {
    if (day is! Directory) continue;
    final into =
        '$to$sep${day.uri.pathSegments.lastWhere((s) => s.isNotEmpty)}';
    await Directory(into).create(recursive: true);
    await for (final file in day.list()) {
      if (file is! File) continue;
      final target = File('$into$sep${file.uri.pathSegments.last}');
      if (target.existsSync()) continue;
      try {
        await file.rename(target.path);
      } on FileSystemException {
        await file.copy(target.path);
        await file.delete();
      }
      moved++;
    }
    if (day.listSync().isEmpty) await day.delete();
  }
  return moved;
}

bool _same(String a, String b) => _norm(a) == _norm(b);

String _norm(String path) =>
    Directory(path).absolute.path
        .toLowerCase()
        .replaceAll(RegExp(r'[\\/]+$'), '');
