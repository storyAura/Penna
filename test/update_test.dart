import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/update/updater.dart';
import 'package:penna/ui/features/update/update_flow.dart';

Release _release(String version, {String notes = '## 新增\n- **本地反推**'}) => (
  version: version,
  notes: notes,
  url: 'https://example.com/x.zip',
  size: 1,
  sha256: null,
);

final _theme = ThemeData(
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
);

void main() {
  test('版本号:按段比数字,开头的 v 不算', () {
    expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(compareVersions('v1.0.1', '1.0.1'), 0);
    expect(compareVersions('1.0.1', '1.1.0'), lessThan(0));
    expect(compareVersions('2.0', '1.9.9'), greaterThan(0));
  });

  test('测试版:比同号的正式版旧,比上一个正式版新,同号的按日期再按第几次', () {
    const dev = '1.0.2-261020-7-dev';
    expect(compareVersions(dev, '1.0.1'), greaterThan(0));
    expect(compareVersions('1.0.2', dev), greaterThan(0));
    expect(compareVersions('1.0.2-261020-10-dev', dev), greaterThan(0));
    expect(compareVersions('1.0.2-261021-1-dev', dev), greaterThan(0));
    expect(compareVersions('v$dev', '$dev+3'), 0);
  });

  test('发行版:挑 Windows 安装包,带上 SHA256;说明去掉图片', () {
    final r = parseRelease({
      'tag_name': 'v1.0.2',
      'body': '# 更新\n\n![图](docs/x.png)\n\n\n\n- 新功能',
      'assets': [
        {'name': 'notes.txt', 'browser_download_url': 'a', 'size': 1},
        {
          'name': 'Penna-v1.0.2-windows-x64.zip',
          'browser_download_url': 'https://github.com/x.zip',
          'size': 42,
          'digest': 'sha256:abc',
        },
        {
          'name': 'Penna-v1.0.2-linux-x86_64.AppImage',
          'browser_download_url': 'https://github.com/x.AppImage',
          'size': 43,
        },
      ],
    }, suffix: '-windows-x64.zip')!;
    expect(r.version, '1.0.2');
    expect(r.url, 'https://github.com/x.zip');
    expect((r.size, r.sha256), (42, 'abc'));
    expect(r.notes, '# 更新\n\n- 新功能');
    expect(parseRelease({'tag_name': 'v1', 'assets': []}), isNull);
  });

  test('发行版:Linux 挑 AppImage,没有 AppImage 的发行版不算', () {
    const linux = '-linux-x86_64.AppImage';
    Map<String, dynamic> release(String asset) => {
      'tag_name': 'v1.0.3',
      'assets': [
        {'name': asset, 'browser_download_url': 'https://github.com/$asset'},
      ],
    };
    expect(
      parseRelease(
        release('Penna-v1.0.3-linux-x86_64.AppImage'),
        suffix: linux,
      )!.url,
      'https://github.com/Penna-v1.0.3-linux-x86_64.AppImage',
    );
    expect(
      parseRelease(release('Penna-v1.0.3-windows-x64.zip'), suffix: linux),
      isNull,
    );
  });

  test('解开安装包:找到 penna.exe 所在的文件夹', () async {
    final tmp = Directory.systemTemp.createTempSync('penna_unpack');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final archive = Archive()
      ..addFile(ArchiveFile.string('penna.exe', 'exe'))
      ..addFile(ArchiveFile.string('data/app.so', 'so'));
    final zip = File('${tmp.path}/u.zip')
      ..writeAsBytesSync(ZipEncoder().encode(archive));

    final dir = await unpackUpdate(zip.path, '${tmp.path}/new');

    expect(File('$dir/penna.exe').existsSync(), isTrue);
    expect(File('$dir/data/app.so').existsSync(), isTrue);
  });

  test(
    '更新脚本:等 Penna 退出后覆盖文件(含子文件夹),再清掉临时文件',
    () async {
      // 路径里有中文、空格和单引号,看引号写对没有。
      final root = Directory.systemTemp.createTempSync('penna 更新 it\'s ');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final from = Directory('${root.path}/new')..createSync();
      final to = Directory('${root.path}/装在这里')..createSync();
      final cleanup = Directory('${root.path}/temp')..createSync();
      File('${from.path}/penna.exe').writeAsStringSync('new exe');
      File('${from.path}/data/app.so')
        ..createSync(recursive: true)
        ..writeAsStringSync('new so');
      File('${to.path}/penna.exe').writeAsStringSync('old exe');
      File('${to.path}/data/app.so')
        ..createSync(recursive: true)
        ..writeAsStringSync('old so');
      File('${to.path}/keep.txt').writeAsStringSync('user file');

      final script = await writeUpdateScript(
        updateScript(
          // 一个已经不在的进程:不用等。
          pid: 999999,
          from: from.path,
          to: to.path,
          cleanup: cleanup.path,
          restart: false,
        ),
        root.path,
      );
      final run = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
      ]);

      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      expect(File('${to.path}/penna.exe').readAsStringSync(), 'new exe');
      expect(File('${to.path}/data/app.so').readAsStringSync(), 'new so');
      expect(File('${to.path}/keep.txt').readAsStringSync(), 'user file');
      expect(cleanup.existsSync(), isFalse);
    },
    skip: Platform.isWindows ? null : '更新脚本是 PowerShell 的,只在 Windows 上跑',
    timeout: const Timeout(Duration(minutes: 1)),
  );

  group('检查更新的弹窗', () {
    Future<void> pump(WidgetTester tester, Future<Release?> Function() fetch) =>
        tester.pumpWidget(
          MaterialApp(
            // 和程序一样用悬浮的提示条(showToast 给了固定宽度)。
            theme: _theme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      checkForUpdate(context, fetch: fetch, current: '1.0.1'),
                  child: const Text('查'),
                ),
              ),
            ),
          ),
        );

    testWidgets('有新版本:弹窗写着版本号和更新说明', (tester) async {
      await pump(tester, () async => _release('1.0.2'));
      await tester.tap(find.text('查'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 v1.0.2'), findsOneWidget);
      expect(find.text('当前版本 v1.0.1'), findsOneWidget);
      expect(find.textContaining('本地反推', findRichText: true), findsOneWidget);
      expect(find.text('更新并重启'), findsOneWidget);

      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v1.0.2'), findsNothing);
    });

    testWidgets('已是最新:只提示一句,不弹窗', (tester) async {
      await pump(tester, () async => _release('1.0.1'));
      await tester.tap(find.text('查'));
      await tester.pump();
      // 提示条要再画一帧才出来。
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('已是最新版本'), findsOneWidget);
      expect(find.text('更新并重启'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('切了通道:旧一些的正式版也给装', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => checkForUpdate(
                  context,
                  switching: true,
                  fetch: () async => _release('1.0.2'),
                  current: '1.0.3-261027-5-dev',
                ),
                child: const Text('查'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('查'));
      await tester.pumpAndSettle();

      expect(find.text('切换到 v1.0.2'), findsOneWidget);
      expect(find.text('更新并重启'), findsOneWidget);
    });

    testWidgets('启动时自动检查出错:不打扰用户', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => checkForUpdate(
                  context,
                  quiet: true,
                  fetch: () async => throw const UpdateException('连不上 GitHub'),
                ),
                child: const Text('查'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('查'));
      await tester.pump();

      expect(find.text('连不上 GitHub'), findsNothing);
    });
  });
}
