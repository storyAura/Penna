import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comfy_workflow.dart';
import 'package:penna/core/harness/comfyui.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/comfy_runner.dart';

import 'fixtures.dart';

// 2026-11-23 用户切到云端 ComfyUI 后反馈的几件事:工作流在这台上缺什么、LoRA 名单要读眼前那台、
// 模型文件能换、H3 的时长、云端子文件夹。

Map<String, Object?> _node(String type, Map<String, Object?> inputs) => {
  'class_type': type,
  'inputs': inputs,
};

/// 一台 Linux 云端:模型名用 `/` 分文件夹。
final _info = parseNodeInfo({
  'UNETLoader': {
    'input': {
      'required': {
        'unet_name': [
          ['Moss/moss.safetensors', 'anima.safetensors'],
          {},
        ],
      },
    },
  },
  'LoraLoaderModelOnly': {
    'input': {
      'required': {
        'lora_name': [
          'COMBO',
          {
            'options': ['Moss-base/turbo.safetensors'],
          },
        ],
        'strength_model': ['FLOAT', {}],
      },
    },
  },
  'Power Lora Loader (rgthree)': {'input': {}},
  'SaveVideo': {
    'input': {
      'required': {
        'format': [
          'COMFY_DYNAMICCOMBO_V3',
          {
            'options': [
              {'key': 'auto', 'inputs': {}},
              {'key': 'mp4', 'inputs': {}},
            ],
          },
        ],
      },
    },
  },
  'LoadImage': {
    'input': {
      'required': {
        'image': [
          ['example.png'],
          {},
        ],
      },
    },
  },
});

