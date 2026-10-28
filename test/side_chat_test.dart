import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/chat_peek.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/core/widgets.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/side_chat.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

/// 主聊天和副聊天共用一个假模型:按顺序说 [replies],请求记在 [seen] 里。
(StudioViewModel, SideChat) _chats(
  List<String> replies,
  List<LlmRequest> seen, {
  bool sidePiercing = false,
  LayoutBoard? layout,
}) {
  final service = tempConfig();
  service.update(
    service.config
        .putLlm(
          const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
        )
        .putLlm(
          const LlmProfile(id: 'b', name: 'B', baseUrl: 'http://b', model: 'n'),
        )
        .copyWith(
          sideLlmId: () => 'b',
          sidePiercing: sidePiercing,
          piercingPrompt: 'PIERCE',
        ),
  );
  final vm = StudioViewModel(
    config: service,
    layout: layout,
    layoutOnly: layout != null,
    streamChat: (req) {
      seen.add(req);
      return Stream.value(replies[seen.length - 1]);
    },
  );
  final side = SideChat(vm);
  vm.side = side;
  return (vm, side);
}

void main() {
  test('拆「看另一边」的标签:成对的、自闭合的都认;没写完的先不显示', () {
    expect(splitPeek('看一下<read-side-chat></read-side-chat>', readSideChat), (
      prose: '看一下',
      asked: true,
    ));
    expect(splitPeek('<read-main-chat/>', readMainChat).asked, isTrue);
    expect(splitPeek('稍等<read-si', readSideChat), (prose: '稍等', asked: false));
    expect(splitPeek('a < b', readSideChat).prose, 'a < b');
  });

  test('副聊天用自己指定的模型和穿甲弹开关,读得到工作区;主聊天不受影响', () async {
    final seen = <LlmRequest>[];
    final (vm, side) = _chats(['副', '主'], seen, sidePiercing: true);

    side.send('这段怎么样');
    await pumpEventQueue();
    expect(seen.single.baseUrl, 'http://b');
    final system = seen.single.messages.first['content']!;
    expect(system, startsWith('PIERCE'));
    expect(system, contains('【工作区】'));
    expect(side.messages.last.text, '副');
    expect(side.isStreaming, isFalse);

    vm.send('写一张图');
    await pumpEventQueue();
    expect(seen.last.baseUrl, 'http://a');
    expect(seen.last.messages.first['content'], isNot(startsWith('PIERCE')));
    // 副聊天说过话,主聊天的系统提示里讲了怎么去看它。
    expect(seen.last.messages.first['content'], contains('【副聊天】'));
    expect(vm.messages.where((m) => !m.fromUser).single.text, '主');
  });

  test('副聊天写的 <draft> 放进工作区:空页直接填,有内容时是待确认改动', () async {
    final seen = <LlmRequest>[];
    final (vm, side) = _chats([
      '写好了。<draft>【主体】a bathroom</draft>',
      '<draft replace>【主体】a garden</draft>',
    ], seen);

    side.send('帮我写一张浴室');
    await pumpEventQueue();
    expect(seen.single.messages.first['content'], contains('<draft>'));
    expect(vm.body, '【主体】a bathroom');

    side.send('整篇换成花园');
    await pumpEventQueue();
    expect(vm.pending?.added, '【主体】a garden');
    vm.acceptDiff();
    expect(vm.body, '【主体】a garden');
  });

  test('换页、主聊天开新对话时副聊天从头开始;自己的成稿写到别的页不算', () async {
    final seen = <LlmRequest>[];
    final (vm, side) = _chats([
      '<draft>【主体】a</draft>',
      '<draft page="2">【主体】b</draft>',
      '好',
    ], seen);

    side.send('第一页怎么样');
    await pumpEventQueue();
    expect(side.messages, hasLength(2));
    // 副聊天自己往第 2 页写成稿:工作区换到那页给用户看,副聊天不算换了页。
    side.send('第二页写个 b');
    await pumpEventQueue();
    expect(vm.seriesLength, 2);
    expect(vm.pageIndex, 1);
    expect(vm.body, '【主体】b');
    expect(side.messages, hasLength(4));

    expect(vm.openPage(0), isNull);
    await pumpEventQueue();
    expect(side.messages, isEmpty);

    side.send('这页呢');
    await pumpEventQueue();
    expect(side.messages, hasLength(2));
    vm.newChat();
    await pumpEventQueue();
    expect(side.messages, isEmpty);
  });

  test('副聊天能带图和文本文件:图随请求发出,文件包进那条消息', () async {
    final seen = <LlmRequest>[];
    final (_, side) = _chats(['看到了'], seen);

    side.send(
      '照这张图',
      attachments: [
        Attachment.image(
          name: 'a.png',
          mime: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        const Attachment.text(name: 'b.txt', text: 'NOTE'),
      ],
    );
    await pumpEventQueue();
    final req = seen.single;
    expect(
      req.messages[1]['content'],
      allOf(contains('照这张图'), contains('NOTE')),
    );
    expect(req.images[1]!.single.mime, 'image/png');
    expect(side.messages.first.attachments, hasLength(2));
  });

  test('副聊天写 <ask-layout> 时交给区域控制的 Agent,排好后接着写', () async {
    const json =
        '{"width": 832, "height": 1216, "items": [{"name": "左", '
        '"bbox": [100, 100, 500, 1100]}], "bbox_coord_space": "abs", '
        '"bbox_format": "xyxy"}';
    final board = LayoutBoard();
    final seen = <LlmRequest>[];
    final (vm, side) = _chats([
      '<ask-layout name="海报">左边一个人</ask-layout>',
      '<layout>$json</layout>',
      '排好了。',
    ], seen);
    vm.layoutAgent = StudioViewModel(
      config: vm.config,
      layout: board,
      layoutOnly: true,
      streamChat: (req) {
        seen.add(req);
        return Stream.value(seen.length == 2 ? '<layout>$json</layout>' : '');
      },
    );

    side.send('排个布局');
    await pumpEventQueue(times: 50);
    expect(seen.first.messages.first['content'], contains('<ask-layout'));
    expect(board.layout.boxes.single.name, '左');
    // JSON 放进主工作区新开的一页(眼前空着就用它),副聊天接着说完。
    expect(vm.body, board.json);
    expect(
      side.messages.firstWhere((m) => m.tool).toolSummary,
      contains('区域控制排好了'),
    );
    expect(side.messages.last.text, '排好了。');
    expect(side.isStreaming, isFalse);
  });

  test('区域控制的副聊天照排布局的要求写,<layout> 放到画板上;那边的主聊天也读得到它', () async {
    const json =
        '{"width": 832, "height": 1216, "summary": {"canvas": "single", '
        '"caption": "Scene."}, "items": [{"name": "凛·1", "label": "character", '
        '"caption": "Waves.", "bbox": [100, 100, 500, 1100]}], '
        '"bbox_coord_space": "abs", "bbox_format": "xyxy"}';
    final board = LayoutBoard();
    final seen = <LlmRequest>[];
    final (vm, side) = _chats(
      ['挪好了。<layout>$json</layout>', '<read-side-chat/>', '照副聊天的看过了'],
      seen,
      layout: board,
    );

    side.send('把凛放左边');
    await pumpEventQueue();
    final system = seen.single.messages.first['content']!;
    expect(system, contains('区域控制工作台的副聊天助手'));
    expect(system, contains('<layout>'));
    expect(board.layout.boxes.single.name, '凛·1');

    vm.send('看看副聊天');
    await pumpEventQueue();
    expect(seen, hasLength(3));
    expect(seen.last.messages.last['content'], contains('【副聊天的记录】'));
    expect(vm.messages.last.text, '照副聊天的看过了');
  });

  test('主聊天写 <read-side-chat> 时读到副聊天的记录,再接着写', () async {
    final seen = <LlmRequest>[];
    final (vm, side) = _chats([
      '光影那段太暗了',
      '<read-side-chat></read-side-chat>',
      '照副聊天说的改亮了',
    ], seen);

    side.send('看看光影');
    await pumpEventQueue();
    vm.send('参考一下副聊天');
    await pumpEventQueue();

    expect(seen, hasLength(3));
    final handed = seen.last.messages.last['content']!;
    expect(handed, contains('【副聊天的记录】'));
    expect(handed, contains('副聊天:光影那段太暗了'));
    expect(vm.messages.last.text, '照副聊天说的改亮了');
    expect(vm.messages.any((m) => m.toolSummary == '读了副聊天'), isTrue);
  });

  testWidgets('点「副聊天」弹出浮窗,发一句收到回复;再点一下关掉,记录还在', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seen = <LlmRequest>[];
    final (vm, _) = _chats(['副聊天的回答'], seen);
    vm.side = null; // AppShell 自己接上一个。
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );
    // 区域控制页(也常驻在 Stack 里)也有一个,找工作台的。
    final toggle = find.descendant(
      of: find.byType(StudioPage),
      matching: find.widgetWithText(PennaButton, '副聊天'),
    );
    expect(toggle, findsOneWidget);
    expect(vm.side, isNotNull);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final box = find.widgetWithText(TextField, '问问工作区里的提示词');
    expect(box, findsOneWidget);
    await tester.enterText(box, '这段怎么样');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    expect(seen.single.baseUrl, 'http://b');
    expect(find.text('副聊天的回答', findRichText: true), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(box, findsNothing);
    expect(vm.side!.messages, hasLength(2));
  });

  test('副聊天写 <read-main-chat> 时读到主聊天的记录,再接着写', () async {
    final seen = <LlmRequest>[];
    final (vm, side) = _chats([
      '画好了一张海边',
      '<read-main-chat/>',
      'Agent 画的是海边',
    ], seen);

    vm.send('画海边');
    await pumpEventQueue();
    side.send('主聊天画了什么');
    await pumpEventQueue();

    expect(seen, hasLength(3));
    expect(seen.last.baseUrl, 'http://b');
    final handed = seen.last.messages.last['content']!;
    expect(handed, contains('【主聊天的记录】'));
    expect(handed, contains('用户:画海边'));
    expect(handed, contains('Agent:画好了一张海边'));
    expect(side.messages.last.text, 'Agent 画的是海边');
    expect(side.messages.any((m) => m.toolSummary == '读了主聊天'), isTrue);
    // 主聊天的对话没多出东西。
    expect(vm.messages, hasLength(2));
  });
}
