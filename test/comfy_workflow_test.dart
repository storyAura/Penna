import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comfy_workflow.dart';
import 'package:penna/core/harness/comfyui.dart';

Map<String, Object?> _node(String type, Map<String, Object?> inputs) => {
  'class_type': type,
  'inputs': inputs,
};

/// 截图里那种:UNET → 仅模型 LoRA → Power Lora Loader → 采样器。
ComfyWorkflow get _moss => {
  '1': _node('UNETLoader', {'unet_name': 'moss.safetensors'}),
  '2': _node('CLIPLoader', {'clip_name': 'clip.safetensors'}),
  '105': _node('LoraLoaderModelOnly', {
    'lora_name': 'Krea2Real\\realism.safetensors',
    'strength_model': 1.0,
    'model': ['1', 0],
  }),
  '24': _node('Power Lora Loader (rgthree)', {
    'PowerLoraLoaderHeaderWidget': {'type': 'PowerLoraLoaderHeaderWidget'},
    'lora_1': {
      'on': true,
      'lora': 'Moss-base\\turbo.safetensors',
      'strength': 1.0,
    },
    'lora_2': {
      'on': false,
      'lora': 'Moss-base\\dino.safetensors',
      'strength': 0.3,
    },
    'lora_3': {'on': false, 'lora': 'None', 'strength': 1.0},
    '➕ Add Lora': '',
    'model': ['105', 0],
    'clip': ['2', 0],
  }),
  '3': _node('KSampler', {
    'seed': 1,
    'model': ['24', 0],
  }),
};

void main() {
  test('认模型加载器,换模型', () {
    expect(modelSlots(_moss).single, (
      node: '1',
      type: 'UNETLoader',
      key: 'unet_name',
      value: 'moss.safetensors',
    ));
    final out = setModel(_moss, '1', 'unet_name', 'other.safetensors');
    expect(modelSlots(out).single.value, 'other.safetensors');
    expect(modelSlots(_moss).single.value, 'moss.safetensors');
  });

  test('仅模型的 LoRA 和 Power Lora Loader 都认出来,None 的槽位不算', () {
    final slots = loraSlots(_moss);
    expect(slots.map((s) => (s.node, s.key, s.on, s.canToggle)), [
      ('24', 'lora_1', true, true),
      ('24', 'lora_2', false, true),
      ('105', 'lora_name', true, false),
    ]);
    expect(slots[1].strength, 0.3);
  });

  test('官方 LoraLoader 两个权重一起改', () {
    final wf = {
      '5': _node('LoraLoader', {
        'lora_name': 'a.safetensors',
        'strength_model': 0.8,
        'strength_clip': 0.5,
      }),
    };
    expect(loraSlots(wf).single.strength, 0.8);
    final out = setLora(wf, '5', 'lora_name', strength: 0.6);
    expect((out['5'] as Map)['inputs'], containsPair('strength_clip', 0.6));
    expect((out['5'] as Map)['inputs'], containsPair('strength_model', 0.6));
  });

  test('Stack 类:按尾号配权重和开关', () {
    final wf = {
      '7': _node('CR LoRA Stack', {
        'switch_1': 'On',
        'lora_name_1': 'a.safetensors',
        'model_weight_1': 0.7,
        'clip_weight_1': 1.0,
        'switch_2': 'Off',
        'lora_name_2': 'b.safetensors',
        'model_weight_2': 1.0,
        'clip_weight_2': 1.0,
        'switch_3': 'Off',
        'lora_name_3': 'None',
        'model_weight_3': 1.0,
        'clip_weight_3': 1.0,
      }),
      '8': _node('LoRA Stacker', {
        'input_mode': 'simple',
        'lora_count': 1,
        'lora_name_1': 'c.safetensors',
        'lora_wt_1': 0.4,
      }),
    };
    final slots = loraSlots(wf);
    expect(slots.map((s) => (s.name, s.strength, s.on, s.canToggle)), [
      ('a.safetensors', 0.7, true, true),
      ('b.safetensors', 1.0, false, true),
      ('c.safetensors', 0.4, true, false),
    ]);
    final on = setLora(wf, '7', 'lora_name_2', on: true, strength: 0.2);
    final inputs = (on['7'] as Map)['inputs'] as Map;
    expect(inputs['switch_2'], 'On');
    expect(inputs['model_weight_2'], 0.2);
    expect(inputs['model_weight_1'], 0.7);
    // Stack 里的去掉就是改成 None。
    final gone = removeLora(wf, '8', 'lora_name_1');
    expect(loraSlots(gone).map((s) => s.name), [
      'a.safetensors',
      'b.safetensors',
    ]);
  });

  test('加 LoRA:有 Power Lora Loader 就加在里面,接着往后编号', () {
    final out = addLora(_moss, 'new.safetensors', 0.5);
    final inputs = (out['24'] as Map)['inputs'] as Map;
    expect(inputs['lora_4'], {
      'on': true,
      'lora': 'new.safetensors',
      'strength': 0.5,
    });
    expect(out.length, _moss.length);
    // 删掉那一项。
    expect(loraSlots(removeLora(out, '24', 'lora_4')).length, 3);
  });

  test('加 LoRA:没有就在模型加载器后面插一个,线改接过去;删掉时接回来', () {
    final wf = {
      '4': _node('CheckpointLoaderSimple', {'ckpt_name': 'm.safetensors'}),
      '3': _node('KSampler', {
        'model': ['4', 0],
      }),
      '8': _node('VAEDecode', {
        'vae': ['4', 2],
      }),
    };
    final out = addLora(wf, 'x.safetensors', 0.8);
    // 编号接在最大的后面。
    expect(out['9'], {
      'class_type': 'LoraLoaderModelOnly',
      'inputs': {
        'lora_name': 'x.safetensors',
        'strength_model': 0.8,
        'model': ['4', 0],
      },
    });
    expect(((out['3'] as Map)['inputs'] as Map)['model'], ['9', 0]);
    // VAE 还接在原来的加载器上。
    expect(((out['8'] as Map)['inputs'] as Map)['vae'], ['4', 2]);
    final back = removeLora(out, '9', 'lora_name');
    expect(back, wf);
  });

  test('没有模型加载器时加不了', () {
    expect(
      () => addLora({'1': _node('SaveImage', {})}, 'x', 1),
      throwsA(isA<ComfyException>()),
    );
  });
}
