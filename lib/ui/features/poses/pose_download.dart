import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../core/harness/local/download.dart' show DownloadException;
import '../../../data/services/skill_store.dart' show safeZipPath;
import '../../../l10n/l10n.dart';

/// 姿势图集从哪下载(用户在页面上选,默认 GitHub 加速)。
enum PoseSource { githubAccel, github, modelscope }

/// GitHub Release 里的整包。
const poseZipUrl =
    'https://github.com/storyAura/shisei-pose-dataset/releases/download/'
    'v1.0.0/shisei_penna_pose_pack_v1.zip';
const poseZipSha256 =
    'd7c4dfacb2ef61a4d658e2c6a15fcb3cf49a4e0c0f2a7bb42a9d7f3dc62c5a3b';
const poseZipSize = 20890096;

/// 魔搭上是散的文件(没有整包),不含 NSFW 的姿势,比 GitHub 的少。
const poseModelScopeBase =
    'https://modelscope.cn/api/v1/datasets/storyaura/shiseiPoseDataset/repo'
    '?Revision=master&FilePath=';

/// 同时下几张图。
const _parallel = 8;
const _timeout = Duration(seconds: 30);
const _tries = 4;
const _backoff = Duration(milliseconds: 600);

/// 从 [base](拼上文件路径就是下载地址)逐个下载图集到 [tmp]:先下 poses.json,
/// 再按它下每张图(索引里有 sha256 的照它校验)。下不到的图从索引里去掉,
/// 一张图都没有的姿势也去掉,最后写回 [tmp] 里的 poses.json。返回下不到几张。
/// 索引都下不到时抛 [DownloadException]。
// ponytail: 不接着下:断了从头来(一张约 20 KB,整套 900 张不到 20 MB)。
Future<int> fetchLoosePack(
  String base,
  String tmp, {
  void Function(int done, int total)? onProgress,
}) async {
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
    final raw = await _get(client, '${base}poses.json');
    if (raw == null) throw DownloadException(tr('下载不到图集的索引'));
    final Map<String, dynamic> index;
    try {
      index = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    } on Object {
      throw DownloadException(tr('图集的索引读不了'));
    }
    final poses = (index['poses'] as List).cast<Map<String, dynamic>>();
    final views = [
      for (final p in poses)
        ...(p['views'] as List).cast<Map<String, dynamic>>(),
    ];
    final got = <String>{};
    var done = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < views.length) {
        final v = views[next++];
        final path = safeZipPath('${v['path']}');
        if (path != null && path.isNotEmpty) {
          final bytes = await _get(client, '$base$path', sha256: v['sha256']);
          if (bytes != null) {
            final out = File(
              '$tmp${Platform.pathSeparator}'
              '${path.replaceAll('/', Platform.pathSeparator)}',
            );
            await out.parent.create(recursive: true);
            await out.writeAsBytes(bytes);
            got.add('${v['path']}');
          }
        }
        onProgress?.call(++done, views.length);
      }
    }

    await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
    final kept = [
      for (final p in poses)
        if ((p['views'] as List).any((v) => got.contains('${v['path']}')))
          {
            ...p,
            'views': [
              for (final v in p['views'] as List)
                if (got.contains('${v['path']}')) v,
            ],
          },
    ];
    await File('$tmp${Platform.pathSeparator}poses.json')
        .writeAsString(jsonEncode({...index, 'poses': kept}));
    return views.length - got.length;
  } finally {
    client.close(force: true);
  }
}

/// 下一个文件,失败再试几次;状态码不是 200、校验不对、超时都算失败,返回 null。
Future<List<int>?> _get(HttpClient client, String url, {Object? sha256}) async {
  for (var attempt = 0; attempt < _tries; attempt++) {
    // 并发多了魔搭偶尔不给(实测 900 张里有 3 张):隔一会儿再要。
    if (attempt > 0) await Future<void>.delayed(_backoff * attempt);
    try {
      final res = await (await client.getUrl(Uri.parse(url)))
          .close()
          .timeout(_timeout);
      final bytes = await res
          .fold<List<int>>([], (a, b) => a..addAll(b))
          .timeout(_timeout);
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200) continue;
      if (sha256 is String && '${_hash(bytes)}' != sha256) continue;
      return bytes;
    } on Object {
      continue;
    }
  }
  return null;
}

Digest _hash(List<int> bytes) => sha256.convert(bytes);
