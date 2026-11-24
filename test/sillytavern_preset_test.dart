// 选文件的窗口要换成假的,只能从平台接口包里拿。
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/preset_import/sillytavern_preset.dart';
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

  test('启用的条目按 prompt_order 的顺序拼成一段', () {
    final text = sillyTavernToPrompt({
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
    });

    expect(text, '你是主持人\n\n文风要求');
  });

  test('没有 prompt_order 时按条目本身的顺序', () {
    final text = sillyTavernToPrompt({
      'prompts': [_prompt('a', '第一段'), _prompt('b', '第二段')],
    });

    expect(text, '第一段\n\n第二段');
  });

  test('注释宏和 {{trim}} 去掉,其他宏原样留着', () {
    final text = sillyTavernToPrompt({
      'prompts': [
        _prompt('a', '{{trim}}{{// 作者\n说明}}'),
        _prompt('b', '{{// 只改 {{user}} 的部分\n}}你好 {{user}}{{trim}}'),
      ],
    });

    expect(text, '你好 {{user}}');
  });

  test('条目的角色和聊天记录的位置写成对话标记', () {
    final text = sillyTavernToPrompt({
      'prompts': [
        _prompt('main', '你是主持人'),
        _prompt('q', '可以开始了吗', role: 'user'),
        _prompt('a', '可以', role: 'assistant'),
        _prompt('a2', '请说', role: 'assistant'),
        _prompt('chatHistory', '', marker: true),
        _prompt('after', '记得写短一点'),
      ],
    });

    expect(
      text,
      '你是主持人\n\n<<user>>\n\n可以开始了吗\n\n<<assistant>>\n\n可以\n\n请说\n\n'
      '<<history>>\n\n<<user>>\n\n记得写短一点',
    );
  });

  test('全是系统条目的预设不写对话标记', () {
    final text = sillyTavernToPrompt({
      'prompts': [
        _prompt('main', '你是主持人'),
        _prompt('chatHistory', '', marker: true),
        _prompt('after', '记得写短一点'),
      ],
    });

    expect(text, '你是主持人\n\n记得写短一点');
  });

  test('不是酒馆预设的 JSON 报错', () {
    expect(() => sillyTavernToPrompt({'nodes': []}), throwsFormatException);
    expect(() => sillyTavernToPrompt([1, 2]), throwsFormatException);
    expect(
      () => sillyTavernToPrompt({
        'prompts': [_prompt('chatHistory', '', marker: true)],
      }),
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
  await tester.ensureVisible(find.text('导入'));
  await tester.pump();
  await tester.runAsync(() async {
    await tester.tap(find.text('导入'));
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

File _temp(String name, Object json) =>
    File('${Directory.systemTemp.createTempSync('st').path}/$name')
      ..writeAsStringSync(jsonEncode(json));

void widgetTests() {
  testWidgets('穿甲弹点「导入」选 SillyTavern 预设:条目填进提示词,Preset 一个不多', (tester) async {
    final service = tempConfig();
    final before = service.config.presets.length;
    final file = _temp('故事主持.json', {
      'prompts': [
        _prompt('main', '你是故事主持人'),
        _prompt('q', '可以开始了吗', role: 'user'),
      ],
    });
    await tester.pumpWidget(_presetPage(service));

    await _importFrom(tester, file);

    expect(find.text('你是故事主持人\n\n<<user>>\n\n可以开始了吗'), findsOneWidget);
    expect(service.config.presets.length, before);
    // 导入只进草稿,点「保存」才写进设置。
    expect(service.config.piercingPrompt, isEmpty);
  });

  testWidgets('选了别的 JSON(例如 ComfyUI 工作流):提示词不动,提示不是酒馆预设', (tester) async {
    final service = tempConfig();
    final file = _temp('workflow.json', {'nodes': [], 'links': []});
    await tester.pumpWidget(_presetPage(service));

    await _importFrom(tester, file);

    expect(find.text('这不是 SillyTavern 预设'), findsOneWidget);
    expect(service.config.piercingPrompt, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });
}
