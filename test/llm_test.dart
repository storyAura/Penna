import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/gemini_provider.dart';
import 'package:penna/core/harness/providers/llm_router.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/settings/settings_llm_section.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

LlmRequest _req(String model) => LlmRequest(
  baseUrl: 'http://x',
  model: model,
  apiKey: '',
  messages: const [],
);

LlmProfile _llm(String id, {bool enabled = true}) => LlmProfile(
  id: id,
  name: id.toUpperCase(),
  baseUrl: 'http://x',
  model: id,
  enabled: enabled,
);

void main() {
  // 文件里有 testWidgets,Flutter 的测试环境一开始就启用并拦掉真实的网络请求;
  // 这里好几条测试要连本机的假服务。
  setUp(() => HttpOverrides.global = null);

  group('Google 协议', () {
    test('请求体:system 单列,assistant 改叫 model,连续同一方合并', () {
      final body = geminiBody(
        const LlmRequest(
          baseUrl: '',
          model: 'm',
          apiKey: '',
          temperature: 0.3,
          messages: [
            {'role': 'system', 'content': 'S'},
            {'role': 'user', 'content': 'a'},
            {'role': 'user', 'content': 'b'},
            {'role': 'assistant', 'content': 'c'},
          ],
        ),
      );

      expect(body['systemInstruction'], {
        'parts': [
          {'text': 'S'},
        ],
      });
      expect(body['contents'], [
        {
          'role': 'user',
          'parts': [
            {'text': 'a\n\nb'},
          ],
        },
        {
          'role': 'model',
          'parts': [
            {'text': 'c'},
          ],
        },
      ]);
      expect(body['generationConfig'], {'temperature': 0.3});
    });

    test('Top P 调低了才发出去;Preset 存取不丢', () {
      final body = geminiBody(
        const LlmRequest(
          baseUrl: '',
          model: 'm',
          apiKey: '',
          topP: 0.5,
          messages: [
            {'role': 'user', 'content': 'a'},
          ],
        ),
      );
      expect(body['generationConfig'], {'temperature': 0.7, 'topP': 0.5});

      final preset = factoryPresets.first.copyWith(topP: 0.8);
      expect(AgentPreset.fromJson(preset.toJson()).topP, 0.8);
      // 旧配置里没有这一项:不限制。
      expect(AgentPreset.fromJson(preset.toJson()..remove('topP')).topP, 1);
    });

    test('流式调用:Key 走请求头不进网址,逐段取出文字', () async {
      late Uri uri;
      late String? keyHeader;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        uri = request.uri;
        keyHeader = request.headers.value('x-goog-api-key');
        await utf8.decodeStream(request);
        request.response.write(
          'data: {"candidates":[{"content":{"parts":[{"text":"你"}]}}]}\n\n'
          'data: {"candidates":[{"content":{"parts":[{"text":"好"}]}}]}\n\n',
        );
        await request.response.close();
      });

      final chunks = await streamChat(
        LlmRequest(
          protocol: protocolGoogle,
          baseUrl: 'http://127.0.0.1:${server.port}/v1beta',
          model: 'gemini-x',
          apiKey: 'g-secret',
          messages: const [
            {'role': 'user', 'content': 'hi'},
          ],
        ),
      ).toList();

      expect(chunks, ['你', '好']);
      expect(uri.path, '/v1beta/models/gemini-x:streamGenerateContent');
      expect(uri.queryParameters, {'alt': 'sse'});
      expect(keyHeader, 'g-secret');
    });

    test('Vertex AI 的地址补到 Google 模型那一层,别的地址不动', () {
      const vertex = 'https://aiplatform.googleapis.com';
      expect(geminiBase('$vertex/v1/'), '$vertex/v1/publishers/google');
      expect(geminiBase(vertex), '$vertex/v1/publishers/google');
      expect(
        geminiBase(
          'https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/us-central1',
        ),
        'https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/us-central1/publishers/google',
      );
      expect(
        geminiBase('$vertex/v1/publishers/google'),
        '$vertex/v1/publishers/google',
      );
      expect(geminiBase('http://x/v1beta/'), 'http://x/v1beta');
      expect(geminiBase(' '), contains('generativelanguage'));
    });

    test('Vertex AI 不去拉模型列表,直接让用户手动填', () {
      expect(
        listModels(
          protocol: protocolGoogle,
          baseUrl: 'https://aiplatform.googleapis.com/v1',
          apiKey: 'k',
        ),
        throwsA(
          isA<LlmException>().having(
            (e) => e.message,
            'message',
            contains('手动填'),
          ),
        ),
      );
    });

    test('被安全策略拦截时报出原因', () {
      expect(
        () => parseGeminiLine(
          'data: {"promptFeedback":{"blockReason":"SAFETY"}}',
        ),
        throwsA(isA<LlmException>()),
      );
    });
  });

  group('拉取模型列表', () {
    test('两种协议:Key 走请求头,只留能对话的,按名字排序', () async {
      final seen = <String, String?>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final google = request.uri.path.startsWith('/v1beta');
        seen[request.uri.path] = google
            ? request.headers.value('x-goog-api-key')
            : request.headers.value(HttpHeaders.authorizationHeader);
        request.response.write(
          google
              ? '{"models":['
                    '{"name":"models/gemini-b","supportedGenerationMethods":["generateContent"]},'
                    '{"name":"models/embed-x","supportedGenerationMethods":["embedContent"]},'
                    '{"name":"models/gemini-a"}]}'
              : '{"data":[{"id":"gpt-b"},{"id":"gpt-a"},{"id":"gpt-a"},{"x":1}]}',
        );
        await request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';

      expect(
        await listModels(
          protocol: protocolGoogle,
          baseUrl: '$base/v1beta',
          apiKey: 'g-secret',
        ),
        ['gemini-a', 'gemini-b'],
      );
      expect(
        await listModels(
          protocol: protocolOpenAi,
          baseUrl: '$base/v1/',
          apiKey: 'o-secret',
        ),
        ['gpt-a', 'gpt-b'],
      );
      expect(seen, {
        '/v1beta/models': 'g-secret',
        '/v1/models': 'Bearer o-secret',
      });
    });

    test('接口报错或回的不是 JSON 时说人话', () async {
      var status = HttpStatus.unauthorized;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response.statusCode = status;
        request.response.write('<html>${'x' * 1000}');
        await request.response.close();
      });
      Future<List<String>> pull() => listModels(
        protocol: protocolOpenAi,
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'o-secret',
      );
      Matcher saying(Matcher message) => throwsA(
        isA<LlmException>().having((e) => e.message, 'message', message),
      );

      await expectLater(
        pull,
        saying(allOf(startsWith('模型接口返回 401'), hasLength(lessThan(400)))),
      );
      status = HttpStatus.ok;
      await expectLater(pull, saying(equals('接口返回的不是模型列表')));
      await expectLater(
        () => listModels(protocol: protocolOpenAi, baseUrl: 'x', apiKey: ''),
        saying(startsWith('Base URL 无效')),
      );
    });
  });

  group('模型按顺序切换', () {
    test('前一个没出字就失败时换下一个,并报告是谁在回答', () async {
      final answering = <String>[];
      final trying = <String>[];

      final out = await streamWithFailover(
        [('A', _req('a')), ('B', _req('b'))],
        (r) => r.model == 'a'
            ? Stream.error(const LlmException('挂了'))
            : Stream.fromIterable(['你', '好']),
        onTrying: trying.add,
        onAnswering: answering.add,
      ).join();

      expect(out, '你好');
      expect(trying, ['A', 'B']);
      expect(answering, ['B']);
    });

    test('已经开始回答后出错,不换模型,直接报错', () async {
      var calledB = false;
      Stream<String> half() async* {
        yield '半';
        throw const LlmException('断了');
      }

      final seen = <String>[];
      await expectLater(
        streamWithFailover([('A', _req('a')), ('B', _req('b'))], (r) {
          if (r.model == 'b') calledB = true;
          return half();
        }).forEach(seen.add),
        throwsA(isA<LlmException>()),
      );

      expect(seen, ['半']);
      expect(calledB, isFalse);
    });

    test('停止后立刻掐断当前模型,也不再去问后面的模型', () async {
      final first = StreamController<String>();
      var cancelledFirst = false;
      first.onCancel = () => cancelledFirst = true;
      final asked = <String>[];

      final sub = streamWithFailover([('A', _req('a')), ('B', _req('b'))], (r) {
        asked.add(r.model);
        return first.stream;
      }).listen((_) {});
      await pumpEventQueue();
      await sub.cancel();
      // 停止之后第一个模型才报错:不应该因此转去问第二个。
      first.addError(const LlmException('挂了'));
      await pumpEventQueue();

      expect(cancelledFirst, isTrue);
      expect(asked, ['a']);
    });

    test('Google 因安全等原因中止且没有内容时,报出原因', () {
      expect(
        () =>
            parseGeminiLine('data: {"candidates":[{"finishReason":"SAFETY"}]}'),
        throwsA(
          isA<LlmException>().having(
            (e) => e.message,
            'message',
            contains('SAFETY'),
          ),
        ),
      );
    });

    test('全部失败时列出每个模型的原因', () async {
      await expectLater(
        streamWithFailover([
          ('A', _req('a')),
          ('B', _req('b')),
        ], (r) => Stream.error(LlmException('${r.model} 挂了'))).join(),
        throwsA(
          isA<LlmException>().having(
            (e) => e.message,
            'message',
            'A:a 挂了\nB:b 挂了',
          ),
        ),
      );
    });
  });

  group('模型顺序与指定', () {
    final cfg = const AppConfig()
        .putLlm(_llm('a'))
        .putLlm(_llm('b', enabled: false))
        .putLlm(_llm('c'));

    test('默认按列表顺序,跳过关掉的', () {
      expect(cfg.agentChain.map((l) => l.id), ['a', 'c']);
      expect(cfg.polishChain.map((l) => l.id), ['a', 'c']);
    });

    test('Agent 和润色可以各指定一个,指定的排第一,其余仍作后备', () {
      final pinned = cfg.copyWith(polishLlmId: () => 'c');

      expect(pinned.agentChain.map((l) => l.id), ['a', 'c']);
      expect(pinned.polishChain.map((l) => l.id), ['c', 'a']);
    });

    test('指定了被关掉的模型时当作没指定', () {
      final pinned = cfg.copyWith(activeLlmId: () => 'b');

      expect(pinned.agentChain.map((l) => l.id), ['a', 'c']);
    });

    test('拖动改顺序;删除模型会清掉对它的指定', () {
      final moved = cfg.moveLlm(2, 0).copyWith(polishLlmId: () => 'c');

      expect(moved.llms.map((l) => l.id), ['c', 'a', 'b']);
      expect(moved.removeLlm('c').polishLlmId, isNull);
    });

    test('协议和开关能存能读;旧配置默认是 OpenAI 且启用', () {
      final google = _llm('g')
          .copyWith(protocol: protocolGoogle, enabled: false);
      final loaded = LlmProfile.fromJson(
        jsonDecode(jsonEncode(google.toJson())) as Map<String, dynamic>,
      );
      final old = LlmProfile.fromJson(const {
        'id': 'o',
        'name': 'O',
        'baseUrl': 'u',
        'model': 'm',
      });

      expect(loaded.protocol, protocolGoogle);
      expect(loaded.enabled, isFalse);
      expect(old.protocol, protocolOpenAi);
      expect(old.enabled, isTrue);
    });
  });

  group('润色', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
    });

    StudioViewModel studio(ChatStreamer stream, {String? polishId}) {
      final config = tempConfig()
        ..update(
          const AppConfig()
              .putLlm(_llm('agent'))
              .putLlm(_llm('polish'))
              .copyWith(polishLlmId: () => polishId),
        );
      return StudioViewModel(config: config, streamChat: stream)
        ..setText(0, 'a red fox, in the rain, 35mm');
    }

    test('只改选中的一段,结果是待确认的改动;采纳后拼回全文', () async {
      late LlmRequest seen;
      final vm = studio((r) {
        seen = r;
        return Stream.fromIterable(['under heavy ', 'monsoon rain']);
      }, polishId: 'polish');
      vm.bodySelection = (10, 22); // " in the rain"

      expect(await vm.polish(''), isNull);

      expect(seen.model, 'polish');
      expect(seen.messages.last['content'], contains('in the rain'));
      expect(vm.finalPrompt, 'a red fox, in the rain, 35mm');
      expect(vm.pending!.removed, ' in the rain');
      expect(vm.pending!.added, ' under heavy monsoon rain');

      vm.acceptDiff();
      expect(vm.finalPrompt, 'a red fox, under heavy monsoon rain, 35mm');
    });

    test('没有选区时改全文;带要求时标题里写明;驳回后原文不变', () async {
      final vm = studio((_) => Stream.value('a crimson fox'));

      expect(await vm.polish('换个颜色'), isNull);

      expect(vm.pending!.title, '修改:换个颜色');
      expect(vm.pending!.removed, 'a red fox, in the rain, 35mm');
      vm.rejectDiff();
      expect(vm.finalPrompt, 'a red fox, in the rain, 35mm');
    });

    test('润色期间成稿被改了就放弃这次结果', () async {
      final reply = StreamController<String>();
      final vm = studio((_) => reply.stream);

      final pending = vm.polish('');
      vm.setText(0, 'something else');
      reply.add('x');
      await reply.close();

      expect(await pending, contains('被改动'));
      expect(vm.pending, isNull);
      expect(vm.finalPrompt, 'something else');
    });

    test('改完一段并采纳后,不选内容再润色是改全文,不沿用旧选区', () async {
      final vm = studio((_) => Stream.value('X'));
      vm.bodySelection = (2, 5);
      await vm.polish('');
      vm.acceptDiff();

      expect(vm.polishRange, (0, vm.body.length));
    });

    test('只选中空白时不润色', () async {
      final vm = studio((_) => Stream.value('X'));
      vm.bodySelection = (1, 2); // "a red" 里的那个空格

      expect(await vm.polish(''), '选中的内容为空');
      expect(vm.pending, isNull);
    });

    test('模型出错、成稿为空、已有待确认改动时都说明原因', () async {
      final failing = studio((_) => Stream.error(const LlmException('挂了')));
      expect(await failing.polish(''), contains('挂了'));
      expect(failing.isPolishing, isFalse);

      final empty = studio((_) => const Stream.empty())..setText(0, '');
      expect(await empty.polish(''), '成稿为空');

      final busy = studio((_) => Stream.value('y'));
      await busy.polish('');
      expect(await busy.polish(''), contains('待确认'));
    });
  });

  group('设置页拉取模型', () {
    testWidgets('测试连接:每个模型发一句,通了说正常,没填模型先提醒', (tester) async {
      late HttpServer server;
      final asked = <Object?>[];
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          final body = jsonDecode(await utf8.decodeStream(request)) as Map;
          asked.add(body['model']);
          request.response.write(
            'data: {"choices":[{"delta":{"content":"hi"}}]}\n\n',
          );
          await request.response.close();
        });
      });
      addTearDown(() => server.close(force: true));
      final config = tempConfig();
      final llm = LlmProfile(
        id: 'a',
        name: 'A',
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: '',
      );
      config.update(const AppConfig().putLlm(llm));
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: config,
                builder: (_, _) => LlmSection(service: config),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('测试连接'));
      await tester.pump();
      expect(find.text('先填模型名称'), findsOneWidget);

      config.update(config.config.putLlm(llm.copyWith(model: 'm1, m2')));
      await tester.pump();
      await tester.tap(find.text('测试连接'));
      for (var i = 0; i < 100 && find.text('连接正常').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(find.text('连接正常'), findsOneWidget);
      expect(asked, ['m1', 'm2']);
    });

    testWidgets('拉取后点一行,就勾选并填进模型名称;点保存才写进设置', (tester) async {
      late HttpServer server;
      await tester.runAsync(() async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          request.response.write('{"data":[{"id":"gpt-a"},{"id":"gpt-b"}]}');
          await request.response.close();
        });
      });
      addTearDown(() => server.close(force: true));
      final config = tempConfig();
      config.update(
        const AppConfig().putLlm(
          LlmProfile(
            id: 'a',
            name: 'A',
            baseUrl: 'http://127.0.0.1:${server.port}',
            model: '',
          ),
        ),
      );
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: config,
                builder: (_, _) => LlmSection(service: config),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('拉取模型'));
      for (var i = 0; i < 100 && find.text('gpt-b').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.ensureVisible(find.text('gpt-b'));
      await tester.tap(find.text('gpt-b'));
      await tester.pump();

      expect(config.config.llms.single.model, '');
      expect(find.text('未保存'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'gpt-b'), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsOneWidget);

      // 再勾一个:两个都留着,按勾选的先后排;已选的列在列表上面。
      await tester.ensureVisible(find.text('gpt-a'));
      await tester.tap(find.text('gpt-a'));
      await tester.pump();

      expect(find.text('1 · gpt-b'), findsOneWidget);
      expect(find.text('2 · gpt-a'), findsOneWidget);

      await tester.ensureVisible(find.text('保存'));
      // 写盘在假时钟里等不到;内存里的设置是立即更新的。
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(config.config.llms.single.model, 'gpt-b, gpt-a');
      expect(config.config.llms.single.models, ['gpt-b', 'gpt-a']);
      expect(find.text('未保存'), findsNothing);
    });

    testWidgets('放弃:改过的名称回到已保存的值', (tester) async {
      final config = tempConfig();
      config.update(
        const AppConfig().putLlm(
          const LlmProfile(id: 'a', name: 'A', baseUrl: '', model: ''),
        ),
      );
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: config,
                builder: (_, _) => LlmSection(service: config),
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.widgetWithText(TextField, 'A'), 'B');
      await tester.pump();
      expect(config.config.llms.single.name, 'A');

      await tester.tap(find.text('放弃'));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'A'), findsOneWidget);
      expect(find.text('未保存'), findsNothing);
    });
  });
}
