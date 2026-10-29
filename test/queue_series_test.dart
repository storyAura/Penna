import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

StudioViewModel _studio(
  Stream<String> Function(LlmRequest) streamChat, {
  List<Block> blocks = const [],
}) {
  final config = tempConfig();
  config.update(
    const AppConfig().putLlm(
      const LlmProfile(id: '1', name: 'A', baseUrl: 'http://x', model: 'm'),
    ),
  );
  return StudioViewModel(
    config: config,
    blocks: blocks,
    streamChat: streamChat,
  );
}

String _text(DraftPage p) => p.blocks.map((b) => b.text).join();

void main() {
  test('Agent 一条回复新开页、起名、写入:操作记录里是一笔,一次撤干净,还能重做', () async {
    final vm = _studio(
      (_) => Stream.value('<draft page="新" name="兔女郎">\n【主体】a bunny\n</draft>'),
      blocks: const [(text: '【主体】a fox', pinned: false)],
    );
    vm.send('再来一页');
    await pumpEventQueue();

    expect(vm.pages, hasLength(2));
    final record = vm.actions.single;
    expect(record.text, 'Agent 写入 系列 1 · 第 2 页');
    expect(record.details, [
      '新增 系列 1 · 第 2 页',
      '系列 1 · 第 2 页改名:兔女郎',
      startsWith('采纳'),
    ]);

    vm.rollback(0);
    expect(vm.pages.map(_text), ['【主体】a fox']);
    vm.restoreTo(0);
    expect(vm.pages.map(_text), ['【主体】a fox', '【主体】a bunny']);
    expect(vm.pages.last.name, '兔女郎');
  });

  test('换了新主题:另起一个系列,原来的页不动,对话跟着过去', () async {
    final vm = _studio(
      (_) => Stream.value(
        '换成烘焙。\n'
        '<draft page="新系列" name="搅拌" series="烘焙时光">\n【主体】a cake\n</draft>\n'
        '<draft page="2" name="出炉">\n【主体】a pie\n</draft>',
      ),
      blocks: const [(text: '【主体】a fox', pinned: false)],
    );
    final old = vm.series;

    vm.send('不要花园了,换成烘焙');
    await pumpEventQueue();

    expect(vm.pages.map(_text), ['【主体】a fox', '【主体】a cake', '【主体】a pie']);
    // 原来那一页没有被提改动。
    expect(vm.pages.first.pending, isNull);
    expect(vm.pages.first.series, old);
    expect(vm.series, isNot(old));
    expect(vm.seriesName(vm.series), '烘焙时光');
    expect(vm.finalPrompt, 'a cake');
    // 还是这场对话,接着聊的是新系列。
    expect(vm.messages, hasLength(2));
    // 能整个撤回去。
    vm.rollback(
      vm.actions.indexWhere((a) => a.details.any((d) => d.startsWith('新建'))),
    );
    expect(vm.pages.map(_text), ['【主体】a fox']);
  });

  test('当前系列还是空的就直接用它,不另起', () async {
    final vm = _studio(
      (_) => Stream.value(
        '<draft page="新系列" series="烘焙时光">\n【主体】a cake\n</draft>',
      ),
    );

    vm.send('写个烘焙的');
    await pumpEventQueue();

    expect(vm.pages.map(_text), ['【主体】a cake']);
    expect(vm.seriesName(vm.series), '烘焙时光');
  });

  test('生成时发的话排队:说完自动发下一条,也能立刻发、能撤掉', () async {
    final replies = <StreamController<String>>[];
    final vm = _studio((_) {
      replies.add(StreamController<String>());
      return replies.last.stream;
    });

    expect(vm.send('一'), isNull);
    expect(vm.send('二'), isNull);
    expect(vm.send('三'), isNull);
    expect(vm.send('四'), isNull);
    expect(vm.outbox.map((m) => m.text), ['二', '三', '四']);
    expect(replies, hasLength(1));

    vm.unqueue(1);
    expect(vm.outbox.map((m) => m.text), ['二', '四']);

    // 第一条说完:自动发「二」。
    replies[0].add('甲');
    await replies[0].close();
    await pumpEventQueue();
    expect(vm.messages.map((m) => m.text), ['一', '甲', '二', '']);
    expect(vm.outbox.map((m) => m.text), ['四']);
    expect(vm.isStreaming, isTrue);

    // 不等了:打断正在说的,马上发「四」。
    expect(vm.sendQueuedNow(0), isNull);
    expect(vm.outbox, isEmpty);
    expect(vm.messages[3].stopped, isTrue);
    expect(vm.messages[4].text, '四');
    expect(replies, hasLength(3));
    vm.stop();
  });
}
