import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/local/local_tools.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/archive_store.dart';
import 'package:penna/ui/features/archive/archive_page.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/local/local_model.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

final _image = Attachment.image(
  name: 'a.png',
  mime: 'image/png',
  bytes: Uint8List.fromList([1, 2, 3]),
);

void main() {
  group('Agent 调本地反推', () {
    test('拆出反推和下载两种标签,按先后;半截的先不显示', () {
      final r = splitLocalTools(
        '好的\n<reverse-image kind="tag">[WD14] eva02-large v3</reverse-image>'
        '<download-model kind="runtime"></download-model>',
      );
      expect(r.prose, '好的');
      expect(r.calls, [
        (action: toolReverse, kind: 'tag', model: '[WD14] eva02-large v3'),
        (action: toolDownload, kind: 'runtime', model: ''),
      ]);
      expect(splitLocalTools('稍等<reverse-im').prose, '稍等');
      expect(splitLocalTools('稍等<reverse-image kind="tag">wd').prose, '稍等');
      // 反推不认 runtime。
      expect(
        splitLocalTools('<reverse-image kind="runtime"></reverse-image>').calls,
        isEmpty,
      );
    });

    test('没装的模型:列出已装的,让模型用选项问用户;没找到、没有图也说清楚', () async {
      final local = LocalModel(streamChat: (_) => const Stream.empty());

      final missing = await local.runTool((
        action: toolReverse,
        kind: 'tag',
        model: 'eva02-large v3',
      ), _image);
      expect(missing.text, contains('「[WD14] eva02-large v3」本机还没装'));
      expect(missing.text, contains('<options>'));
      expect(missing.text, contains('<download-model kind="tag">'));
      expect(missing.note, '「[WD14] eva02-large v3」还没装');

      final unknown = await local.runTool((
        action: toolReverse,
        kind: 'nl',
        model: '不存在的模型',
      ), _image);
      expect(unknown.text, contains('没有叫「不存在的模型」的看图模型'));

      // 没装的模型先说没装,有图没图都一样;装了才看图。
      final noModel = await local.runTool((
        action: toolReverse,
        kind: 'nl',
        model: '',
      ), null);
      expect(noModel.note, '还没选看图模型');

      // 测试里没有存放的地方:下载失败也照实说。
      final failed = await local.runTool((
        action: toolDownload,
        kind: 'tag',
        model: 'eva02-large v3',
      ), null);
      expect(failed.text, contains('没跑成'));

      expect(local.agentPrompt, contains('【本地反推】'));
      expect(local.agentPrompt, contains('没装、可以下载:'));
    });

    test('对话里写了反推标签:程序跑完接上结果,模型接着说;用的是用户发的图', () async {
      final seen = <LlmRequest>[];
      var round = 0;
      final config = tempConfig()
        ..update(
          const AppConfig().putLlm(
            const LlmProfile(
              id: 'a',
              name: 'A',
              baseUrl: 'http://x',
              model: 'm',
            ),
          ),
        );
      final vm = StudioViewModel(
        config: config,
        skills: tempSkills(),
        streamChat: (req) {
          seen.add(req);
          return Stream.value(
            round++ == 0
                ? '<reverse-image kind="tag">eva02-large v3</reverse-image>'
                : '还没装,要下载吗?\n<options>\n下载\n</options>',
          );
        },
      )..local = LocalModel(streamChat: (_) => const Stream.empty());

      vm.send('用 eva02 给这张图 Tag 反推', attachments: [_image]);
      await pumpEventQueue();

      expect(seen.first.messages.first['content'], contains('【本地反推】'));
      final tool = vm.messages.firstWhere((m) => m.tool);
      expect(tool.text, contains('【本地工具的结果】'));
      expect(tool.text, contains('本机还没装'));
      expect(tool.toolSummary, contains('还没装'));
      expect(vm.messages.last.text, contains('<options>'));
      expect(vm.isStreaming, isFalse);
    });
  });

  group('主工作区把排布局转给区域控制', () {
    test('转过去:那边开一场对话写布局,JSON 放进主工作区这个系列新开的一页,不另起系列', () async {
      final config = tempConfig()
        ..update(
          const AppConfig().putLlm(
            const LlmProfile(
              id: 'a',
              name: 'A',
              baseUrl: 'http://x',
              model: 'm',
            ),
          ),
        );
      final board = LayoutBoard();
      final layoutChat = StudioViewModel(
        config: config,
        streamChat: (_) => Stream.value(
          '排好了。<layout>{"summary": {"caption": "two girls"}, "items": ['
          '{"name": "左", "label": "character", "caption": "a", '
          '"bbox": [-100, -100, 100, 0]}]}</layout>',
        ),
        layout: board,
        layoutOnly: true,
        messages: [
          ChatMessage(fromUser: true, text: '上次的话', time: DateTime(2026)),
        ],
      );
      final seen = <LlmRequest>[];
      var round = 0;
      final vm = StudioViewModel(
        config: config,
        skills: tempSkills(),
        layout: board,
        blocks: const [(text: '【主体】a fox', pinned: false)],
        streamChat: (req) {
          seen.add(req);
          return Stream.value(
            round++ == 0
                ? '<ask-layout name="双人海报">左边十四行诗,右边维尔汀</ask-layout>'
                : '排好了,放在「双人海报」里。',
          );
        },
      )..layoutAgent = layoutChat;

      vm.send('转成 JSON', attachments: [_image]);
      await pumpEventQueue(times: 50);

      // 主工作区的系统提示只讲怎么转过去,布局的写法不带。
      final system = seen.first.messages.first['content']!;
      expect(system, contains('<ask-layout'));
      expect(system, isNot(contains('怎么写描述')));

      // 区域控制那边:另起一个系列(有自己的对话),收到任务和图,写出的布局放到画板上;
      // 原来那个系列和它的对话都留着。
      expect(layoutChat.pages, hasLength(2));
      expect(layoutChat.seriesName(layoutChat.series), '双人海报');
      layoutChat.openPage(0);
      expect(layoutChat.messages.single.text, '上次的话');
      layoutChat.openPage(1);
      final task = layoutChat.messages.first;
      expect(task.text, contains('【主工作区转来的任务】左边十四行诗,右边维尔汀'));
      expect(task.attachments.single.name, 'a.png');
      expect(board.layout.boxes.single.name, '左');

      // 主工作区:还是原来那个系列,新开的一页里是交出去的 JSON,原来那页还在。
      expect(vm.pages, hasLength(2));
      expect(vm.pages[1].series, vm.pages[0].series);
      expect(vm.pages[1].name, '双人海报');
      expect(vm.pages[1].blocks.single.text, board.json);
      expect(vm.pages.first.blocks.single.text, '【主体】a fox');
      expect(
        vm.messages.firstWhere((m) => m.tool).toolSummary,
        contains('区域控制排好了 · 1 个框'),
      );
      expect(vm.messages.last.text, '排好了,放在「双人海报」里。');
      expect(vm.isStreaming, isFalse);
    });

    test('转过去时参考图是横的:不用开自动审批,新系列的画布照图对调', () async {
      final config = tempConfig()
        ..update(
          const AppConfig().putLlm(
            const LlmProfile(
              id: 'a',
              name: 'A',
              baseUrl: 'http://x',
              model: 'm',
            ),
          ),
        );
      expect(config.config.autoApprove, isFalse);
      final board = LayoutBoard();
      final asked = <LlmRequest>[];
      final layoutChat = StudioViewModel(
        config: config,
        streamChat: (req) {
          asked.add(req);
          return Stream.value(
            '<layout>{"width": 1216, "height": 832, "items": ['
            '{"name": "人", "bbox": [700, 60, 1020, 832]}],'
            ' "bbox_coord_space": "abs", "bbox_format": "xyxy"}</layout>',
          );
        },
        layout: board,
        layoutOnly: true,
      );
      var round = 0;
      final vm = StudioViewModel(
        config: config,
        skills: tempSkills(),
        layout: board,
        streamChat: (_) => Stream.value(
          round++ == 0 ? '<ask-layout name="横版">照参考图</ask-layout>' : '排好了。',
        ),
      )..layoutAgent = layoutChat;
      final wide = Attachment.image(
        name: 'wide.png',
        mime: 'image/png',
        bytes: img.encodePng(img.Image(width: 300, height: 200)),
      );

      vm.send('照这张排个布局', attachments: [wide]);
      await pumpEventQueue(times: 50);

      expect((board.layout.width, board.layout.height), (1216, 832));
      expect(board.layout.boxes.single.right, 1020);
      // 那边发图的那条里带着对调后的画布尺寸。
      expect(asked.single.messages.last['content'], contains('画布是 1216×832'));
      expect(
        vm.messages.firstWhere((m) => m.tool).toolSummary,
        contains('画布已换成 1216×832'),
      );
    });

    test('拆 <ask-layout>:名字可空,半截的不显示', () {
      final r = splitAskLayout('好的<ask-layout>排一张海报</ask-layout>');
      expect(r.prose, '好的');
      expect(r.asks, [(name: '', brief: '排一张海报')]);
      expect(splitAskLayout('稍等<ask-lay').prose, '稍等');
      expect(splitAskLayout('稍等<ask-layout name="x">排').prose, '稍等');
      // 带别的属性、name 用单引号的也认。
      expect(
        splitAskLayout("<ask-layout kind=\"json\" name='光与对立'>两个人</ask-layout>")
            .asks,
        [(name: '光与对立', brief: '两个人')],
      );
    });
  });

  group('区域控制存档', () {
    test('存进档案库的布局带着分区,重新读回来还在', () async {
      final dir = await Directory.systemTemp.createTemp('penna_archive');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/archive.json');
      ArchiveStore(file)
        ..add(text: 'a fox')
        ..add(text: '{}', kind: archiveLayout, category: '海报');
      final again = ArchiveStore(file);
      await again.load();
      expect(again.entries.map((e) => e.kind), [archiveLayout, archivePrompt]);
      expect(again.categoriesOf(archiveLayout), ['海报']);
      expect(again.categoriesOf(archivePrompt), [uncategorized]);
    });

    testWidgets('档案库「区域控制」分区里的布局放回区域控制工作台,不进主工作区', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final board = LayoutBoard();
      final vm = StudioViewModel(
        config: tempConfig(),
        streamChat: (_) => const Stream.empty(),
        layout: board,
      );
      addTearDown(vm.dispose);
      const saved = Layout(
        width: 1024,
        height: 1024,
        caption: 'a poster',
        boxes: [
          LayoutBox(
            name: '标题',
            label: 'text',
            caption: 'title',
            left: 0,
            top: 0,
            right: 1024,
            bottom: 200,
          ),
        ],
      );
      final archive = ArchiveStore()
        ..add(text: 'old cat')
        ..add(
          text: jsonEncode(saved.toJson()),
          title: '海报',
          kind: archiveLayout,
        );
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArchivePage(
              archive: archive,
              vm: vm,
              board: board,
              onOpenStudio: () {},
              onOpenLayout: () => opened = true,
            ),
          ),
        ),
      );
      expect(find.text('old cat'), findsOneWidget);
      expect(find.text('海报'), findsNothing);

      await tester.tap(find.text('区域控制'));
      await tester.pumpAndSettle();
      expect(find.text('old cat'), findsNothing);
      expect(find.text('海报'), findsOneWidget);

      await tester.tap(find.text('放到区域控制工作台'));
      await tester.pumpAndSettle();
      expect(board.layout.width, 1024);
      expect(board.layout.boxes.single.name, '标题');
      expect(vm.body, isEmpty);
      expect(opened, isTrue);
    });
  });
}
