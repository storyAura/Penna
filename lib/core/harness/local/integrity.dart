import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'gguf.dart';

/// 要核对的一个模型文件;[size]、[sha256] 不知道时为 null。
typedef CheckFile = ({String path, int? size, String? sha256});

/// 核对的结果:好的;只知道大小、大小对得上(要 Token 的仓库查不到 SHA256);不在;大小不对;
/// SHA256 不对;读不出来(GGUF 开头坏了);没有校验值、也不是 GGUF,没法核对。
enum FileHealth {
  ok,
  sizeOk,
  missing,
  wrongSize,
  badHash,
  unreadable,
  unchecked,
}

typedef FileCheck = ({String path, FileHealth health});

/// 逐个核对 [files](2026-11-13 用户要求:本地反推出乱码时查查模型文件坏没坏)。
/// 知道 SHA256 的整个算一遍,8 GB 的要十几秒,所以在另一个线程里做;
/// 不知道的 .gguf 只看开头读不读得出来(截断在后半截的查不出)。
Future<List<FileCheck>> checkFiles(List<CheckFile> files) =>
    Isolate.run(() async => [for (final f in files) await _check(f)]);

Future<FileCheck> _check(CheckFile f) async {
  FileCheck as(FileHealth h) => (path: f.path, health: h);
  final file = File(f.path);
  if (!file.existsSync()) return as(FileHealth.missing);
  if (f.size case final size? when file.lengthSync() != size) {
    return as(FileHealth.wrongSize);
  }
  if (f.sha256 case final want?) {
    final got = '${await sha256.bind(file.openRead()).first}';
    return as(got == want.toLowerCase() ? FileHealth.ok : FileHealth.badHash);
  }
  if (!f.path.toLowerCase().endsWith('.gguf')) {
    return as(f.size == null ? FileHealth.unchecked : FileHealth.sizeOk);
  }
  return as(readGguf(f.path) == null ? FileHealth.unreadable : FileHealth.ok);
}
