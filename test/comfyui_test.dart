import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comfy_workflow.dart';
import 'package:penna/core/harness/comfyui.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/core/harness/comfyui_progress.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/comfy_images.dart';
import 'package:penna/ui/features/studio/comfy_progress_view.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

Map<String, Object?> _node(String type, Map<String, Object?> inputs) => {
  'class_type': type,
  'inputs': inputs,
};

/// Flux 默认模板的接法:SamplerCustomAdvanced ← BasicGuider ← FluxGuidance ← CLIPTextEncode。
Map<String, Object?> get _flux => {
  '6': _node('CLIPTextEncode', {
    'text': 'old',
    'clip': ['11', 0],
  }),
  '26': _node('FluxGuidance', {
    'guidance': 3.5,
    'conditioning': ['6', 0],
  }),
  '22': _node('BasicGuider', {
    'model': ['12', 0],
    'conditioning': ['26', 0],
  }),
  '25': _node('RandomNoise', {'noise_seed': 7}),
  '13': _node('SamplerCustomAdvanced', {
    'noise': ['25', 0],
    'guider': ['22', 0],
  }),
};

/// 只有一台、连到本机 [port] 的设置。
ComfySettings _at(int port) => ComfySettings(
  servers: [(id: comfyLocalId, name: '本机', url: 'http://127.0.0.1:$port')],
);