void main() {
  test('读 object_info:老写法、新写法的下拉都认,不是下拉的不留', () {
    expect(_info['UNETLoader']!['unet_name'], [
      'Moss/moss.safetensors',
      'anima.safetensors',
    ]);
    expect(_info['LoraLoaderModelOnly'], {
      'lora_name': ['Moss-base/turbo.safetensors'],
    });
    expect(loraNamesOf(_info), ['Moss-base/turbo.safetensors']);
  });

  test('工作流在这台上缺什么:没装的节点、没有的模型和 LoRA;分隔写法不同不算缺,上传格子不算', () {
    final wf = {
      '1': _node('UNETLoader', {'unet_name': r'Moss\moss.safetensors'}),
      '2': _node('Power Lora Loader (rgthree)', {
        'lora_1': {'on': true, 'lora': r'Moss-base\turbo.safetensors'},
        'lora_2': {'on': true, 'lora': 'gone.safetensors'},
        // 关着的不加载,不算缺。
        'lora_4': {'on': false, 'lora': 'off.safetensors'},
        // 本机放在 Moss\,这台只有一个同名的、放在 Moss-base/:算有。
        'lora_3': {'on': true, 'lora': r'Moss\turbo.safetensors'},
      }),
      '3': _node('LoadImage', {'image': 'my-ref.png'}),
      '4': _node('SageAttention', {'mode': 'auto'}),
      '5': _node('UNETLoader', {'unet_name': 'minimax_h3.safetensors'}),
      // 动态下拉的选项是 {key, inputs}:auto 在里面,不算缺。
      '6': _node('SaveVideo', {'format': 'auto'}),
    };
    expect(workflowProblems(wf, _info), [
      '缺 gone.safetensors',
      '缺节点 SageAttention',
      '缺 minimax_h3.safetensors',
    ]);
    // 还没读到名单时什么都不报。
    expect(workflowProblems(wf, const {}), isEmpty);

    // 出图前换成这台的写法,原来的不动。
    final out = adaptToServer(wf, _info);
    expect((out['1'] as Map)['inputs']['unet_name'], 'Moss/moss.safetensors');
    expect(
      ((out['2'] as Map)['inputs']['lora_1'] as Map)['lora'],
      'Moss-base/turbo.safetensors',
    );
    expect(
      ((out['2'] as Map)['inputs']['lora_3'] as Map)['lora'],
      'Moss-base/turbo.safetensors',
    );
    expect((wf['1'] as Map)['inputs']['unet_name'], r'Moss\moss.safetensors');
  });

  test('模型文件:UNet、文本编码器、VAE 都列出来;H3 的时长是秒数,能改', () {
    final h3 = parseApiWorkflow(
      File('assets/comfy/minimax-h3-video.json').readAsStringSync(),
    );
    expect(fileSlots(h3).map((s) => s.key).toSet(), {
      'unet_name',
      'clip_name',
      'vae_name',
    });
    final d = durationSlot(h3)!;
    expect((d.value, d.frames), (10, false));
    final set = applyComfySet(h3, 'duration=6s');
    expect(durationSlot(set.workflow)!.value, 6);

    // 没标时长的:画面大小节点上的 length 是帧数。
    final latent = {
      '1': _node('EmptyHunyuanLatentVideo', {
        'width': 832,
        'height': 480,
        'length': 81,
      }),
    };
    final f = durationSlot(latent)!;
    expect((f.value, f.frames), (81, true));
    expect(
      durationSlot(applyComfySet(latent, 'length=121').workflow)!.value,
      121,
    );
  });

  test('存视频的节点不在 Penna.Output 组里也认得是输出', () {
    final text = File(
      'assets/comfy/minimax-h3-video.json',
    ).readAsStringSync().replaceAll('Penna.Output.save 保存视频', '保存视频');
    final wf = parseApiWorkflow(text);
    expect(
      wf.values.map((n) => (n as Map)['class_type']),
      contains('SaveVideo'),
    );
    expect(fileSlots(wf), isNotEmpty);
  });

  test('素材接口列的图:相对路径拆成子文件夹和文件名,只留图片', () {
    final shots = parseOutputAssets({
      'assets': [
        {
          'display_name': '26_11_23/ComfyUI_00001_.png',
          'created_at': '2026-11-23T10:00:00Z',
        },
        {'display_name': 'top.webp', 'created_at': '2026-11-23T09:00:00Z'},
        {'display_name': 'video/MiniMax_H3_00001.mp4'},
      ],
      'next_cursor': null,
    });
    expect(shots.map((s) => (shotFolder(s), s.file['filename'])), [
      ('26_11_23', 'ComfyUI_00001_.png'),
      ('', 'top.webp'),
    ]);
    expect(shots.first.time, isNotNull);
  });

  group('换服务器', () {
    setUp(() => HttpOverrides.global = null);

    test('测连接测到一半换了一台:读回的名单不记成新那台的', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final res = req.response;
        if (req.uri.path == '/system_stats') {
          res.write('{"system": {"comfyui_version": "1"}}');
        } else if (req.uri.path == '/object_info') {
          // 慢一点,好在读的中途换一台。
          await Future<void>.delayed(const Duration(milliseconds: 200));
          res.write(
            jsonEncode({
              'LoraLoaderModelOnly': {
                'input': {
                  'required': {
                    'lora_name': [
                      ['local-only.safetensors'],
                      {},
                    ],
                  },
                },
              },
            }),
          );
        } else {
          res.statusCode = 404;
        }
        await res.close();
      });
      addTearDown(() => server.close(force: true));
      // 另一台连不上(端口没人听)。
      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = dead.port;
      await dead.close();

      final config = tempConfig();
      config.update(
        config.config.copyWith(
          comfy: ComfySettings(
            servers: [
              (
                id: comfyLocalId,
                name: '本机',
                url: 'http://127.0.0.1:${server.port}',
              ),
              (id: 'cloud', name: '云', url: 'http://127.0.0.1:$deadPort'),
            ],
          ),
        ),
      );
      final runner = ComfyRunner(config);
      final first = runner.check(full: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      runner.selectServer('cloud');
      await first;
      // 测完发现换了,接着测新的那台;等它也测完。
      for (
        var i = 0;
        i < 50 && (runner.checking || runner.status == null);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(runner.loraOptions, isEmpty);
      expect(runner.status?.connected, isFalse);
    });
  });
}
