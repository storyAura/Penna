import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../l10n/l10n.dart';

// 检查更新与自更新:看 GitHub 上最新的发行版,比版本号;要更新时下载 zip、解开,
// 交给一个独立的 PowerShell 脚本等 Penna 退出后把新文件盖上去,再重新打开。

/// 发行版所在的仓库。
const updateRepo = 'storyAura/Penna';

/// 一个发行版:版本号(不带 v)、更新说明、安装包的地址和大小、SHA256(GitHub 给了才有)。
typedef Release = ({
  String version,
  String notes,
  String url,
  int? size,
  String? sha256,
});

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 测试版的版本号:`1.0.2-261020-7-dev`,即下一个正式版的号、日期(年月日各两位)、
/// 当天第几次改。
final _devVersion = RegExp(r'^(.*?)-(\d{6})-(\d+)-dev$');

/// 拆成 [主.次.修订, 日期, 第几次]。正式版没有后两个,算作比同号的测试版都新。
List<int> _parts(String version) {
  final v = version.trim().replaceFirst(RegExp('^[vV]'), '').split('+').first;
  final dev = _devVersion.firstMatch(v);
  final core = (dev?[1] ?? v).split(RegExp('[.-]'));
  return [
    for (var i = 0; i < 3; i++)
      i < core.length ? int.tryParse(core[i]) ?? 0 : 0,
    // 正式版排在同号的所有测试版后面。
    if (dev == null) ...[
      1 << 30,
      0,
    ] else ...[
      int.parse(dev[2]!),
      int.parse(dev[3]!),
    ],
  ];
}

/// 比较两个版本号(1.0.10 比 1.0.9 新,开头的 v 不算;1.0.2 比 1.0.2-261020-7-dev 新,
/// 同号的测试版按日期、再按第几次):a 新返回正数,一样返回 0。
int compareVersions(String a, String b) {
  final x = _parts(a), y = _parts(b);
  for (var i = 0; i < x.length; i++) {
    final d = x[i] - y[i];
    if (d != 0) return d;
  }
  return 0;
}

/// 更新通道:正式版只看 GitHub 标成最新的那个发行版;测试版看最近的所有发行版
/// (测试版和正式版都算),取最新的。
const updateChannels = ['main', 'dev'];

/// 这个平台的安装包名字的结尾:Windows 是 zip,Linux 是 AppImage。
String get releaseAssetSuffix =>
    Platform.isWindows ? '-windows-x64.zip' : '-linux-x86_64.AppImage';

/// 从 GitHub 的发行版 JSON 里取出版本号、说明和这个平台的安装包(名字以 [suffix] 结尾,
/// 默认 [releaseAssetSuffix]);没有安装包时为 null。
Release? parseRelease(Map<String, dynamic> j, {String? suffix}) {
  final end = suffix ?? releaseAssetSuffix;
  final asset = (j['assets'] as List? ?? const [])
      .cast<Map<String, dynamic>>()
      .where((a) => '${a['name']}'.endsWith(end))
      .firstOrNull;
  if (asset == null) return null;
  final digest = '${asset['digest'] ?? ''}';
  return (
    version: '${j['tag_name'] ?? ''}'.replaceFirst(RegExp('^[vV]'), ''),
    notes: releaseNotes('${j['body'] ?? ''}'),
    url: '${asset['browser_download_url']}',
    size: asset['size'] as int?,
    sha256: digest.startsWith('sha256:') ? digest.substring(7) : null,
  );
}

/// 弹窗里显示的更新说明:去掉图片那几行,多余的空行合并。
String releaseNotes(String body) => body
    .split(RegExp(r'\r?\n'))
    .where((l) => !l.trimLeft().startsWith('!['))
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// 问 GitHub 最新的发行版([channel] 见 [updateChannels])。
/// 还没有发行版时为 null;连不上、出错时抛 [UpdateException]。
Future<Release?> fetchLatestRelease({
  String channel = 'main',
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (channel != 'dev') {
    final j = await _getJson('releases/latest', timeout);
    return j is Map<String, dynamic> ? parseRelease(j) : null;
  }
  final list = await _getJson('releases?per_page=30', timeout);
  final releases = [
    for (final j in list is List ? list : const [])
      if (j is Map<String, dynamic> && j['draft'] != true) ?parseRelease(j),
  ];
  if (releases.isEmpty) return null;
  return releases.reduce(
    (a, b) => compareVersions(a.version, b.version) >= 0 ? a : b,
  );
}

/// GET GitHub 的一个发行版接口,返回解出来的 JSON;404 返回 null。
Future<Object?> _getJson(String path, Duration timeout) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(
      Uri.parse('https://api.github.com/repos/$updateRepo/$path'),
    );
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set(HttpHeaders.userAgentHeader, 'Penna');
    final response = await request.close().timeout(timeout);
    final body = await utf8.decodeStream(response).timeout(timeout);
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode != HttpStatus.ok) {
      throw UpdateException(tr('检查更新失败(HTTP {0})', [response.statusCode]));
    }
    return jsonDecode(body);
  } on UpdateException {
    rethrow;
  } on TimeoutException {
    throw UpdateException(tr('检查更新超时'));
  } on SocketException {
    throw UpdateException(tr('连不上 GitHub'));
  } on Object catch (e) {
    // 只报类型,不转述原文。
    throw UpdateException(tr('检查更新失败({0})', [e.runtimeType]));
  } finally {
    client.close(force: true);
  }
}

