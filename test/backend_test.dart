import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/config_service.dart';

import 'fixtures.dart';

/// 起一个本机假接口,返回 [status] 和 [body],并把收到的请求交给 [onRequest]。
Future<HttpServer> _serve(
  int status,
  String body, {
  void Function(HttpRequest request, String body)? onRequest,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    onRequest?.call(request, await utf8.decodeStream(request));
    request.response.statusCode = status;
    request.response.write(body);
    await request.response.close();
  });
  return server;
}

LlmRequest _request(HttpServer server) => LlmRequest(
  baseUrl: 'http://127.0.0.1:${server.port}/v1/',
  model: 'm',
  apiKey: 'sk-secret',
  messages: const [
    {'role': 'user', 'content': 'hi'},
  ],
);

void main() {
  group('OpenAI 兼容流式接口', () {
    test('解析 SSE 增量,忽略心跳,遇到 [DONE] 结束', () async {
      late String auth;
      late Map<String, dynamic> sent;
      final server = await _serve(
        200,
        ': keep-alive\n\n'
        'data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"你"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"好"}}]}\n\n'
        'data: [DONE]\n\n'
        'data: {"choices":[{"delta":{"content":"不该出现"}}]}\n\n',
        onRequest: (request, body) {
          auth = request.headers.value('authorization')!;
          sent = jsonDecode(body) as Map<String, dynamic>;
        },
      );
      addTearDown(server.close);

      final chunks = await streamOpenAiChat(_request(server)).toList();

      expect(chunks, ['你', '好']);
      expect(auth, 'Bearer sk-secret');
      expect(sent['stream'], isTrue);
      expect(sent['model'], 'm');
    });

    test('接口报错时给出状态码,且错误信息里没有 Key', () async {
      final server = await _serve(401, '{"error":"bad key"}');
      addTearDown(server.close);

      await expectLater(
        streamOpenAiChat(_request(server)).toList(),
        throwsA(
          isA<LlmException>()
              .having((e) => e.message, 'message', contains('401'))
              .having((e) => e.message, 'message', isNot(contains('sk-'))),
        ),
      );
    });

    test('没有空格的 data:[DONE] 也能结束,不会一直等', () async {
      final server = await _serve(
        200,
        'data:{"choices":[{"delta":{"content":"好"}}]}\n\n'
        'data:[DONE]\n\n'
        'data:{"choices":[{"delta":{"content":"不该出现"}}]}\n\n',
      );
      addTearDown(server.close);

      expect(await streamOpenAiChat(_request(server)).toList(), ['好']);
    });

    test('接口不走流式、直接回整段 JSON 时也能拿到回复', () async {
      final server = await _serve(
        200,
        '{"choices":[{"message":{"role":"assistant","content":"整段"}}]}',
      );
      addTearDown(server.close);

      expect(await streamOpenAiChat(_request(server)).toList(), ['整段']);
    });

    test('Key 里混进换行时报错,且错误信息里没有 Key', () async {
      final server = await _serve(200, 'data: [DONE]\n\n');
      addTearDown(server.close);
      final request = LlmRequest(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        model: 'm',
        apiKey: 'sk-sec\nret',
        messages: const [],
      );

      await expectLater(
        streamOpenAiChat(request).toList(),
        throwsA(
          isA<LlmException>().having(
            (e) => e.message,
            'message',
            isNot(contains('sk-')),
          ),
        ),
      );
    });

    test('Base URL 不合法时直接报错', () {
      const bad = LlmRequest(
        baseUrl: 'api.example.com',
        model: 'm',
        apiKey: '',
        messages: [],
      );

      expect(streamOpenAiChat(bad).toList(), throwsA(isA<LlmException>()));
    });
  });

  group('设置存取', () {
    const llm = LlmProfile(id: 'a', name: 'A', baseUrl: 'u', model: 'm');

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('保存后重新读取内容一致,Key 不落进配置文件', () async {
      final first = tempConfig();
      first.update(
        const AppConfig()
            .putLlm(llm)
            .setSecret(llmSecretKey('a'), 'sk-secret')
            .copyWith(activePresetId: 'free', mtEnabled: {'baidu'}),
      );
      await first.flushed();

      final second = ConfigService(dir: first.dir);
      await second.load();

      expect(first.lastError, isNull);
      expect(second.lastError, isNull);
      expect(second.config.agentChain.firstOrNull?.name, 'A');
      expect(second.config.llmKey('a'), 'sk-secret');
      expect(second.config.activePreset.name, '自由改稿');
      expect(second.config.mtEnabled, {'baidu'});
      expect(first.file.readAsStringSync(), isNot(contains('sk-secret')));
      // Key 在 Windows 上放 keys.dat;别的平台在系统钥匙串里,没有这个文件。
      if (Platform.isWindows) {
        expect(first.keysFile.readAsStringSync(), isNot(contains('sk-secret')));
      }
    });

    test('删除模型会连同它的 Key 一起清掉', () async {
      final service = tempConfig();
      service.update(
        const AppConfig().putLlm(llm).setSecret(llmSecretKey('a'), 'sk'),
      );
      service.update(service.config.removeLlm('a'));
      await service.flushed();

      final reloaded = ConfigService(dir: service.dir);
      await reloaded.load();

      expect(reloaded.config.llms, isEmpty);
      expect(reloaded.config.agentChain, isEmpty);
      expect(reloaded.config.secrets, isEmpty);
    });

    test('配置文件损坏时用默认设置,并留下备份', () async {
      final service = tempConfig();
      service.file.writeAsStringSync('{ not json');

      await service.load();

      expect(service.lastError, contains('读取设置失败'));
      expect(service.config.presets, hasLength(factoryPresets.length));
      final names = service.file.parent.listSync().map((f) => f.path);
      expect(names.where((p) => p.contains('config.json.bad-')), hasLength(1));
      expect(service.file.existsSync(), isFalse);
    });
  });
}
