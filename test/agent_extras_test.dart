import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/llm_log.dart';
import 'package:penna/core/harness/llm_probe.dart';
import 'package:penna/core/harness/notebook_tags.dart';
import 'package:penna/core/harness/piercing_document.dart';
import 'package:penna/core/harness/providers/gemini_provider.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/core/harness/providers/llm_router.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/notebook_store.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

// 2026-11-13 这一轮加的:Agent 读写记事本、穿甲弹的文档模式、测试连接测速。

StudioViewModel _studio(
  List<LlmRequest> seen,
  String Function() reply, {
  AppConfig Function(AppConfig)? setup,
}) {
  final config = tempConfig();
  final base = const AppConfig().putLlm(
    const LlmProfile(id: '1', name: 'A', baseUrl: 'http://x', model: 'm'),
  );
  config.update(setup?.call(base) ?? base);
  return StudioViewModel(
    config: config,
    streamChat: (r) {
      seen.add(r);
      return Stream.value(reply());
    },
  );
}

/// 写了几个字就断线。
Stream<String> _broken() async* {
  yield 'a fox in ';
  throw const LlmException('断了');
}

void main() {
  group('记事本', () {
    test('拆出 <save-note>:属性顺序随意,没写 book 的不算,半截的先不显示', () {
      final r = splitSaveNote(
        '记下了<save-note title="咪咪" book="风格">8k, cel</save-note>'
        '<save-note title="x">没有本子</save-note>',
      );
      expect(r.prose, '记下了');
      expect(r.saves.single.book, '风格');
      expect(r.saves.single.title, '咪咪');
      expect(r.saves.single.text, '8k, cel');
      expect(splitSaveNote('好的<save-no').prose, '好的');
      expect(splitSaveNote('好的<save-note book="a">写到一半').prose, '好的');
    });

    test('putNote:没有的本子新建(用掉自带的空条),同名条目换内容', () {
      final store = NotebookStore()..putNote('服装', '女仆', 'maid');
      expect(store.books.single.name, '服装');
      expect(store.books.single.notes.single.text, 'maid');
      store
        ..putNote('服装', '女仆', 'maid, apron')
        ..putNote('服装', '水手服', 'serafuku');
      final notes = store.books.single.notes;
      expect([for (final n in notes) n.title], ['女仆', '水手服']);
      expect(notes.first.text, 'maid, apron');
    });

    test('系统提示列出本子,<read-notebook> 读回全文,<save-note> 说完存进去', () async {
      final seen = <LlmRequest>[];
      final vm = _studio(
        seen,
        () => seen.length == 1
            ? '<read-notebook>风格</read-notebook>'
            : '存好了<save-note book="服装" title="女仆">maid</save-note>',
      );
      final store = NotebookStore()..putNote('风格', 'PVC', 'pastel aesthetic');
      vm.notebooks = store;

      vm.send('用记事本里的 PVC 风格');
      await pumpEventQueue();

      final system = seen.first.messages.first['content']!;
      expect(system, contains('「风格」:PVC'));
      expect(system, contains('<read-notebook>'));
      final tool = seen.last.messages.last['content']!;
      expect(tool, contains('【记事本】'));
      expect(tool, contains('pastel aesthetic'));
      expect(store.books.last.name, '服装');
      expect(store.books.last.notes.single.text, 'maid');
      expect(vm.messages.last.toolSummary, contains('服装 · 女仆'));
    });
  });

  group('穿甲弹文档模式', () {
    const messages = [
      {'role': 'system', 'content': 'S'},
      {'role': 'user', 'content': '画一只猫'},
      {'role': 'assistant', 'content': 'A'},
      {'role': 'user', 'content': '再来'},
    ];

    test('收不了文件的接口:用户的话包成「要求-N.md」放进消息,要求回复写成文档', () {
      final out = documentRequest(messages, const {}, asFile: false);
      expect(out.messages.first['content'], 'S');
      expect(
        out.messages[1]['content'],
        startsWith('<upload name="要求-1.md">\n画一只猫\n</upload>'),
      );
      expect(out.messages[1]['content'], contains('<document name="回复-1.md">'));
      expect(out.messages[2]['content'], 'A');
      expect(out.messages[3]['content'], contains('要求-2.md'));
      expect(out.images, isEmpty);
    });

    test('Google 接口:文档当文件传,消息里只留要求', () {
      final img = (mime: 'image/png', bytes: Uint8List(1));
      final out = documentRequest(messages, {
        1: [img],
      }, asFile: true);
      expect(out.messages[1]['content'], isNot(contains('画一只猫')));
      expect(out.messages[1]['content'], contains('要求-1.md'));
      expect(out.images[1]!.first.mime, 'image/png');
      expect(out.images[1]!.last.mime, documentMime);
      expect(utf8.decode(out.images[1]!.last.bytes), '画一只猫');
      expect(utf8.decode(out.images[3]!.single.bytes), '再来');
    });

    test('显示时去掉 <document> 包装,半截的标签先不显示', () {
      expect(
        stripDocumentMarks('写好了\n<document name="a.md">\n# 正文\n</document>'),
        '写好了\n\n# 正文\n',
      );
      expect(stripDocumentMarks('好<docu'), '好');
      expect(stripDocumentMarks('好<document name="a'), '好');
      expect(stripDocumentMarks('正文</doc'), '正文');
      expect(stripDocumentMarks('a < b'), 'a < b');
    });

    test('对话走文档模式:不带提示词模式的文字;关掉穿甲弹就不走', () async {
      final seen = <LlmRequest>[];
      final vm = _studio(
        seen,
        () => '<document name="x.md">好</document>',
        setup: (c) => c.copyWith(
          piercing: true,
          piercingPrompt: '穿甲',
          piercingDocument: true,
        ),
      );
      vm.send('你好');
      await pumpEventQueue();

      final sent = seen.single.messages;
      expect(sent.first['content'], isNot(contains('穿甲')));
      expect(vm.config.config.piercingText, isEmpty);
      expect(sent, hasLength(2));
      expect(sent.last['content'], startsWith('<upload name="要求-1.md">\n你好'));
      expect(sent.last['content'], isNot(contains('穿甲')));

      vm.config.update(vm.config.config.copyWith(piercing: false));
      vm.send('再来');
      await pumpEventQueue();
      expect(seen.last.messages.last['content'], '再来');
    });
  });

  group('Google 用量档位', () {
    LlmRequest req(String base, String tier, {String key = 'k'}) => LlmRequest(
      baseUrl: base,
      model: 'gemini-3.8-flash',
      apiKey: key,
      protocol: 'google',
      serviceTier: tier,
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
    );
    const dev = 'https://generativelanguage.googleapis.com/v1beta';
    const express = 'https://aiplatform.googleapis.com/v1';
    const project =
        'https://aiplatform.googleapis.com/v1/projects/p/locations/global';

    test('认出三条线', () {
      expect(geminiTransport(dev), GeminiTransport.developer);
      expect(geminiTransport(''), GeminiTransport.developer);
      expect(geminiTransport(express), GeminiTransport.vertexExpress);
      expect(geminiTransport(project), GeminiTransport.vertexProject);
      expect(geminiTierSupported(express), isFalse);
    });

    test('Developer API:档位放在请求体最外层,自动时不传;不加 Vertex 的头', () {
      expect(geminiBody(req(dev, 'flex'))['service_tier'], 'flex');
      expect(geminiBody(req(dev, '')).containsKey('service_tier'), isFalse);
      expect(geminiHeaders(req(dev, 'priority')), {'x-goog-api-key': 'k'});
    });

    test('Vertex 项目路径:档位走请求头,Flex 带服务端超时;OAuth 令牌用 Bearer', () {
      expect(
        geminiBody(req(project, 'flex')).containsKey('service_tier'),
        isFalse,
      );
      final h = geminiHeaders(req(project, 'flex', key: 'ya29.token'));
      expect(h['authorization'], 'Bearer ya29.token');
      expect(h['X-Vertex-AI-LLM-Shared-Request-Type'], 'flex');
      expect(h['X-Server-Timeout'], '600');
      // 默认先用已买的容量:不加 Request-Type: shared。
      expect(h.containsKey('X-Vertex-AI-LLM-Request-Type'), isFalse);
      expect(geminiHeaders(req(project, 'standard')).keys, ['x-goog-api-key']);
    });

    test('Vertex Express 不传档位', () {
      expect(
        geminiBody(req(express, 'flex')).containsKey('service_tier'),
        isFalse,
      );
      expect(geminiHeaders(req(express, 'flex')), {'x-goog-api-key': 'k'});
    });

    test('读出实际档位;Flex 等得更久;设置里存得下来', () {
      expect(
        parseGeminiTier('data: {"usageMetadata":{"serviceTier":"STANDARD"}}'),
        'standard',
      );
      expect(
        parseGeminiTier(
          'data: {"usageMetadata":{"trafficType":"ON_DEMAND_PRIORITY"}}',
        ),
        'priority',
      );
      expect(parseGeminiTier('data: {"usageMetadata":{}}'), isNull);
      expect(llmStallFor(req(dev, 'flex')), const Duration(minutes: 15));
      const p = LlmProfile(
        id: 'g',
        name: 'G',
        baseUrl: dev,
        model: 'm',
        protocol: 'google',
        serviceTier: 'flex',
      );
      expect(LlmProfile.fromJson(p.toJson()).serviceTier, 'flex');
      expect(
        LlmProfile.fromJson({...p.toJson(), 'serviceTier': 'turbo'})
            .serviceTier,
        '',
      );
    });
  });

  group('接着写', () {
    test('写了半截出错:留着写好的部分,接着写时一起发回去,写出来的接在后面', () async {
      final seen = <LlmRequest>[];
      var calls = 0;
      final config = tempConfig()
        ..update(
          const AppConfig().putLlm(
            const LlmProfile(
              id: '1',
              name: 'A',
              baseUrl: 'http://x',
              model: 'm',
            ),
          ),
        );
      final vm = StudioViewModel(
        config: config,
        streamChat: (r) {
          seen.add(r);
          calls++;
          if (calls == 1) {
            return _broken();
          }
          return Stream.value('the snow');
        },
      );

      vm.send('画狐狸');
      await pumpEventQueue();
      expect(vm.messages.last.failed, isTrue);
      expect(vm.partialLast, 'a fox in ');
      expect(llmLog.events.first.kind, LlmEventKind.error);

      expect(vm.continueReply(), isNull);
      await pumpEventQueue();

      final sent = seen.last.messages;
      expect(sent[sent.length - 2], {
        'role': 'assistant',
        'content': 'a fox in ',
      });
      expect(sent.last['content'], contains('【接着写】'));
      expect(vm.messages, hasLength(2));
      expect(vm.messages.last.text, 'a fox in the snow');
      expect(vm.messages.last.failed, isFalse);
      expect(vm.partialLast, isNull);
    });

    test('只有半截的才算:写完的、空的不算,停在半截的算', () {
      final t = DateTime(2026);
      ChatMessage reply(
        String text, {
        bool failed = false,
        bool stopped = false,
      }) => ChatMessage(
        fromUser: false,
        text: text,
        time: t,
        failed: failed,
        stopped: stopped,
      );
      expect(partialReply(reply('done')), isNull);
      expect(partialReply(reply('', stopped: true)), isNull);
      expect(partialReply(reply('half', stopped: true)), 'half');
      expect(partialReply(reply('\n[出错] x', failed: true)), isNull);
      expect(
        partialReply(reply('ab', failed: false).copyWith(cut: LlmCut.length)),
        'ab',
      );
    });
  });

  group('模型日志', () {
    test('没出字就失败换下一个、用户停止都记一条', () async {
      llmLog.clear();
      final out = await streamWithFailover(
        [
          (
            'A',
            const LlmRequest(
              baseUrl: 'a',
              model: 'm',
              apiKey: '',
              messages: [],
            ),
          ),
          (
            'B',
            const LlmRequest(
              baseUrl: 'b',
              model: 'm',
              apiKey: '',
              messages: [],
            ),
          ),
        ],
        (r) => r.baseUrl == 'a'
            ? Stream.error(const LlmException('429'))
            : Stream.value('ok'),
      ).join();
      expect(out, 'ok');
      expect(llmLog.events.single.kind, LlmEventKind.failover);
      expect(llmLog.events.single.model, 'A');
      expect(llmLog.events.single.message, '429');
      expect(llmLog.unseen, 1);
      llmLog.markSeen();
      expect(llmLog.unseen, 0);
    });
  });

  group('测试连接', () {
    LlmRequest req() =>
        const LlmRequest(baseUrl: '', model: 'm', apiKey: '', messages: []);

    test('通了给毫秒,出错给原因,一个字没有也算失败', () async {
      final ok = await probeChat(req(), (_) => Stream.value('hi'));
      expect(ok.error, isNull);
      expect(ok.ms, isNotNull);
      final bad = await probeChat(
        req(),
        (_) => Stream.error(const LlmException('429')),
      );
      expect(bad.error, '429');
      final empty = await probeSearch(req(), (_) => const Stream.empty());
      expect(empty.error, isNotNull);
      final searched = <LlmRequest>[];
      await probeSearch(req(), (r) {
        searched.add(r);
        return Stream.value('结果');
      });
      expect(searched.single.webSearch, isTrue);
      final slow = await probeChat(
        req(),
        (_) => StreamController<String>().stream,
        limit: const Duration(milliseconds: 10),
      );
      expect(slow.error, isNotNull);
      expect(formatMs(820), '820 ms');
      expect(formatMs(3250), '3.3 s');
    });
  });
}
