import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/local/florence.dart';
import 'package:penna/data/services/florence_engine.dart';
import 'package:penna/data/services/onnx_model.dart';

/// 只模拟不可控的 native 边界;模型包装、张量创建和错误路径仍运行真实实现。
class _NativeOnnx {
  final sessions = <String>{};
  final values = <String, ({String type, List<int> shape, Object data})>{};
  var creates = 0, sequence = 0, decoderSteps = 0;
  int? failCreate;
  bool failMetadata = false, failDecoder = false, failFloatRead = false;

  Map<String, Object> _value(String type, List<int> shape, Object data) {
    final id = 'value-${sequence++}';
    values[id] = (type: type, shape: shape, data: data);
    return {'valueId': id, 'dataType': type, 'shape': shape};
  }

  Future<Object?> call(MethodCall call) async {
    final args = call.arguments as Map;
    switch (call.method) {
      case 'createSession':
        if (++creates == failCreate) throw PlatformException(code: 'OOM');
        final id = args['modelPath'] as String;
        sessions.add(id);
        return {
          'sessionId': id,
          'inputNames': ['input'],
          'outputNames': ['output'],
        };
      case 'closeSession':
        expect(sessions.remove(args['sessionId']), isTrue);
        return null;
      case 'getOutputInfo':
        if (failMetadata) throw PlatformException(code: 'METADATA');
        return [
          {
            'name': 'output',
            'shape': [1, 3],
          },
        ];
      case 'getInputInfo':
        if ((args['sessionId'] as String).endsWith(florenceDecoder)) {
          return [
            {
              'name': 'past_key_values.decoder.key',
              'shape': [1, 1, 0, 1],
            },
          ];
        }
        return <Object>[];
      case 'createOrtValue':
        return _value(
          args['sourceType'] as String,
          List<int>.from(args['shape'] as List),
          args['data'] as Object,
        );
      case 'releaseOrtValue':
        expect(values.remove(args['valueId']), isNotNull, reason: '同一张量只释放一次');
        return null;
      case 'getOrtValueData':
        if (failFloatRead) throw PlatformException(code: 'READ');
        return {'data': values[args['valueId']]!.data};
      case 'convertOrtValue':
        final value = values[args['valueId']]!;
        return _value(args['targetType'] as String, value.shape, value.data);
      case 'runInference':
        final id = args['sessionId'] as String;
        for (final input in (args['inputs'] as Map).values) {
          expect(
            values.containsKey((input as Map)['valueId']),
            isTrue,
            reason: '推理使用的缓存和输入必须仍然有效',
          );
        }
        if (failDecoder && id.endsWith(florenceDecoder)) {
          throw PlatformException(code: 'OOM');
        }
        if (id.endsWith(florenceDecoder)) {
          final logits = _value('float32', [
            1,
            1,
            4,
          ], ++decoderSteps == 2 ? [0.0, 0.0, 0.0, 1.0] : [0.0, 0.0, 1.0, 0.0]);
          final cache = _value('float32', [1, 1, 1, 1], [0.0]);
          return {
            'logits': [logits['valueId'], logits['dataType'], logits['shape']],
            'present.decoder.key': [
              cache['valueId'],
              cache['dataType'],
              cache['shape'],
            ],
          };
        }
        final type = failFloatRead && id.endsWith(florenceVision)
            ? 'float16'
            : 'float32';
        final value = _value(type, [1, 1, 1], [0.0]);
        return {
          'output': [value['valueId'], value['dataType'], value['shape']],
        };
      default:
        throw StateError('未预期的 native 方法 ${call.method}');
    }
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_onnxruntime');
  late _NativeOnnx native;
  late Directory dir;
  setUp(() {
    native = _NativeOnnx();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      native.call,
    );
    dir = Directory.systemTemp.createTempSync('penna_onnx_lifecycle');
    File('${dir.path}/$florenceTokenizer').writeAsStringSync(
      '{"model":{"vocab":{"t":3},"merges":[]},"added_tokens":[]}',
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  test('打标模型读取 metadata 失败时释放已创建的 session', () async {
    native.failMetadata = true;
    await expectLater(
      OnnxModel.load('model.onnx'),
      throwsA(isA<OnnxException>()),
    );
    expect(native.sessions, isEmpty);
  });

  test('Florence 后续模型加载失败时释放此前创建的 session', () async {
    native.failCreate = 2;
    await expectLater(
      FlorenceEngine.load(dir.path),
      throwsA(isA<FlorenceException>()),
    );
    expect(native.sessions, isEmpty);
  });

  test('Florence decoder 失败时释放本步临时张量和已有中间结果', () async {
    native.failDecoder = true;
    final engine = await FlorenceEngine.load(dir.path);
    try {
      await expectLater(
        engine.caption(
          Float32List(3 * florenceImageSize * florenceImageSize),
          '<CAPTION>',
        ),
        throwsA(isA<FlorenceException>()),
      );
      expect(native.values, isEmpty);
    } finally {
      await engine.close();
    }
    expect(native.sessions, isEmpty);
  });

  test('Florence 成功解码时跨步缓存保持有效,结束后释放全部张量', () async {
    final engine = await FlorenceEngine.load(dir.path);
    try {
      expect(
        await engine.caption(
          Float32List(3 * florenceImageSize * florenceImageSize),
          '<CAPTION>',
        ),
        't',
      );
      expect(native.decoderSteps, 3);
      expect(native.values, isEmpty);
    } finally {
      await engine.close();
    }
    expect(native.sessions, isEmpty);
  });

  test('Florence FP16转为FP32后读取失败时也释放转换张量', () async {
    native.failFloatRead = true;
    final engine = await FlorenceEngine.load(dir.path);
    try {
      await expectLater(
        engine.caption(
          Float32List(3 * florenceImageSize * florenceImageSize),
          '<CAPTION>',
        ),
        throwsA(isA<FlorenceException>()),
      );
      expect(native.values, isEmpty);
    } finally {
      await engine.close();
    }
  });
}
