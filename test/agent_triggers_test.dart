import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

const _llm = LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm');

StudioViewModel _vm(
  Stream<String> Function(LlmRequest req) reply, {
  LayoutBoard? layout,
}) {
  final service = tempConfig();
  service.update(service.config.putLlm(_llm));
  return StudioViewModel(
    config: service,
    layout: layout,
    layoutOnly: layout != null,
    streamChat: reply,
  );
}

void main() {
  test('思考拆进 thinking:里面引用的 <draft> 不当真,系统提示要它写 <think>', () async {
    final systems = <String>[];
    final vm = _vm((req) {
      systems.add(req.messages.first['content']!);
      return Stream.value(
        '思考过程:\n1. 要不要写 `<draft>`?要。\n\n好的,写好了。\n\n'
        '<draft>【主体】a cat</draft>',
      );
    });
    vm.send('画一只猫');
    await pumpEventQueue();
    final last = vm.messages.last;
    expect(last.thinking, contains('要不要写'));
    expect(last.text, startsWith('好的,写好了。'));
    expect(vm.body, contains('a cat'));
    expect(systems.single, contains('<think></think>'));
  });

  test('写到上限:程序自己接着写,写的接在后面,不等用户点', () async {
    var calls = 0;
    final vm = _vm((req) {
      calls++;
      if (calls == 1) {
        req.onCut?.call(LlmCut.length);
        return Stream.value('<draft>【主体】a ');
      }
      return Stream.value('cat</draft>');
    });
    vm.send('画一只猫');
    await pumpEventQueue();
    expect(calls, 2);
    expect(vm.messages.last.text, '<draft>【主体】a cat</draft>');
    expect(vm.messages.last.cut, isNull);
    // 接齐了才交:成稿只放一次,是完整的那份。
    expect(vm.body, contains('a cat'));
  });

  test('一直被截断:最多自己接两次,不打转', () async {
    var calls = 0;
    final vm = _vm((req) {
      calls++;
      req.onCut?.call(LlmCut.length);
      return Stream.value('半截');
    });
    vm.send('写长点');
    await pumpEventQueue();
    expect(calls, 3);
    expect(vm.isStreaming, isFalse);
  });

  test('区域控制收到转来的任务却提问了:自己叫醒它直接排', () async {
    var calls = 0;
    final board = LayoutBoard()..setSize(100, 200);
    final vm = _vm((req) {
      calls++;
      return Stream.value(
        calls == 1
            ? '先问一下:\n<options>\n竖构图\n横构图\n</options>'
            : '<layout>{"width": 100, "height": 200, '
                  '"summary": {"caption": "a cat"}, "items": [{"name": "猫", '
                  '"caption": "a cat", "bbox": [10, 10, 90, 190]}], '
                  '"bbox_coord_space": "abs", "bbox_format": "xyxy"}</layout>',
      );
    }, layout: board);
    await vm.sendAndWait('$handoffMark排一只猫');
    expect(calls, 2);
    expect(board.layout.boxes, hasLength(1));
    expect(vm.messages.where((m) => m.tool).single.text, contains('没交出布局'));
  });
}
