import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/local/caption_catalog.dart';
import 'package:penna/core/harness/local/florence.dart';
import 'package:penna/core/harness/local/llama_server.dart';
import 'package:penna/core/harness/local/model_scan.dart';
import 'package:penna/core/harness/local/tagger.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/local/local_model.dart';
import 'package:penna/ui/features/local/local_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('penna_local'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('Florence-2', () {
    // 一个很小的 BPE 词表:单个字母,加上 "Wh"、"Wha"、"What" 三条合并;Ġ 是空格。
    const tokenizer = '''{
      "model": {
        "vocab": {"<s>": 0, "<pad>": 1, "</s>": 2, "W": 3, "h": 4, "a": 5,
          "t": 6, "Wh": 7, "Wha": 8, "What": 9, "Ġ": 10, "Ġa": 11},
        "merges": ["W h", "Wh a", "Wha t", "Ġ a"]
      },
      "added_tokens": [{"id": 12, "content": "<loc_1>"}]
    }''';

    test('分词:按合并规则拼词,首尾套上 <s> </s>;解码去掉特殊符号', () {
      final t = FlorenceTokenizer.parse(tokenizer);
      expect(t.encode('What a'), [9, 11]);
      expect(t.encodePrompt('What'), [florenceBos, 9, florenceEos]);
      expect(t.decode([0, 9, 11, 12, 2]), 'What a<loc_1>');
      expect(
        () => FlorenceTokenizer.parse('{}'),
        throwsA(isA<FlorenceException>()),
      );
    });

    test('防重复:出了就会重复一个三连词的那个字不能出;挑最大的时跳过它', () {
      expect(bannedNext([5, 6, 7, 5, 6]), {7});
      expect(bannedNext([5, 6]), isEmpty);
      expect(argmaxExcept([0.1, 0.9, 0.5], {1}), 2);
    });

    test('指令:官方的几个换成英文问句,PromptGen 的原样', () {
      expect(florencePrompt('<CAPTION>'), 'What does the image describe?');
      expect(florencePrompt('<GENERATE_TAGS>'), '<GENERATE_TAGS>');
    });

    test('像素:透明算白,按 ImageNet 均值方差归一化,通道在前', () {
      // 1×1:一个全透明的点 → 白色。
      final px = florencePixels(Uint8List.fromList([0, 0, 0, 0]), 1);
      expect(px[0], closeTo((1 - 0.485) / 0.229, 1e-5));
      expect(px[2], closeTo((1 - 0.406) / 0.225, 1e-5));
    });
  });

  group('模型清单、量化档与排序', () {
    LocalModel fresh() =>
        LocalModel(dir: tmp, streamChat: (_) => const Stream.empty());
    CaptionModel byId(String id) => captionModels.firstWhere((m) => m.id == id);

    test('清单只收能看图的;默认用推荐档,选过的档存盘后还在', () async {
      expect(
        captionModels.map((m) => m.id),
        isNot(contains('gemma4-26b-a4b-heretic')),
      );
      expect(
        captionModels.every((m) => m.florence || m.mmproj != null),
        isTrue,
      );

      final model = fresh();
      final gemma = byId('gemma4-e4b');
      expect(model.quantOf(gemma).label, 'Q4_K_M');
      model.pickQuant(gemma, 'Q8_0');
      expect(
        fileName(model.captionFiles(gemma).first.path),
        'gemma-4-E4B-it-Q8_0.gguf',
      );
      // GGUF:本体 + 视觉组件;Florence-2:解码器 + 另外三个 ONNX + 分词器。
      expect(model.captionFiles(gemma), hasLength(2));
      expect(model.captionFiles(byId('florence2-base-ft')), hasLength(5));

      final again = fresh();
      await again.load();
      expect(again.quantOf(gemma).label, 'Q8_0');
    });

    test('按系列分组;整组拖、组里拖都存盘后还在', () async {
      final model = fresh();
      expect(
        [for (final g in model.taggerGroups) g.series],
        ['WD14', 'PixAI', 'CL', 'OppaiOracle'],
      );
      expect(
        [for (final g in model.captionGroups) g.series],
        [
          'Gemma 4',
          'Gemma 4 · Heretic',
          'ToriiGate',
          'JoyCaption',
          'Florence-2',
        ],
      );
      // 把 OppaiOracle 整组挪到最前;WD14 组里把第一个挪到第三个。
      model.moveTagger(null, 3, 0);
      final first = model.taggerGroups[1].items.first.id;
      model.moveTagger(1, 0, 2);
      // NL:Florence-2 组挪到最前。
      model.moveCaption(null, 4, 0);

      final again = fresh();
      await again.load();
      expect(again.taggerGroups.first.series, 'OppaiOracle');
      expect(again.taggerGroups[1].items[2].id, first);
      expect(again.captionGroups.first.series, 'Florence-2');
      expect(
        again.captionGroups.expand((g) => g.items),
        hasLength(captionModels.length),
      );
    });

    test('要申请访问的模型没填 Token 时不下载', () async {
      final gated = taggerModels.firstWhere((m) => m.gated);
      expect(await fresh().downloadTagger(gated), contains('Token'));
    });

    test('文件夹里有别的量化档、NLapt 放的 Florence-2:都直接能用', () async {
      for (final p in [
        'nl/gemma4-e4b/gemma-4-E4B-it-Q8_0.gguf',
        'nl/gemma4-e4b/mmproj-F16.gguf',
        for (final f in [...florenceOnnx, florenceTokenizer])
          'nl/florence2-base-ft/$f',
      ]) {
        File('${tmp.path}/$p')
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
      final model = fresh()..addFolder('${tmp.path}/nl');
      while (model.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final gemma = model.captionPaths(byId('gemma4-e4b'))!;
      expect(fileName(gemma.model), 'gemma-4-E4B-it-Q8_0.gguf');
      expect(fileName(gemma.mmproj), 'mmproj-F16.gguf');

      final florence = byId('florence2-base-ft');
      expect(model.useCaption(florence), isTrue);
      expect(model.florenceMode, isTrue);
      expect(
        model.captionPaths(florence)!.model,
        endsWith('florence2-base-ft'),
      );
      // 用的指令:它不认的换成它的第一个。
      model.update(() => model.florenceTask = '<ANALYZE>');
      expect(model.florenceTaskOf(florence), florence.tasks.first);
      // 选回 GGUF 就不是 Florence 了。
      expect(model.useCaption(byId('gemma4-e4b')), isTrue);
      expect(model.florenceMode, isFalse);
    });
  });

  group('看图描述的要求', () {
    LocalModel fresh() =>
        LocalModel(dir: tmp, streamChat: (_) => const Stream.empty());

    test('像 Preset 一样:新建、改名、改正文、切换、删除,存盘后还在', () async {
      final model = fresh();
      expect(model.captionPrompts, defaultCaptionPrompts);
      expect(model.currentPrompt.name, '详细描述');

      model.addPrompt();
      expect(model.currentPrompt.name, '详细描述 副本');
      model.editPrompt(name: '中文', text: '用中文描述');
      model.pickPrompt(1);

      final again = fresh();
      await again.load();
      expect(again.captionPrompts.last, (name: '中文', text: '用中文描述'));
      expect(again.currentPrompt.name, '简短描述');

      again.pickPrompt(again.captionPrompts.length - 1);
      again.removePrompt();
      expect(again.captionPrompts, hasLength(defaultCaptionPrompts.length));
      expect(again.currentPrompt.name, defaultCaptionPrompts.last.name);
    });

    test('以前只有一条要求:改过的那条留下来并选中', () async {
      File('${tmp.path}/local.json')
          .writeAsStringSync(jsonEncode({'captionPrompt': '您是一套图像分析系统'}));
      final model = fresh();
      await model.load();
      expect(model.currentPrompt, (name: '我的要求', text: '您是一套图像分析系统'));
      expect(model.captionPrompts, hasLength(defaultCaptionPrompts.length + 1));
    });
  });

  group('本地推理页的状态', () {
    test('换打标模型:阈值换成它的推荐值;设置存盘后还在', () async {
      final model = LocalModel(
        dir: tmp,
        streamChat: (_) => const Stream.empty(),
      );
      model.pickTagger(taggerModels[2].id);
      expect(model.general, taggerModels[2].general);
      model.setThresholds(character: 0.7);
      model.update(() => model.port = 9100);

      final again = LocalModel(
        dir: tmp,
        streamChat: (_) => const Stream.empty(),
      );
      await again.load();
      expect(again.taggerRepo, taggerModels[2].id);
      expect(again.character, 0.7);
      expect(again.port, 9100);
    });

    test('起了服务才能看图写描述,图带在请求里', () async {
      LlmRequest? asked;
      final model = LocalModel(
        dir: tmp,
        streamChat: (request) {
          asked = request;
          return Stream.fromIterable(['a girl ', 'in a field']);
        },
        server: LlamaServer(
          start: (_, _) async => FakeProcess(),
          health: (_) async => true,
        ),
      );
      final spec = fakeServerSpec(tmp);
      model.update(() {
        model.exePath = spec.exe;
        model.modelPath = spec.model;
      });

      model.setImage(
        Attachment.image(
          name: 'a.png',
          mime: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      expect(await model.runCaption(), '先启动模型');
      expect(await model.startServer(), isNull);
      expect(model.serverRunning, isTrue);

      expect(await model.runCaption(), isNull);
      expect(model.caption, 'a girl in a field');
      expect(asked!.baseUrl, 'http://127.0.0.1:8091/v1');
      // 用的是选中的那条要求。
      expect(asked!.messages.single['content'], model.currentPrompt.text);
      expect(asked!.images[0]!.single.bytes, [1, 2, 3]);

      // 正在用的模型不能删。
      expect(
        await model.remove([
          (url: '', path: spec.model, size: null, sha256: null),
        ]),
        contains('正在用'),
      );

      await model.stopServer();
      expect(model.serverRunning, isFalse);
    });

    test('生成途中换了图:前一张图的字不会挂到新图上', () async {
      final reply = StreamController<String>();
      final model = LocalModel(
        dir: tmp,
        streamChat: (_) => reply.stream,
        server: LlamaServer(
          start: (_, _) async => FakeProcess(),
          health: (_) async => true,
        ),
      );
      final spec = fakeServerSpec(tmp);
      model.update(() {
        model.exePath = spec.exe;
        model.modelPath = spec.model;
      });
      Attachment image(int b) => Attachment.image(
        name: 'a.png',
        mime: 'image/png',
        bytes: Uint8List.fromList([b]),
      );
      model.setImage(image(1));
      expect(await model.startServer(), isNull);

      final running = model.runCaption();
      reply.add('a cat ');
      await pumpEventQueue();
      model.setImage(image(2));
      reply.add('on a sofa');
      await reply.close();

      expect(await running, isNull);
      expect(model.caption, isEmpty);
      expect(model.captioning, isFalse);
      await model.stopServer();
    });

    testWidgets('结果「发送给 Agent」:切回工作台,填进聊天输入框', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final local = LocalModel(
        dir: tmp,
        streamChat: (_) => Stream.value('a cat on a sofa'),
        server: LlamaServer(
          start: (_, _) async => FakeProcess(),
          health: (_) async => true,
        ),
      );
      await tester.runAsync(() async {
        final spec = fakeServerSpec(tmp);
        local.update(() {
          local.exePath = spec.exe;
          local.modelPath = spec.model;
        });
        local.setImage(
          Attachment.image(
            name: 'a.png',
            mime: 'image/png',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        );
        await local.startServer();
        await local.runCaption();
      });
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            vm: vm,
            config: vm.config,
            skills: tempSkills(),
            local: local,
          ),
        ),
      );

      await tester.tap(find.byTooltip('本地反推'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NL 反推'));
      await tester.pumpAndSettle();
      final send = find.descendant(
        of: find.byType(LocalPage),
        matching: find.text('发送给 Agent'),
      );
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'a cat on a sofa'), findsOneWidget);
      await tester.runAsync(local.stopServer);
    });
  });

  group('LLM 反推', () {
    LocalModel withImage() =>
        LocalModel(streamChat: (_) => const Stream.empty())..setImage(
          Attachment.image(
            name: 'a.png',
            mime: 'image/png',
            bytes: Uint8List.fromList([1]),
          ),
        );

    test('最多选两个,再选挤掉最早的;取消选择', () {
      final model = withImage();
      const a = (llm: 'x', model: 'a'), b = (llm: 'x', model: 'b');
      const c = (llm: 'y', model: 'c');
      model.toggleLlm(a);
      model.toggleLlm(b);
      model.toggleLlm(c);
      expect(model.llmPicks, [b, c]);
      model.toggleLlm(b);
      expect(model.llmPicks, [c]);
    });

    test('两个模型一起跑,各自出结果;一个出错不影响另一个', () async {
      final model = withImage();
      const a = (llm: 'x', model: 'a'), b = (llm: 'y', model: 'b');
      final gate = Completer<String>();
      final running = model.runLlm([a, b], (pick, image) {
        expect(image.mime, 'image/png');
        return pick == a
            ? gate.future
            : Future.error(const LlmException('看不了图'));
      });
      await pumpEventQueue();
      expect(model.llmResultOf(a)!.busy, isTrue);
      expect(model.llmResultOf(b)!.error, '看不了图');
      expect(model.llmBusy, isTrue);

      gate.complete(' a fox ');
      expect(await running, isNull);
      expect(model.llmResultOf(a), (text: 'a fox', error: null, busy: false));
      expect(model.llmBusy, isFalse);
    });

    test('等结果时换了图,旧结果作废', () async {
      final model = withImage();
      const a = (llm: 'x', model: 'a');
      final gate = Completer<String>();
      final running = model.runLlm([a], (_, _) => gate.future);
      model.setImage(null);
      gate.complete('old');
      await running;
      expect(model.llmResultOf(a), isNull);
      expect(model.llmBusy, isFalse);
      expect(await model.runLlm([a], (_, _) async => ''), '先放一张图');
    });

    testWidgets('选两个模型一起反推,结果并排显示', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final config = tempConfig()
        ..update(
          const AppConfig().putLlm(
            const LlmProfile(
              id: 'a',
              name: 'A',
              baseUrl: 'http://x',
              model: 'm1, m2',
            ),
          ),
        );
      final vm = StudioViewModel(
        config: config,
        streamChat: (req) => Stream.value('from ${req.model}'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            vm: vm,
            config: config,
            skills: tempSkills(),
            local: withImage(),
          ),
        ),
      );

      await tester.tap(find.byTooltip('本地反推'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LLM 反推'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('m1'));
      await tester.tap(find.text('m2'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(LocalPage), matching: find.text('反推')),
      );
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();

      expect(find.text('from m1'), findsOneWidget);
      expect(find.text('from m2'), findsOneWidget);
      // 对话顶栏也写着「A · m1」,只看本地反推这一页。
      expect(
        find.descendant(
          of: find.byType(LocalPage),
          matching: find.text('A · m1'),
        ),
        findsOneWidget,
      );
    });
  });
}
