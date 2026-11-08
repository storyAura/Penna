import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/chat_pane.dart';
import 'package:penna/ui/features/studio/right_bar.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final (family, file) in [
      (bundledLatinFont, 'font/MapleMono-Regular.ttf'),
      (bundledCjkFont, 'font/LXGW975YuanSC-500W.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(file))).load();
    }
  });

  testWidgets('420px真实字体下长模型和Preset不溢出,菜单及会话操作仍可用', (tester) async {
    final config = tempConfig()
      ..update(
        const AppConfig()
            .putLlm(
              const LlmProfile(
                id: 'a',
                name: 'Desktop smoke — a deliberately long model name',
                baseUrl: 'http://localhost',
                model: 'a',
              ),
            )
            .putLlm(
              const LlmProfile(
                id: 'b',
                name: '备用模型 — 另一个足够长的模型名称用来检验省略和切换',
                baseUrl: 'http://localhost',
                model: 'b',
              ),
            )
            .copyWith(
              presets: const [
                AgentPreset(
                  id: 'p1',
                  name: '长名称视觉预设 — 包含构图、材质、灯光以及详细风格说明',
                  systemPrompt: '',
                  tools: {},
                ),
                AgentPreset(
                  id: 'p2',
                  name: '备用预设 — 切换后仍然正确显示并保持菜单能够操作',
                  systemPrompt: '',
                  tools: {},
                ),
              ],
              activePresetId: 'p1',
            ),
      );
    final vm = StudioViewModel(
      config: config,
      streamChat: (_) => const Stream.empty(),
      messages: [
        ChatMessage(
          fromUser: true,
          text: '应保留在历史里的会话',
          time: DateTime(2026, 11, 6),
        ),
      ],
    );
    final input = TextEditingController();
    final focus = FocusNode();
    var openedSettings = 0;
    addTearDown(vm.dispose);
    addTearDown(input.dispose);
    addTearDown(focus.dispose);
    Future<void> show(double width) => tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width + RightBar.closedWidth,
              child: ListenableBuilder(
                listenable: Listenable.merge([vm, config]),
                builder: (context, _) => Stack(
                  children: [
                    Positioned.fill(
                      right: RightBar.closedWidth,
                      child: ChatPane(
                        vm: vm,
                        config: config,
                        input: input,
                        inputFocus: focus,
                        onQuickAction: (_) {},
                        onOpenSettings: () => openedSettings++,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: RightBar(vm: vm, runner: vm.comfy, config: config),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await show(420);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    Finder item(String id) => find.byWidgetPredicate(
      (w) => w is PopupMenuItem<String> && w.value == id,
    );
    await tester.tap(find.byTooltip('Agent 使用的模型'));
    await tester.pumpAndSettle();
    await tester.tap(item('b'));
    await tester.pumpAndSettle();
    expect(config.config.activeLlmId, 'b');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('切换 Preset'));
    await tester.pumpAndSettle();
    await tester.tap(item('p2'));
    await tester.pumpAndSettle();
    expect(config.config.activePresetId, 'p2');
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.add_comment_outlined));
    await tester.pumpAndSettle();
    expect(vm.messages, isEmpty);
    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(RightBar),
        matching: find.text('应保留在历史里的会话'),
      ),
    );
    await tester.pumpAndSettle();
    expect(vm.messages.first.text, '应保留在历史里的会话');
    await tester.tap(find.byTooltip('历史对话'));
    await tester.pumpAndSettle();

    await show(720);
    await tester.pumpAndSettle();
    expect(find.text('新对话'), findsOneWidget);
    expect(find.byTooltip('历史对话'), findsOneWidget);
    expect(tester.takeException(), isNull);

    config.update(config.config.copyWith(llms: const []));
    await show(420);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('未连接模型 · 去设置'));
    expect(openedSettings, 1);
  });
}
