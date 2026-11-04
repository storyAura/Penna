import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/translate_engines.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

const _text = '【主体】a fox';

StudioViewModel _studio({
  Future<TranslateResult> Function(AppConfig, String)? translate,
  Stream<String> Function(LlmRequest)? streamChat,
  File? saveFile,
}) {
  final config = tempConfig()
    ..update(
      const AppConfig().putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x', model: 'm'),
      ),
    );
  return StudioViewModel(
    config: config,
    blocks: const [(text: _text, pinned: false)],
    streamChat: streamChat ?? (_) => const Stream.empty(),
    translate:
        translate ??
        (_, text) async => TranslateResult(text, 'mymemory', const []),
    saveFile: saveFile,
  );
}

void _openIdenticalPage(StudioViewModel vm) {
  expect(vm.addPage(), isNull);
  vm.setText(0, _text);
}

void main() {
  test('整页翻译返回时已换页，即使正文相同也不串页', () async {
    final result = Completer<TranslateResult>();
    final vm = _studio(translate: (_, _) => result.future);
    addTearDown(vm.dispose);
    final running = vm.translateDraft();
    _openIdenticalPage(vm);
    result.complete(const TranslateResult('狐狸', 'mymemory', []));
    await running;
    expect(vm.translation, isNull);
    expect(vm.isTranslating, isFalse);
  });

  test('段落翻译返回时已换页，同名同文段落不被改写', () async {
    final result = Completer<TranslateResult>();
    final vm = _studio(translate: (_, _) => result.future);
    addTearDown(vm.dispose);
    final running = vm.translateSection(_text, 'a fox');
    _openIdenticalPage(vm);
    result.complete(const TranslateResult('狐狸', 'mymemory', []));
    await running;
    expect(vm.pages.map((p) => p.blocks.map((b) => b.text).join()), [
      _text,
      _text,
    ]);
  });

  test('润色返回时已换页，相同正文不成为另一页的待确认改动', () async {
    final reply = StreamController<String>();
    final vm = _studio(streamChat: (_) => reply.stream);
    addTearDown(vm.dispose);
    final running = vm.polish('');
    _openIdenticalPage(vm);
    reply.add('a red fox');
    await reply.close();
    await running;
    expect(vm.pages.every((p) => p.pending == null), isTrue);
    expect(vm.finalPrompt, 'a fox');
  });

  test('还原数据中靠后的字段损坏时，已有工作台保持完整', () {
    final vm = _studio();
    addTearDown(vm.dispose);
    final before = vm.toJson();
    expect(
      () => vm.restore({
        'pages': [
          {
            'series': 9,
            'blocks': [
              {'text': 'should not replace', 'pinned': false},
            ],
          },
        ],
        'translation': 42,
      }),
      throwsA(isA<TypeError>()),
    );
    expect(vm.toJson(), before);
  });

  test('生成期间关闭工作台也保存已输入消息和已返回的部分', () async {
    final dir = Directory.systemTemp.createTempSync('penna_stream_close');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/workspace.json');
    final reply = StreamController<String>();
    final vm = _studio(streamChat: (_) => reply.stream, saveFile: file);
    expect(vm.send('hello'), isNull);
    reply.add('partial reply');
    await pumpEventQueue();
    expect(vm.isStreaming, isTrue);
    vm.dispose();
    await reply.close();
    expect(file.existsSync(), isTrue);
    final loaded = _studio(saveFile: file);
    addTearDown(loaded.dispose);
    await loaded.load();
    expect(loaded.messages.map((m) => m.text), ['hello', 'partial reply']);
    expect(loaded.body, _text);
  });
}
