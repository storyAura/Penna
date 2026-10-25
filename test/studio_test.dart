import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/translate_engines.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

const _llm = LlmProfile(
  id: 'a',
  name: '测试模型',
  baseUrl: 'http://localhost/v1',
  model: 'm',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('成稿与 diff', () {
    test('采纳 diff 会替换对应的块,固定区不变', () {
      final vm = sampleStudio();
      final added = vm.pending!.added;

      vm.acceptDiff();

      expect(vm.pending, isNull);
      expect(vm.blocks[2].text, added);
      expect(
        vm.finalPrompt,
        startsWith('masterpiece, titanium armor plating, A'),
      );
      expect(vm.finalPrompt, isNot(contains('flat generic ambient lighting')));
    });

    test('驳回 diff 保留原文', () {
      final vm = sampleStudio();
      final before = vm.finalPrompt;

      vm.rejectDiff();

      expect(vm.pending, isNull);
      expect(vm.finalPrompt, before);
    });

    test('手动编辑正文会更新成稿;空成稿没有多余空格', () {
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
      );
      expect(vm.finalPrompt, '');

      vm.setText(0, 'a red fox');

      expect(vm.finalPrompt, 'a red fox');
    });
  });

  group('发送消息', () {
    test('空白消息、没配模型都不发送,并说明原因', () {
      final vm = sampleStudio();
      final count = vm.messages.length;

      expect(vm.send('   '), contains('请输入'));
      expect(vm.send('你好'), contains('添加模型'));
      expect(vm.messages, hasLength(count));
    });

    test('流式回复逐段拼进 Agent 消息,系统提示带上 Preset 与成稿', () async {
      final config = tempConfig();
      config.update(
        const AppConfig().putLlm(_llm).setSecret(llmSecretKey('a'), 'sk-x'),
      );
      final reply = StreamController<String>();
      late LlmRequest seen;
      final vm = sampleStudio(
        config: config,
        streamChat: (req) {
          seen = req;
          return reply.stream;
        },
      );

      expect(vm.send(' 你好 '), isNull);
      expect(vm.isStreaming, isTrue);
      expect(vm.outbox, isEmpty);

      reply
        ..add('Hel')
        ..add('lo');
      await reply.close();
      await pumpEventQueue();

      expect(vm.isStreaming, isFalse);
      expect(vm.messages.last.text, 'Hello');
      expect(vm.messages[vm.messages.length - 2].text, '你好');
      expect(seen.apiKey, 'sk-x');
      expect(seen.messages.first['role'], 'system');
      expect(seen.messages.first['content'], contains('【固定区】'));
      expect(seen.messages.last, {'role': 'user', 'content': '你好'});
    });

    test('每段的对照译文跟着界面语言:日文界面要日文,英文界面不要〔译〕', () async {
      expect(const AppConfig().glossLanguage, 'zh');
      expect(const AppConfig(language: 'zh-Hant').glossLanguage, 'zh-Hant');
      expect(const AppConfig(language: 'en').glossLanguage, isNull);

      Future<String> systemFor(String language) async {
        final config = tempConfig();
        config.update(
          AppConfig(language: language)
              .putLlm(_llm)
              .setSecret(llmSecretKey('a'), 'sk-x'),
        );
        late LlmRequest seen;
        final vm = sampleStudio(
          config: config,
          streamChat: (req) {
            seen = req;
            return const Stream.empty();
          },
        );
        vm.send('写一张图');
        await pumpEventQueue();
        return seen.messages.first['content'] as String;
      }

      expect(await systemFor('zh-Hans'), contains('这段的简体中文翻译'));
      expect(await systemFor('ja'), contains('这段的日文翻译'));
      final english = await systemFor('en');
      expect(english, contains('不写〔译〕行'));
      expect(english, isNot(contains('翻译,只给用户对照看')));
    });

    test('模型出错时把原因写进回复并结束', () async {
      final config = tempConfig()..update(const AppConfig().putLlm(_llm));
      final vm = sampleStudio(
        config: config,
        streamChat: (_) => Stream.error(const LlmException('接口返回 401')),
      );

      vm.send('你好');
      await pumpEventQueue();

      expect(vm.isStreaming, isFalse);
      expect(vm.messages.last.text, contains('接口返回 401'));
      expect(vm.messages.last.failed, isTrue);
    });

    test('翻译成稿:成功时记下译文和引擎名,失败时把原因交给界面', () async {
      var fail = false;
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        translate: (_, text) async => fail
            ? throw const TranslateException('翻译失败')
            : TranslateResult('译:$text', 'mymemory', const []),
      );

      expect(await vm.translateDraft(), '成稿为空');

      vm.setText(0, 'a red fox');
      expect(await vm.translateDraft(), isNull);
      expect(vm.translation, '译:a red fox');
      expect(vm.translationBy, 'MyMemory');

      fail = true;
      expect(await vm.translateDraft(), '翻译失败');
      expect(vm.isTranslating, isFalse);
      expect(vm.translation, '译:a red fox');
    });

    test('停止后保留已生成的部分', () async {
      final config = tempConfig()..update(const AppConfig().putLlm(_llm));
      final reply = StreamController<String>();
      final vm = sampleStudio(config: config, streamChat: (_) => reply.stream);

      vm.send('你好');
      reply.add('半句');
      await pumpEventQueue();
      vm.stop();

      expect(vm.isStreaming, isFalse);
      expect(vm.messages.last.text, '半句');
    });
  });

  testWidgets('空白启动能渲染;进设置能添加模型并切换分区', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final config = tempConfig();
    final vm = StudioViewModel(
      config: config,
      streamChat: (_) => const Stream.empty(),
    );
    addTearDown(vm.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: config, skills: tempSkills()),
      ),
    );
    // 布局页的对话也会这么提示:只看工作台的。
    expect(
      find.descendant(
        of: find.byType(StudioPage),
        matching: find.text('未连接模型 · 去设置'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    await tester.tap(find.text('添加模型'));
    await tester.pump();
    expect(config.config.agentChain.firstOrNull?.name, '新模型');
    await tester.tap(find.text('常用服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();
    final added = config.config.llms.last;
    expect(added.name, 'DeepSeek');
    expect(added.baseUrl, 'https://api.deepseek.com/v1');
    expect(added.model, 'deepseek-flash');

    await tester.tap(find.text('翻译').last);
    await tester.pump();
    expect(find.text('百度翻译'), findsOneWidget);
    expect(find.text('免费'), findsNWidgets(2));

    await tester.tap(find.text('Preset'));
    await tester.pump();
    await tester.tap(find.text('新建 Preset(复制当前)'));
    await tester.pump();
    expect(config.config.presets, hasLength(factoryPresets.length + 1));
    expect(config.config.activePreset.name, '动漫风格 副本');

    await tester.tap(find.text('Skills'));
    await tester.pump();
    expect(find.text('添加 Skill'), findsOneWidget);

    await tester.tap(find.text('参数与工具'));
    await tester.pump();
    expect(find.text('温度'), findsOneWidget);

    await tester.tap(find.text('MCP'));
    await tester.pump();
    await tester.tap(find.text('添加服务'));
    await tester.pump();
    expect(config.config.mcpServers, hasLength(1));
    expect(find.text('测试连接'), findsOneWidget);

    await tester.tap(find.text('软件设置'));
    await tester.pump();
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(config.config.language, 'en');
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(config.config.darkMode, isTrue);
    await tester.ensureVisible(find.text('微软雅黑'));
    await tester.tap(find.text('微软雅黑'));
    await tester.pump();
    expect(config.config.fontCjk, 'Microsoft YaHei UI');
  });

  testWidgets('有待确认 diff 时点击采纳后 diff 块消失', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = sampleStudio();
    addTearDown(vm.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );

    expect(find.text('Diff 待合并'), findsOneWidget);
    await tester.tap(find.text('采纳'));
    await tester.pump();

    expect(find.text('Diff 待合并'), findsNothing);
    // 区域控制工作台也有「保存」:只看工作台这一页。
    expect(
      find.descendant(of: find.byType(StudioPage), matching: find.text('保存')),
      findsOneWidget,
    );
  });

  testWidgets('回复里的新成稿显示成卡片,并自动成为左侧的待确认改动;能重新运行', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var asked = 0;
    final vm = StudioViewModel(
      config: tempConfig()..update(const AppConfig().putLlm(_llm)),
      streamChat: (_) {
        asked++;
        return Stream.value('写好了。\n<draft>\n【主体】a fox\n【场景】snow\n</draft>');
      },
      blocks: const [(text: 'old', pinned: false)],
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );

    vm.send('画只狐狸');
    await tester.pumpAndSettle();
    // 流的收尾事件在假时钟里送不到,得放到真的事件循环里等一下。
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();

    // 已经送到左边了,右边的卡片收起来,各段的标注竖着列一行一个当摘要。
    expect(find.text('新成稿'), findsOneWidget);
    expect(find.text('·  主体'), findsOneWidget);
    expect(find.text('·  场景'), findsOneWidget);
    expect(find.text('主体'), findsOneWidget);
    expect(find.textContaining('<draft>'), findsNothing);

    // 点标题展开:右边卡片里一个,左边待确认的分段框里一个。
    await tester.tap(find.text('新成稿'));
    await tester.pumpAndSettle();
    expect(find.text('主体'), findsNWidgets(2));

    expect(vm.body, 'old');
    expect(vm.pending!.added, '【主体】a fox\n【场景】snow');
    expect(find.text('待确认'), findsOneWidget);

    await tester.tap(find.text('采纳'));
    await tester.pumpAndSettle();

    expect(find.text('已在成稿'), findsOneWidget);
    expect(vm.finalPrompt, 'a fox\nsnow');

    await tester.tap(find.text('重新运行'));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();

    expect(asked, 2);
    expect(vm.messages, hasLength(2));
  });

  testWidgets('只改一段时,其他段照常是分段框,对比只出现在那一段里', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      blocks: const [
        (text: '【主体】a fox\n【构图】wide shot\n【画质】sharp', pinned: false),
      ],
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );

    vm.proposeDraft('【构图】close-up');
    await tester.pumpAndSettle();

    // 三段都还是带标注的框,没有被摊成一整篇带【】的文字。
    expect(find.text('主体'), findsOneWidget);
    expect(find.text('构图'), findsOneWidget);
    expect(find.text('画质'), findsOneWidget);
    expect(find.textContaining('【'), findsNothing);
    // 没变的段原样;变的那段一删一增。
    expect(find.text('a fox'), findsOneWidget);
    expect(find.text('- wide shot'), findsOneWidget);
    expect(find.text('+ close-up'), findsOneWidget);

    await tester.tap(find.text('采纳'));
    await tester.pumpAndSettle();
    expect(vm.finalPrompt, 'a fox\nclose-up\nsharp');
  });

  testWidgets('成稿按标注分成几个框;点讨论把那段带到输入框,删除只去掉那段', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      blocks: const [
        (text: '【主体】a fox\n〔译〕一只狐狸\n【光影】flat light', pinned: false),
      ],
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );

    expect(find.text('主体'), findsOneWidget);
    expect(find.text('光影'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'flat light'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'a fox'), findsOneWidget);

    // 中文对照默认收着,点标注那一行才展开。
    expect(find.text('一只狐狸'), findsNothing);
    await tester.tap(find.text('主体'));
    await tester.pumpAndSettle();
    expect(find.text('一只狐狸'), findsOneWidget);

    await tester.tap(find.byTooltip('和 Agent 讨论这段').last);
    await tester.pumpAndSettle();

    expect(vm.quote, '【光影】flat light');
    expect(find.text('段 · 光影'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'flat light'),
      'rim light',
    );
    expect(vm.body, '【主体】a fox\n〔译〕一只狐狸\n【光影】rim light');
    expect(vm.finalPrompt, 'a fox\nrim light');
    await tester.pump();

    await tester.tap(find.byTooltip('删除这段').first);
    await tester.pumpAndSettle();

    expect(vm.body, '【光影】rim light');
  });
}
