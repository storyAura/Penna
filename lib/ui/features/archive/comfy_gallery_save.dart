part of 'comfy_gallery.dart';

/// [dir] 里不重名的路径:撞了在名字后面加 (1)、(2)…
String _freePath(Directory dir, String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var path = '${dir.path}${Platform.pathSeparator}$name';
  for (var n = 1; File(path).existsSync(); n++) {
    path = '${dir.path}${Platform.pathSeparator}$stem ($n)$ext';
  }
  return path;
}

/// 存进「下载」文件夹(2026-11-23 用户要求):一张直接存图,几张打成一个 zip
/// (里面按子文件夹放,同名的不会互相盖掉)。[read] 取一张的原图;[onStep] 报取到第几张。
/// 返回存好的路径。
Future<String> saveShots(
  List<ComfyShot> shots,
  Future<Uint8List> Function(ComfyShot) read, {
  void Function(int done)? onStep,
}) async {
  final dir = await downloadsDir();
  await dir.create(recursive: true);
  if (shots.length == 1) {
    final path = _freePath(dir, '${shots.single.file['filename']}');
    await File(path).writeAsBytes(await read(shots.single), flush: true);
    return path;
  }
  final zip = Archive();
  for (final (i, s) in shots.indexed) {
    final folder = shotFolder(s);
    final name = '${folder.isEmpty ? '' : '$folder/'}${s.file['filename']}';
    zip.addFile(ArchiveFile.typedData(name, await read(s)));
    onStep?.call(i + 1);
  }
  final stamp = DateTime.now();
  String two(int n) => '$n'.padLeft(2, '0');
  final path = _freePath(
    dir,
    'Penna-${stamp.year}${two(stamp.month)}${two(stamp.day)}'
    '-${two(stamp.hour)}${two(stamp.minute)}${two(stamp.second)}.zip',
  );
  await File(path).writeAsBytes(ZipEncoder().encodeBytes(zip), flush: true);
  return path;
}
