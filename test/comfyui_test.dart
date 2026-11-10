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
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/side_chat.dart';
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

  test('读 ComfyUI 的历史:新的在前,找回当时的提示词,预览图不算', () {
    Map<String, Object?> run(String text, int at, List<Map> images) => {
      'prompt': [
        0,
        'x',
        prepareWorkflow(defaultWorkflow('m'), text),
        {},
        ['9'],
      ],
      'outputs': {
        '9': {'images': images},
      },
      'status': {
        'status_str': 'success',
        'messages': [
          [
            'execution_start',
            {'timestamp': at - 5},
          ],
          [
            'execution_success',
            {'timestamp': at},
          ],
        ],
      },
    };
    final shots = parseHistory({
      'old': run('a fox', 1000, [
        {'filename': 'a.png', 'type': 'output'},
      ]),
      'new': run('a cat', 2000, [
        {'filename': 'b.png', 'type': 'output'},
        {'filename': 'c.png', 'type': 'output'},
        {'filename': 'tmp.png', 'type': 'temp'},
      ]),
    });
    expect(shots.map((s) => s.file['filename']), ['b.png', 'c.png', 'a.png']);
    expect(shots.first.prompt, 'a cat');
    expect(shots.last.time, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(parseHistory('nope'), isEmpty);
    // 缩略图让 ComfyUI 压成 WebP。
    final client = ComfyClient('http://h:1/', key: 'k');
    expect(
      client.viewUrl(shots.first.file, preview: true),
      'http://h:1/view?filename=b.png&subfolder&type=output&preview=webp%3B75',
    );
    expect(client.headers, {'authorization': 'Bearer k'});
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
    Object? forgotten;

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
        } else if (path == '/history' && req.method == 'POST') {
          forgotten = jsonDecode(await utf8.decoder.bind(req).join());
          res.write('{}');
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

    test('一条回复写了好几页:默认不自动出图;开了系列连续出图就按页的先后都出', () async {
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
      const reply =
          '<draft page="1">\n【主体】a cat\n</draft>'
          '<draft page="2">\n【主体】a dog\n</draft>'
          '<generate-image></generate-image>';
      final vm = StudioViewModel(
        config: service,
        streamChat: (_) => Stream.value(reply),
      );
      expect(vm.send('画两页'), isNull);
      await pumpEventQueue();
      expect(vm.pages, hasLength(2));
      expect(vm.comfy.jobs, isEmpty);
      expect(vm.messages.last.toolSummary, contains('没有自动出图'));

      service.update(service.config.copyWith(seriesGenerate: true));
      expect(vm.send('再画两页'), isNull);
      await pumpEventQueue();
      expect(
        [for (final j in vm.comfy.jobs.reversed) j.prompt],
        ['a cat', 'a dog'],
      );
      for (var i = 0; i < 100 && vm.messages.last.images.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(vm.messages.last.images, hasLength(2));
    });

    test('区域控制的 Agent 出图:先放布局,用画板交出去的 JSON,和工作台同一条队列', () async {
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
      final main = StudioViewModel(
        config: service,
        streamChat: (_) => const Stream.empty(),
      );
      final board = LayoutBoard()..setSize(400, 400);
      final vm = StudioViewModel(
        config: service,
        streamChat: (_) => Stream.value(
          '<layout>{"width": 400, "height": 400, "summary": {"caption": "cat"}, '
          '"items": [{"name": "猫", "bbox": [0, 0, 200, 200]}], '
          '"bbox_coord_space": "abs", "bbox_format": "xyxy"}</layout>'
          // 标签里写的字不算:区域控制始终用画板上的布局。
          '<generate-image>a dog</generate-image>',
        ),
        layout: board,
        layoutOnly: true,
        comfy: main.comfy,
      );
      expect(vm.send('排一只猫并出图'), isNull);
      for (var i = 0; i < 100 && vm.messages.last.images.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(vm.messages.last.images, hasLength(1));
      expect(board.layout.boxes, hasLength(1));
      expect(
        ((queued['prompt'] as Map)['6'] as Map)['inputs']['text'],
        board.json,
      );
      expect(identical(vm.comfy, main.comfy), isTrue);
    });

    test('正在出图时再要一张:排进队列,前一张出完接着出;撤掉排着的;记录存盘读回', () async {
      final service = tempConfig();
      service.update(service.config.copyWith(comfy: _at(server.port)));
      final runner = ComfyRunner(service);
      final first = runner.generate('a cat');
      final second = runner.generate('a dog', owner: 'reply');
      final third = runner.generate('a fox');
      expect(runner.running, isTrue);
      expect(runner.waiting, 2);
      expect(runner.aheadOf('reply'), 1);
      runner.cancel(runner.jobs.first.id);
      expect((await third).images, isEmpty);

      expect((await first).error, isNull);
      expect((await second).images, hasLength(1));
      final [fox, dog, cat] = runner.jobs;
      expect(fox.state, ComfyJobState.canceled);
      expect([dog.state, cat.state], everyElement(ComfyJobState.done));
      expect(dog.started!.isBefore(cat.finished!), isFalse);
      expect(cat.took, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      final again = ComfyRunner(service);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(again.jobs.map((j) => j.prompt), ['a fox', 'a dog', 'a cat']);
      expect(again.jobs[1].images, dog.images);
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
      // 改了没存:保存按钮亮;用回那一套就回到存的样子。
      expect(runner.loraPreset?.name, '柔和');
      expect(runner.loraPresetChanged, isTrue);
      final preset = service.config.comfy.loraPresets.single;
      expect(runner.applyLoraPreset(preset), isNull);
      expect(loraSlots(runner.workflow!).single.strength, 0.7);
      expect(runner.loraPresetChanged, isFalse);

      // 各套各是各的名单:另一套多加的 LoRA,换回「柔和」时去掉,而不是留着关掉。
      runner.edit((wf) => addLora(wf, 'extra.safetensors', 0.5));
      expect(runner.saveLoraPreset('加一个'), isNull);
      expect(loraSlots(runner.workflow!).map((l) => l.name), hasLength(2));
      expect(runner.applyLoraPreset(preset), isNull);
      expect(loraSlots(runner.workflow!).map((l) => l.name), [
        preset.loras.single.name,
      ]);
      // 改了眼前这一套再保存,存回的就是它。
      final again = loraSlots(runner.workflow!).single;
      runner.edit((wf) => setLora(wf, again.node, again.key, strength: 0.3));
      expect(runner.saveLoraPreset(runner.loraPreset!.name), isNull);
      expect(
        service.config.comfy.loraPresets
            .firstWhere((p) => p.name == '柔和')
            .loras
            .single
            .strength,
        0.3,
      );
      expect(runner.loraPresetChanged, isFalse);
      // 删掉正用着的那一套,就不算用着哪一套了。
      runner.removeLoraPreset('柔和');
      expect(runner.loraPreset, isNull);
      // 设置存盘读回,用着哪一套也留着。
      expect(
        ComfySettings.fromJson(
          service.config.comfy.copyWith(loraPreset: '加一个').toJson(),
        ).loraPreset,
        '加一个',
      );
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

    test('副聊天也能出图:系统提示里有出图的说明,图贴在副聊天那条回复下面', () async {
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
      final seen = <LlmRequest>[];
      final vm = StudioViewModel(
        config: service,
        streamChat: (req) {
          seen.add(req);
          return Stream.value('好的<generate-image>a cat</generate-image>');
        },
      );
      final side = SideChat(vm);
      vm.side = side;
      expect(side.send('跑出来我看看'), isNull);
      for (var i = 0; i < 100 && side.messages.last.images.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(seen.single.messages.first['content'], contains('【出图】'));
      expect(side.messages.last.images, hasLength(1));
      // 主聊天不受影响。
      expect(vm.messages, isEmpty);
    });

    test('手动确认:回复说完不出图,点「出图」才出;成稿卡片上的用那份成稿', () async {
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
            .copyWith(comfy: _at(server.port).copyWith(autoGenerate: false)),
      );
      final vm = StudioViewModel(
        config: service,
        streamChat: (_) =>
            Stream.value('好的<generate-image>a cat</generate-image>'),
      );
      expect(vm.send('出图'), isNull);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(vm.comfy.running, isFalse);
      expect(vm.messages.last.images, isEmpty);

      // 回复下面的「出图」:用标签里写的提示词。
      vm.generateReply(vm.messages.last);
      for (var i = 0; i < 100 && vm.messages.last.images.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(vm.messages.last.images, hasLength(1));
      expect(
        ((queued['prompt'] as Map)['6'] as Map)['inputs']['text'],
        'a cat',
      );

      // 成稿卡片上的「出图」:用那份成稿,出的图接在同一条回复下面。
      polls = 0;
      vm.generateReply(vm.messages.last, prompt: 'a dog');
      for (var i = 0; i < 100 && vm.messages.last.images.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(vm.messages.last.images, hasLength(2));
      expect(
        ((queued['prompt'] as Map)['6'] as Map)['inputs']['text'],
        'a dog',
      );
    });

    test('从 ComfyUI 的历史里去掉几单', () async {
      await ComfyClient('http://127.0.0.1:${server.port}').forget(['p1', 'p2']);
      expect(forgotten, {
        'delete': ['p1', 'p2'],
      });
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

  test('输出文件夹:只留图片,去掉 [output],历史里有的不重复', () {
    final files = parseOutputFiles([
      'b.png [output]',
      'a.webp',
      'note.txt [output]',
      7,
    ]);
    expect([for (final f in files) f['filename']], ['b.png', 'a.webp']);
    expect(parseOutputFiles('nope'), isEmpty);
    final history = <ComfyShot>[
      (
        id: '1',
        file: {'filename': 'b.png', 'subfolder': '', 'type': 'output'},
        prompt: 'cat',
        time: DateTime(2026),
        path: null,
      ),
    ];
    final all = mergeShots(history, shotsOfFiles(files));
    expect(all.length, 2);
    expect(all.first.prompt, 'cat');
    expect(all.last.file['filename'], 'a.webp');
    expect(all.last.id, isEmpty);
  });

  test('硬盘上的输出文件夹:连子文件夹列出图片,配上历史的提示词', () async {
    final dir = Directory.systemTemp.createTempSync('penna-out');
    addTearDown(() => dir.deleteSync(recursive: true));
    final sep = Platform.pathSeparator;
    Directory('${dir.path}${sep}a${sep}b').createSync(recursive: true);
    File('${dir.path}${sep}root.png').writeAsBytesSync([1]);
    File('${dir.path}${sep}a${sep}b${sep}deep.png').writeAsBytesSync([1]);
    File('${dir.path}${sep}a${sep}note.txt').writeAsStringSync('x');
    final disk = await listOutputFolder(dir.path);
    expect(
      {for (final s in disk) shotFolder(s): s.file['filename']},
      {'': 'root.png', 'a/b': 'deep.png'},
    );
    expect(disk.every((s) => s.path != null && s.time != null), isTrue);
    final history = <ComfyShot>[
      (
        id: '9',
        // ComfyUI 的历史里子文件夹可能是反斜杠。
        file: {'filename': 'deep.png', 'subfolder': r'a\b', 'type': 'output'},
        prompt: 'dog',
        time: null,
        path: null,
      ),
    ];
    final all = mergeShots(history, disk);
    expect(all.length, 2);
    final deep = all.firstWhere((s) => s.file['filename'] == 'deep.png');
    expect(deep.prompt, 'dog');
    expect(deep.path, isNotNull);
    expect(deep.time, isNotNull);
    expect(await listOutputFolder('${dir.path}${sep}missing'), isEmpty);
  });

  test('本机 ComfyUI 的输出文件夹照启动参数找', () {
    Map<String, Object?> stats(List<String> argv) => {
      'system': {'argv': argv},
    };
    final sep = Platform.pathSeparator;
    final main = Platform.isWindows
        ? r'D:\ComfyUI\main.py'
        : '/opt/ComfyUI/main.py';
    final base = File(main).parent.path;
    expect(localOutputDir(stats([main])), '$base${sep}output');
    final out = Platform.isWindows ? r'E:\out' : '/data/out';
    expect(localOutputDir(stats([main, '--output-directory', out])), out);
    // 便携版用相对路径启动:找不出来。
    expect(localOutputDir(stats(['ComfyUI/main.py'])), isNull);
    expect(localOutputDir(null), isNull);
  });
}