/// 解开下载好的安装包,返回里面 penna.exe 所在的文件夹(在别的 isolate 里解,界面不卡)。
Future<String> unpackUpdate(String zip, String into) async {
  await Isolate.run(() => extractFileToDisk(zip, into));
  final exe =
      Directory(into)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.uri.pathSegments.last.toLowerCase() == 'penna.exe')
          .toList()
        ..sort((a, b) => a.path.length - b.path.length);
  if (exe.isEmpty) throw UpdateException(tr('安装包里没有 penna.exe'));
  return exe.first.parent.path;
}

/// PowerShell 单引号字符串里的单引号要写两次。
String _quote(String s) => "'${s.replaceAll("'", "''")}'";

/// 更新脚本:等 [pid](正在运行的 Penna)退出,用 robocopy 把 [from] 里的文件盖到 [to]
/// (文件还被占着时它会重试),再打开 [to] 里的 penna.exe([restart] 为假时不打开),最后删掉 [cleanup]。
String updateScript({
  required int pid,
  required String from,
  required String to,
  required String cleanup,
  bool restart = true,
}) => [
  r"$ErrorActionPreference = 'SilentlyContinue'",
  'Wait-Process -Id $pid -Timeout 120',
  'Start-Sleep -Milliseconds 500',
  'robocopy ${_quote(from)} ${_quote(to)} /E /R:20 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null',
  if (restart)
    'Start-Process -FilePath ${_quote('$to${Platform.pathSeparator}penna.exe')} '
        '-WorkingDirectory ${_quote(to)}',
  'Remove-Item -LiteralPath ${_quote(cleanup)} -Recurse -Force',
].join('\r\n');

/// 把脚本写成 [dir] 里的 update.ps1。带 BOM 的 UTF-8:Windows 自带的 PowerShell 5 才认得路径里的中文。
Future<File> writeUpdateScript(String script, String dir) =>
    File('$dir${Platform.pathSeparator}update.ps1')
        .writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(script)]);

/// 把脚本写进 [dir] 并在后台(不弹窗口)启动它。之后调用方要尽快退出 Penna。
///
/// 不能用 [ProcessStartMode.detached]:它是 DETACHED_PROCESS(没有控制台),
/// PowerShell 5.1 在这种状态下还没读脚本就以 0 退出(issue #2)。默认模式在
/// 窗口程序里用 CREATE_NO_WINDOW,不弹窗,Penna 退出后脚本照样跑完。
Future<void> launchUpdater(String script, String dir) async {
  final file = await writeUpdateScript(script, dir);
  await Process.start('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    file.path,
  ]);
}

/// Linux:AppImage 是单个文件。把下好的 [next] 设成可执行、换掉 [target](正在跑的文件
/// 在 Linux 上也能直接换),再在后台等 Penna([pid])退出后打开新的。之后调用方要尽快退出。
Future<void> swapAppImage(String next, String target, {int? pid}) async {
  final chmod = await Process.run('chmod', ['+x', next]);
  if (chmod.exitCode != 0) {
    throw UpdateException(tr('更新失败({0})', ['chmod']));
  }
  await File(next).rename(target);
  await Process.start('sh', [
    '-c',
    'while kill -0 ${pid ?? 0} 2>/dev/null; do sleep 0.2; done; exec "\$0"',
    target,
  ], mode: ProcessStartMode.detached);
}

/// 删掉临时文件夹里一小时前留下的 `penna-update-*`(更新没走完时脚本删不到它们)。
/// 新的不动:可能正有一个在下载。出错不管。
Future<void> clearOldUpdates() async {
  try {
    final before = DateTime.now().subtract(const Duration(hours: 1));
    await for (final d in Directory.systemTemp.list()) {
      final name = d.path.split(Platform.pathSeparator).last;
      if (d is! Directory || !name.startsWith('penna-update-')) continue;
      if ((await d.stat()).modified.isBefore(before)) {
        await d.delete(recursive: true).catchError((_) => d);
      }
    }
  } on Object catch (e) {
    debugPrint('清理旧的更新文件失败:${e.runtimeType}');
  }
}
