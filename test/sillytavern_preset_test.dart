// 选文件的窗口要换成假的,只能从平台接口包里拿。
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/preset_import/sillytavern_preset.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/config_service.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/settings/settings_agent_sections.dart';

import 'fixtures.dart';

Map<String, dynamic> _prompt(
  String id,
  String content, {
  bool marker = false,
  String role = 'system',
}) => {'identifier': id, 'content': content, 'marker': marker, 'role': role};

Map<String, dynamic> _slot(String id, {bool enabled = true}) => {
  'identifier': id,
  'enabled': enabled,
};

void main() {
  widgetTests();

  test('启用的条目按 prompt_order 的顺序拼成系统提示', () {
    final preset = sillyTavernToPreset({
      'temperature': 1.09,
      'top_p': 0.98,
      'prompts': [
        _prompt('style', '文风要求'),
        _prompt('main', '你是主持人'),
        _prompt('off', '关掉的条目'),
        _prompt('chatHistory', '', marker: true),
        _prompt('config', 'x' * 30000),
      ],
      'prompt_order': [
        {
          'character_id': 100000,
          'order': [_slot('main')],
        },
        {
          'character_id': 100001,
          'order': [
            _slot('main'),
            _slot('chatHistory'),
            _slot('off', enabled: false),
            _slot('config'),
            _slot('style'),
          ],
        },
      ],
    }, name: '测试');

    expect(preset.systemPrompt, '你是主持人\n\n文风要求');
    expect(preset.name, '测试');
    expect(preset.temperature, 1.09);
    expect(preset.topP, 0.98);
    expect(preset.tools, {for (final o in builtinTools) o.id});
    expect(isFactoryPreset(preset.id), isFalse);
  });

  test('没有 prompt_order 时按条目本身的顺序', () {
    final preset = sillyTavernToPreset({
      'prompts': [_prompt('a', '第一段'), _prompt('b', '第二段')],
    }, name: 'x');

    expect(preset.systemPrompt, '第一段\n\n第二段');
    expect(preset.temperature, 0.7);
    expect(preset.topP, 1);
  });

  test('注释宏和 {{trim}} 去掉,其他宏原样留着', () {
    final preset = sillyTavernToPreset({
      'prompts': [
        _prompt('a', '{{trim}}{{// 作者\n说明}}'),
        _prompt('b', '{{// 只改 {{user}} 的部分\n}}你好 {{user}}{{trim}}'),
      ],
    }, name: 'x');

    expect(preset.systemPrompt, '你好 {{user}}');
  });

  test('条目的角色和聊天记录的位置写成对话标记', () {
    final preset = sillyTavernToPreset({
      'prompts': [
        _prompt('main', '你是主持人'),
        _prompt('q', '可以开始了吗', role: 'user'),
        _prompt('a', '可以', role: 'assistant'),
        _prompt('a2', '请说', role: 'assistant'),
        _prompt('chatHistory', '', marker: true),
        _prompt('after', '记得写短一点'),
      ],
    }, name: 'x');

    expect(
      preset.systemPrompt,
      '你是主持人\n\n<<user>>\n\n可以开始了吗\n\n<<assistant>>\n\n可以\n\n请说\n\n'
      '<<history>>\n\n<<user>>\n\n记得写短一点',
    );
  });

  test('全是系统条目的预设不写对话标记', () {
    final preset = sillyTavernToPreset({
      'prompts': [
        _prompt('main', '你是主持人'),
        _prompt('chatHistory', '', marker: true),
        _prompt('after', '记得写短一点'),
      ],
    }, name: 'x');

    expect(preset.systemPrompt, '你是主持人\n\n记得写短一点');
  });

  test('超出范围的参数收进 Penna 的范围', () {
    final preset = sillyTavernToPreset({
      'temperature': 5,
      'top_p': 0,
      'prompts': [_prompt('a', '内容')],
    }, name: 'x');

    expect(preset.temperature, 2);
    expect(preset.topP, 0.1);
  });

  test('转出来的 Preset 能存进设置再读回来', () {
    final preset = sillyTavernToPreset({
      'prompts': [_prompt('a', '内容')],
    }, name: 'x');

    final back = AgentPreset.fromJson(preset.toJson());

    expect(back.systemPrompt, preset.systemPrompt);
    expect(back.tools, preset.tools);
  });

  test('不是酒馆预设的 JSON 报错', () {
    expect(
      () => sillyTavernToPreset({'nodes': []}, name: 'x'),
      throwsFormatException,
    );
    expect(
      () => sillyTavernToPreset({
        'prompts': [_prompt('chatHistory', '', marker: true)],
      }, name: 'x'),
      throwsFormatException,
    );
  });
}

/// 假的选文件窗口:直接返回 [path]。
class _PickFile extends FileSelectorPlatform {
  _PickFile(this.path);

  final String path;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile(path);
}

Future<void> _importFrom(WidgetTester tester, File file) async {
  FileSelectorPlatform.instance = _PickFile(file.path);
  await tester.runAsync(() async {
    await tester.tap(find.text('导入 SillyTavern 预设'));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pump();
}

Widget _presetPage(ConfigService service) => MaterialApp(
  theme: pennaTheme(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: ListenableBuilder(
        listenable: service,
        builder: (_, _) => PresetSection(service: service),
      ),
    ),
  ),
);

void widgetTests() {
  testWidgets('设置里点「导入 SillyTavern 预设」:多出一个 Preset 并切过去,名字用文件名', (
    tester,
  ) async {
    final service = tempConfig();
    final before = service.config.presets.length;
    final file =
        File('${Directory.systemTemp.createTempSync('st').path}/故事主持-2.1.json')
          ..writeAsStringSync(
            jsonEncode({
              'temperature': 1.09,
              'top_p': 0.98,
              'prompts': [_prompt('main', '你是故事主持人')],
            }),
          );
    await tester.pumpWidget(_presetPage(service));

    await _importFrom(tester, file);

    final active = service.config.activePreset;
    expect(service.config.presets.length, before + 1);
    expect(active.name, '故事主持-2.1');
    expect(active.systemPrompt, '你是故事主持人');
    expect(active.temperature, 1.09);
    expect(find.text('故事主持-2.1'), findsWidgets);
    expect(find.text('你是故事主持人'), findsOneWidget);
    // 提示还挂着一个定时器,等它走完。
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('选了别的 JSON(例如 ComfyUI 工作流):不加 Preset,提示不是酒馆预设', (tester) async {
    final service = tempConfig();
    final before = service.config.presets.length;
    final file = File(
      '${Directory.systemTemp.createTempSync('st').path}/workflow.json',
    )..writeAsStringSync(jsonEncode({'nodes': [], 'links': []}));
    await tester.pumpWidget(_presetPage(service));

    await _importFrom(tester, file);

    expect(service.config.presets.length, before);
    expect(find.text('这不是 SillyTavern 预设'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
