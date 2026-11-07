import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/providers/llm_http.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/features/poses/pose_library.dart';
import 'package:penna/ui/features/poses/poses_page.dart';

import 'fixtures.dart';

/// 一个最小的图集:套了一层文件夹,两个姿势,一个是性感系列。
List<int> _pack({String image = 'images/a_front.webp'}) {
  final index = {
    'poses': [
      {
        'id': 'standing-001',
        'category': 'standing',
        'tags': ['people:1'],
        'descriptionZh': '站',
        'views': [
          {'angle': 'front', 'path': image},
          {'angle': 'side', 'path': 'images/a_side.webp'},
        ],
      },
      {
        'id': 'lying-002',
        'category': 'lying',
        'tags': ['people:1', 'sensitive:suggestive_series'],
        'views': [
          {'angle': 'front', 'path': 'images/b_front.webp'},
        ],
      },
    ],
  };
  final zip = Archive()
    ..add(ArchiveFile.string('pack/poses.json', jsonEncode(index)))
    ..add(ArchiveFile.bytes('pack/images/a_front.webp', [1, 2, 3]))
    ..add(ArchiveFile.bytes('pack/images/a_side.webp', [4]))
    ..add(ArchiveFile.bytes('pack/images/b_front.webp', [5]));
  return ZipEncoder().encode(zip);
}

void main() {
  looseTests();
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('penna-poses'));
  tearDown(() => home.deleteSync(recursive: true));

  File zipOf(List<int> bytes) =>
      File('${home.path}${Platform.pathSeparator}in.zip')
        ..writeAsBytesSync(bytes);

  test('导入套了一层文件夹的图集:读得到姿势,图片路径是完整的;重开后还在', () async {
    final lib = PoseLibrary(home);
    expect(await lib.importZip(zipOf(_pack()).path), isNull);
    expect(lib.poses, hasLength(2));
    final front = lib.poses.first.views.first.path;
    expect(File(front).readAsBytesSync(), [1, 2, 3]);
    expect(isSuggestive(lib.poses.last), isTrue);

    final again = PoseLibrary(home);
    await again.load();
    expect(again.installed, isTrue);
    await again.remove();
    expect(again.installed, isFalse);
  });

  test('索引里的路径想跳出文件夹、不是压缩包、没有索引:都拒收,原来的不动', () async {
    final lib = PoseLibrary(home);
    expect(await lib.importZip(zipOf(_pack()).path), isNull);
    expect(
      await lib.importZip(zipOf(_pack(image: '../evil.webp')).path),
      isNotNull,
    );
    expect(await lib.importZip(zipOf([1, 2, 3]).path), isNotNull);
    final empty = ZipEncoder().encode(
      Archive()..add(ArchiveFile.bytes('x.txt', [1])),
    );
    expect(await lib.importZip(zipOf(empty).path), isNotNull);
    expect(() => parsePoses({'poses': 1}, home.path), throwsFormatException);
    final still = PoseLibrary(home);
    await still.load();
    expect(still.poses, hasLength(2));
  });

  test('Agent 写 <pose-ref> 时程序挑图附在工具结果里,下一轮模型看得到;性感系列不挑', () async {
    final lib = PoseLibrary(home);
    await lib.importZip(zipOf(_pack()).path);
    final config = tempConfig();
    config.update(
      config.config.putLlm(
        const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
      ),
    );
    final seen = <LlmRequest>[];
    final replies = ['<pose-ref>standing side</pose-ref>', '好的'];
    final vm = StudioViewModel(
      config: config,
      streamChat: (req) {
        seen.add(req);
        return Stream.value(replies[seen.length - 1]);
      },
    )..poses = lib;

    vm.send('她站着回头');
    await pumpEventQueue();
    final system = seen.first.messages.first['content']!;
    expect(system, contains('【姿势图库】'));
    expect(system, contains('standing 站姿(1)'));
    expect(system, isNot(contains('lying')));
    expect(seen, hasLength(2));
    final tool = vm.messages.firstWhere((m) => m.tool);
    expect(tool.attachments.single.bytes, [4]);
    expect(tool.toolSummary, contains('1'));
    expect(seen.last.images.values.expand((i) => i).single.bytes, [4]);
    expect(vm.messages.last.text, '好的');
  });

  testWidgets('默认藏起性感系列;点开换视角,附到对话交出图和一句话', (tester) async {
    final lib = PoseLibrary(home);
    await tester.runAsync(() async {
      await lib.importZip(zipOf(_pack()).path);
    });
    Attachment? sent;
    String? text;
    await tester.pumpWidget(
      MaterialApp(
        home: PosesPage(
          library: lib,
          onSend: (image, t) {
            sent = image;
            text = t;
          },
        ),
      ),
    );
    expect(find.text('站姿 001'), findsOneWidget);
    expect(find.text('卧姿 002'), findsNothing);
    await tester.tap(find.text('性感系列'));
    await tester.pump();
    expect(find.text('卧姿 002'), findsOneWidget);

    await tester.tap(find.text('站姿 001'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('侧面'));
    await tester.pump();
    await tester.tap(find.text('附到对话'));
    await tester.pumpAndSettle();
    expect(sent!.bytes, [4]);
    expect(text, contains('侧面'));
  });
}

/// 魔搭那种散文件:本机起一个假服务器,`?f=` 后面是文件路径。
Future<HttpServer> _looseServer(Map<String, List<int>> files) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final body = files[req.uri.queryParameters['f']];
    req.response.statusCode = body == null ? 404 : 200;
    if (body != null) req.response.add(body);
    req.response.close();
  });
  return server;
}

void looseTests() {
  test('魔搭的散文件:逐个下载,下不到的图从索引里去掉,姿势一张都没有就整个去掉', () async {
    // widget 测试初始化过之后,Flutter 会拦掉真实的请求。
    HttpOverrides.global = null;
    final home = Directory.systemTemp.createTempSync('penna-poses-loose');
    addTearDown(() => home.deleteSync(recursive: true));
    final index = {
      'poses': [
        {
          'id': 'standing-001',
          'category': 'standing',
          'tags': <String>[],
          'views': [
            {'angle': 'front', 'path': 'images/a.webp'},
            {'angle': 'side', 'path': 'images/gone.webp'},
          ],
        },
        {
          'id': 'lying-002',
          'category': 'lying',
          'tags': <String>[],
          'views': [
            {'angle': 'front', 'path': 'images/gone2.webp'},
          ],
        },
      ],
    };
    final server = await _looseServer({
      'poses.json': utf8.encode(jsonEncode(index)),
      'images/a.webp': [7, 7],
    });
    addTearDown(() => server.close(force: true));
    final lib = PoseLibrary(home)
      ..looseBase = 'http://127.0.0.1:${server.port}/?f=';
    final note = await lib.download(PoseSource.modelscope);
    expect(note, contains('2'));
    expect(lib.poses.single.id, 'standing-001');
    expect(lib.poses.single.views.single.angle, 'front');
    expect(File(lib.poses.single.views.single.path).readAsBytesSync(), [7, 7]);
  });
}
