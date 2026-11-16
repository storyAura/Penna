import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comfy_workflow.dart';
import 'package:penna/core/harness/comfyui.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/comfy_panel.dart';
import 'package:penna/ui/features/studio/comfy_runner.dart';

import 'fixtures.dart';

// 2026-11-16:侧栏的 ComfyUI 面板:模型只看、采样默认收起、上传素材、LoRA 配置能拖。

void main() {
  testWidgets('模型只看不改;采样默认收起;有几个加载图片的节点就有几行上传;LoRA 配置的下拉能打开', (tester) async {
    final wf = addLora(
      {
        ...defaultWorkflow('m.safetensors'),
        '20': {
          'class_type': 'LoadImage',
          'inputs': {'image': 'example.png'},
          '_meta': {'title': '参考人物'},
        },
        '21': {
          'class_type': 'PreviewImage',
          'inputs': {
            'images': ['20', 0],
          },
        },
      },
      'style.safetensors',
      0.8,
    );
    final config = tempConfig();
    config.update(
      config.config.copyWith(
        comfy: const ComfySettings()
            .putFlow((id: 'f', name: 'Edit', text: jsonEncode(wf)))
            .copyWith(flowId: 'f')
            .putLoraPreset((
              flow: 'f',
              name: '柔和',
              loras: const [(name: 'style.safetensors', strength: 1, on: true)],
            ))
            .putLoraPreset((flow: 'f', name: '浓', loras: const [])),
      ),
    );
    final runner = ComfyRunner(config);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ListenableBuilder(
              listenable: Listenable.merge([config, runner]),
              builder: (_, _) => ComfyPanel(runner: runner, config: config),
            ),
          ),
        ),
      ),
    );

    // 模型那一行没有笔:点了不弹选择框。
    expect(find.text('m.safetensors'), findsOneWidget);
    await tester.tap(find.text('m.safetensors'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    // 采样默认收起,点标题展开。
    expect(find.text('步数'), findsNothing);
    await tester.tap(find.text('采样'));
    await tester.pumpAndSettle();
    expect(find.text('步数'), findsOneWidget);

    // 一个加载图片的节点:一行上传,名字是节点标题,没选文件时显示工作流里的。
    expect(find.text('上传素材 · 1'), findsOneWidget);
    expect(find.text('参考人物'), findsOneWidget);
    expect(find.text('example.png'), findsOneWidget);

    // LoRA 配置的下拉:两套都在,能拖动的那几项排得开,没有布局报错。
    await tester.scrollUntilVisible(find.text('LoRA 配置'), 100);
    await tester.tap(find.text('LoRA 配置'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('柔和'), findsOneWidget);
    expect(find.text('浓'), findsOneWidget);
    await tester.tap(find.text('柔和'));
    await tester.pumpAndSettle();
    expect(runner.loraPreset?.name, '柔和');
  });
}
