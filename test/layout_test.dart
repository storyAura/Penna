import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_canvas.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

const _official = '''
{
  "summary": {"meta": ["poster"], "canvas": "single", "caption": "A travel poster."},
  "items": [
    {"label": "text", "caption": "Title.", "text": "EXPLORE", "bbox": [-416, -384, -288, 384]},
    {"label": "object", "caption": "Mountain.", "bbox": [-192, -288, 384, 288]}
  ],
  "bbox_coord_space": "abs_centralized",
  "bbox_format": "yxyx"
}''';

void main() {
  _regionTests();
  test('官方示例读进来再写出去,坐标不变', () {
    final l = parseMossLayout(_official, width: 1024, height: 1024)!;
    expect(l.boxes.first.left, 128);
    expect(l.boxes.first.top, 96);
    expect(l.boxes.first.label, 'text');
    expect(l.boxes.first.text, 'EXPLORE');
    expect(l.meta, 'poster');
    final out = jsonDecode(mossLayoutJson(l)) as Map;
    expect(out['bbox_format'], 'yxyx');
    expect(out['bbox_coord_space'], 'abs_centralized');
    final items = out['items'] as List;
    expect(items[0]['bbox'], [-416, -384, -288, 384]);
    expect(items[1]['bbox'], [-192, -288, 384, 288]);
    expect(items[1].containsKey('text'), isFalse);
  });

  test('框超出画布截掉,写反的摆正,没面积的不要,代码块外壳去掉', () {
    final l = parseMossLayout(
      '```json\n{"items": ['
      '{"label": "bogus", "bbox": [600, 500, -700, -10]},'
      '{"bbox": [0, 0, 0, 100]}'
      ']}\n```',
      width: 832,
      height: 1216,
    )!;
    expect(l.boxes, hasLength(1));
    final b = l.boxes.single;
    expect((b.left, b.top, b.right, b.bottom), (406, 0, 832, 1208));
    expect(b.label, 'object');
    expect(parseMossLayout('不是 JSON', width: 64, height: 64), isNull);
  });

  test('模型写坏的 JSON 能修就修:漏了 summary 的右括号、多余逗号、前后带话', () {
    // DeepSeek 实际写出来的样子:summary 没收尾,items 落进了 summary,整份少一个 }。
    const missing = '''
{
  "summary": {
    "canvas": "single",
    "caption": "Two girls. She says \\"hi\\" {not a brace}.",
    "items": [
      {"name": "左", "label": "character", "caption": "a", "bbox": [-100, -100, 100, 0]},
      {"name": "右", "label": "character", "caption": "b", "bbox": [-100, 0, 100, 100]}
    ],
    "bbox_coord_space": "abs_centralized",
    "bbox_format": "yxyx"
  }''';
    final fixed = parseMossLayout(missing, width: 400, height: 400)!;
    expect(fixed.boxes.map((b) => b.name), ['左', '右']);
    expect(fixed.caption, 'Two girls. She says "hi" {not a brace}.');

    final commas = parseMossLayout(
      '这是布局:\n{"summary": {"caption": "x",}, '
      '"items": [{"bbox": [0, 0, 10, 10],},],}\n以上。',
      width: 400,
      height: 400,
    )!;
    expect(commas.boxes, hasLength(1));
    expect(commas.caption, 'x');

    expect(parseMossLayout('不是 JSON', width: 400, height: 400), isNull);
  });

  test('草稿格式(abs + xyxy):从左上角量;给 Agent 的草稿读回来和原来一样', () {
    final l = parseMossLayout(
      '{"width": 832, "height": 1216, "items": [{"bbox": [100, 200, 300, 400]}],'
      ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}',
      width: 832,
      height: 1216,
    )!;
    final b = l.boxes.single;
    expect((b.left, b.top, b.right, b.bottom), (100, 200, 300, 400));

    final official = parseMossLayout(_official, width: 1024, height: 1024)!;
    final draft = mossLayoutJson(official, draft: true);
    expect(draft, contains('"bbox_coord_space": "abs"'));
    final back = parseMossLayout(draft, width: 1024, height: 1024)!;
    // 交出去的仍是官方格式,坐标一点不差。
    expect(mossLayoutJson(back), mossLayoutJson(official));
    expect(mossLayoutJson(back), isNot(contains('"width"')));
  });

  test('读的时候改掉的地方都记下来:超出画布的、读不了的、没面积的;差一像素不算', () {
    final read = readMossLayout(
      '{"items": ['
      '{"name": "甲", "bbox": [-10, 0, 50, 50]},'
      '{"bbox": [0, 0, 100.6, 100]},'
      '{"name": "乙", "bbox": [1, 2, 3]},'
      '{"bbox": [10, 10, 10, 50]}'
      '], "bbox_coord_space": "abs", "bbox_format": "xyxy"}',
      width: 100,
      height: 100,
    )!;
    expect(read.layout.boxes, hasLength(2));
    expect(read.fixes, [
      (item: 1, name: '甲', clipped: true),
      (item: 3, name: '乙', clipped: false),
      (item: 4, name: '', clipped: false),
    ]);
  });

  test('接上漏写的名字和层:先按名字,块数没变时按位置,不按先后', () {
    const a = LayoutBox(left: 0, top: 0, right: 100, bottom: 100, name: '左');
    const b = LayoutBox(left: 500, top: 0, right: 600, bottom: 100, name: '右');
    final old = [a.copyWith(layer: 'front'), b.copyWith(layer: 'back')];
    // Agent 把两块的先后换了,名字都漏了,位置略有挪动。
    final swapped = inheritNames(old, [
      const LayoutBox(left: 510, top: 0, right: 610, bottom: 100),
      const LayoutBox(left: 10, top: 0, right: 110, bottom: 100),
    ], keepLayers: true);
    expect(swapped.map((x) => (x.name, x.layer)), [
      ('右', 'back'),
      ('左', 'front'),
    ]);
    // 块数变了:写了名字的照名字接层,没写名字的新块不乱认。
    final more = inheritNames(old, [
      const LayoutBox(left: 0, top: 0, right: 10, bottom: 10, name: '右'),
      const LayoutBox(left: 0, top: 0, right: 10, bottom: 10),
      const LayoutBox(left: 0, top: 0, right: 10, bottom: 10),
    ], keepLayers: true);
    expect(more.map((x) => (x.name, x.layer)), [
      ('右', 'back'),
      ('', defaultLayer),
      ('', defaultLayer),
    ]);
    // Agent 写了 layer 时用它写的。
    final own = inheritNames(old, [
      a.copyWith(layer: 'middle'),
      b.copyWith(layer: 'middle'),
    ], keepLayers: false);
    expect(own.map((x) => x.layer), ['middle', 'middle']);
  });

  test('画布边长对齐到设置的倍数,并留在范围里', () {
    expect(snapLayoutSide(830, 16), 832);
    expect(snapLayoutSide(1200, 16), 1200);
    expect(snapLayoutSide(1207, 16), 1200);
    expect(snapLayoutSide(1207, 1), 1207);
    expect(snapLayoutSide(830, 64), 832);
    // 贴着两头时也取范围里的倍数。
    expect(snapLayoutSide(10, 100), 100);
    expect(snapLayoutSide(5000, 100), 4000);
    expect(snapLayoutSide(2100, 16, max: 2048), 2048);
    expect(snapLayoutSide(10, 16), minLayoutSide);
    expect(snapLayoutSide(5000, 16), maxLayoutSide);
  });

  test('画板:放上去时改掉的地方写进给 Agent 的系统提示,画板再改过就不提了', () {
    final board = LayoutBoard()..setSize(400, 400);
    expect(
      board.apply(
        '{"items": [{"name": "人", "bbox": [300, 0, 500, 100]}],'
        ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}',
      ),
      isTrue,
    );
    expect(board.layout.boxes.single.right, 400);
    expect(board.fixes, hasLength(1));
    expect(board.prompt, contains('第 1 项「人」超出画布'));
    board.setSummary(caption: 'x');
    expect(board.fixes, isEmpty);
    expect(board.prompt, isNot(contains('超出画布')));
  });

  test('锁定:存得住,Agent 重写布局时接上,交出去的 JSON 里没有', () {
    final board = LayoutBoard()..setSize(400, 400);
    const json =
        '{"items": [{"name": "人", "bbox": [0, 0, 200, 200]}],'
        ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}';
    board.apply(json);
    board.select(0);
    board.setLocked(0, true);
    expect(board.selected, isNull);
    final box = board.layout.boxes.single;
    expect(box.locked, isTrue);
    expect(LayoutBox.fromJson(box.toJson())!.locked, isTrue);
    board.apply(json);
    expect(board.layout.boxes.single.locked, isTrue);
    expect(board.json, isNot(contains('locked')));
    board.setLocked(0, false);
    expect(board.layout.boxes.single.toJson(), isNot(contains('locked')));
  });

  test('画板:用户画了还没写描述的框,给 Agent 的提示里点名它们不能动', () {
    final board = LayoutBoard()
      ..addBox(const LayoutBox(left: 0, top: 0, right: 100, bottom: 100))
      ..addBox(
        const LayoutBox(
          left: 0,
          top: 120,
          right: 100,
          bottom: 200,
          caption: 'a cat',
        ),
      );
    // 只点名没写描述的那块(第 1 块写了 a cat)。
    expect(board.prompt, contains('【画好的框】第 2 块是'));
    board.updateBox(1, board.layout.boxes[1].copyWith(caption: 'a dog'));
    expect(board.prompt, isNot(contains('【画好的框】')));
  });

  test('画板:Agent 写的画布宽高和画板一横一竖时对调;别的比例不认,框缩放到画布上', () {
    final board = LayoutBoard()..setPerspective(1);
    expect(board.prompt, contains('竖构图'));
    expect(
      board.apply(
        '{"width": 1216, "height": 832, "items": ['
        '{"name": "签名", "bbox": [980, 690, 1160, 780]},'
        '{"name": "人", "bbox": [480, 10, 1216, 832]}],'
        ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}',
      ),
      isTrue,
    );
    expect((board.layout.width, board.layout.height), (1216, 832));
    expect(board.layout.boxes, hasLength(2));
    expect(board.fixes, isEmpty);
    expect(board.layout.perspective!.horizon, 416);
    expect(board.prompt, contains('横构图'));

    // 写了别的比例:画布不变,框从它写的尺寸缩放过来。
    board.apply(
      '{"width": 1000, "height": 1000, "items": [{"bbox": [0, 0, 500, 1000]}],'
      ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}',
    );
    expect((board.layout.width, board.layout.height), (1216, 832));
    expect(
      (board.layout.boxes.single.right, board.layout.boxes.single.bottom),
      (608, 832),
    );

    // 照参考图写成 1216×684、框却是 0–1000 的比例坐标(Gemini 看图的习惯):
    // 画布不变,按 1000×1000 换算,不截掉。
    board.apply(
      '{"width": 1216, "height": 684, "items": ['
      '{"name": "人", "bbox": [374, 34, 628, 850]},'
      '{"name": "桌", "bbox": [583, 626, 999, 999]}],'
      ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}',
    );
    expect((board.layout.width, board.layout.height), (1216, 832));
    expect(board.fixes, isEmpty);
    final desk = board.layout.boxes.firstWhere((b) => b.name == '桌');
    expect((desk.right, desk.bottom), (1215, 831));

    // 照参考图量的 ref1000:没写宽高、框也没出界,照样按比例拉到画布上,贴边的还贴边。
    board.apply(
      '{"items": [{"name": "头", "bbox": [300, 80, 1000, 1000]},'
      '{"name": "日期", "bbox": [0, 0, 500, 60]}],'
      ' "bbox_coord_space": "ref1000", "bbox_format": "xyxy"}',
    );
    expect((board.layout.width, board.layout.height), (1216, 832));
    final head = board.layout.boxes.firstWhere((b) => b.name == '头');
    expect(
      (head.left, head.top, head.right, head.bottom),
      (365, 67, 1216, 832),
    );
    expect(board.fixes, isEmpty);

    // 只稍微画出界的照常截掉,不当成比例坐标。
    board.apply(
      '{"width": 1216, "height": 832, "items": [{"bbox": [0, 0, 300, 860]}],'
      ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}',
    );
    expect(board.layout.boxes.single.bottom, 832);
    expect(board.fixes.single.clipped, isTrue);

    // 没写或写得离谱时用画板原来的尺寸。
    board.apply(
      '{"width": 5, "height": 832, "items": [{"bbox": [0, 0, 10, 10]}],'
      ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}',
    );
    expect((board.layout.width, board.layout.height), (1216, 832));
  });

  test('拆 <layout>:写完的取出来,写到一半的不显示', () {
    final done = splitLayout('排好了。<layout>{"items": []}</layout>');
    expect(done.prose, '排好了。');
    expect(done.json, '{"items": []}');
    expect(done.complete, isTrue);
    final half = splitLayout('排好了。<layout>{"ite');
    expect(half.prose, '排好了。');
    expect(half.complete, isFalse);
    expect(splitLayout('排好了。<lay').prose, '排好了。');

    // 开始标签上可以带页、页名、系列名,同 <draft>;属性没写完时也不露出来。
    final paged = splitLayout(
      '换了主题。<layout page="新系列" name="海报" series="小绿">{"items": []}</layout>',
    );
    expect(paged.prose, '换了主题。');
    expect(paged.json, '{"items": []}');
    expect((paged.page, paged.name, paged.series), ('新系列', '海报', '小绿'));
    final opening = splitLayout('换了主题。<layout page="新系');
    expect(
      (opening.prose, opening.json, opening.complete),
      ('换了主题。', '', false),
    );

    // 发回给模型时整个换成一句话;查资料那条里的照实说没放上去。
    final reply = '<layout page="2">{"items": []}</layout>';
    expect(forgetLayouts(reply), contains('已放到画板上'));
    expect(forgetLayouts(reply, placed: false), contains('没有放到画板上'));
    expect(forgetLayouts(reply), isNot(contains('<layout')));
  });

  test('区域控制分页:每页一张布局,换页换画板;Agent 换主题时另起系列,旧的布局留着', () async {
    // 旧版只有一张画板:头一回对上时收进眼前这一页。
    final board = LayoutBoard()
      ..addBox(
        const LayoutBox(left: 0, top: 0, right: 100, bottom: 100, name: '旧'),
      );
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final seen = <List<Map<String, String>>>[];
    final replies = [
      '换成小绿。<layout page="新系列" name="海报" series="小绿">'
          '{"width": 832, "height": 1216, "items": [{"name": "小绿", "bbox": [100, 100, 500, 1100]}],'
          ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}</layout>',
      '再来一版。<layout page="新">'
          '{"width": 832, "height": 1216, "items": [{"name": "另一版", "bbox": [0, 0, 400, 400]}],'
          ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}</layout>',
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

    expect(chat.send('角色换成小绿'), isNull);
    await pumpEventQueue();
    expect(seen.first.first['content'], contains('【分页】'));
    expect(chat.pages, hasLength(2));
    expect(chat.pages.first.blocks.single.text, contains('"name":"旧"'));
    expect(chat.seriesName(chat.series), '小绿');
    expect(chat.pages[chat.pageIndex].name, '海报');
    expect(board.layout.boxes.single.name, '小绿');
    expect(chat.messages.last.toolSummary, contains('「小绿」第 1 页'));
    // 换主题的对话跟着到了新系列。
    expect(chat.messages.first.text, '角色换成小绿');

    expect(chat.send('再来一版'), isNull);
    await pumpEventQueue();
    expect(chat.seriesLength, 2);
    expect(board.layout.boxes.single.name, '另一版');
    // 同系列的其他页列给 Agent 看。
    expect(seen.last.first['content'], contains('小绿'));

    // 画板上改的写回眼前这一页;换页时画板换成那一页的布局。
    board.updateBox(0, board.layout.boxes.single.copyWith(right: 300));
    chat.openPage(0);
    expect(board.layout.boxes.single.name, '旧');
    chat.openPage(2);
    expect(board.layout.boxes.single.right, 300);

    // 存盘读回,页里的布局都在。
    final again = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (_) => const Stream.empty(),
    )..restore(jsonDecode(jsonEncode(chat.toJson())) as Map<String, dynamic>);
    again.openPage(1);
    expect(board.layout.boxes.single.name, '小绿');
  });

  test('读旧版的布局对话存档(页是空的):画板上已有的布局收进眼前这页,不被清掉', () {
    final board = LayoutBoard()
      ..addBox(
        const LayoutBox(left: 0, top: 0, right: 10, bottom: 10, name: '旧'),
      );
    final chat =
        StudioViewModel(
          config: tempConfig(),
          layout: board,
          layoutOnly: true,
          streamChat: (_) => const Stream.empty(),
        )..restore({
          'pages': [
            {'series': 0, 'blocks': []},
          ],
          'page': 0,
        });
    expect(board.layout.boxes.single.name, '旧');
    expect(chat.body, contains('"name":"旧"'));
  });

  test('参考图:Agent 照图写了别的比例时等比摆进画布正中,贴边的撑满;发图那条带上画布尺寸', () async {
    final board = LayoutBoard();
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final seen = <List<Map<String, String>>>[];
    final chat = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (request) {
        seen.add(request.messages);
        return Stream.value(
          seen.length > 1
              ? '好的。'
              : '<layout>{"width": 832, "height": 1056, "items": ['
                    '{"name": "人", "bbox": [200, 150, 800, 950]},'
                    '{"name": "背景", "layer": "back", "bbox": [0, 0, 832, 1056]}],'
                    ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}</layout>',
        );
      },
    );
    final image = Attachment.image(
      name: 'ref.png',
      mime: 'image/png',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(chat.send('参考这张', attachments: [image]), isNull);
    await pumpEventQueue();
    // 发图的那条后面带着画布尺寸;存下来的消息不带。
    expect(seen.first.last['content'], contains('程序提示:画布是 832×1216'));
    expect(chat.messages.first.text, '参考这张');

    // 画布不变;人等比放进正中(上下各让出 80),背景撑满。
    expect((board.layout.width, board.layout.height), (832, 1216));
    final person = board.layout.boxes.firstWhere((b) => b.name == '人');
    expect(
      (person.left, person.top, person.right, person.bottom),
      (200, 230, 800, 1030),
    );
    final back = board.layout.boxes.firstWhere((b) => b.name == '背景');
    expect((back.top, back.bottom), (0, 1216));
    expect(chat.messages.last.toolSummary, contains('832×1056 → 832×1216'));

    // 下一轮告诉 Agent 它上次写的尺寸不对;不带图的消息不加提示。
    expect(chat.send('再改改'), isNull);
    await pumpEventQueue();
    expect(seen.last.first['content'], contains('832×1056,和画布 832×1216 对不上'));
    expect(seen.last.last['content'], '再改改');
  });

  test('写在查资料那条回复里的布局,发回给模型时说没放上去', () async {
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final seen = <List<Map<String, String>>>[];
    final t = DateTime(2026);
    final chat = StudioViewModel(
      config: service,
      layout: LayoutBoard(),
      layoutOnly: true,
      messages: [
        ChatMessage(fromUser: true, text: '换成阿米娅', time: t),
        ChatMessage(
          fromUser: false,
          text: '<search-character>阿米娅</search-character><layout>{"items": []}</layout>',
          time: t,
        ),
        ChatMessage(fromUser: true, text: '【角色库查询结果】…', time: t, tool: true),
        ChatMessage(
          fromUser: false,
          text: '<layout>{"items": []}</layout>',
          time: t,
        ),
      ],
      streamChat: (request) {
        seen.add(request.messages);
        return Stream.value('好的。');
      },
    );
    expect(chat.send('没在画布上啊'), isNull);
    await pumpEventQueue();
    final sent = seen.single;
    expect(sent[2]['content'], contains('没有放到画板上'));
    expect(sent[4]['content'], contains('已放到画板上'));
    expect(sent.first['content'], contains('不要照抄'));
  });

  test('画板:换尺寸时框跟着缩放,对调,存尺寸,存盘读回', () async {
    final dir = Directory.systemTemp.createTempSync('penna_layout');
    final board = LayoutBoard(dir: dir)
      ..addBox(const LayoutBox(left: 0, top: 0, right: 416, bottom: 608));
    expect(board.setSize(10, 10), isFalse);
    board.swap();
    expect((board.layout.width, board.layout.height), (1216, 832));
    expect(board.layout.boxes.single.right, 608);
    expect(board.layout.boxes.single.bottom, 416);
    board
      ..saveSize()
      ..setSummary(caption: 'sunset')
      ..dispose();
    final again = LayoutBoard(dir: dir);
    await again.load();
    expect(again.layout.caption, 'sunset');
    expect(again.layout.boxes.single.right, 608);
    expect(again.sizes, contains((width: 1216, height: 832)));
  });

  test('画板:layout.json 读不了时改名留底,从空画板开始', () async {
    final dir = Directory.systemTemp.createTempSync('penna_layout');
    File('${dir.path}/layout.json').writeAsStringSync('{坏的');
    final board = LayoutBoard(dir: dir);
    await board.load();
    expect(board.layout.boxes, isEmpty);
    final names = dir.listSync().map((f) => f.uri.pathSegments.last);
    expect(names.where((n) => n.startsWith('layout.json.bad-')), hasLength(1));
    expect(names, isNot(contains('layout.json')));
    dir.deleteSync(recursive: true);
  });

  test('图层和透视:存盘读回;Agent 漏写 layer 时沿用,透视线留着;都说给模型听', () {
    final board = LayoutBoard()
      ..addBox(
        const LayoutBox(left: 0, top: 0, right: 100, bottom: 100, name: '人'),
      )
      ..updateBox(
        0,
        const LayoutBox(
          left: 0,
          top: 0,
          right: 100,
          bottom: 100,
          name: '人',
          layer: 'front',
        ),
      )
      ..setPerspective(3);
    final again = Layout.fromJson(board.layout.toJson());
    expect(again.boxes.single.layer, 'front');
    expect(again.perspective!.points, 3);
    // 交出去的 JSON 不带 layer,给 Agent 的带。
    expect(board.json, isNot(contains('layer')));
    expect(board.prompt, contains('"layer": "front"'));
    expect(board.prompt, contains('前景'));
    expect(board.prompt, contains('【透视辅助】'));

    expect(
      board.apply(
        '{"summary": {"caption": "x"}, "items": [{"label": "object", '
        '"caption": "y", "bbox": [-600, -400, -500, -300]}]}',
      ),
      isTrue,
    );
    expect(board.layout.boxes.single.layer, 'front');
    expect(board.layout.boxes.single.name, '人');
    expect(board.layout.perspective, isNotNull);

    // 拖地平线上的消失点,地平线跟着走(能拖到画面外);换尺寸时跟着缩放。
    board.moveVanishing(0, -40, 300);
    final p = board.layout.perspective!;
    expect((p.xs.first, p.horizon), (-40, 300));
    board.swap();
    expect(board.layout.perspective!.horizon, (300 * 832 / 1216).round());
    board.setPerspective(null);
    expect(board.prompt, contains('【透视辅助】现在关着'));
  });

  test('<perspective>:按画布像素读 [x, y] 的点,能放到画面外,off 是关掉;写到一半的不显示', () {
    final p = parsePerspective(
      '{"vanishing": [[100, 1000], [950, 1000]], "third": [500, -800]}',
      1000,
      2000,
    )!;
    expect(p.off, isFalse);
    expect(p.value!.horizon, 1000);
    expect(p.value!.xs, [100, 950]);
    expect(p.value!.third, (x: 500, y: -800));
    expect(Perspective.fromJson(p.value!.toJson())!.spec, p.value!.spec);
    // 两个点写得不一样高,地平线取平均。
    expect(
      parsePerspective(
        '{"vanishing": [[0, 100], [10, 200]]}',
        1000,
        1000,
      )!.value!.horizon,
      150,
    );
    // 只有一个点时可以不套外面那层;带 horizon 的一串数是地平线上各点的 x。
    final one = parsePerspective('{"vanishing": [450, 85]}', 832, 1216)!;
    expect((one.value!.xs.single, one.value!.horizon), (450, 85));
    final flat = parsePerspective(
      '{"horizon": 600, "vanishing": [10, 800]}',
      832,
      1216,
    )!;
    expect(flat.value!.xs, [10, 800]);
    expect(flat.value!.horizon, 600);
    // 太远的截到画布边长的 -3 / 4 倍。
    expect(
      parsePerspective('{"vanishing": [[99999, 50]]}', 100, 100)!.value!.xs,
      [400],
    );
    expect(parsePerspective(' off ', 100, 100)!.off, isTrue);
    expect(parsePerspective('{"horizon": 50}', 100, 100), isNull);
    expect(parsePerspective('{"vanishing": []}', 100, 100), isNull);
    expect(parsePerspective('{"vanishing": [1, 2, 3]}', 100, 100), isNull);

    final done = splitPerspective('调好了。<perspective>off</perspective>');
    expect((done.prose, done.spec), ('调好了。', 'off'));
    final half = splitPerspective('调好了。<persp');
    expect((half.prose, half.spec), ('调好了。', null));
    expect(splitPerspective('调好了。<perspective>{"hor').spec, isNull);
  });

  test('布局对话:Agent 写了 <perspective> 就改画板的透视线,下一轮不重发旧的数', () async {
    final board = LayoutBoard();
    final seen = <List<Map<String, String>>>[];
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final replies = [
      '照参考图调了透视。<perspective>{"vanishing": [[166, 912], [666, 912]]}</perspective>',
      '好的。',
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
    expect(chat.send('照这张图的透视'), isNull);
    await pumpEventQueue();
    expect(seen.first.first['content'], contains('【透视辅助】现在关着'));
    final p = board.layout.perspective!;
    expect((p.points, p.horizon), (2, 912));
    expect(chat.messages.last.toolSummary, contains('2 点透视'));

    expect(chat.send('再说说'), isNull);
    await pumpEventQueue();
    expect(seen.last[2]['content'], isNot(contains('"vanishing"')));
    expect(seen.last[2]['content'], isNot(contains('<perspective>')));
    expect(seen.last.first['content'], contains('2 点透视'));
    expect(
      seen.last.first['content'],
      contains('"vanishing":[[166,912],[666,912]]'),
    );
  });

  test('图层顺序:第 1 个在最前;拖动换前后时前中后景跟着落点变;改层时选中跟着走', () {
    LayoutBox box(String name, String layer) => LayoutBox(
      left: 0,
      top: 0,
      right: 10,
      bottom: 10,
      name: name,
      layer: layer,
    );
    String order(LayoutBoard b) =>
        b.layout.boxes.map((x) => '${x.name}${x.layer[0]}').join(' ');
    final board = LayoutBoard()
      ..addBox(box('山', 'back'))
      ..addBox(box('甲', 'middle'))
      ..addBox(box('乙', 'middle'))
      ..addBox(box('字', 'front'));
    // 前景在前、后景在后;同一层里新加的在最前。
    expect(order(board), '字f 乙m 甲m 山b');
    expect(board.selected, 0);

    // 后景的「山」拖到「乙」和「甲」之间:夹在两个中景之间,成了中景。
    board.move(3, 2);
    expect(order(board), '字f 乙m 山m 甲m');
    expect(board.selected, 2);
    // 拖到最前面:成了前景。
    board.move(2, 0);
    expect(order(board), '山f 字f 乙m 甲m');

    // 把「甲」改成前景:挪到前景那一组里,选中的跟着它。
    board
      ..select(3)
      ..updateBox(3, board.layout.boxes[3].copyWith(layer: 'front'));
    expect(order(board), '山f 字f 甲f 乙m');
    expect(board.layout.boxes[board.selected!].name, '甲');

    // Agent 写回来的 JSON 也按前后排好,画板存的旧数据读回来也一样。
    expect(stacked([box('a', 'back'), box('b', 'front')]).first.name, 'b');
    expect(board.prompt, contains('1 在最前面'));
  });

  test('<layers>:Agent 只调图层的先后、名字和前中后景,位置和描述不动', () async {
    expect(parseLayers('[{"from": 2, "name": " 甲 "}, {"from": 1}]'), [
      (from: 2, name: '甲', layer: null),
      (from: 1, name: null, layer: null),
    ]);
    expect(parseLayers('[{"from": 1, "layer": "top"}]'), isNull);
    expect(parseLayers('不是 JSON'), isNull);
    expect(parseLayers('[]'), isNull);
    final half = splitLayers('调好了。<layers>[{"fr');
    expect((half.prose, half.spec), ('调好了。', null));

    final board = LayoutBoard();
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    for (final (i, n) in ['人', '树', '字'].indexed) {
      board.addBox(
        LayoutBox(
          left: i * 10,
          top: 0,
          right: i * 10 + 10,
          bottom: 10,
          name: n,
          caption: '$n 的描述',
        ),
      );
    }
    // 都是中景,新加的在前:字、树、人。
    final before = {for (final b in board.layout.boxes) b.name: b};
    final seen = <List<Map<String, String>>>[];
    final chat = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (request) {
        seen.add(request.messages);
        return Stream.value(
          seen.length == 1
              ? '把人放到最前。<layers>[{"from": 3, "name": "主角", "layer": "front"},'
                    ' {"from": 1}, {"from": 2, "layer": "back"}]</layers>'
              : '好的。',
        );
      },
    );
    expect(chat.send('人放最前,改名主角,树放后面'), isNull);
    await pumpEventQueue();
    final boxes = board.layout.boxes;
    expect(boxes.map((b) => '${b.name}${b.layer[0]}').join(' '), '主角f 字m 树b');
    expect(boxes.first.left, before['人']!.left);
    expect(boxes.first.caption, '人 的描述');
    expect(chat.messages.last.toolSummary, contains('已调整图层'));
    expect(chat.messages.last.text, contains('<layers>'));

    // 下一轮不重发旧的 <layers>。
    expect(chat.send('好'), isNull);
    await pumpEventQueue();
    expect(seen.last[2]['content'], isNot(contains('<layers>')));
    // 序号对不上的不收,画板不动。
    expect(board.applyLayers([(from: 9, name: null, layer: null)]), isFalse);
  });

  test('参考图和画布一横一竖时给出对调后的尺寸', () async {
    final board = LayoutBoard();
    Uint8List png(int w, int h) =>
        img.encodePng(img.Image(width: w, height: h));
    expect(await board.swapFor(png(30, 20)), (width: 1216, height: 832));
    expect(await board.swapFor(png(20, 30)), isNull);
    expect(await board.swapFor(png(20, 20)), isNull);
    expect(await board.swapFor(Uint8List(3)), isNull);
  });

  testWidgets('画布上单击选中并告诉属性栏,双击去改,Delete 删掉', (tester) async {
    final board = LayoutBoard()
      ..setSize(100, 200)
      ..addBox(const LayoutBox(left: 0, top: 0, right: 50, bottom: 50))
      ..select(null);
    final picked = <int>[], edited = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 400,
            child: LayoutCanvas(
              board: board,
              onPick: picked.add,
              onEdit: edited.add,
            ),
          ),
        ),
      ),
    );
    final at =
        tester.getTopLeft(find.byType(LayoutCanvas)) + const Offset(40, 40);
    // 双击靠按下时的时间戳判断,测试里自己给。
    final g = await tester.createGesture();
    await g.down(at, timeStamp: const Duration(seconds: 1));
    await g.up();
    await tester.pump();
    expect(board.selected, 0);
    expect(picked, [0]);
    expect(edited, isEmpty);

    // 隔得久的第二下不算双击;紧跟着的第三下算。
    final g2 = await tester.createGesture();
    await g2.down(at, timeStamp: const Duration(seconds: 5));
    await g2.up();
    await tester.pump();
    expect(edited, isEmpty);
    final g3 = await tester.createGesture();
    await g3.down(at, timeStamp: const Duration(seconds: 5, milliseconds: 100));
    await g3.up();
    await tester.pump();
    expect(edited, [0]);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(board.layout.boxes, isEmpty);
  });

  testWidgets('画布上拖出一个框,再拖着它挪动、拉右下角改大小', (tester) async {
    // 画布 100×200 画在 200×400 的地方:屏幕上 2 个点是画布 1 个像素。
    final board = LayoutBoard()..setSize(100, 200);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 400,
            child: LayoutCanvas(board: board),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(LayoutCanvas));
    Future<void> drag(Offset from, Offset by) async {
      await tester.dragFrom(origin + from, by);
      await tester.pump();
    }

    await drag(const Offset(20, 20), const Offset(80, 100));
    var b = board.layout.boxes.single;
    expect((b.left, b.top, b.right, b.bottom), (10, 10, 50, 60));
    expect(board.selected, 0);

    await drag(const Offset(60, 60), const Offset(20, 40));
    b = board.layout.boxes.single;
    expect((b.left, b.top, b.right, b.bottom), (20, 30, 60, 80));

    // 右下角在屏幕 (120, 160)。
    await drag(const Offset(120, 160), const Offset(40, 400));
    b = board.layout.boxes.single;
    expect((b.left, b.top, b.right, b.bottom), (20, 30, 80, 200));

    // 太小的不算。
    await drag(const Offset(180, 380), const Offset(4, 4));
    expect(board.layout.boxes, hasLength(1));
  });

  test('布局页的对话:系统提示只讲布局,回复里的布局放到画板,接着改时带着历史', () async {
    final board = LayoutBoard();
    final seen = <List<Map<String, String>>>[];
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final named = _official.replaceFirst(
      '"label": "text"',
      '"name": "标题", "label": "text"',
    );
    final replies = [
      '排好了。<layout>$named</layout>',
      // 没写 name、还顺手写了成稿:名字按位置接上,成稿不理。
      '改好了。<layout>$_official</layout><draft>【主体】x</draft>',
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
    expect(chat.send('旅行海报'), isNull);
    await pumpEventQueue();
    final system = seen.first.first['content']!;
    expect(system, contains('布局助手'));
    expect(system, contains('bbox_format'));
    expect(system, contains('【布局画板】画布 832×1216'));
    expect(system, isNot(contains('<draft> 和 </draft> 之间')));
    expect(board.layout.boxes, hasLength(2));
    expect(board.layout.boxes.first.name, '标题');
    expect(chat.messages.last.toolSummary, contains('2'));

    // 用户在两轮之间手动挪了标题框。
    board.updateBox(
      0,
      board.layout.boxes.first.copyWith(
        left: 0,
        top: 0,
        right: 416,
        bottom: 608,
      ),
    );
    chat.quoteSection('【标题】text · x 0 y 0 · 10×10');
    expect(chat.send('再大一点'), isNull);
    await pumpEventQueue();
    // 上一轮自己写的旧坐标不重发,画板此刻的位置在系统提示里。
    expect(seen.last[2]['content'], isNot(contains('bbox')));
    expect(seen.last[2]['content'], contains('现在的样子看【布局画板】'));
    // 标签本身也不留:留着的话模型会照样子把那句说明当成布局写回来。
    expect(seen.last[2]['content'], isNot(contains('<layout>')));
    expect(seen.last.first['content'], contains('横向 0%–50%,纵向 0%–50%'));
    // 给 Agent 的现有布局是草稿格式:左上角原点,不用它换算。
    expect(seen.last.first['content'], contains('"bbox_coord_space": "abs"'));
    expect(seen.last.first['content'], contains('"width": 832'));
    expect(seen.last.first['content'], isNot(contains('-608')));
    // 第二轮带着上一轮;选中的那块随消息发出,系统提示里是带名字的现有布局。
    expect(seen.last.map((m) => m['role']), [
      'system',
      'user',
      'assistant',
      'user',
    ]);
    expect(seen.last.last['content'], contains('布局里的这一块'));
    expect(seen.last.first['content'], contains('"name": "标题"'));
    expect(board.layout.boxes.first.name, '标题');
    // 区域控制那场对话的每一页存的就是这一页的布局。
    expect(chat.body, contains('"name":"标题"'));
    // 交出去的 JSON 不带 name:官方格式不认。
    expect(board.json, isNot(contains('"name"')));
  });

  test('Agent 写的 <layout> 回复说完后放到画板上,系统提示里有画布尺寸', () async {
    final board = LayoutBoard();
    final sent = <String>[];
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final vm = StudioViewModel(
      config: service,
      layout: board,
      streamChat: (request) {
        sent.add(request.messages.first['content']!);
        return Stream.value('排好了。<layout>$_official</layout>');
      },
    );
    expect(vm.send('做一张海报'), isNull);
    await pumpEventQueue();
    expect(sent.single, contains('【布局画板】画布 832×1216'));
    expect(board.layout.boxes, hasLength(2));
    expect(vm.messages.last.toolSummary, contains('2'));
    expect(vm.messages.last.toolSummary, isNot(contains('画布换成')));
  });

  test('Agent 换了横构图:画布跟着换,回复的记录上写一句', () async {
    final board = LayoutBoard();
    final service = tempConfig();
    service.update(
      service.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final vm = StudioViewModel(
      config: service,
      layout: board,
      layoutOnly: true,
      streamChat: (_) => Stream.value(
        '换成横的了。<layout>{"width": 1216, "height": 832, "items": '
        '[{"bbox": [700, 60, 1020, 832]}], "bbox_coord_space": "abs", '
        '"bbox_format": "xyxy"}</layout>',
      ),
    );
    expect(vm.send('横构图'), isNull);
    await pumpEventQueue();
    expect((board.layout.width, board.layout.height), (1216, 832));
    expect(board.layout.boxes.single.right, 1020);
    expect(vm.messages.last.toolSummary, contains('画布换成 1216×832'));
    expect(vm.messages.last.toolSummary, isNot(contains('截掉')));
  });
}

void _regionTests() {
  test('布局 JSON 按功能区切出位置:整体和每一块,字符串里的括号不算', () {
    const text =
        '{"summary": {"caption": "a {curly} [x] \\"q\\""},'
        ' "items": [{"name": "标题", "label": "text", "text": "HI", "bbox": [1, 2, 3, 4]},'
        ' {"label": "object", "caption": "}", "bbox": [5, 6, 7, 8]}],'
        ' "bbox_coord_space": "abs_centralized", "bbox_format": "yxyx"}';
    final r = layoutJsonRegions(text)!;
    expect(r.map((x) => x.item), [-1, 0, 1]);
    expect(text.substring(r[0].start, r[0].end), startsWith('{"caption"'));
    expect(text.substring(r[1].start, r[1].end), endsWith('[1, 2, 3, 4]}'));
    expect(text.substring(r[2].start, r[2].end), endsWith('[5, 6, 7, 8]}'));
    expect((r[1].name, r[1].label, r[1].text), ('标题', 'text', 'HI'));
    expect(layoutJsonRegions('【主体】a girl'), isNull);
    expect(layoutJsonRegions('{"items": []}'), isNull);
  });

  testWidgets('成稿是布局 JSON 时按功能区分框显示,点编辑换回一整块输入框', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final json = mossLayoutJson(
      parseMossLayout(_official, width: 1024, height: 1024)!,
    );
    final vm = StudioViewModel(
      config: tempConfig(),
      streamChat: (_) => const Stream.empty(),
      blocks: [(text: json, pinned: false)],
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(vm: vm, config: vm.config, skills: tempSkills()),
      ),
    );
    // 布局页的 JSON 卡片也这样显示:只看工作台的。
    Finder inStudio(Finder f) =>
        find.descendant(of: find.byType(StudioPage), matching: f);
    expect(inStudio(find.text('整体')), findsOneWidget);
    expect(inStudio(find.text('1 · 文字 「EXPLORE」')), findsOneWidget);
    expect(inStudio(find.text('2 · 物体')), findsOneWidget);
    await tester.tap(inStudio(find.text('编辑')));
    await tester.pump();
    expect(inStudio(find.text('整体')), findsNothing);
    // 成稿还是那一整份 JSON,没被拆成分段。
    expect(vm.body, json);
  });
}
