import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/services/translate_engines.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/activity_bar.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

const _body = '【主体】a fox\n〔译〕一只狐狸\n【光影】flat light\n【构图】wide shot';

StudioViewModel _studio({String zh = '平光'}) => StudioViewModel(
  config: tempConfig(),
  streamChat: (_) => const Stream.empty(),
  translate: (_, text) async => TranslateResult(zh, 'mymemory', const []),
  blocks: const [(text: _body, pinned: false)],
);

void main() {
  group('只固定一段', () {
    test('整段原样留着,只是锁上了;交付的提示词和带标注的全文都不变', () {
      final vm = _studio();
      final prompt = vm.finalPrompt;
      final labeled = vm.labeledPrompt;
      final start = _body.indexOf('【光影】');
      final end = _body.indexOf('\n【构图】');

      expect(vm.pinSection(start, end, 'flat light'), isTrue);

      expect(vm.blocks, [
        (text: '【主体】a fox\n〔译〕一只狐狸', pinned: false),
        (text: '【光影】flat light', pinned: true),
        (text: '\n【构图】wide shot', pinned: false),
      ]);
      expect(vm.finalPrompt, prompt);
      expect(vm.labeledPrompt, labeled);
    });

    test('带中文对照的第一段也能固定;解除后和原来一模一样', () {
      final vm = _studio();
      final end = _body.indexOf('\n【光影】');

      expect(vm.pinSection(0, end, 'a fox'), isTrue);
      expect(vm.blocks.first, (text: '【主体】a fox\n〔译〕一只狐狸', pinned: true));
      expect(vm.finalPrompt, 'a fox\nflat light\nwide shot');

      vm.unpin(0);
      expect(vm.body, _body);
    });

    test('固定的段拖到别处,标注还在行首', () {
      final vm = _studio();
      final start = _body.indexOf('【光影】');
      vm.pinSection(start, _body.indexOf('\n【构图】'), 'flat light');

      // 拖到最后。
      vm.movePin(1, vm.body.length);

      expect(
        vm.labeledPrompt,
        '【主体】a fox\n〔译〕一只狐狸\n【构图】wide shot\n【光影】flat light',
      );
      expect(vm.finalPrompt, 'a fox\nwide shot\nflat light');

      // 再拖回最前面。
      vm.movePin(vm.blocks.length - 1, 0);
      expect(vm.finalPrompt, 'flat light\na fox\nwide shot');
    });

    test('有待确认改动、或这段是空的时不固定', () {
      final vm = _studio()..proposeDraft('【光影】hard light');
      expect(vm.pinSection(0, 5, 'a fox'), isFalse);
      expect(_studio().pinSection(0, 4, '  '), isFalse);
    });
  });

  group('拖动和合并', () {
    test('把一段拖到另一段的位置上,中文对照跟着走', () {
      final vm = _studio();

      vm.moveSection(0, 0, 2);
      expect(vm.body, '【光影】flat light\n【构图】wide shot\n【主体】a fox\n〔译〕一只狐狸');
      expect(vm.finalPrompt, 'flat light\nwide shot\na fox');

      vm.moveSection(0, 2, 0);
      expect(vm.body, _body);
    });

    test('固定区后面那一栏里拖动,和固定区之间的换行不丢', () {
      final vm = _studio();
      vm.pinSection(0, _body.indexOf('\n【光影】'), 'a fox');
      final column = vm.parts.last;

      vm.moveSection(column.index, 0, 1);

      expect(vm.finalPrompt, 'a fox\nwide shot\nflat light');
      expect(vm.labeledPrompt, startsWith('【主体】a fox\n〔译〕一只狐狸\n【构图】'));
    });

    test('合并:标注和对照去掉,提示词不变,能从历史放回来;固定的段不动', () {
      final vm = _studio();
      final prompt = vm.finalPrompt;
      vm.pinSection(
        _body.indexOf('【光影】'),
        _body.indexOf('\n【构图】'),
        'flat light',
      );

      expect(vm.unsection(), isTrue);

      expect(vm.finalPrompt, prompt);
      expect(vm.blocks, [
        (text: 'a fox', pinned: false),
        (text: '【光影】flat light', pinned: true),
        (text: '\nwide shot', pinned: false),
      ]);
      expect(vm.promptLog.first.text, contains('【主体】a fox'));
      // 已经没有分段了。
      expect(vm.unsection(), isFalse);
    });
  });

  group('脱离分段', () {
    test('中间的段留在原处变成普通文字,不并进上一段;交付的提示词不变', () {
      final vm = _studio();
      final prompt = vm.finalPrompt;

      vm.detachSection(0, 1);

      expect(vm.body, '【主体】a fox\n〔译〕一只狐狸\n【】flat light\n【构图】wide shot');
      expect(vm.finalPrompt, prompt);
      // Agent 只改【主体】时,脱离的那一行原样留着。
      vm.proposeDraft('【主体】a red fox');
      vm.acceptDiff();
      expect(vm.finalPrompt, 'a red fox\nflat light\nwide shot');
    });

    test('第一段只是去掉标注和对照', () {
      final vm = _studio();

      vm.detachSection(0, 0);

      expect(vm.body, 'a fox\n【光影】flat light\n【构图】wide shot');
      expect(vm.finalPrompt, 'a fox\nflat light\nwide shot');
    });

    test('只脱离选中的:拿出来跟在那段后面,中文对照留给原来那段', () {
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        blocks: const [
          (text: '【甲】red hat, blue coat\n〔译〕一\n【乙】b', pinned: false),
        ],
      );
      vm.bodySelection = (3, 11);

      expect(vm.detachSelection(), isTrue);

      expect(vm.body, '【甲】blue coat\n〔译〕一\n【】red hat,\n【乙】b');
    });

    test('翻译选中的:只翻那一截', () async {
      String? asked;
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        translate: (_, text) async {
          asked = text;
          return TranslateResult('狐狸', 'mymemory', const []);
        },
        blocks: const [(text: _body, pinned: false)],
      );
      vm.bodySelection = (6, 9);

      expect(await vm.translateDraft(selection: true), isNull);

      expect(asked, 'fox');
      expect(vm.translation, '狐狸');
    });
  });

  group('改名与建立分段', () {
    StudioViewModel plain(String text) => StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      blocks: [(text: text, pinned: false)],
    );

    test('改名只换标注,交付的提示词不变;【】和换行去掉', () {
      final vm = _studio();
      final prompt = vm.finalPrompt;

      vm.renameSection(0, 1, '光线');
      expect(vm.body, '【主体】a fox\n〔译〕一只狐狸\n【光线】flat light\n【构图】wide shot');
      expect(vm.finalPrompt, prompt);

      expect(vm.renameSection(0, 0, '【新】\n名'), isTrue);
      expect(vm.body, startsWith('【新名】a fox'));
      expect(vm.actions.first.text, startsWith('「主体」改名为「新名」'));

      // 和别的段重名不行:按标注并入的改动只会认第一个。
      expect(vm.renameSection(0, 0, '构图'), isFalse);
      expect(vm.body, startsWith('【新名】a fox'));
      expect(vm.sectionNameTaken('构图'), isTrue);
    });

    test('整栏普通文字:选中的建成一段,后面剩下的仍是普通文字', () {
      final vm = plain('red hat, blue coat')..bodySelection = (0, 8);

      expect(vm.sectionSelection('帽子'), isTrue);

      expect(vm.body, '【帽子】red hat,\n【】blue coat');
      expect(vm.finalPrompt, 'red hat,\nblue coat');
    });

    test('脱离出来的那一行里选一截建成一段;分段里的文字不行', () {
      const text = '【主体】a fox\n【】flat light, rim light';
      final at = text.indexOf('rim');
      final vm = plain(text)..bodySelection = (at, text.length);

      expect(vm.sectionSelection('光'), isTrue);
      expect(vm.body, '【主体】a fox\n【】flat light,\n【光】rim light');

      vm.bodySelection = (4, 9);
      expect(vm.sectionSelection('狐狸'), isFalse);
    });

    test('当前页的各段:标注和提示词,对照不带', () {
      expect(_studio().sectionsHere, [
        (label: '主体', text: 'a fox'),
        (label: '光影', text: 'flat light'),
        (label: '构图', text: 'wide shot'),
      ]);
    });
  });

  group('回滚', () {
    test('回到某一步之前、之后:记录都留着,能反复切;回到前面再做别的,原来那几步成了另一个分支', () {
      final vm = _studio();
      vm.moveSection(0, 0, 2);
      final moved = vm.body;
      vm.unsection();
      final merged = vm.body;
      vm.clearDraft();
      expect(vm.body, isEmpty);
      List<ActionState> states() => [
        for (var i = 0; i < vm.actions.length; i++) vm.stateOf(i),
      ];
      expect(states(), [
        ActionState.current,
        ActionState.done,
        ActionState.done,
      ]);

      // 第 1 条是「取消分段」(新的在前:清空、取消分段、拖动)。回到它之前:后两步撤掉,记录不删。
      expect(vm.rollback(1), isNull);
      expect(vm.body, moved);
      expect(vm.actions, hasLength(3));
      expect(states(), [
        ActionState.undone,
        ActionState.undone,
        ActionState.current,
      ]);

      // 再回到「清空」之后,然后又切回「取消分段」之后:来回切都对得上。
      expect(vm.restoreTo(0), isNull);
      expect(vm.body, isEmpty);
      expect(vm.restoreTo(1), isNull);
      expect(vm.body, merged);
      expect(vm.stateOf(0), ActionState.undone);

      // 在这里做别的:「清空」那一步成了另一个分支,还能切过去。
      vm.addPin('masterpiece');
      expect(vm.actions, hasLength(4));
      expect(vm.stateOf(0), ActionState.current);
      expect(vm.stateOf(1), ActionState.branch);
      expect(vm.restoreTo(1), isNull);
      expect(vm.body, isEmpty);
      expect(vm.stateOf(0), ActionState.branch);
      expect(vm.stateOf(1), ActionState.current);
    });

    testWidgets('操作记录栏:标出当前、已撤销,两个按钮来回切', (tester) async {
      final vm = _studio();
      vm.unsection();
      vm.clearDraft();
      await tester.pumpWidget(
        MaterialApp(
          theme: pennaTheme(),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: vm,
              builder: (_, _) => ActivityBar(vm: vm),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();
      expect(find.text('当前'), findsOneWidget);
      // 眼前这一笔没有「之后」可回。
      expect(find.byIcon(Icons.redo), findsOneWidget);

      await tester.tap(find.byIcon(Icons.undo).last);
      await tester.pumpAndSettle();
      expect(vm.body, _body);
      expect(find.text('已撤销'), findsNWidgets(2));
      expect(find.text('当前'), findsNothing);

      await tester.tap(find.byIcon(Icons.redo).first);
      await tester.pumpAndSettle();
      expect(vm.body, isEmpty);
      expect(find.text('当前'), findsOneWidget);
    });

    test('换走时手打的字记在眼前这一步上,切回来还在', () {
      final vm = _studio();
      vm.clearDraft();
      vm.setText(0, 'typed after clear');
      vm.rollback(0);
      expect(vm.body, _body);
      vm.restoreTo(0);
      expect(vm.body, 'typed after clear');
    });

    test('采纳改动能撤回:成稿变回去,那处改动重新等确认', () {
      final vm = _studio()..proposeDraft('【光影】hard light');
      vm.acceptDiff();
      expect(vm.finalPrompt, contains('hard light'));

      vm.rollback(0);

      expect(vm.body, _body);
      expect(vm.pending?.added, contains('hard light'));
    });

    test('删掉的页和系列能找回来,连同它的对话', () async {
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        blocks: const [(text: 'A', pinned: false)],
      );
      vm.addPage(newSeries: true);
      vm.setText(0, 'B');
      vm.renameSeries(vm.series, '城市');

      vm.removeSeries(vm.series);
      expect(vm.pages, hasLength(1));

      vm.rollback(0);
      expect(vm.pages, hasLength(2));
      expect(vm.finalPrompt, 'B');
      expect(vm.seriesName(vm.series), '城市');
    });
  });

  group('只翻译一段', () {
    test('译文写成这段的中文对照,交付的提示词不变', () async {
      final vm = _studio();
      final before = vm.finalPrompt;

      expect(await vm.translateSection('【光影】flat light', 'flat light'), isNull);

      expect(vm.body, contains('【光影】flat light\n〔译〕平光\n【构图】'));
      expect(vm.finalPrompt, before);
      expect(vm.isTranslating, isFalse);
    });

    test('原来有对照就换掉;多行译文并成一行', () async {
      final vm = _studio(zh: '一只\n赤狐');

      await vm.translateSection('【主体】a fox\n〔译〕一只狐狸', 'a fox');

      expect(vm.body, startsWith('【主体】a fox\n〔译〕一只 赤狐\n【光影】'));
    });

    test('提示词和标注有相同的字时,标注不会被切坏', () async {
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        translate: (_, text) async =>
            const TranslateResult('light', 'mymemory', []),
        blocks: const [(text: '【光影】光', pinned: false)],
      );

      await vm.translateSection('【光影】光', '光');

      expect(vm.body, '【光影】光\n〔译〕light');
    });

    test('这段已经变了、或有待确认改动时不写', () async {
      final vm = _studio();
      expect(await vm.translateSection('【光影】别的内容', '别的内容'), '这段已经变了');
      vm.proposeDraft('【光影】hard light');
      expect(
        await vm.translateSection('【光影】flat light', 'flat light'),
        contains('待确认'),
      );
      expect(vm.body, _body);
    });
  });

  testWidgets('每段框上有自己的固定、润色、翻译', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vm = _studio();
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );

    // 润色:范围就是这一段的提示词(flat light,10 个字符)。
    await tester.tap(find.byTooltip('润色这段').at(1));
    await tester.pumpAndSettle();
    expect(find.text('范围:10 个字符'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    // 取消后不留着这个范围,下次点顶栏的润色不会还落在这一段上。
    expect(vm.bodySelection, isNull);

    await tester.tap(find.byTooltip('翻译这段').at(1));
    await tester.pumpAndSettle();
    expect(vm.body, contains('【光影】flat light\n〔译〕平光'));

    await tester.tap(find.byTooltip('固定这段').at(1));
    await tester.pumpAndSettle();
    expect(vm.blocks[1], (text: '【光影】flat light\n〔译〕平光', pinned: true));
    // 固定后还是那个分段框:标注在,能复制、能解除。
    expect(find.text('光影'), findsOneWidget);
    expect(find.byTooltip('复制这段'), findsNWidgets(3));

    await tester.tap(find.byTooltip('取消固定'));
    await tester.pumpAndSettle();
    expect(vm.blocks.every((b) => !b.pinned), isTrue);
  });
}
