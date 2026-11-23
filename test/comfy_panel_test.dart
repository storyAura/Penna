import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comfy_workflow.dart';
import 'package:penna/core/harness/comfyui.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/size_panel.dart';
import 'package:penna/ui/features/studio/comfy_panel.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

// 2026-11-16:侧栏的 ComfyUI 面板:模型只看、采样默认收起、上传素材、LoRA 配置能拖。

void main() {
  testWidgets('模型能改;采样默认收起;有几个加载图片的节点就有几行上传;LoRA 配置的下拉能打开', (tester) async {
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
              server: comfyLocalId,
              flow: 'f',
              name: '柔和',
              loras: const [(name: 'style.safetensors', strength: 1, on: true)],
            ))
            .putLoraPreset((
              server: comfyLocalId,
              flow: 'f',
              name: '浓',
              loras: const [],
            )),
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

    // 模型那一行能改(2026-11-23 起):行尾有笔。
    expect(find.text('m.safetensors'), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('m.safetensors'),
          matching: find.byType(InkWell),
        ),
        matching: find.byIcon(Icons.edit_outlined),
      ),
      findsOneWidget,
    );

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

  // 2026-11-22:画面大小换成和区域控制一样的分辨率面板,常用尺寸能存能删。
  testWidgets('画面大小点开是分辨率面板:点常用尺寸换过去,存下的尺寸写进设置', (tester) async {
    final config = tempConfig();
    config.update(
      config.config.copyWith(
        comfy: const ComfySettings()
            .putFlow((
              id: 'f',
              name: 'T2I',
              text: jsonEncode(defaultWorkflow('m.safetensors')),
            ))
            .copyWith(flowId: 'f'),
      ),
    );
    final runner = ComfyRunner(config);
    // 和程序里一样摆在窗口右边,面板往左边弹。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 300,
              child: ListenableBuilder(
                listenable: Listenable.merge([config, runner]),
                builder: (_, _) => ComfyPanel(runner: runner, config: config),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('1024 × 1024'));
    await tester.pumpAndSettle();
    expect(find.byKey(sizePadKey), findsOneWidget);
    // 面板弹在旁边、不盖住这个框:再点一下收起来,再点又打开。
    await tester.tap(find.text('1024 × 1024'));
    await tester.pumpAndSettle();
    expect(find.byKey(sizePadKey), findsNothing);
    await tester.tap(find.text('1024 × 1024'));
    await tester.pumpAndSettle();
    expect(find.byKey(sizePadKey), findsOneWidget);

    await tester.tap(find.text('832×1216'));
    await tester.pumpAndSettle();
    expect(latentSize(runner.workflow!), (width: 832, height: 1216));

    runner.edit((wf) => setLatentSize(wf, (width: 640, height: 960)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pumpAndSettle();
    expect(runner.sizes.last, (width: 640, height: 960));
    expect(
      ComfySettings.fromJson(
        jsonDecode(jsonEncode(config.config.comfy.toJson())),
      ).sizes.last,
      (width: 640, height: 960),
    );
  });

  // 2026-11-22:对话里附的图出图时按先后填进参考图格子;侧栏的工作流能拖着排。
  test('对话里最近一条附了图的消息,图按先后填进参考图格子,多的格子清掉', () {
    Attachment png(int n) => Attachment.image(
      name: '$n.png',
      mime: 'image/png',
      bytes: Uint8List.fromList([n]),
    );
    final t = DateTime(2026);
    final messages = [
      ChatMessage(fromUser: true, text: '旧图', time: t, attachments: [png(9)]),
      ChatMessage(
        fromUser: true,
        text: '改成这样',
        time: t.add(const Duration(seconds: 1)),
        attachments: [png(1), png(2)],
      ),
      ChatMessage(
        fromUser: true,
        text: '再亮一点',
        time: t.add(const Duration(seconds: 2)),
      ),
      ChatMessage(
        fromUser: false,
        text: '<generate-image></generate-image>',
        time: t.add(const Duration(seconds: 3)),
      ),
    ];
    final refs = StudioComfy.refImagesBefore(
      messages,
      t.add(const Duration(seconds: 3)),
    );
    expect(refs.map((a) => a.name), ['1.png', '2.png']);

    final wf = {
      ...defaultWorkflow('m.safetensors'),
      for (final id in ['20', '21', '22'])
        id: {
          'class_type': 'LoadImage',
          'inputs': {'image': ''},
        },
      '30': {
        'class_type': 'PreviewImage',
        'inputs': {
          'images': ['20', 0],
          'b': ['21', 0],
          'c': ['22', 0],
        },
      },
    };
    final config = tempConfig();
    config.update(
      config.config.copyWith(
        comfy: const ComfySettings()
            .putFlow((id: 'a', name: 'A', text: '{}'))
            .putFlow((id: 'f', name: 'Edit', text: jsonEncode(wf)))
            .copyWith(flowId: 'f')
            .putInput('f', '22', 'old.png'),
      ),
    );
    final runner = ComfyRunner(config);
    expect(runner.fillUploads(refs), 2);
    final files = runner.uploadFiles;
    expect(files.keys, unorderedEquals(['20', '21']));
    expect(File(files['20']!).readAsBytesSync(), [1]);
    expect(File(files['21']!).readAsBytesSync(), [2]);
    // 同样的图再填一次:格子没变,不算填了。
    expect(runner.fillUploads(refs), 0);

    runner.moveFlow(1, 0);
    expect(config.config.comfy.flows.map((f) => f.id), ['f', 'a']);
  });
}
