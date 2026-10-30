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

/// GitHub 文件的国内加速前缀(2026-10-30 测过,能下但不稳:常有 403、半路卡住),
/// 按顺序试,都不行再直连。
const githubProxies = [
  'https://gh-proxy.com/',
  'https://ghfast.top/',
  'https://ghproxy.net/',
];

/// 下 [f] 时依次试的地址:GitHub 上的文件先走加速前缀、最后是原地址
/// ([proxyFirst] 为假时先原地址、再加速)。
/// 没有 SHA256 的不走加速:那是别人的服务器,内容被换了校验不出来。
List<String> downloadUrls(RemoteFile f, {bool proxyFirst = true}) {
  final host = Uri.tryParse(f.url)?.host;
  final github = host == 'github.com' || host == 'raw.githubusercontent.com';
  if (!github || f.sha256 == null) return [f.url];
  final proxied = [for (final p in githubProxies) '$p${f.url}'];
  return proxyFirst ? [...proxied, f.url] : [f.url, ...proxied];
}

/// 文件已经在了(知道大小时大小也对得上)。
bool isDownloaded(RemoteFile f) {
  final file = File(f.path);
  return file.existsSync() && (f.size == null || file.lengthSync() == f.size);
}

/// 把 [f] 下载到它的 [RemoteFile.path]:先写进旁边的 `.part`,
/// 下完并校验通过才改成正式的名字,所以半截文件不会被当成下好了。
/// 已经下好的直接返回;`.part` 还在时从断开的地方接着下。
/// 地址按 [urls](默认 [downloadUrls])依次试,不管下到哪儿断的都换下一个:有 SHA256 的
/// 接着下(接错了校验得出来,删掉后再换下一个从头下),没有的从头下(不同服务器给的半截
/// 不一定接得上,又校验不出来)。都不行报最后一个的错,`.part` 留着,再点一次接着下。
/// 停下([cancel])时抛 [DownloadException],`.part` 留着。
Future<void> downloadFile(
  RemoteFile f, {
  DownloadProgress? onProgress,
  DownloadCancel? cancel,
  Map<String, String> headers = const {},
  List<String>? urls,
}) async {
  if (isDownloaded(f)) return;
  final part = File('${f.path}.part');
  await part.parent.create(recursive: true);
  final tries = urls ?? downloadUrls(f);
  for (var i = 0; ; i++) {
    try {
      return await _downloadFrom(
        tries[i],
        f,
        part,
        onProgress,
        cancel,
        headers,
      );
    } on DownloadException {
      if ((cancel?.cancelled ?? false) || i == tries.length - 1) rethrow;
      // ponytail: 没有 SHA256 的(打标模型)换地址就丢掉已下的部分,哪怕这个地址一个字节也没给。
      // 升级路径:清单里给打标模型记上 SHA256,就和别的文件一样接着下。
      if (f.sha256 == null && part.existsSync()) await part.delete();
    }
  }
}

Future<void> _downloadFrom(
  String url,
  RemoteFile f,
  File part,
  DownloadProgress? onProgress,
  DownloadCancel? cancel,
  Map<String, String> headers,
) async {
  var have = part.existsSync() ? part.lengthSync() : 0;
  if (f.size != null && have > f.size!) {
    await part.delete();
    have = 0;
  }
  final client = HttpClient()
    ..userAgent = 'Penna'
    ..connectionTimeout = const Duration(seconds: 15);
  unawaited(cancel?.whenCancelled.then((_) => client.close(force: true)));
  try {
    if (f.size == null || have < f.size!) {
      have = await _fetch(
        client,
        url,
        f,
        part,
        have,
        onProgress,
        cancel,
        headers,
      );
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
  final target = File(f.path);
  if (target.existsSync()) await target.delete();
  await part.rename(f.path);
}

/// 等响应、等两段数据之间最多这么久,卡住就算这个地址下不了。
const _stall = Duration(seconds: 30);

/// 从第 [have] 个字节接着下到 [part],返回下完后一共有多少字节。
Future<int> _fetch(
  HttpClient client,
  String url,
  RemoteFile f,
  File part,
  int have,
  DownloadProgress? onProgress,
  DownloadCancel? cancel,
  Map<String, String> headers,
) async {
  final request = await client.getUrl(Uri.parse(url));
  headers.forEach(request.headers.set);
  if (have > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
  final response = await request.close().timeout(_stall);
  final status = response.statusCode;
  // 416:要的那一段已经超出文件末尾,说明其实已经下完了。
  if (status == HttpStatus.requestedRangeNotSatisfiable) {
    await response.drain<void>();
    return have;
  }
  if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
    await response.drain<void>();
    throw DownloadException(switch (status) {
      401 || 403 when Uri.tryParse(f.url)?.host == 'huggingface.co' => tr(
        '下载被拒绝(HTTP {0}):这个模型可能要登录才能下',
        [status],
      ),
      401 || 403 => tr('下载被拒绝(HTTP {0})', [status]),
      404 => tr('找不到这个文件(HTTP 404)'),
      _ => tr('下载失败(HTTP {0})', [status]),
    });
  }
  // 服务器不认断点续传,只能从头来。
  if (status == HttpStatus.ok) have = 0;
  final length = response.contentLength;
  // 加速站常用 200 回一张报错网页:写进 .part 的话,下一个地址会接在它后面。
  if (response.headers.contentType?.mimeType == 'text/html' ||
      (f.size != null && length >= 0 && have + length != f.size)) {
    await response.drain<void>();
    throw DownloadException(tr('服务器回的不是这个文件'));
  }
  final total = f.size ?? (length < 0 ? null : have + length);
  final sink = part.openWrite(
    mode: have > 0 ? FileMode.writeOnlyAppend : FileMode.writeOnly,
  );
  try {
    await for (final chunk in response.timeout(_stall)) {
      if (cancel?.cancelled ?? false) break;
      sink.add(chunk);
      have += chunk.length;
      onProgress?.call(have, total);
    }
  } finally {
    await sink.close();
  }
  if (cancel?.cancelled ?? false) throw DownloadException(tr('已停止下载'));
  return have;
}
