import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

const _rin =
    'Rin, a slender teenage girl with a short black bob and bright green eyes, '
    'wearing a navy school blazer';

const _page = Layout(
  caption: 'A two-panel page.',
  cast: {'凛': _rin, '蓝': 'Ao, a tall girl with long blue hair'},
  boxes: [
    LayoutBox(
      left: 0,
      top: 0,
      right: 100,
      bottom: 100,
      label: 'character',
      name: '凛·1',
      caption: 'She smiles.',
    ),
    LayoutBox(
      left: 0,
      top: 120,
      right: 100,
      bottom: 200,
      label: 'character',
      name: '两人组·2',
      caption: 'Two girls.',
    ),
    LayoutBox(
      left: 0,
      top: 0,
      right: 400,
      bottom: 400,
      name: '第1格',
      caption: 'Panel 1.',
    ),
  ],
);

String _layout(String name, {String cast = '', String page = ''}) =>
    '<layout$page>{"width": 832, "height": 1216, "summary": {"canvas": "single", '
    '$cast"caption": "Scene."}, '
    '"items": [{"name": "$name", "label": "character", "caption": "Waves.", '
    '"bbox": [100, 100, 500, 1100]}], '
    '"bbox_coord_space": "abs", "bbox_format": "xyxy"}</layout>';

void main() {
  test('交出去时角色卡原样接在人物块描述前面,整体描述末尾列出这页的角色;草稿不带', () {
    final out = jsonDecode(mossLayoutJson(_page)) as Map;
    final items = out['items'] as List;
    expect(items[0]['caption'], '$_rin. She smiles.');
    // 没对上角色卡的不动,物体块不动。
    expect(items[1]['caption'], 'Two girls.');
    expect(items[2]['caption'], 'Panel 1.');
    // 这页没出现的「蓝」不列。
    expect(out['summary']['caption'], 'A two-panel page. Characters: $_rin.');

    final draft = jsonDecode(mossLayoutJson(_page, draft: true)) as Map;
    expect((draft['items'] as List)[0]['caption'], 'She smiles.');
    expect(draft['summary'].containsKey('cast'), isFalse);
  });

  test('导入交出去的 JSON 再交出去,角色卡不重复', () {
    final once = mossLayoutJson(_page);
    final back = parseMossLayout(once, width: 832, height: 1216)!;
    expect(mossLayoutJson(back.copyWith(cast: _page.cast)), once);
  });

  test('没对上角色卡的人物块挑得出来;没有角色卡时不挑', () {
    expect(castMisses(_page).map((b) => b.name), ['两人组·2']);
    expect(castMisses(_page.copyWith(cast: const {})), isEmpty);
  });

  test('读 summary.cast;存档读回还在;属性栏的文字来回换得通', () {
    final read = parseMossLayout(
      '{"summary": {"cast": {"凛": " $_rin ", "空": " "}, "caption": "x"}, '
      '"items": []}',
      width: 832,
      height: 1216,
    )!;
    expect(read.cast, {'凛': _rin});
    expect(Layout.fromJson(read.toJson()).cast, {'凛': _rin});
    expect(parseCastText(castText(_page.cast)), _page.cast);
    expect(parseCastText('凛:$_rin\n\n没写卡\n'), {'凛': _rin});
  });

  test('Agent 改布局时没写角色卡就沿用;没对上的写进下一轮的提示', () {
    final board = LayoutBoard()..setCast({'凛': _rin});
    expect(
      board.apply(_layout('两人组·1').replaceAll(RegExp('</?layout>'), '')),
      isTrue,
    );
    expect(board.layout.cast, {'凛': _rin});
    expect(board.prompt, contains('【角色卡没对上】'));
    expect(board.prompt, contains('两人组·1'));
  });

  test('交出的人物块没对上角色卡:程序自己让 Agent 改,最多三轮', () async {
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final seen = <List<Map<String, String>>>[];
    var replies = [_layout('小葱·1'), _layout('凛·1')];
    final board = LayoutBoard()..setCast({'凛': _rin});
    final chat = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (request) {
        seen.add(request.messages);
        return Stream.value(replies[seen.length - 1]);
      },
    );

    chat.send('画凛');
    await pumpEventQueue();
    expect(seen, hasLength(2));
    final fix = seen.last.last['content']!;
    expect(fix, contains('【程序检查:角色卡没对上】'));
    expect(fix, contains('「小葱·1」'));
    expect(fix, contains('现有:凛'));
    expect(castMisses(board.layout), isEmpty);
    expect(chat.isStreaming, isFalse);

    // 一直改不对也会停:一条消息最多再要三轮。
    seen.clear();
    replies = List.filled(10, _layout('小葱·1'));
    chat.send('再画一张');
    await pumpEventQueue();
    expect(seen, hasLength(4));
    expect(chat.isStreaming, isFalse);
  });

  test('角色卡跟着系列:同系列新开一页沿用,另起系列不带过去', () async {
    final board = LayoutBoard();
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final seen = <List<Map<String, String>>>[];
    final replies = [
      _layout(
        '凛·1',
        cast: '"cast": {"凛": "$_rin"}, ',
        page: ' page="新系列" series="凛"',
      ),
      _layout('凛·1', page: ' page="新"'),
      _layout('蓝·1', page: ' page="新系列" series="蓝"'),
    ];
    final chat = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (request) {
        seen.add(request.messages);
        return Stream.value(replies[seen.length - 1]);
      },
    );

    chat.send('画凛');
    await pumpEventQueue();
    expect(seen.last.first['content'], contains('【本系列角色卡】还没定'));
    expect(board.layout.cast, {'凛': _rin});

    chat.send('下一页');
    await pumpEventQueue();
    expect(seen.last.first['content'], contains('【本系列角色卡】已定'));
    expect(seen.last.first['content'], contains(_rin));
    expect(chat.seriesLength, 2);
    expect(board.layout.cast, {'凛': _rin});

    chat.send('换成蓝');
    await pumpEventQueue();
    expect(board.layout.cast, isEmpty);
  });
}
