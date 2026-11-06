import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comfyui.dart';
import 'package:penna/data/services/comfy_images.dart';

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

    setUp(() async {
      polls = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final res = req.response;
        final path = req.uri.path;
        if (path == '/object_info/CheckpointLoaderSimple') {
          res.write(
            jsonEncode({
              'CheckpointLoaderSimple': {
                'input': {
                  'required': {
                    'ckpt_name': [
                      'COMBO',
                      {
                        'options': ['m.safetensors'],
                      },
                    ],
                  },
                },
              },
            }),
          );
        } else if (path == '/prompt') {
          queued =
              jsonDecode(await utf8.decoder.bind(req).join())
                  as Map<String, Object?>;
          res.write(jsonEncode({'prompt_id': 'p1'}));
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

    tearDown(() => server.close(force: true));

    test('没导入工作流时用内置文生图和第一个模型,出的图下载回来', () async {
      final client = ComfyClient('http://127.0.0.1:${server.port}/')
        ..poll = Duration.zero;
      final images = await client.run('', 'a cat');
      expect(images.single.name, 'Penna_0001.png');
      expect(images.single.bytes, [1, 2, 3]);
      final prompt = queued['prompt'] as Map;
      expect((prompt['6'] as Map)['inputs']['text'], 'a cat');
      expect((prompt['4'] as Map)['inputs']['ckpt_name'], 'm.safetensors');
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
