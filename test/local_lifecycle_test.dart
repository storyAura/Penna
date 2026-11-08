import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/data/services/onnx_model.dart';
import 'package:penna/ui/features/local/local_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final image = Attachment.image(
    name: 'image.png',
    mime: 'image/png',
    bytes: File('assets/avatar.png').readAsBytesSync(),
  );

  test('本地页面状态释放后，LLM 迟到结果不再通知或写回', () async {
    final result = Completer<String>();
    final model = LocalModel(streamChat: (_) => const Stream.empty())
      ..setImage(image);
    const pick = (llm: 'a', model: 'm');
    final running = model.runLlm([pick], (_, _) => result.future);
    final before = model.llmResultOf(pick);
    model.dispose();
    result.complete('late result');
    expect(await running, isNull);
    expect(model.llmResultOf(pick), before);
  });

  test('扫描模型文件夹期间释放状态，完成后不再通知', () async {
    final dir = Directory.systemTemp.createTempSync('penna_scan_dispose');
    addTearDown(() => dir.deleteSync(recursive: true));
    final model = LocalModel(streamChat: (_) => const Stream.empty());
    model.modelFolders = [dir.path];
    final running = model.rescan();
    model.dispose();
    await running;
  });

  test('ONNX 加载期间释放状态，迟到 session 被关闭且不开始推理', () async {
    const channel = MethodChannel('flutter_onnxruntime');
    var sessions = 0, inferences = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'createSession':
              sessions++;
              return {
                'sessionId': 'late',
                'inputNames': ['input'],
                'outputNames': ['output'],
              };
            case 'getInputInfo':
              return [
                {
                  'name': 'input',
                  'shape': [1, 1, 1, 3],
                },
              ];
            case 'getOutputInfo':
              return [
                {
                  'name': 'output',
                  'shape': [1, 1],
                },
              ];
            case 'closeSession':
              sessions--;
              return null;
            case 'createOrtValue':
              return {
                'valueId': 'input-value',
                'dataType': 'float32',
                'shape': [1, 1, 1, 3],
              };
            case 'runInference':
              inferences++;
              return {
                'output': [
                  'output-value',
                  'float32',
                  [1, 1],
                ],
              };
            case 'getOrtValueData':
              return {
                'data': [0.75],
              };
            case 'releaseOrtValue':
              return null;
          }
          throw StateError('Unexpected native call: ${call.method}');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final dir = Directory.systemTemp.createTempSync('penna_load_dispose');
    addTearDown(() => dir.deleteSync(recursive: true));
    final loading = Completer<OnnxModel>(), started = Completer<void>();
    final model = LocalModel(
      dir: dir,
      streamChat: (_) => const Stream.empty(),
      loadOnnx: (_) {
        started.complete();
        return loading.future;
      },
    )..setImage(image);
    for (final file in model.taggerFiles(model.tagger)) {
      File(file.path)
        ..createSync(recursive: true)
        ..writeAsStringSync('name,category\nsmile,0\n');
    }
    final running = model.runTagger();
    await started.future;
    model.dispose();
    loading.complete(await OnnxModel.load('late-model.onnx'));
    expect(await running, isNull);
    expect(sessions, 0);
    expect(inferences, 0);
  });
}
