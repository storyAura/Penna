// 在真实的桌面上跑真应用和真插件,补 `test/` 里跑不到的那一段:
//
//   1. 在设置里填 API Key、点保存,重启后还读得出来。
//      Windows 上 Key 走 DPAPI 存进 keys.dat;别的平台走系统钥匙串
//      (libsecret / Secret Service),这一条只有真跑起来才验得到。
//   2. 本地反推认得出已经配好的 llama-server。
//
// 跑法(需要能连上会话钥匙串的桌面会话):
//
//   PENNA_HOME=/tmp/penna_it flutter test integration_test/linux_settings_test.dart -d linux
//
// 带上 PENNA_TEST_LLAMA_SERVER=<llama-server 的路径> 时才会跑第 2 条。
// PENNA_HOME 是应用本来就认的环境变量,指向哪就只动哪个文件夹,不碰真实数据。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:penna/data/services/config_service.dart';
import 'package:penna/main.dart' as app;
import 'package:penna/ui/core/widgets.dart';
import 'package:penna/ui/features/local/local_page.dart';
import 'package:penna/ui/features/settings/settings_page.dart';

const _secret = 'sk-integration-钥匙';

/// 按标签找到 [PennaField] 里的输入框。
Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(PennaField)),
  matching: find.byType(TextField),
);

/// 「API Key」那张卡片里的保存按钮。页面上别处也可能有同名按钮,所以要限定范围。
Finder _saveButton() => find.descendant(
  of: find.ancestor(of: find.text('API Key'), matching: find.byType(PennaCard)),
  matching: find.widgetWithText(PennaButton, '保存'),
);

Future<void> _fill(WidgetTester tester, String label, String text) async {
  await tester.enterText(_field(label), text);
  await tester.pumpAndSettle();
}

/// 卡片可能在滚动区外面,先滚过去再点。匹配到 0 个或多个时直接报清楚是哪一个,
/// 比 `ensureVisible` 抛出来的 "Bad state: Too many elements" 好查。
Future<void> _tap(WidgetTester tester, Finder finder, String what) async {
  final matches = finder.evaluate().toList();
  if (matches.length != 1) {
    for (final e in matches) {
      debugPrint('「$what」命中:${e.debugGetCreatorChain(4)}');
    }
    fail('「$what」匹配到 ${matches.length} 个,应该只有 1 个');
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final home = Directory(Platform.environment['PENNA_HOME']!);
  final llamaServer = Platform.environment['PENNA_TEST_LLAMA_SERVER'];

  setUpAll(() {
    home.createSync(recursive: true);
    if (llamaServer != null) {
      // 界面上的「选择 llama-server」落盘就是这个样子,先摆好再启动。
      File('${home.path}${Platform.pathSeparator}local.json')
          .writeAsStringSync(jsonEncode({'exePath': llamaServer}));
    }
  });

  testWidgets('设置里填 API Key 保存后重启仍读得出来', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    await _tap(tester, find.byTooltip('设置'), '图标栏的设置');
    await _tap(tester, find.text('添加模型'), '添加模型');

    await _fill(tester, '显示名称', 'IT');
    await _fill(tester, '模型名称', 'it-model');
    await _fill(tester, 'Base URL', 'https://example.invalid/v1');
    await _fill(tester, 'API Key', _secret);
    await _tap(tester, _saveButton(), '保存');

    // 普通设置进 config.json,明文 Key 不能落在里面。
    final json = File('${home.path}${Platform.pathSeparator}config.json')
        .readAsStringSync();
    expect(json, contains('IT'));
    expect(json, isNot(contains(_secret)));
    if (!Platform.isWindows) {
      // 别的平台没有 keys.dat,机密在系统钥匙串里。
      expect(
        File('${home.path}${Platform.pathSeparator}keys.dat').existsSync(),
        isFalse,
      );
    }

    // 「重启」走的就是这条路:新建一个 ConfigService 再 load()。
    final restarted = ConfigService(dir: home);
    await restarted.load();
    expect(restarted.lastError, isNull);
    expect(restarted.config.secrets.values, contains(_secret));
    // 同一个 PENNA_HOME 再跑一次会多一个同名的,所以只要求「有这个模型」。
    expect(restarted.config.llms.where((l) => l.name == 'IT'), isNotEmpty);
  });

  testWidgets('本地反推认得出配置好的 llama-server', (tester) async {
    if (llamaServer == null) {
      markTestSkipped('没给 PENNA_TEST_LLAMA_SERVER');
      return;
    }
    await app.main();
    await tester.pumpAndSettle();

    // 「本地反推」页一直留在树里,直接从它的 model 上看解析结果:
    // local.json 里的 exePath 有没有被读进来、有没有被当成要用的 llama-server。
    final page = tester.widget<LocalPage>(find.byType(LocalPage));
    expect(page.model.serverExe, llamaServer);

    // 设置 ▸ 本地反推 那张卡片上也要看得见这个路径。
    await _tap(tester, find.byTooltip('设置'), '图标栏的设置');
    await _tap(
      tester,
      find.descendant(
        of: find.byType(SettingsPage),
        matching: find.text('本地反推'),
      ),
      '设置里的本地反推分区',
    );
    expect(find.textContaining(llamaServer), findsWidgets);
  });
}
