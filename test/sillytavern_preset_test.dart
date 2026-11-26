// 选文件的窗口要换成假的,只能从平台接口包里拿。
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/ui/features/settings/settings_piercing.dart';
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
  await tester.ensureVisible(find.text('导入 SillyTavern 预设'));
  await tester.pump();
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

File _temp(String name, Object json) =>
    File('${Directory.systemTemp.createTempSync('st').path}/$name')
      ..writeAsStringSync(jsonEncode(json));

void widgetTests() {
  testWidgets('穿甲弹点「导入 SillyTavern 预设」:存成以文件名命名的一段并换过去,能预览', (tester) async {
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
    expect(service.config.piercingName, '故事主持');
    expect(service.config.piercingSaved.single.name, '故事主持');
    expect(service.config.piercingPrompt, contains('可以开始了吗'));
    // 预览:开头是系统提示,事先说好的那句算用户说的,后面是聊天记录的位置。
    Finder inPreview(String text) => find.descendant(
      of: find.byType(PiercingPreview),
      matching: find.text(text),
    );
    expect(inPreview('系统提示'), findsOneWidget);
    expect(inPreview('可以开始了吗'), findsOneWidget);
    expect(inPreview('聊天记录'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('工具调用模式不用写字:默认不带预设,导入的酒馆预设能挑来用', (tester) async {
    final service = tempConfig();
    service.update(
      service.config.copyWith(
        piercingSaved: const [(name: '旧的', text: '旧提示词')],
        piercingName: '旧的',
        piercingPrompt: '旧提示词',
      ),
    );
    await tester.pumpWidget(_presetPage(service));
    await tester.ensureVisible(find.text('工具调用'));
    await tester.tap(find.text('工具调用'));
    await tester.pump();
    expect(service.config.piercingTool, isTrue);
    // 工具调用用自己那张表,提示词模式挑的那段留着不动。
    expect(service.config.piercingName, '旧的');
    expect(service.config.piercingToolName, isEmpty);
    expect(service.config.piercingText, isEmpty);
    expect(find.text('不用预设'), findsOneWidget);
    expect(find.text('导入文本'), findsNothing);

    final file = _temp('主持.json', {
      'prompts': [_prompt('main', '你是主持人')],
    });
    await _importFrom(tester, file);
    expect(service.config.piercingToolName, '主持');
    expect([for (final p in service.config.piercingSaved) p.name], ['旧的']);
    service.update(service.config.copyWith(piercing: true));
    expect(service.config.piercingText, '你是主持人');
    await tester.pump(const Duration(seconds: 5));
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

  test('副聊天的穿甲弹各挑各的段:提示词默认第一段,工具调用默认不用预设,文档不带字', () {
    const two = [(name: 'A', text: '甲'), (name: 'B', text: '乙')];
    const base = AppConfig(
      piercingSaved: two,
      piercingName: 'B',
      piercingPrompt: '乙',
      piercingToolSaved: [(name: 'T', text: '酒馆')],
      sidePiercing: true,
    );
    expect(base.sidePiercingText, '甲');
    expect(base.copyWith(sidePiercingName: 'B').sidePiercingText, '乙');
    expect(
      base.copyWith(sidePiercingMode: piercingModeTool).sidePiercingText,
      '',
    );
    // 工具调用只认它自己那张表:提示词模式的 B 在这里对不上。
    expect(
      base
          .copyWith(sidePiercingMode: piercingModeTool, sidePiercingName: 'B')
          .sidePiercingText,
      '',
    );
    expect(
      base
          .copyWith(sidePiercingMode: piercingModeTool, sidePiercingName: 'T')
          .sidePiercingText,
      '酒馆',
    );
    expect(
      base
          .copyWith(
            sidePiercingMode: piercingModeDocument,
            sidePiercingName: 'B',
          )
          .sidePiercingText,
      '',
    );
    expect(base.copyWith(sidePiercing: false).sidePiercingText, '');
  });

  test('提示词和工具调用各一张表:旧设置抄一份过去,各挑各的;按模型的规则存得住', () {
    // 旧设置:两边共用一张,工具调用模式挑着「酒馆」。
    final old = AppConfig.fromJson({
      'piercing': true,
      'piercingTool': true,
      'piercingSaved': [
        {'name': '默认', 'text': '甲'},
        {'name': '酒馆', 'text': '乙'},
      ],
      'piercingName': '酒馆',
      'piercingPrompt': '乙',
    });
    expect([for (final p in old.piercingToolSaved) p.name], ['默认', '酒馆']);
    expect(old.piercingToolName, '酒馆');
    expect(old.piercingText, '乙');

    // 换到提示词模式不动工具调用挑的那段,文字用提示词那段。
    final prompt = old.copyWith(
      piercingTool: false,
      piercingName: '默认',
      piercingPrompt: '甲',
    );
    expect(prompt.piercingText, '甲');
    expect(prompt.piercingToolName, '酒馆');

    final ruled = AppConfig.fromJson(
      prompt
          .copyWith(
            piercingRules: const [
              (model: 'g', mode: piercingModeTool, name: '酒馆'),
            ],
          )
          .toJson(),
    );
    expect(ruled.piercingRuleFor('g')?.name, '酒馆');
    expect(ruled.piercingRuleFor('x'), isNull);
    expect(ruled.piercingSegment(piercingModeTool, '酒馆'), '乙');
    expect(ruled.piercingSegment(piercingModeDocument, '酒馆'), '');
  });
}
