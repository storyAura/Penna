import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/draft_block.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/side_chat.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

// 2026-11-23 用户反馈:叫 Agent 删掉系列里的某一页,结果是清空页面。
// 现在写 <draft page="N" delete></draft> 就是删掉那一页。

StudioViewModel _studio(String Function(LlmRequest) reply) {
  final config = tempConfig()
    ..update(
      const AppConfig().putLlm(
        const LlmProfile(id: '1', name: 'A', baseUrl: 'http://x', model: 'm'),
      ),
    );
  return StudioViewModel(
    config: config,
    blocks: const [(text: '【主体】a fox', pinned: false)],
    streamChat: (r) => Stream.value(reply(r)),
  );
}

/// 本系列三页:fox、crow、owl,另有一个系列 city;眼前停在第 1 页。
void _fourPages(StudioViewModel vm) {
  vm.addPage();
  vm.setText(0, '【主体】a crow');
  vm.addPage();
  vm.setText(0, '【主体】an owl');
  vm.addPage(newSeries: true);
  vm.setText(0, '【主体】a city');
  vm.openPage(0);
}

List<String> _texts(StudioViewModel vm) => [
  for (final p in vm.pages) p.blocks.map((b) => b.text).join(),
];

void main() {
  test('拆出删页的标签:不画成稿卡片的内容,半截的不算完成', () {
    final s = splitDrafts('好的。<draft page="2" delete></draft>');
    expect(s.prose, '好的。');
    expect(s.drafts.single.delete, isTrue);
    expect(s.drafts.single.page, '2');
    expect(s.drafts.single.sections, isEmpty);
    expect(
      splitDrafts('<draft page="2">【主体】a</draft>').drafts.single.delete,
      isFalse,
    );
    expect(
      splitDrafts('<draft page="2" delete>').drafts.single.complete,
      isFalse,
    );
  });

  test('Agent 删掉第 2、3 页:页码按删之前数,别的系列不动,一步能撤回', () async {
    final vm = _studio(
      (_) =>
          '删掉了。<draft page="2" delete></draft><draft page="3" delete></draft>',
    );
    _fourPages(vm);

    vm.send('把第 2 页和第 3 页删掉');
    await pumpEventQueue();

    expect(_texts(vm), ['【主体】a fox', '【主体】a city']);
    expect(vm.messages.last.toolSummary, contains('删除了第 2、3 页'));

    vm.undo();
    expect(_texts(vm), ['【主体】a fox', '【主体】a crow', '【主体】an owl', '【主体】a city']);
  });

  test('页码对不上就一页都不删,并说出来', () async {
    final vm = _studio(
      (_) => '<draft page="2" delete></draft><draft page="9" delete></draft>',
    );
    _fourPages(vm);

    vm.send('删掉第 2 页和第 9 页');
    await pumpEventQueue();

    expect(vm.pages, hasLength(4));
    expect(vm.messages.last.toolSummary, contains('没有第 9 页'));
  });

  test('副聊天也能删页', () async {
    final vm = _studio((_) => '<draft page="3" delete></draft>');
    _fourPages(vm);
    final side = SideChat(vm);
    vm.side = side;

    side.send('删掉第 3 页');
    await pumpEventQueue();

    expect(_texts(vm), ['【主体】a fox', '【主体】a crow', '【主体】a city']);
    expect(side.messages.last.toolSummary, contains('删除了第 3 页'));
  });
}
