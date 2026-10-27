import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/draft_block.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/body_card.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

const _llm = LlmProfile(
  id: 'a',
  name: '测试模型',
  baseUrl: 'http://localhost/v1',
  model: 'm',
);

StudioViewModel _studio({
  ChatStreamer? streamChat,
  List<Block> blocks = const [],
}) => StudioViewModel(
  config: tempConfig()..update(const AppConfig().putLlm(_llm)),
  streamChat: streamChat ?? (_) => const Stream.empty(),
  blocks: blocks,
);

void main() {
  group('拆出回复里的新成稿', () {
    test('没有标签时整条都是正文', () {
      final split = splitDraft('只是聊两句');

      expect(split.prose, '只是聊两句');
      expect(split.draft, isNull);
    });

    test('按【】分段,标签外的话留作正文', () {
      final split = splitDraft(
        '改好了。\n<draft>\n【主体】a woman\n【光影】\nside light,\nsoft shadows\n</draft>\n还要调吗?',
      );

      expect(split.prose, '改好了。\n\n还要调吗?');
      expect(split.draft!.complete, isTrue);
      expect(split.draft!.sections, [
        (label: '主体', text: 'a woman', zh: ''),
        (label: '光影', text: 'side light, soft shadows', zh: ''),
      ]);
      expect(split.draft!.text, '【主体】a woman\n【光影】side light, soft shadows');
    });

    test('还没写完的成稿先按已有的显示,半截标签不露出来', () {
      expect(splitDraft('好的。<dra').prose, '好的。');

      final split = splitDraft('好的。<draft>\n【主体】a wom</dr');
      expect(split.draft!.complete, isFalse);
      expect(split.draft!.sections, [(label: '主体', text: 'a wom', zh: '')]);
    });

    test('每段下面的中文对照跟着这段走,但不进交付的提示词', () {
      final draft = splitDraft(
        '<draft>\n【主体】a fox\n〔译〕一只狐狸\n【场景】snow\n译:雪地\n</draft>',
      ).draft!;

      expect(draft.sections, [
        (label: '主体', text: 'a fox', zh: '一只狐狸'),
        (label: '场景', text: 'snow', zh: '雪地'),
      ]);
      expect(draft.text, '【主体】a fox\n〔译〕一只狐狸\n【场景】snow\n〔译〕雪地');
      expect(stripSectionLabels(draft.text), 'a fox\nsnow');

      final spans = sectionSpans(draft.text);
      expect(spans.map((s) => s.zh), ['一只狐狸', '雪地']);
      expect(
        draft.text.substring(spans[0].textStart, spans[0].textEnd),
        'a fox',
      );
    });

    test('空的成稿标签不算成稿', () {
      expect(splitDraft('没改。<draft>\n</draft>').draft, isNull);
    });

    test('去掉行首的分段标注', () {
      expect(stripSectionLabels('【主体】a fox\n【场景】 snow'), 'a fox\nsnow');
      expect(stripSectionLabels('a 【b】 c'), 'a 【b】 c');
      expect(stripSectionLabels('【b】c\n【d】e', atLineStart: false), '【b】c\ne');
    });

    test('前面的话里提到标签时,仍取最后那一对', () {
      final split = splitDraft('我会放进 <draft> 里。\n<draft>\n【主体】a fox\n</draft>');

      expect(split.prose, '我会放进 <draft> 里。');
      expect(split.draft!.text, '【主体】a fox');
    });
  });

  group('按标注分段', () {
    test('一栏文字切成几段,位置对得上', () {
      const text = 'intro\n【主体】a fox\n【场景】 snow';
      final spans = sectionSpans(text);

      expect(spans.map((s) => s.label), ['', '主体', '场景']);
      expect(
        [for (final s in spans) text.substring(s.textStart, s.end)],
        ['intro', 'a fox', 'snow'],
      );
      expect(text.substring(spans[1].start, spans[1].end), '【主体】a fox');
      expect(sectionSpans('no labels here'), isEmpty);
    });

    test('段的短名:有标注用标注,没有就截一小截', () {
      expect(sectionTitle('【光影】soft light'), '光影');
      expect(sectionTitle('a very long plain line'), 'a very long …');
    });

    test('按行比对:没变的行原样,变了的行一删一增', () {
      expect(lineDiff('【主体】a fox\n【场景】snow', '【主体】a fox\n【场景】rain'), [
        ('【主体】a fox', 0),
        ('【场景】snow', -1),
        ('【场景】rain', 1),
      ]);
      expect(lineDiff('', 'new'), [('new', 1)]);
    });
  });

  test('一个接口填了几个模型:按先后试,回复上标出是哪个模型', () async {
    final asked = <String>[];
    final vm = StudioViewModel(
      config: tempConfig()
        ..update(
          const AppConfig().putLlm(
            LlmProfile(
              id: 'a',
              name: 'A',
              baseUrl: 'http://x',
              model: 'm1, m2',
            ),
          ),
        ),
      streamChat: (req) {
        asked.add(req.model);
        return req.model == 'm1'
            ? Stream.error(const LlmException('挂了'))
            : Stream.value('好');
      },
    );

    vm.send('你好');
    await pumpEventQueue();

    expect(asked, ['m1', 'm2']);
    expect(vm.messages.last.by, 'A · m2');
  });

  group('只改几段的成稿按标注并进去', () {
    const current = '【主体】a fox\n〔译〕狐狸\n【场景】snow\n【质感】fur';

    test('同标注的换掉,新标注接在后面,留空的删掉,没提到的不动', () {
      expect(
        mergeSections(current, '【场景】rain\n【质感】\n【光影】rim light'),
        '【主体】a fox\n〔译〕狐狸\n【场景】rain\n【光影】rim light',
      );
      // 一个标注都对不上:算整篇重写。
      expect(mergeSections(current, '【人物】a girl'), '【人物】a girl');
      expect(mergeSections('plain text', '【主体】x'), '【主体】x');
    });

    test('改了好几段时可以一段一段地采纳或驳回', () {
      final vm = _studio()..setText(0, current);
      // 换场景、删质感、加光影。
      vm.proposeDraft('【场景】rain\n【质感】\n【光影】rim light');

      vm.acceptSection('场景');
      expect(vm.body, '【主体】a fox\n〔译〕狐狸\n【场景】rain\n【质感】fur');
      expect(vm.pending, isNotNull);

      vm.rejectSection('质感');
      expect(vm.pending!.added, contains('【质感】fur'));

      vm.rejectSection('光影');
      // 剩下的都处理完了:没有待确认的改动,成稿只多了采纳的那一段。
      expect(vm.pending, isNull);
      expect(vm.body, '【主体】a fox\n〔译〕狐狸\n【场景】rain\n【质感】fur');
    });

    test('逐段采纳:新增的段落在该在的位置,删掉的段能删', () {
      expect(
        applySection('【a】1\n【c】3', '【a】1\n【b】2\n【c】3', 'b'),
        '【a】1\n【b】2\n【c】3',
      );
      expect(applySection('【a】1\n【b】2', '【a】1', 'b'), '【a】1');
      expect(applySection('【a】1', '【a】9', 'a'), '【a】9');
    });

    test('直接对话只改一段时,其他段留在成稿里', () async {
      final vm = _studio(
        streamChat: (_) => Stream.value('<draft>\n【场景】rain\n</draft>'),
      )..setText(0, current);

      vm.send('换成下雨');
      await pumpEventQueue();

      expect(vm.pending!.added, '【主体】a fox\n〔译〕狐狸\n【场景】rain\n【质感】fur');
      vm.acceptDiff();
      expect(vm.finalPrompt, 'a fox\nrain\nfur');
    });
  });

  group('存盘、对话历史和历史提示词', () {
    test('存下再读回,成稿、对话、历史都在', () async {
      final a = _studio(streamChat: (_) => Stream.value('你好呀'))
        ..addPin('masterpiece,')
        ..setText(1, '【主体】a fox');
      a.send('第一场');
      await pumpEventQueue();
      a
        ..recordPrompt()
        ..newChat();

      final b = _studio()..restore(jsonDecode(jsonEncode(a.toJson())));

      expect(b.blocks, a.blocks);
      expect(b.messages, isEmpty);
      expect(b.pastChats.single.messages.map((m) => m.text), ['第一场', '你好呀']);
      expect(b.promptLog.single.text, 'masterpiece, 【主体】a fox');
    });

    test('开新对话把旧的收进历史,还能再打开接着聊', () async {
      final vm = _studio(streamChat: (_) => Stream.value('好'));
      vm.send('第一场');
      await pumpEventQueue();

      expect(vm.newChat(), isTrue);
      expect(vm.messages, isEmpty);
      vm.send('第二场');
      await pumpEventQueue();

      expect(vm.openChat(vm.pastChats.single.id), isTrue);
      expect(vm.messages.first.text, '第一场');
      expect(vm.pastChats.single.messages.first.text, '第二场');

      vm.deleteChat(vm.pastChats.single.id);
      expect(vm.pastChats, isEmpty);
    });

    test('采纳改动会记一条历史提示词,能放回成稿', () {
      final vm = _studio()..setText(0, 'old');
      vm
        ..proposeDraft('【主体】a fox')
        ..acceptDiff()
        ..setText(0, 'something else');

      expect(vm.promptLog.single.text, '【主体】a fox');
      expect(vm.restorePrompt(vm.promptLog.single), isNull);
      expect(vm.pending!.added, '【主体】a fox');
    });

    test('有存盘文件时改动会落盘,下次能读回', () async {
      final dir = Directory.systemTemp.createTempSync('penna_ws');
      final file = File('${dir.path}${Platform.pathSeparator}workspace.json');
      StudioViewModel open() => StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        saveFile: file,
      );

      open()
        ..setText(0, 'a red fox')
        ..dispose();
      final again = open();
      await again.load();
      expect(again.finalPrompt, 'a red fox');
      again.dispose();

      // 文件坏了:留底,从空白开始。
      file.writeAsStringSync('{oops');
      final broken = open();
      await broken.load();
      expect(broken.finalPrompt, '');
      expect(file.existsSync(), isFalse);
      broken.dispose();
    });
  });

  group('选一段和 Agent 讨论', () {
    const body = '【主体】a fox\n【光影】flat light';

    test('选中的段随消息发出;回复里的那一段自动成为待确认改动', () async {
      late LlmRequest seen;
      final vm = _studio(
        streamChat: (req) {
          seen = req;
          return Stream.value('改亮了。\n<draft>\n【光影】rim light\n</draft>');
        },
        blocks: const [
          (text: 'masterpiece,', pinned: true),
          (text: body, pinned: false),
        ],
      )..quoteSection('【光影】flat light');

      expect(vm.send('更戏剧一点'), isNull);
      expect(vm.quote, isNull);
      expect(vm.messages.first.quote, '【光影】flat light');
      expect(seen.messages.last['content'], contains('【光影】flat light'));
      await pumpEventQueue();

      expect(vm.pending!.removed, '【光影】flat light');
      expect(vm.pending!.added, '【光影】rim light');
      expect(vm.body, 'masterpiece,$body');

      vm.acceptDiff();
      expect(vm.finalPrompt, 'masterpiece, a fox\nrim light');
    });

    test('整篇新成稿自动送到左侧:成稿是空的直接填,有内容就等确认', () async {
      final vm = _studio(
        streamChat: (_) =>
            Stream.value('好了。\n<draft>\n【主体】a fox\n【场景】snow\n</draft>'),
      );

      vm.send('画只狐狸');
      await pumpEventQueue();

      expect(vm.pending, isNull);
      expect(vm.body, '【主体】a fox\n【场景】snow');

      vm
        ..setText(0, '【主体】a wolf')
        ..regenerate();
      await pumpEventQueue();

      expect(vm.body, '【主体】a wolf');
      expect(vm.pending!.added, '【主体】a fox\n【场景】snow');
    });

    test('那一段已经被改掉时不收', () {
      final vm = _studio()..setText(0, body);

      expect(vm.proposeDraft('【光影】x', replacing: '【光影】gone'), contains('变了'));
      expect(vm.pending, isNull);
    });
  });

  group('新成稿放到左侧', () {
    test('只生成待确认 diff;采纳后成稿带标注,交付的提示词不带', () {
      final vm = _studio()..setText(0, 'old');

      expect(vm.proposeDraft('【主体】a fox\n【场景】snow'), isNull);
      expect(vm.finalPrompt, 'old');
      expect(vm.pending!.removed, 'old');

      vm.acceptDiff();

      expect(vm.body, '【主体】a fox\n【场景】snow');
      expect(vm.finalPrompt, 'a fox\nsnow');
    });

    test('空的新成稿不收;从一行中间开始的块,开头的【】不当标注去掉', () {
      final vm = _studio(
        blocks: const [
          (text: 'a girl, ', pinned: false),
          (text: '【光影】soft light', pinned: false),
        ],
      );

      expect(vm.proposeDraft('  '), contains('空'));
      expect(vm.pending, isNull);
      expect(vm.finalPrompt, 'a girl, 【光影】soft light');
    });

    test('空成稿也能放', () {
      final vm = _studio();

      expect(vm.proposeDraft('【主体】a fox'), isNull);
      vm.acceptDiff();

      expect(vm.finalPrompt, 'a fox');
    });

    test('固定区留在原位,只换那一栏文字', () {
      final vm = _studio(
        blocks: const [
          (text: 'masterpiece,', pinned: true),
          (text: 'old', pinned: false),
        ],
      );

      expect(vm.proposeDraft('【主体】a fox'), isNull);
      vm.acceptDiff();

      expect(vm.blocks.first, (text: 'masterpiece,', pinned: true));
      expect(vm.finalPrompt, 'masterpiece, a fox');
    });

    test('被固定区隔成几栏时整篇重写:第一栏换成新的,其余栏清空;已有待确认改动时不收', () {
      final split = _studio(
        blocks: const [
          (text: 'a ', pinned: false),
          (text: 'pin', pinned: true),
          (text: ' b', pinned: false),
        ],
      );
      expect(split.proposeDraft('x'), isNull);
      split
        ..acceptDiff()
        ..acceptDiff();
      expect(split.pending, isNull);
      expect(split.finalPrompt, 'x pin');

      expect(sampleStudio().proposeDraft('x'), contains('待确认'));
    });
  });

  group('重新运行与打断', () {
    test('重新运行丢掉上一条回复,把同一个问题再发一次', () async {
      final seen = <LlmRequest>[];
      var round = 0;
      final vm = _studio(
        streamChat: (req) {
          seen.add(req);
          return Stream.value('回复${++round}');
        },
      );
      expect(vm.regenerate(), contains('没有'));

      vm.send('画只狐狸');
      await pumpEventQueue();
      expect(vm.regenerate(), isNull);
      await pumpEventQueue();

      expect(vm.messages.map((m) => m.text), ['画只狐狸', '回复2']);
      expect(seen.last.messages.last, {'role': 'user', 'content': '画只狐狸'});
      expect(seen.last.messages, hasLength(2));
    });

    test('生成中不能重新运行', () {
      final reply = StreamController<String>();
      final vm = _studio(streamChat: (_) => reply.stream)..send('你好');

      expect(vm.regenerate(), contains('正在生成'));
      expect(vm.messages, hasLength(2));
    });

    test('打断后标记为已停止', () async {
      final reply = StreamController<String>();
      final vm = _studio(streamChat: (_) => reply.stream)..send('你好');
      reply.add('半句');
      await pumpEventQueue();

      vm.stop();

      expect(vm.messages.last.stopped, isTrue);
      expect(vm.messages.last.text, '半句');
    });

    test('系统提示要求另出一份分段标注的成稿,并带上有标注的当前成稿', () {
      late LlmRequest seen;
      final vm = _studio(
        streamChat: (req) {
          seen = req;
          return const Stream.empty();
        },
      )..setText(0, '【主体】a fox');

      vm.send('改一下');

      final system = seen.messages.first['content']!;
      expect(system, contains('<draft>'));
      expect(system, contains('【当前成稿】\n【主体】a fox'));
    });

    test('页或系列还没名字时,系统提示要它这次起上;都起了就不提', () async {
      final seen = <String>[];
      final vm = _studio(
        streamChat: (req) {
          seen.add(req.messages.first['content']!);
          return const Stream.empty();
        },
      );

      vm.send('画一只狐狸');
      await pumpEventQueue();
      expect(seen.last, contains('【还没起名】这一页和这个系列还没有名字'));
      expect(seen.last, contains('name="两到六个字的页名" series="两到六个字的系列名"'));

      vm.renamePage(vm.pageIndex, '狐狸');
      vm.send('再来');
      await pumpEventQueue();
      expect(seen.last, contains('【还没起名】这个系列还没有名字'));
      expect(seen.last, isNot(contains('name="两到六个字的页名"')));

      vm.renameSeries(vm.series, '森林');
      vm.send('再来');
      await pumpEventQueue();
      expect(seen.last, isNot(contains('【还没起名】')));
    });
  });
}