void main() {
  group('prepareWorkflow', () {
    test('有 {{prompt}} 记号就换掉它,种子重摇,原来的不动', () {
      final wf = defaultWorkflow('a.safetensors');
      final out = prepareWorkflow(wf, '1girl, smile');
      expect((out['6'] as Map)['inputs']['text'], '1girl, smile');
      expect((wf['6'] as Map)['inputs']['text'], comfyPromptMark);
      // 负面框不动。
      expect((out['7'] as Map)['inputs']['text'], contains('lowres'));
      final seeds = {
        for (var i = 0; i < 5; i++)
          (prepareWorkflow(wf, 'x')['3'] as Map)['inputs']['seed'],
      };
      expect(seeds.length, greaterThan(1));
    });

    test('没有记号时顺着 KSampler 的 positive 找正面框', () {
      final wf = defaultWorkflow('a')
        ..['6'] = _node('CLIPTextEncode', {
          'text': 'old',
          'clip': ['4', 1],
        });
      final out = prepareWorkflow(wf, 'new');
      expect((out['6'] as Map)['inputs']['text'], 'new');
      expect((out['7'] as Map)['inputs']['text'], contains('lowres'));
    });

    test('Flux:穿过 BasicGuider 和 FluxGuidance', () {
      final out = prepareWorkflow(_flux, 'new');
      expect((out['6'] as Map)['inputs']['text'], 'new');
      expect((out['25'] as Map)['inputs']['noise_seed'], isNot(7));
    });

    test('找不到放提示词的地方就报错', () {
      expect(
        () => prepareWorkflow({
          '1': _node('SaveImage', {'filename_prefix': 'x'}),
        }, 'p'),
        throwsA(isA<ComfyException>()),
      );
    });
  });

  test('拆出图标签:空的、自闭合、带提示词,流式时半截的不显示', () {
    expect(splitGenerate('好<generate-image></generate-image>'), (
      prose: '好',
      asked: true,
      prompt: '',
    ));
    expect(splitGenerate('好<generate-image/>').asked, isTrue);
    expect(
      splitGenerate('<generate-image> a cat </generate-image>').prompt,
      'a cat',
    );
    expect(splitGenerate('好<generate-im').prose, '好');
    expect(splitGenerate('好').asked, isFalse);
  });

  test('进度:大半按采样步数,用了缓存的节点算做完', () {
    final t = ComfyProgressTracker(defaultWorkflow('m'));
    expect(t.handle('status', {}), isNull);
    final cached = t.handle('execution_cached', {
      'nodes': ['4', '6', '7'],
    })!;
    expect(cached, closeTo(0.1 * 3 / 7, 1e-9));
    // 只有一步的不算。
    expect(t.handle('progress', {'node': '4', 'value': 1, 'max': 1}), isNull);
    final half = t.handle('progress', {'node': '3', 'value': 5, 'max': 10})!;
    expect(half, closeTo(cached + 0.45, 1e-9));
  });

  test('旧设置(一个地址、一个工作流)读成列表,存回去再读一样', () {
    final old = ComfySettings.fromJson({
      'url': 'http://10.0.0.2:8188',
      'workflow': '{"1":{"class_type":"SaveImage","inputs":{}}}',
      'workflowName': 'Moss',
      'imageDir': 'D:/img',
    });
    expect(old.server.url, 'http://10.0.0.2:8188');
    expect(old.serverId, comfyLocalId);
    expect(old.flow?.name, 'Moss');
    expect(old.imageDir, 'D:/img');
    expect(ComfySettings.fromJson(null).flow, isNull);
    final again = ComfySettings.fromJson(jsonDecode(jsonEncode(old.toJson())));
    expect(again.toJson(), old.toJson());
    // 选中的 id 对不上时用第一个;删掉眼前那个就换到剩下的第一个。
    final two = const ComfySettings(flowId: 'gone')
        .putFlow((id: 'a', name: 'A', text: '{}'))
        .putFlow((id: 'b', name: 'B', text: '{}'));
    expect(two.flow?.id, 'a');
    expect(two.copyWith(flowId: 'b').removeFlow('b').flow?.id, 'a');
    expect(two.removeFlow('a').removeFlow('b').flow, isNull);
    // 本机那台的 Key 沿用旧键名。
    expect(comfyKeyName(comfyLocalId), 'comfy.key');
  });

  test('同一张图每次拿到的是同一个附件:重建界面时不重新读、不闪', () {
    expect(
      identical(
        comfyImageAttachment('a/x.png'),
        comfyImageAttachment('a/x.png'),
      ),
      isTrue,
    );
    expect(comfyImageAttachment('a/x.webp').mime, 'image/webp');
  });

  test('只认 API 格式', () {
    expect(
      () => parseApiWorkflow('{"nodes": [], "links": []}'),
      throwsA(isA<ComfyException>()),
    );
    expect(() => parseApiWorkflow('nope'), throwsA(isA<ComfyException>()));
    expect(parseApiWorkflow(jsonEncode(_flux)).length, 5);
  });

  test('有存下来的图就不要预览图', () {
    final files = pickOutputImages({
      '9': {
        'images': [
          {'filename': 'a.png', 'type': 'output'},
        ],
      },
      '10': {
        'images': [
          {'filename': 'b.png', 'type': 'temp'},
        ],
      },
    });
    expect(files.map((f) => f['filename']), ['a.png']);
  });

  group('假的 ComfyUI', () {
    late HttpServer server;
    late Map<String, Object?> queued;
    var polls = 0;
    final sockets = <WebSocket>[];

    setUp(() async {
      polls = 0;
      sockets.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final res = req.response;
        final path = req.uri.path;
        if (path == '/ws') {
          sockets.add(await WebSocketTransformer.upgrade(req));
          return;
        }
        if (path == '/object_info/CheckpointLoaderSimple') {
          res.write(
            jsonEncode({
              'CheckpointLoaderSimple': {
                'input': {
                  'required': {
                    'ckpt_name': [
                      'COMBO',
                      {
                        'options': ['m.safetensors', 'sdxl/m2.safetensors'],
                      },
                    ],
                  },
                },
              },
            }),
          );
        } else if (path == '/object_info/LoraLoaderModelOnly') {
          res.write(
            jsonEncode({
              'LoraLoaderModelOnly': {
                'input': {
                  'required': {
                    'lora_name': [
                      ['style.safetensors'],
                      {},
                    ],
                  },
                },
              },
            }),
          );
        } else if (path == '/system_stats') {
          res.write(
            jsonEncode({
              'system': {'comfyui_version': '9.9'},
            }),
          );
        } else if (path == '/prompt') {
          queued = jsonDecode(
            await utf8.decoder.bind(req).join(),
          ) as Map<String, Object?>;
          res.write(jsonEncode({'prompt_id': 'p1'}));
          // 进度:别人的单子不算,采样器走到一半、走完,整单做完。
          for (final m in [
            {
              'type': 'progress',
              'data': {
                'node': '3',
                'value': 9,
                'max': 10,
                'prompt_id': 'other',
              },
            },
            {
              'type': 'executing',
              'data': {'node': '3', 'prompt_id': 'p1'},
            },
            {
              'type': 'progress',
              'data': {'node': '3', 'value': 5, 'max': 10, 'prompt_id': 'p1'},
            },
            {
              'type': 'progress',
              'data': {'node': '3', 'value': 10, 'max': 10, 'prompt_id': 'p1'},
            },
            {
              'type': 'executing',
              'data': {'node': null, 'prompt_id': 'p1'},
            },
          ]) {
            for (final ws in sockets) {
              ws.add(jsonEncode(m));
            }
          }
        } else if (path == '/history/p1') {
          // 第一次问还没做完。
          res.write(
            jsonEncode(
              ++polls < 2
                  ? {}
                  : {
                      'p1': {
                        'status': {'status_str': 'success'},
                        'outputs': {
                          '9': {
                            'images': [
                              {
                                'filename': 'Penna_0001.png',
                                'subfolder': '',
                                'type': 'output',
                              },
                            ],
                          },
                        },
                      },
                    },
            ),
          );
        } else if (path == '/view') {
          expect(req.uri.queryParameters['filename'], 'Penna_0001.png');
          res.add([1, 2, 3]);
        } else {
          res.statusCode = 404;
        }
        await res.close();
      });
    });

    tearDown(() async {
      for (final ws in sockets) {
        await ws.close();
      }
      await server.close(force: true);
    });

    test('没导入工作流时用内置文生图和第一个模型,出的图下载回来', () async {
      final client = ComfyClient('http://127.0.0.1:${server.port}/')
        ..poll = Duration.zero;
      final seen = <double>[];
      final images = await client.run('', 'a cat', onProgress: seen.add);
      expect(images.single.name, 'Penna_0001.png');
      expect(seen, isNotEmpty);
      expect(seen.last, greaterThan(0.9));
      expect(seen.first, lessThan(seen.last));
      expect(images.single.bytes, [1, 2, 3]);
      final prompt = queued['prompt'] as Map;
      expect((prompt['6'] as Map)['inputs']['text'], 'a cat');
      expect((prompt['4'] as Map)['inputs']['ckpt_name'], 'm.safetensors');
    });

    test('Agent 写了出图标签:出图,图贴回那条回复', () async {
      final service = tempConfig();
      service.update(
        service.config
            .putLlm(
              const LlmProfile(
                id: 'a',
                name: 'A',
                baseUrl: 'http://a',
                model: 'm',
              ),
            )
            .copyWith(comfy: _at(server.port)),
      );
      final vm = StudioViewModel(
        config: service,
        streamChat: (_) =>
            Stream.value('好的。<generate-image>【主体】a cat</generate-image>'),
      );
      expect(vm.send('画一只猫'), isNull);
      for (var i = 0; i < 100 && vm.messages.last.images.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final reply = vm.messages.last;
      expect(reply.images, hasLength(1));
      expect(File(reply.images.single).readAsBytesSync(), [1, 2, 3]);
      // 标注不带进提示词。
      expect(
        ((queued['prompt'] as Map)['6'] as Map)['inputs']['text'],
        'a cat',
      );
      expect(vm.comfy.latestFor('a cat'), reply.images.single);
    });

    test('测连接、读名单;内置的改过后另存一份;按名字或模型换工作流;LoRA 配置', () async {
      final service = tempConfig();
      service.update(service.config.copyWith(comfy: _at(server.port)));
      final runner = ComfyRunner(service);
      await runner.check(full: true);
      expect(runner.status?.connected, isTrue);
      expect(runner.status?.version, '9.9');
      expect(runner.loraOptions, ['style.safetensors']);
      // 一个都没导入:只有内置文生图。
      expect(runner.flowChoices.map((f) => f.name), ['内置 · 文生图']);

      // 内置的加了 LoRA:另存一份并换过去,名字照旧。
      expect(
        runner.edit((wf) => addLora(wf, 'style.safetensors', 0.7)),
        isNull,
      );
      expect(service.config.comfy.flows, hasLength(1));
      expect(runner.workflowName, '内置 · 文生图');
      expect(loraSlots(runner.workflow!).single.strength, 0.7);

      // 导入了别的:下拉里只有导入的,没有现拼的内置文生图。
      service.update(
        service.config.copyWith(
          comfy: service.config.comfy.putFlow((
            id: 'f2',
            name: 'SDXL 二采',
            text: jsonEncode(defaultWorkflow('sdxl/m2.safetensors')),
          )),
        ),
      );
      expect(runner.flowChoices.map((f) => f.name), ['内置 · 文生图', 'SDXL 二采']);
      // 按它用的模型找:去掉文件夹和后缀也认。
      expect(runner.switchWorkflow('M2').flow, 'SDXL 二采');
      expect(runner.flowId, 'f2');
      expect(runner.switchWorkflow('内置').flow, '内置 · 文生图');
      expect(runner.switchWorkflow('nope').problem, contains('nope'));

      // 存一套,改掉,再用回那一套。
      expect(runner.saveLoraPreset('柔和'), isNull);
      final slot = loraSlots(runner.workflow!).single;
      runner.edit((wf) => setLora(wf, slot.node, slot.key, strength: 0.2));
      expect(loraSlots(runner.workflow!).single.strength, 0.2);
      final preset = service.config.comfy.loraPresets.single;
      expect(runner.applyLoraPreset(preset), isNull);
      expect(loraSlots(runner.workflow!).single.strength, 0.7);
    });

    test('Agent 换成用那个模型的工作流再出图;换不成就不出图', () async {
      final service = tempConfig();
      service.update(
        service.config
            .putLlm(
              const LlmProfile(
                id: 'a',
                name: 'A',
                baseUrl: 'http://a',
                model: 'm',
              ),
            )
            .copyWith(
              comfy: _at(server.port)
                  .putFlow((
                    id: 'f1',
                    name: 'Moss',
                    text: jsonEncode(defaultWorkflow('m.safetensors')),
                  ))
                  .putFlow((
                    id: 'f2',
                    name: 'SDXL 二采',
                    text: jsonEncode(defaultWorkflow('sdxl/m2.safetensors')),
                  )),
            ),
      );
      final replies = [
        '<$comfyWorkflowTag>nope</$comfyWorkflowTag><generate-image>a dog</generate-image>',
        '换好了。<$comfyWorkflowTag>SDXL 二采</$comfyWorkflowTag><generate-image>a cat</generate-image>',
      ];
      var turn = 0;
      final seen = <LlmRequest>[];
      final vm = StudioViewModel(
        config: service,
        streamChat: (req) {
          seen.add(req);
          return Stream.value(replies[turn++]);
        },
      );
      await vm.comfy.check(full: true);

      expect(vm.send('换 nope 出图'), isNull);
      await pumpEventQueue();
      // 系统提示里有每个工作流和它用的模型。
      final system = seen.single.messages.first['content']!;
      expect(system, contains('- Moss(眼前用的):m.safetensors'));
      expect(system, contains('- SDXL 二采:sdxl/m2.safetensors'));
      expect(system, isNot(contains('内置 · 文生图')));
      expect(vm.messages.last.toolSummary, contains('没换成工作流'));
      expect(vm.comfy.running, isFalse);

      expect(vm.send('用 m2 出图'), isNull);
      for (var i = 0; i < 100 && vm.messages.last.images.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(vm.messages.last.toolSummary, contains('已换工作流:SDXL 二采'));
      expect(vm.messages.last.images, hasLength(1));
      expect(
        ((queued['prompt'] as Map)['4'] as Map)['inputs']['ckpt_name'],
        'sdxl/m2.safetensors',
      );
    });

    test('停止时报 canceled', () async {
      final client = ComfyClient('http://127.0.0.1:${server.port}')
        ..poll = Duration.zero;
      await expectLater(
        client.run('', 'a cat', canceled: () => true),
        throwsA(
          isA<ComfyException>().having((e) => e.canceled, 'canceled', true),
        ),
      );
    });
  });

  test('连不上时说人话', () async {
    final client = ComfyClient('http://127.0.0.1:1');
    await expectLater(
      client.version(),
      throwsA(
        isA<ComfyException>().having(
          (e) => e.message,
          'message',
          contains('127.0.0.1:1'),
        ),
      ),
    );
  });

  test('存图、换位置只搬 Penna 出的图', () async {
    final root = await Directory.systemTemp.createTemp('penna-comfy');
    addTearDown(() => root.delete(recursive: true));
    final from = '${root.path}${Platform.pathSeparator}a';
    final to = '${root.path}${Platform.pathSeparator}b';
    final time = DateTime(2026, 11, 6, 9, 5, 3);
    final one = saveComfyImage(from, 'x.png', Uint8List(1), time);
    final two = saveComfyImage(from, 'x.webp', Uint8List(1), time);
    expect(one.path, endsWith('Penna-20261106-090503-1.png'));
    expect(two.path, endsWith('Penna-20261106-090503-1.webp'));
    File('$from${Platform.pathSeparator}mine.txt').writeAsStringSync('keep');
    expect(await moveComfyImages(from, to), 2);
    expect(Directory(to).listSync().length, 2);
    expect(Directory(from).listSync().length, 1);
    expect(await moveComfyImages(to, to), 0);
  });
}
