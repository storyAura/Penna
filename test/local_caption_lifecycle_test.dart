import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/local/caption_catalog.dart';
import 'package:penna/core/harness/local/florence.dart';
import 'package:penna/ui/features/local/local_model.dart';

class _PausedFlorence {
  _PausedFlorence({required this.duringLoad});

  final bool duringLoad;
  final entered = Completer<void>(), release = Completer<void>();
  final sessions = <String>{}, values = <String>{};
  var sequence = 0;
  bool inferring = false, closedDuringInference = false;

  Future<Object?> call(MethodCall call) async {
    final args = call.arguments as Map;
    switch (call.method) {
      case 'createSession':
        final id = args['modelPath'] as String;
        sessions.add(id);
        if (duringLoad && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return {
          'sessionId': id,
          'inputNames': ['input'],
          'outputNames': ['output'],
        };
      case 'getInputInfo':
        return <Object>[];
      case 'closeSession':
        closedDuringInference |= inferring;
        sessions.remove(args['sessionId']);
        return null;
      case 'createOrtValue':
        final id = 'value-${sequence++}';
        values.add(id);
        return {
          'valueId': id,
          'dataType': args['sourceType'],
          'shape': args['shape'],
        };
      case 'releaseOrtValue':
        values.remove(args['valueId']);
        return null;
      case 'runInference':
        inferring = true;
        if (!duringLoad && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        inferring = false;
        // 在 native 边界结束本次任务，应用层仍走真实错误与资源释放路径。
        throw PlatformException(code: 'FIXTURE_INFERENCE_END');
      default:
        throw StateError('Unexpected native call: ${call.method}');
    }
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_onnxruntime');
  for (final duringLoad in [true, false]) {
    test(
      duringLoad ? 'Florence 加载中换选项仍不能删在用模型' : 'Florence 推理中换选项仍不能删在用模型',
      () async {
        final native = _PausedFlorence(duringLoad: duringLoad);
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          native.call,
        );
        final dir = Directory.systemTemp.createTempSync(
          'penna_florence_remove_',
        );
        final model = LocalModel(
          dir: dir,
          streamChat: (_) => const Stream.empty(),
        );
        addTearDown(() async {
          model.dispose();
          await pumpEventQueue();
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
          dir.deleteSync(recursive: true);
        });
        // 名字有共同前缀也仍是两个目录，删除 base-ft 不能关闭 base 的 session。
        final active = captionModels.firstWhere(
          (m) => m.id == 'florence2-base',
        );
        final other = captionModels.firstWhere(
          (m) => m.id == 'florence2-base-ft',
        );
        final choices = [active, other];
        for (final pick in choices) {
          for (final remote in model.captionFiles(pick)) {
            final file = File(remote.path)..createSync(recursive: true);
            file.writeAsStringSync(
              remote.path.endsWith(florenceTokenizer)
                  ? jsonEncode({
                      'model': {'vocab': <String, int>{}, 'merges': []},
                      'added_tokens': [],
                    })
                  : 'native fixture',
            );
          }
        }
        // 扫描真实目录发现小型 native 夹具，沿用生产模型路径解析；不伪造下载大小。
        model.modelFolders = ['${dir.path}/models'];
        await model.rescan();
        expect(model.useCaption(active), isTrue);
        model.setImage(
          Attachment.image(
            name: 'one.png',
            mime: 'image/png',
            bytes: img.encodePng(img.Image(width: 1, height: 1)),
          ),
        );
        final running = model.runCaption();
        await native.entered.future;
        try {
          expect(model.useCaption(other), isTrue);
          expect(await model.removeCaption(other), isNull);
          expect(
            model.captionFiles(other).every((f) => !File(f.path).existsSync()),
            isTrue,
          );
          expect(await model.removeCaption(active), contains('正在生成'));
          expect(
            model.captionFiles(active).every((f) => File(f.path).existsSync()),
            isTrue,
          );
          expect(native.sessions, hasLength(duringLoad ? 1 : 4));
          expect(native.closedDuringInference, isFalse);
        } finally {
          native.release.complete();
          await running;
        }
        await pumpEventQueue();
        expect(native.sessions, isEmpty);
        expect(native.values, isEmpty);
        expect(await model.removeCaption(active), isNull);
        expect(
          model.captionFiles(active).every((f) => !File(f.path).existsSync()),
          isTrue,
        );
      },
    );
  }
}
