import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/draft_block.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/markdown_text.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

/// 一个接好了假模型的工作台:[reply] 是模型每次的回复,[seen] 收着发出去的请求。
StudioViewModel _studio({
  String Function(LlmRequest)? reply,
  List<LlmRequest>? seen,
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
    streamChat: (r) {
      seen?.add(r);
      return Stream.value(reply?.call(r) ?? '好');
    },
  );
}

Finder _tab(int n) => _inStudio(find.byTooltip('第 $n 页 · 双击改名 · 右键更多'));

/// 区域控制页也有一排页签:找工作台的要限定在它里面。
Finder _inStudio(Finder f) =>
    find.descendant(of: find.byType(StudioPage), matching: f);

void main() {
  group('成稿标签', () {
    test('一条回复里的几份成稿都拆出来,各带各的页', () {
      final (:prose, :drafts) = splitDrafts(
        '分成两镜。\n'
        '<draft page="新">\n【主体】a fox\n</draft>\n'
        '<draft page="2">\n【主体】a crow\n</draft>\n'
        '完成。',
      );

      expect(prose, '分成两镜。\n\n完成。');
      expect(drafts.map((d) => d.page), ['新', '2']);
      expect(drafts.map((d) => d.text), ['【主体】a fox', '【主体】a crow']);
      expect(drafts.every((d) => d.complete), isTrue);
    });

    test('不带页码的还是原来的写法;半截的开始标签不显示', () {
      expect(splitDrafts('<draft>a fox</draft>').drafts.single.page, isNull);
      expect(splitDrafts('好的。<draft pa').prose, '好的。');
      expect(
        splitDrafts('好的。<draft page="新">a f').drafts.single.complete,
        isFalse,
      );
    });

    test('话里提到这个标签时,不会被当成成稿的开头', () {
      final (:prose, :drafts) = splitDrafts(
        '我放进 <draft> 里。\n<draft>a fox</draft>',
      );

      expect(drafts.single.text, 'a fox');
      expect(prose, contains('我放进'));
    });

    test('<draft replace> 是整篇重写;名字里的 replace 不算', () {
      final d = splitDrafts('<draft replace name="浴室">【主体】a</draft>').drafts;
      expect((d.single.replace, d.single.name), (true, '浴室'));
      expect(
        splitDrafts('<draft name="replace">【主体】a</draft>')
            .drafts
            .single
            .replace,
        isFalse,
      );
    });

    test('整篇重写换掉没写到的旧段;不带 replace 时旧段留着', () async {
      const old = [(text: '【主体】two girls\n【希罗】hiro\n【艾玛】emma', pinned: false)];
      const draft = '【主体】a bathroom\n【维尔汀】vertin';

      final merged = _studio(
        reply: (_) => '<draft>$draft</draft>',
        blocks: old,
      );
      merged.send('换成维尔汀');
      await pumpEventQueue();
      merged.acceptDiff();
      expect(merged.body, contains('【希罗】'));

      final replaced = _studio(
        reply: (_) => '<draft replace>$draft</draft>',
        blocks: old,
      );
      replaced.send('换成维尔汀');
      await pumpEventQueue();
      replaced.acceptDiff();
      expect(replaced.body, '【主体】a bathroom\n【维尔汀】vertin');
    });
  });

  group('分页', () {
    test('新开的页是空的,各页的成稿互不相干', () {
      final vm = _studio(blocks: const [(text: 'a fox', pinned: false)]);

      expect(vm.addPage(), isNull);
      expect(vm.pageIndex, 1);
      expect(vm.body, isEmpty);

      vm.setText(0, 'a crow');
      expect(vm.finalPrompt, 'a crow');

      vm.openPage(0);
      expect(vm.finalPrompt, 'a fox');
      expect(vm.pages.map((p) => p.series), [0, 0]);
    });

    test('每个系列的页数不限,系列最多 20 个;只剩一页时不能删', () {
      final vm = _studio();
      for (var i = 0; i < 24; i++) {
        expect(vm.addPage(), isNull);
      }
      expect(vm.pages, hasLength(25));
      for (var i = 1; i < StudioPages.maxSeries; i++) {
        expect(vm.addPage(newSeries: true), isNull);
      }
      expect(vm.seriesCount, StudioPages.maxSeries);
      expect(vm.addPage(newSeries: true), StudioPages.fullMessage);
      // 满了也还能往已有的系列里加页。
      expect(vm.addPage(), isNull);

      final one = _studio();
      expect(one.removePage(0), '只剩这一页了');
    });

    test('待确认的改动跟着它那一页走', () {
      final vm = _studio(blocks: const [(text: 'a fox', pinned: false)]);
      vm.proposeDraft('a red fox');
      vm.addPage();

      expect(vm.pending, isNull);
      expect(vm.pages.first.pending?.added, 'a red fox');

      vm.openPage(0);
      vm.acceptDiff();
      expect(vm.finalPrompt, 'a red fox');
    });

    test('删掉一页后,留下的页还是原来的内容', () {
      final vm = _studio(blocks: const [(text: 'a fox', pinned: false)]);
      vm.addPage();
      vm.setText(0, 'a crow');
      vm.addPage();
      vm.setText(0, 'an owl');

      expect(vm.removePage(1), isNull);

      expect(vm.pageIndex, 1);
      expect(vm.finalPrompt, 'an owl');
      vm.openPage(0);
      expect(vm.finalPrompt, 'a fox');
    });
  });

  group('系列', () {
    test('同系列的其他页会给 Agent 看,别的系列的不会', () async {
      final seen = <LlmRequest>[];
      final vm = _studio(
        seen: seen,
        blocks: const [(text: 'a fox in snow', pinned: false)],
      );
      vm.addPage();
      vm.setText(0, 'a fox at night');
      vm.addPage(newSeries: true);
      vm.setText(0, 'a city street');

      vm.send('看看');
      await pumpEventQueue();
      final other = seen.last.messages.first['content']!;
      expect(other, contains('a city street'));
      expect(other, isNot(contains('a fox')));

      vm.openPage(1);
      vm.send('看看');
      await pumpEventQueue();
      final mine = seen.last.messages.first['content']!;
      expect(mine, contains('第 1 页'));
      expect(mine, contains('a fox in snow'));
      expect(mine, isNot(contains('a city street')));
    });

    test('每个系列有自己的对话;删掉整个系列,它的对话收进历史', () async {
      final vm = _studio();
      vm.send('第一个系列');
      await pumpEventQueue();
      expect(vm.messages, hasLength(2));

      vm.addPage(newSeries: true);
      expect(vm.messages, isEmpty);
      vm.send('第二个系列');
      await pumpEventQueue();

      vm.openPage(0);
      expect(vm.messages.first.text, '第一个系列');
      // 发给模型的上文里没有另一个系列说过的话。
      expect(vm.messages.map((m) => m.text), isNot(contains('第二个系列')));

      expect(vm.removePage(1), isNull);
      expect(vm.pastChats.single.messages.first.text, '第二个系列');
    });

    test('生成中不能换页', () {
      final vm = StudioViewModel(
        config: _studio().config,
        streamChat: (_) => const Stream.empty(),
      )..addPage();
      vm.send('你好');

      expect(vm.isStreaming, isTrue);
      expect(vm.openPage(0), isNotNull);
      expect(vm.addPage(), isNotNull);
      expect(vm.removePage(0), isNotNull);
      vm.stop();
    });
  });

  group('Agent 一次写好几页', () {
    const storyboard =
        '三镜。\n'
        '<draft page="新">\n【主体】a fox\n</draft>\n'
        '<draft page="新">\n【主体】a crow\n</draft>\n'
        '<draft page="新">\n【主体】an owl\n</draft>';

    test('空白的当前页先用上,其余的各开一页,人还留在原来那页', () async {
      final vm = _studio(reply: (_) => storyboard);

      vm.send('做三个分镜');
      await pumpEventQueue();

      expect(vm.pageIndex, 0);
      expect(vm.pages, hasLength(3));
      expect(vm.pages.map((p) => p.blocks.map((b) => b.text).join()), [
        '【主体】a fox',
        '【主体】a crow',
        '【主体】an owl',
      ]);
      expect(vm.pages.every((p) => p.series == vm.series), isTrue);
      expect(vm.finalPrompt, 'a fox');
    });

    test('当前页有内容、新写的一页开在后面时,写完换到那一页', () async {
      final vm = _studio(
        blocks: const [(text: '【主体】a fox', pinned: false)],
        reply: (_) => '<draft page="新" name="若叶睦">\n【主体】a girl\n</draft>',
      );

      vm.send('换成若叶睦');
      await pumpEventQueue();

      expect(vm.pages, hasLength(2));
      expect(vm.pageIndex, 1);
      expect(vm.finalPrompt, 'a girl');
      expect(vm.pageName, '若叶睦');
    });

    test('页码是系列里的第几页:有内容的页只提改动,没有的页自动开,碰不到别的系列', () async {
      final vm = _studio(
        blocks: const [(text: '【主体】a fox', pinned: false)],
        reply: (_) =>
            '<draft page="2">\n【主体】a wolf\n</draft>\n'
            '<draft page="3">\n【主体】an owl\n</draft>',
      );
      vm.addPage();
      vm.setText(0, '【主体】a crow');
      vm.addPage(newSeries: true);
      vm.setText(0, '【主体】a city');
      vm.openPage(0);

      vm.send('把第 2 页换成狼,再加一页猫头鹰');
      await pumpEventQueue();

      expect(vm.pages.map((p) => p.series), [0, 0, 0, 1]);
      expect(vm.pages[1].pending?.added, '【主体】a wolf');
      // 这个系列本来只有两页,第 3 页是新开的,接在本系列后面。
      expect(vm.pages[2].blocks.single.text, '【主体】an owl');
      expect(vm.pages[3].blocks.single.text, '【主体】a city');
      expect(vm.pages[3].pending, isNull);
      expect(vm.pending, isNull);
    });

    test('第二个系列里说的第 1 页,是它自己的第 1 页', () async {
      final vm = _studio(
        blocks: const [(text: '【主体】a fox', pinned: false)],
        reply: (_) => '<draft page="1">\n【主体】a town\n</draft>',
      );
      vm.addPage(newSeries: true);
      vm.setText(0, '【主体】a city');

      vm.send('改成小镇');
      await pumpEventQueue();

      expect(vm.pages[0].pending, isNull);
      expect(vm.pending?.added, '【主体】a town');
    });

    test('一组页顺手起了名字;用户起过的不改', () async {
      final vm = _studio(
        reply: (_) =>
            '<draft page="1" name="玩耍" series="午后客厅">\n【主体】a fox\n</draft>\n'
            '<draft page="2" name="犯困">\n【主体】a crow\n</draft>',
      );

      vm.send('做两个分镜');
      await pumpEventQueue();

      expect(vm.seriesName(vm.series), '午后客厅');
      expect(vm.pages.map((p) => p.name), ['玩耍', '犯困']);

      vm.renameSeries(vm.series, '我的系列');
      vm.placeDraft('【主体】x', page: '1', seriesTitle: '别的名字', name: '别的');
      expect(vm.seriesName(vm.series), '我的系列');
      expect(vm.pages.first.name, '玩耍');
    });

    test('系列满了时 Agent 要另起系列:放不上、亮出提醒,删掉一个系列提醒就消失', () {
      final vm = _studio();
      for (var i = 1; i < StudioPages.maxSeries; i++) {
        vm.addPage(newSeries: true);
      }
      vm.setText(0, 'a fox');
      expect(vm.seriesAlert, isNull);
      expect(vm.placeDraft('x', page: '新系列'), StudioPages.fullMessage);
      expect(vm.seriesAlert, StudioPages.fullMessage);
      expect(vm.removeSeries(vm.pages.first.series), isNull);
      expect(vm.seriesAlert, isNull);
    });
  });

  group('存盘', () {
    test('各页、当前页、别的系列的对话都存得回来', () async {
      final vm = _studio(blocks: const [(text: 'a fox', pinned: true)]);
      vm.addPage(newSeries: true);
      vm.setText(0, 'a city');
      vm.send('第二个系列');
      await pumpEventQueue();
      vm.openPage(0);

      final loaded = _studio()
        ..restore(jsonDecode(jsonEncode(vm.toJson())) as Map<String, dynamic>);

      expect(loaded.pageIndex, 0);
      expect(loaded.blocks, const [(text: 'a fox', pinned: true)]);
      expect(loaded.pages.map((p) => p.series), [0, 1]);
      expect(loaded.messages, isEmpty);
      loaded.openPage(1);
      expect(loaded.finalPrompt, 'a city');
      expect(loaded.messages.first.text, '第二个系列');
    });

    test('旧版只有一页的存档照样读得进来', () {
      final vm = _studio()
        ..restore({
          'blocks': [
            {'text': 'a fox', 'pinned': false},
          ],
        });

      expect(vm.pages, hasLength(1));
      expect(vm.finalPrompt, 'a fox');
    });
  });

  testWidgets('保存系列:已经存过的页不再存,只存新的', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = _studio(blocks: const [(text: 'a fox', pinned: false)]);
    vm.addPage();
    vm.setText(0, 'a crow');
    final archive = ArchiveStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(
          vm: vm,
          config: vm.config,
          skills: tempSkills(),
          archive: archive,
        ),
      ),
    );

    await tester.tap(find.text('保存系列'));
    await tester.pump();
    expect(archive.entries, hasLength(2));

    await tester.tap(find.text('保存系列'));
    await tester.pump();
    expect(archive.entries, hasLength(2));
    expect(find.text('这个系列的页都已经存过了'), findsOneWidget);

    vm.addPage();
    vm.setText(0, 'an owl');
    await tester.pump();
    await tester.tap(find.text('保存系列'));
    await tester.pump();
    expect(archive.entries.map((e) => e.text), ['an owl', 'a fox', 'a crow']);
  });

  testWidgets('页签:加一页、另起系列、点页码换页', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = _studio(blocks: const [(text: 'a fox', pinned: false)]);
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );

    expect(_inStudio(find.text('系列 1')), findsOneWidget);
    // 页签的宽度跟着字走,不会被撑开。
    expect(tester.getSize(_tab(1)).width, lessThan(40));
    // 只有一页时没有「保存系列」。
    expect(find.text('保存系列'), findsNothing);

    await tester.tap(_inStudio(find.byTooltip('在这个系列里加一页')));
    await tester.pumpAndSettle();
    expect(vm.pageIndex, 1);
    expect(_tab(2), findsOneWidget);
    expect(find.text('保存系列'), findsOneWidget);

    await tester.tap(_inStudio(find.text('新系列')));
    await tester.pumpAndSettle();
    expect(vm.pages.map((p) => p.series), [0, 0, 1]);
    expect(_inStudio(find.text('系列 2')), findsOneWidget);
    // 每个系列的页码都从 1 数。
    expect(_tab(1), findsNWidgets(2));

    await tester.tap(_tab(1).first);
    await tester.pumpAndSettle();
    expect(vm.pageIndex, 0);
    expect(find.text('a fox'), findsWidgets);

    // 右键页签:空白页直接删,不用确认。
    await tester.tap(_tab(1).last, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除这一页'));
    await tester.pumpAndSettle();
    expect(vm.pages, hasLength(2));
    expect(_inStudio(find.text('系列 2')), findsNothing);

    // 右键系列名:改名。
    await tester.tap(_inStudio(find.text('系列 1')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('改名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '狐狸');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(_inStudio(find.text('狐狸')), findsOneWidget);

    // 双击页签、系列名:直接改名。
    await tester.tap(_tab(1));
    await tester.tap(_tab(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '远景');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(vm.pages.first.name, '远景');
    // 系列名用的是 Flutter 自带的双击:两下之间至少隔 40 毫秒才算。
    await tester.tap(_inStudio(find.text('狐狸')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(_inStudio(find.text('狐狸')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '狐');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(vm.seriesName(0), '狐');
  });

  group('整理页', () {
    StudioViewModel three() {
      final vm = _studio(blocks: const [(text: 'A', pinned: false)]);
      vm.addPage();
      vm.setText(0, 'B');
      vm.addPage();
      vm.setText(0, 'C');
      return vm;
    }

    List<String> texts(StudioViewModel vm) => [
      for (final p in vm.pages) p.blocks.map((b) => b.text).join(),
    ];

    test('在系列里拖着调顺序,眼前还是原来那页', () {
      final vm = three();
      expect(vm.pageIndex, 2);

      expect(vm.movePage(2, 0), isNull);
      expect(texts(vm), ['C', 'A', 'B']);
      expect(vm.finalPrompt, 'C');

      expect(vm.movePage(1, 2), isNull);
      expect(texts(vm), ['C', 'B', 'A']);
      expect(vm.finalPrompt, 'C');

      vm.addPage(newSeries: true);
      expect(vm.movePage(0, 3), '只能在同一个系列里调顺序');
    });

    test('删掉整个系列,别的系列不受影响', () {
      final vm = three();
      vm.addPage(newSeries: true);
      vm.setText(0, 'D');
      vm.renameSeries(vm.series, '城市');
      vm.openPage(0);

      expect(vm.removeSeries(vm.pages.last.series), isNull);
      expect(texts(vm), ['A', 'B', 'C']);
      expect(vm.finalPrompt, 'A');

      // 删的是眼前这个系列:换到留下来的那个上。
      vm.addPage(newSeries: true);
      vm.setText(0, 'E');
      vm.openPage(1);
      expect(vm.removeSeries(vm.series), isNull);
      expect(texts(vm), ['E']);
      expect(vm.finalPrompt, 'E');
      expect(vm.seriesName(vm.series), '系列 1');
    });

    test('最后一个系列也能删:留一张空白页,对话收进历史', () async {
      final vm = three();
      vm.renameSeries(vm.series, '动物');
      vm.send('聊过的话');
      await pumpEventQueue();

      expect(vm.removeSeries(vm.series), isNull);

      expect(texts(vm), ['']);
      expect(vm.finalPrompt, isEmpty);
      expect(vm.pending, isNull);
      expect(vm.messages, isEmpty);
      expect(vm.seriesName(vm.series), '系列 1');
      expect(vm.pastChats.single.messages.first.text, '聊过的话');
    });

    test('操作记录:新的在前,说得出是哪个系列的第几页', () {
      final vm = three();
      vm.renameSeries(vm.series, '动物');
      vm.movePage(2, 0);
      vm.detachPage(1);
      vm.clearDraft();

      expect(vm.actions.map((a) => a.text).take(4), [
        '清空 动物 · 第 1 页',
        '动物 · 第 2 页脱离系列',
        '拖动 动物:第 3 页 → 第 1 页',
        '系列改名:系列 1 → 动物',
      ]);
      // 名字没变就不记。
      final before = vm.actions.length;
      vm.renameSeries(vm.series, '动物');
      expect(vm.actions, hasLength(before));
    });

    test('对话标签:关掉只是不占标签,历史里还在;从历史打开又回来;在历史里删才是真删', () async {
      final vm = three();
      vm.send('第一场');
      await pumpEventQueue();
      final first = vm.chatId;
      vm.newChat();
      vm.send('第二场');
      await pumpEventQueue();
      List<String> tabs() => [
        for (final c in vm.chatTabs) chatTitle(c.messages),
      ];
      expect(tabs(), ['第一场', '第二场']);

      // 关掉不在眼前的那个。
      expect(vm.closeChat(first), isTrue);
      expect(tabs(), ['第二场']);
      expect(vm.pastChats.single.id, first);

      // 关掉眼前这个:没有别的标签了,换成一场新的;两场都还在历史里。
      expect(vm.closeChat(vm.chatId), isTrue);
      expect(tabs(), ['新对话']);
      expect(vm.pastChats, hasLength(2));

      // 关掉的标签存盘后还是关着的。
      final loaded = _studio()
        ..restore(jsonDecode(jsonEncode(vm.toJson())) as Map<String, dynamic>);
      expect(loaded.chatTabs, hasLength(1));
      expect(loaded.pastChats, hasLength(2));

      vm.openChat(first);
      expect(tabs(), ['第一场']);

      vm.deleteChat(vm.pastChats.single.id);
      expect(vm.pastChats, isEmpty);
    });

    test('对话标签:删掉眼前这场,换到最近的另一场;都删光就是一场新的', () async {
      final vm = three();
      vm.send('第一场');
      await pumpEventQueue();
      vm.newChat();
      vm.send('第二场');
      await pumpEventQueue();
      final second = vm.chatId;

      expect(vm.deleteChat(second), isTrue);
      expect(vm.messages.first.text, '第一场');
      expect(vm.pastChats, isEmpty);

      expect(vm.deleteChat(vm.chatId), isTrue);
      expect(vm.messages, isEmpty);
      expect(chatTitle(vm.messages), '新对话');
    });

    test('脱离系列:这一页自成一个新系列,对话从空白开始', () async {
      final vm = three();
      vm.send('聊过的话');
      await pumpEventQueue();

      // 脱离的不是眼前这页:人留在原地,对话也还在。
      expect(vm.detachPage(0), isNull);
      expect(texts(vm), ['B', 'C', 'A']);
      expect(vm.pages.map((p) => p.series), [0, 0, 1]);
      expect(vm.finalPrompt, 'C');
      expect(vm.messages, isNotEmpty);

      // 脱离的就是眼前这页:人跟过去,那边还没聊过。
      expect(vm.detachPage(vm.pageIndex), isNull);
      expect(texts(vm), ['B', 'A', 'C']);
      expect(vm.pages.map((p) => p.series), [0, 1, 2]);
      expect(vm.finalPrompt, 'C');
      expect(vm.messages, isEmpty);

      expect(vm.detachPage(0), '这一页已经自成一个系列了');
      vm.openPage(0);
      expect(vm.messages.first.text, '聊过的话');
    });

    test('存整个系列:一页一条,空白页不算,名字存盘后还在', () {
      final vm = three();
      vm.renamePage(1, '乌鸦');
      vm.renameSeries(vm.series, '动物');
      vm.addPage();

      expect(vm.seriesPrompts, [
        (title: '第 1 页', text: 'A'),
        (title: '第 2 页 · 乌鸦', text: 'B'),
        (title: '第 3 页', text: 'C'),
      ]);
      expect(vm.pageIndex, 3);

      final loaded = _studio()
        ..restore(jsonDecode(jsonEncode(vm.toJson())) as Map<String, dynamic>);
      expect(loaded.seriesName(loaded.series), '动物');
      expect(loaded.pages[1].name, '乌鸦');
    });
  });

  group('回复里的小部件', () {
    test('选项拆成一个个按钮的字,写完了才算', () {
      final (:prose, :options, :multi, sections: _) = splitOptions(
        '方案如上。\n<options>\n- 确认,开始写\n2. 我要改一下\n</options>',
      );

      expect(multi, isFalse);
      // 多选的:标签上多一个 multi。
      final pick = splitOptions('转哪几段?\n<options multi>\n主体\n服装\n</options>');
      expect((pick.prose, pick.multi), ('转哪几段?', true));
      expect(pick.options, ['主体', '服装']);
      expect(splitOptions('转哪几段?<options mu').prose, '转哪几段?');
      expect(prose, '方案如上。');
      expect(options, ['确认,开始写', '我要改一下']);
      expect(splitOptions('方案如上。\n<options>\n确认').options, isEmpty);
      expect(splitOptions('方案如上。<opt').prose, '方案如上。');

      // 挑成稿里的段:标签里可以不写,界面自己读出各段。
      final parts = splitOptions('要转哪几段?\n<options sections></options>');
      expect(
        (parts.prose, parts.multi, parts.sections),
        ('要转哪几段?', true, true),
      );
      expect(parts.options, isEmpty);
      expect(splitOptions('要转哪几段?<options sec').prose, '要转哪几段?');
      expect(pick.sections, isFalse);
    });

    test('Markdown 的记号不原样显示', () {
      final plain = markdownSpan(
        '### 镜头表\n- **第 1 镜**:玩耍\n---\n用 `1girl`',
        const TextStyle(fontSize: 14),
      ).toPlainText();

      expect(plain, contains('镜头表'));
      expect(plain, contains('第 1 镜:玩耍'));
      expect(plain, contains('1girl'));
      expect(plain, isNot(contains('#')));
      expect(plain, isNot(contains('**')));
      expect(plain, isNot(contains('`')));
      expect(plain, isNot(contains('---')));
    });
  });
}
