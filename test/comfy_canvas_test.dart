import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comfy_canvas.dart';
import 'package:penna/core/harness/comfyui.dart';

// 夹具是用户的标准工作流(普通保存的画布格式),模型名和提示词换成了占位的。
Map<String, Object?> _canvas() =>
    jsonDecode(File('test/fixtures/comfy_canvas.json').readAsStringSync())
        as Map<String, Object?>;

/// 把某个组的标题换掉。
Map<String, Object?> _retitle(Map<String, Object?> wf, int id, String title) {
  for (final g in wf['groups'] as List) {
    if ((g as Map)['id'] == id) g['title'] = title;
  }
  return wf;
}

Map<String, Object?> _inputs(Map<String, Object?> api, String id) =>
    ((api[id] as Map)['inputs'] as Map).cast<String, Object?>();

void main() {
  group('普通保存的工作流转 API', () {
    test('只留从存图节点接得上的;旁路、Reroute、残留、说明卡片都不写', () {
      final api = parseApiWorkflow(jsonEncode(_canvas()));
      expect(api.keys.toSet(), {
        '16', '17', '18', '93', '94', '95', '104', '108', '112', '119', //
      });
    });

    test('连线穿过旁路的 LoRA 链和 Reroute', () {
      final api = canvasToApi(_canvas());
      expect(_inputs(api, '16')['model'], ['108', 0]);
      expect(_inputs(api, '119')['clip'], ['108', 1]);
      expect(_inputs(api, '112')['clip'], ['94', 0]);
      expect(_inputs(api, '16')['latent_image'], ['104', 0]);
    });

    test('连线穿过 KJNodes 的 GetNode → 同名 SetNode,两个都不写', () {
      final wf = _canvas();
      final nodes = wf['nodes'] as List;
      final ks = nodes.cast<Map>().firstWhere((n) => n['id'] == 16);
      final model = (ks['inputs'] as List).cast<Map>().firstWhere(
        (i) => i['name'] == 'model',
      );
      nodes.addAll([
        {
          'id': 900,
          'type': 'SetNode',
          'mode': 0,
          'inputs': [
            {'name': 'MODEL', 'type': 'MODEL', 'link': model['link']},
          ],
          'widgets_values': ['Model'],
        },
        {
          'id': 901,
          'type': 'GetNode',
          'mode': 0,
          'outputs': [
            {'name': 'MODEL', 'type': 'MODEL'},
          ],
          'widgets_values': ['Model'],
        },
      ]);
      (wf['links'] as List).add([9001, 901, 0, 16, 0, 'MODEL']);
      model['link'] = 9001;
      final api = canvasToApi(wf);
      expect(_inputs(api, '16')['model'], ['108', 0]);
      expect(api.keys, isNot(contains('900')));
      expect(api.keys, isNot(contains('901')));
    });

    test('控件按名字取,control_after_generate 不进 API', () {
      final ks = _inputs(canvasToApi(_canvas()), '16');
      expect(ks['steps'], 8);
      expect(ks['cfg'], 1);
      expect(ks['scheduler'], 'sgm_uniform');
      expect(ks.containsKey('control_after_generate'), isFalse);
    });

    test('没有按名字存的旧文件按输入表的先后对上,跳过 randomize', () {
      final wf = _canvas();
      for (final n in wf['nodes'] as List) {
        (n as Map).remove('widgets_values_named');
      }
      final ks = _inputs(canvasToApi(wf), '16');
      expect(ks['steps'], 8);
      expect(ks['sampler_name'], 'euler');
      expect(ks['denoise'], 1);
    });

    test('Power Lora Loader 没有 LoRA 时只剩连线;有的写成 lora_1', () {
      expect(_inputs(canvasToApi(_canvas()), '108').keys.toSet(), {
        'model',
        'clip',
      });
      final wf = _canvas();
      final power = (wf['nodes'] as List).cast<Map>().firstWhere(
        (n) => n['id'] == 108,
      );
      power['widgets_values'] = [
        {},
        {'type': 'PowerLoraLoaderHeaderWidget'},
        {'on': true, 'lora': 'a.safetensors', 'strength': 0.8},
        {},
        '',
      ];
      expect(_inputs(canvasToApi(wf), '108')['lora_1'], {
        'on': true,
        'lora': 'a.safetensors',
        'strength': 0.8,
      });
    });

    test('组名记号:正面提示词框换成 {{prompt}},画布组的尺寸换成画板的', () {
      final wf = _retitle(
        _retitle(_canvas(), 2, 'Penna.Prompt.positive 正向提示词'),
        6,
        'Penna.Latent 画布',
      );
      final api = canvasToApi(wf);
      expect(_inputs(api, '119')['text'], comfyPromptMark);
      expect((api['104'] as Map)['_meta'], {'title': 'Penna.Latent'});
      final ready = prepareWorkflow(
        api,
        'a cat',
        size: (width: 832, height: 1216),
      );
      expect(_inputs(ready, '119')['text'], 'a cat');
      expect(_inputs(ready, '104')['width'], 832);
      expect(_inputs(ready, '104')['height'], 1216);
    });

    test('没有记号时提示词顺着采样器找到正面框', () {
      final ready = prepareWorkflow(canvasToApi(_canvas()), 'a cat');
      expect(_inputs(ready, '119')['text'], 'a cat');
      expect(_inputs(ready, '112')['text'], isNot('a cat'));
    });

    test('组标题记号:只认第一个词,旧标题不算', () {
      expect(
        groupToken('Penna.LoRA.power  中文说明 / English'),
        'Penna.LoRA.power',
      );
      expect(groupToken('Penna.Sampler#hires'), 'Penna.Sampler#hires');
      expect(groupToken('LoRA Loading 1'), isNull);
      expect(groupToken('penna.Latent'), isNull);
    });

    test('节点挪出组框就不算组里的', () {
      final wf = _retitle(_canvas(), 6, 'Penna.Latent');
      final latent = (wf['nodes'] as List).cast<Map>().firstWhere(
        (n) => n['id'] == 104,
      );
      latent['pos'] = [-447.0, 2000.0];
      expect((canvasToApi(wf)['104'] as Map)['_meta'], {
        'title': 'EmptyLatentImage',
      });
    });

    test('没有存图节点时报错', () {
      final wf = _canvas();
      wf['nodes'] = [
        for (final n in wf['nodes'] as List)
          if ((n as Map)['type'] != 'SaveImage') n,
      ];
      expect(() => canvasToApi(wf), throwsA(isA<ComfyException>()));
    });
  });

  test('出图尺寸:没有记号时换所有空白画布,取 8 的倍数', () {
    final ready = prepareWorkflow(
      defaultWorkflow('m.safetensors'),
      'x',
      size: (width: 830, height: 1219),
    );
    expect(_inputs(ready, '5')['width'], 832);
    expect(_inputs(ready, '5')['height'], 1216);
    // 不给尺寸照工作流里写的。
    expect(
      _inputs(prepareWorkflow(defaultWorkflow('m'), 'x'), '5')['width'],
      1024,
    );
  });
}
