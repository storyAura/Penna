import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../../../l10n/l10n.dart';

/// 要下载的一个文件。[size]、[sha256] 知道才校验(null 表示不校验)。
typedef RemoteFile = ({String url, String path, int? size, String? sha256});

/// 下载进度:已经有了多少字节,总共多少(不知道时为 null)。
typedef DownloadProgress = void Function(int received, int? total);

class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 中途停下下载用。停下后已下的部分留在 `.part` 里,下次接着下。
class DownloadCancel {
  final _done = Completer<void>();

  bool get cancelled => _done.isCompleted;
  Future<void> get whenCancelled => _done.future;

  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// 文件已经在了(知道大小时大小也对得上)。
bool isDownloaded(RemoteFile f) {
  final file = File(f.path);
  return file.existsSync() && (f.size == null || file.lengthSync() == f.size);
}

/// 把 [f] 下载到它的 [RemoteFile.path]:先写进旁边的 `.part`,
/// 下完并校验通过才改成正式的名字,所以半截文件不会被当成下好了。
/// 已经下好的直接返回;`.part` 还在时从断开的地方接着下。
/// 停下([cancel])时抛 [DownloadException],`.part` 留着。
Future<void> downloadFile(
  RemoteFile f, {
  DownloadProgress? onProgress,
  DownloadCancel? cancel,
  Map<String, String> headers = const {},
}) async {
  if (isDownloaded(f)) return;
  if (cancel?.cancelled ?? false) throw DownloadException(tr('已停止下载'));
  final part = File('${f.path}.part');
  await part.parent.create(recursive: true);
  var have = part.existsSync() ? part.lengthSync() : 0;
  if (f.size != null && have > f.size!) {
    await part.delete();
    have = 0;
  }
  final client = HttpClient()..userAgent = 'Penna';
  unawaited(cancel?.whenCancelled.then((_) => client.close(force: true)));
  try {
    if (f.size == null || have < f.size!) {
      have = await _fetch(client, f, part, have, onProgress, cancel, headers);
    }
  } on Object catch (e) {
    if (cancel?.cancelled ?? false) throw DownloadException(tr('已停止下载'));
    if (e is DownloadException) rethrow;
    // 只报类型:原文里可能带着地址。
    throw DownloadException(tr('下载失败({0}),可以再点一次接着下', [e.runtimeType]));
  } finally {
    client.close(force: true);
  }
  if (f.size != null && have != f.size) {
    throw DownloadException(tr('下载不完整,可以再点一次接着下'));
  }
  if (f.sha256 case final want?) {
    final path = part.path;
    final got = await Isolate.run(
      () async => '${await sha256.bind(File(path).openRead()).first}',
    );
    if (got != want.toLowerCase()) {
      await part.delete();
      throw DownloadException(tr('文件校验没通过,已删掉,请重新下载'));
    }
  }
  if (cancel?.cancelled ?? false) throw DownloadException(tr('已停止下载'));
  final target = File(f.path);
  if (target.existsSync()) await target.delete();
  await part.rename(f.path);
}

/// 从第 [have] 个字节接着下到 [part],返回下完后一共有多少字节。
Future<int> _fetch(
  HttpClient client,
  RemoteFile f,
  File part,
  int have,
  DownloadProgress? onProgress,
  DownloadCancel? cancel,
  Map<String, String> headers,
) async {
  final request = await client.getUrl(Uri.parse(f.url));
  headers.forEach(request.headers.set);
  if (have > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
  final response = await request.close();
  final status = response.statusCode;
  // 416 也可能是分片比远端文件更长,只有远端明确给出的长度一致才算下完。
  if (status == HttpStatus.requestedRangeNotSatisfiable) {
    final range = RegExp(
      r'^bytes \*/(\d+)$',
      caseSensitive: false,
    ).firstMatch(response.headers.value(HttpHeaders.contentRangeHeader) ?? '');
    await response.drain<void>();
    if (have > 0 && range != null && int.parse(range[1]!) == have) return have;
    if (have > 0) {
      return _fetch(client, f, part, 0, onProgress, cancel, headers);
    }
    throw DownloadException(tr('下载失败(HTTP {0})', [status]));
  }
  if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
    await response.drain<void>();
    throw DownloadException(switch (status) {
      401 || 403 => tr('下载被拒绝(HTTP {0}):这个模型可能要登录才能下', [status]),
      404 => tr('找不到这个文件(HTTP 404)'),
      _ => tr('下载失败(HTTP {0})', [status]),
    });
  }
  // 服务器不认断点续传,只能从头来。
  if (status == HttpStatus.ok) have = 0;
  final length = response.contentLength;
  var total = f.size ?? (length < 0 ? null : have + length);
  int? end;
  if (status == HttpStatus.partialContent) {
    final range = RegExp(
      r'^bytes (\d+)-(\d+)/(\d+|\*)$',
      caseSensitive: false,
    ).firstMatch(response.headers.value(HttpHeaders.contentRangeHeader) ?? '');
    if (range == null || int.parse(range[1]!) != have) {
      throw DownloadException(tr('下载不完整,可以再点一次接着下'));
    }
    end = int.parse(range[2]!);
    if (range[3] != '*') total = int.parse(range[3]!);
    if (end < have ||
        total != null && end >= total ||
        length >= 0 && length != end - have + 1) {
      throw DownloadException(tr('下载不完整,可以再点一次接着下'));
    }
  }
  final sink = part.openWrite(
    mode: have > 0 ? FileMode.writeOnlyAppend : FileMode.writeOnly,
  );
  try {
    await for (final chunk in response) {
      if (cancel?.cancelled ?? false) break;
      sink.add(chunk);
      have += chunk.length;
      onProgress?.call(have, total);
    }
  } finally {
    await sink.close();
  }
  if (cancel?.cancelled ?? false) throw DownloadException(tr('已停止下载'));
  if (end != null && (have != end + 1 || total != null && have != total)) {
    throw DownloadException(tr('下载不完整,可以再点一次接着下'));
  }
  return have;
}
