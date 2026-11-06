import 'dart:io';
import 'dart:typed_data';

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

bool _same(String a, String b) => _norm(a) == _norm(b);

String _norm(String path) =>
    Directory(path).absolute.path
        .toLowerCase()
        .replaceAll(RegExp(r'[\\/]+$'), '');
