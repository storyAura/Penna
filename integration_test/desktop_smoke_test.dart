// PENNA_HOME 必须指向专用测试目录。真实模型接口由本机 HTTP 服务提供，
// 原生窗口、剪贴板、图片解码和持久化仍使用实际插件。
// 可选 PENNA_TEST_ONNX 指向 input/output 均为 [1, 3] 的 Identity ONNX 模型。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/config_service.dart';
import 'package:penna/data/services/notebook_store.dart';
import 'package:penna/data/services/onnx_model.dart';
import 'package:penna/main.dart' as app;
import 'package:penna/ui/features/local/local_model.dart';
import 'package:penna/ui/features/notebook/notebook_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面主流程：真实窗口、流式成稿、七页导航、保存重载及原生插件', (tester) async {
    final homePath = Platform.environment['PENNA_HOME'];
    expect(homePath, isNotNull, reason: '请指定独立的 PENNA_HOME 测试目录');
    final home = Directory(homePath!)..createSync(recursive: true);
    final configFile = File('${home.path}/config.json');
    if (!configFile.existsSync()) configFile.writeAsStringSync('{}');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requestedModels = <Object?>[];
    server.listen((request) async {
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      requestedModels.add(body['model']);
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': '<draft>【主体】a red fox in a quiet garden</draft>'},
            },
          ],
        })}\n\n',
      );
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final errorHandler = FlutterError.onError;
    final dispatcherHandler = tester.binding.platformDispatcher.onError;
    final printHandler = debugPrint;
    try {
      await app.main();
    } finally {
      // 保留测试框架的错误捕获；应用日志入口不能吞掉测试失败。
      FlutterError.onError = errorHandler;
      tester.binding.platformDispatcher.onError = dispatcherHandler;
      debugPrint = printHandler;
    }
    await tester.pumpAndSettle();
    final shell = tester.widget<AppShell>(find.byType(AppShell));
    final config = shell.config;
    config.update(
      config.config.putLlm(
        LlmProfile(
          id: 'desktop-smoke',
          name: 'Desktop smoke',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'desktop-smoke',
        ),
      ),
    );
    await config.flushed();
    await tester.pumpAndSettle();
    final composer = find
        .byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText ==
                  'Enter 发送 · Shift+Enter 换行 · @ 引用 Skill',
        )
        .hitTestable();
    expect(composer, findsOneWidget);
    await tester.enterText(composer, '写一只红狐狸');
    await tester.tap(find.byTooltip('发送').hitTestable());
    for (
      var i = 0;
      i < 100 && (requestedModels.isEmpty || shell.vm.isStreaming);
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(requestedModels, ['desktop-smoke']);
    expect(shell.vm.finalPrompt, 'a red fox in a quiet garden');
    shell.vm.flush();
    final saved = jsonDecode(
      File('${home.path}/workspace.json').readAsStringSync(),
    );
    expect(saved['messages'], hasLength(2));

    for (final page in ['档案库', '角色库', '本地反推', '区域控制工作台', '记事本', '设置', '工作台']) {
      await tester.tap(find.byTooltip(page));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: page);
    }
    await tester.tap(find.byTooltip('记事本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建本子').hitTestable());
    await tester.pumpAndSettle();
    final notes = tester.widget<NotebookPage>(find.byType(NotebookPage)).store;
    final book = notes.books.last;
    notes.updateNote(book.id, book.notes.single.id, text: '桌面原生保存验收');
    final loadedNotes = NotebookStore(File('${home.path}/notebooks.json'));
    await loadedNotes.load();
    expect(loadedNotes.books.last.notes.single.text, '桌面原生保存验收');
    loadedNotes.dispose();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    try {
      await Clipboard.setData(const ClipboardData(text: 'Penna desktop smoke'));
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        'Penna desktop smoke',
      );
    } finally {
      await Clipboard.setData(clipboard ?? const ClipboardData(text: ''));
    }
    final bytes = (await rootBundle.load('assets/avatar.png')).buffer
        .asUint8List();
    final pixels = await decodeImage(bytes, (_, _) => (width: 2, height: 2));
    expect(pixels.rgba, hasLength(16));

    const sampleKey = 'native-smoke-test-secret';
    config.update(
      config.config.setSecret(llmSecretKey('desktop-smoke'), sampleKey),
    );
    await config.flushed();
    expect(configFile.readAsStringSync(), isNot(contains(sampleKey)));
    if (Platform.isWindows) expect(config.keysFile.existsSync(), isTrue);
    final loadedConfig = ConfigService(dir: home);
    await loadedConfig.load();
    expect(
      loadedConfig.config.llms.any((m) => m.id == 'desktop-smoke'),
      isTrue,
    );
    expect(loadedConfig.lastError, isNull);
    expect(loadedConfig.config.llmKey('desktop-smoke'), sampleKey);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('可选原生 ONNX：实际创建 session、推理并释放', (tester) async {
    final path = Platform.environment['PENNA_TEST_ONNX'];
    if (path == null) {
      markTestSkipped('未提供 PENNA_TEST_ONNX');
      return;
    }
    for (var i = 0; i < 3; i++) {
      final model = await OnnxModel.load(path);
      try {
        final result = await model.run({
          'input': (
            data: Float32List.fromList([0.25, 0.5, 0.75]),
            shape: [1, 3],
          ),
        });
        expect(result, [0.25, 0.5, 0.75]);
      } finally {
        await model.close();
      }
    }
  });
}
