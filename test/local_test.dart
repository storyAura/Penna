import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/local/caption_catalog.dart';
import 'package:penna/core/harness/local/download.dart';
import 'package:penna/core/harness/local/llama_server.dart';
import 'package:penna/core/harness/local/model_scan.dart';
import 'package:penna/core/harness/local/model_sources.dart';
import 'package:penna/core/harness/local/tagger.dart';
import 'package:penna/ui/features/local/local_model.dart';

import 'fixtures.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('penna_local'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('打标模型', () {
    test('标签表:v3 和老版本的写法都认,表头跳过', () {
      expect(
        parseSelectedTags(
          'tag_id,name,category,count\n9999999,general,9,1\n1,long_hair,0,5\n'
          '2,hatsune_miku,4,3\n',
        ),
        [
          (name: 'general', category: 9),
          (name: 'long_hair', category: 0),
          (name: 'hatsune_miku', category: 4),
        ],
      );
      expect(parseSelectedTags('name,category\nsmile,0\r\n'), [
        (name: 'smile', category: 0),
      ]);
    });

    test('输入的形状:通道在后或在前', () {
      expect(inputLayout([1, 448, 448, 3]), (size: 448, nchw: false));
      expect(inputLayout([-1, 448, 448, 3]), (size: 448, nchw: false));
      expect(inputLayout([1, 3, 384, 384]), (size: 384, nchw: true));
      expect(inputLayout([]), (size: 448, nchw: false));
      expect(fitInside(1000, 500, 448), (width: 448, height: 224));
      expect(fitInside(100, 50, 448), (width: 100, height: 50));
    });

    test('贴到白底正中,透明的算白色,输出 BGR', () {
      // 1×2 的图:上面一个不透明的红点,下面一个全透明的点。
      final rgba = Uint8List.fromList([255, 0, 0, 255, 0, 0, 0, 0]);
      final out = letterboxBgr(rgba, 1, 2, size: 2);
      // 宽 1 放在第 0 列(左右各空 0.5 取整),上面一行是红点。
      expect(out.sublist(0, 3), [0, 0, 255]);
      expect(out.sublist(3, 6), [255, 255, 255]);
      expect(out.sublist(6, 9), [255, 255, 255]);

      final planes = letterboxBgr(rgba, 1, 2, size: 2, nchw: true);
      // 通道在前:B、G、R 各一整块,红点在每块的第 0 个。
      expect([planes[0], planes[4], planes[8]], [0, 0, 255]);
    });

    test('按阈值筛:角色、通用分开,分级取把握最大的;没过 sigmoid 的先补上', () {
      const labels = [
        (name: 'general', category: tagRating),
        (name: 'sensitive', category: tagRating),
        (name: 'long_hair', category: tagGeneral),
        (name: 'smile', category: tagGeneral),
        (name: 'hatsune_miku', category: tagCharacter),
      ];
      final r = decodeTags(
        [0.2, 0.7, 0.4, 0.9, 0.95],
        labels,
        general: 0.35,
        character: 0.85,
      );
      expect(r.rating, 'sensitive');
      expect(r.characters.map((t) => t.tag), ['hatsune_miku']);
      expect(r.general.map((t) => t.tag), ['smile', 'long_hair']);
      expect(tagPrompt(r), 'hatsune miku, smile, long hair');
      expect(tagPrompt(r, without: {'smile'}), 'hatsune miku, long hair');

      final logits = decodeTags(
        [-5, -5, 3, -3, -1],
        labels,
        general: 0.5,
        character: 0.85,
      );
      expect(logits.general.map((t) => t.tag), ['long_hair']);
      expect(logits.characters, isEmpty);
    });

    test('颜文字的下划线留着', () {
      expect(tagText('^_^'), '^_^');
      expect(tagText('looking_at_viewer'), 'looking at viewer');
    });
  });

  group('llama-server', () {
    test('退出的原因:不认参数的说换程序,提到内存的才说显存不够', () {
      expect(
        exitReason(["error: unknown command '-m'"], r'F:\x\llama-server.exe'),
        allOf(contains(r'F:\x\llama-server.exe'), contains('不认')),
      );
      expect(
        exitReason(['ggml_vulkan: ErrorOutOfDeviceMemory'], 'a.exe'),
        contains('显存不够'),
      );
      expect(
        exitReason(['failed to load model'], 'a.exe'),
        isNot(contains('显存')),
      );
    });

    test('参数:-1 层是全部放进显卡,有视觉组件才带 --mmproj', () {
      final spec = (
        exe: 'a.exe',
        model: 'm.gguf',
        mmproj: 'p.gguf',
        port: 9000,
        context: 2048,
        gpuLayers: -1,
      );
      final args = serverArgs(spec);
      expect(args.join(' '), contains('-ngl 999'));
      expect(args.join(' '), contains('--port 9000'));
      expect(args.sublist(args.length - 2), ['--mmproj', 'p.gguf']);
      expect(
        serverArgs((
          exe: 'a.exe',
          model: 'm.gguf',
          mmproj: '',
          port: 9000,
          context: 2048,
          gpuLayers: 20,
        )),
        isNot(contains('--mmproj')),
      );
    });

    test('等到 /health 通了才算起来;停掉会结束进程', () async {
      final process = FakeProcess();
      var polls = 0;
      final server = LlamaServer(
        start: (_, _) async => process,
        health: (_) async => ++polls >= 3,
      );

      final url = await server.start(fakeServerSpec(tmp), poll: Duration.zero);

      expect(url, 'http://127.0.0.1:8091/v1');
      expect(server.running, isTrue);
      await server.stop();
      expect(process.killed, isTrue);
      expect(server.running, isFalse);
    });

    test('起来后马上退出:报出最后一行输出', () async {
      final process = FakeProcess();
      final server = LlamaServer(
        start: (_, _) async {
          scheduleMicrotask(() => process.exit(1, 'loading\nout of memory\n'));
          return process;
        },
        health: (_) async => false,
      );

      await expectLater(
        server.start(
          fakeServerSpec(tmp),
          poll: const Duration(milliseconds: 5),
        ),
        throwsA(
          isA<LocalServerException>().having(
            (e) => e.message,
            'message',
            allOf(contains('退出了'), contains('out of memory')),
          ),
        ),
      );
      expect(server.running, isFalse);
    });

    test('加载途中点停止:说「已停止」,不当成崩了', () async {
      final server = LlamaServer(
        start: (_, _) async => FakeProcess(),
        health: (_) async => false,
      );

      final starting = server.start(
        fakeServerSpec(tmp),
        poll: const Duration(milliseconds: 5),
      );
      // 先挂上判断,不然它报错时还没人接。
      final check = expectLater(
        starting,
        throwsA(
          isA<LocalServerException>().having(
            (e) => e.message,
            'message',
            '已停止',
          ),
        ),
      );
      // 等它真的起了进程、开始等 /health 再停。
      while (!server.running) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await server.stop();
      await check;
    });

    test('找不到文件时不启动', () async {
      final server = LlamaServer(start: (_, _) => fail('不该启动'));
      await expectLater(
        server.start((
          exe: '${tmp.path}/none.exe',
          model: 'm',
          mmproj: '',
          port: 1,
          context: 1,
          gpuLayers: 0,
        )),
        throwsA(isA<LocalServerException>()),
      );
    });

    test('在解开的运行时里找最浅的 llama-server', () {
      Directory('${tmp.path}/a/b').createSync(recursive: true);
      File('${tmp.path}/a/b/$llamaServerFileName').writeAsStringSync('');
      File('${tmp.path}/a/$llamaServerFileName').writeAsStringSync('');
      expect(
        findServerExe(tmp)!.path.replaceAll('\\', '/'),
        endsWith('/a/$llamaServerFileName'),
      );
      expect(findServerExe(Directory('${tmp.path}/none')), isNull);
    });
  });

  group('下载', () {
    // 这个文件里有 testWidgets,Flutter 会拦掉真实的网络请求;这组要连本机的假服务器。
    setUp(() => HttpOverrides.global = null);

    late HttpServer http;
    final body = List.generate(1000, (i) => i % 251);
    final ranges = <String?>[];

    setUp(() async {
      ranges.clear();
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        ranges.add(range);
        if (request.uri.path == '/missing') {
          request.response.statusCode = 404;
        } else if (request.uri.path == '/short') {
          request.response.add(body.sublist(0, 400));
        } else if (range != null) {
          final from = int.parse(range.split('=')[1].split('-')[0]);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.add(body.sublist(from));
        } else {
          request.response.add(body);
        }
        await request.response.close();
      });
    });
    tearDown(() => http.close(force: true));

    RemoteFile file({String path = '/f', String? sha}) => (
      url: 'http://127.0.0.1:${http.port}$path',
      path: '${tmp.path}/out.bin',
      size: body.length,
      sha256: sha,
    );

    test('从断开的地方接着下;校验通过才改成正式的名字', () async {
      File('${tmp.path}/out.bin.part').writeAsBytesSync(body.sublist(0, 400));
      final seen = <int>[];

      await downloadFile(
        file(sha: '${sha256.convert(body)}'),
        onProgress: (got, _) => seen.add(got),
      );

      expect(ranges, ['bytes=400-']);
      expect(File('${tmp.path}/out.bin').readAsBytesSync(), body);
      expect(File('${tmp.path}/out.bin.part').existsSync(), isFalse);
      expect(seen.last, 1000);
      expect(isDownloaded(file()), isTrue);
    });

    test('GitHub 上校验得了的文件先走加速,都不行再直连;别处和不校验的直连', () {
      const url = 'https://github.com/o/r/releases/download/v1/a.zip';
      RemoteFile at(String u, String? sha) =>
          (url: u, path: 'x', size: null, sha256: sha);
      expect(downloadUrls(at(url, 'ab')), [
        for (final p in githubProxies) '$p$url',
        url,
      ]);
      expect(downloadUrls(at(url, null)), [url]);
      expect(downloadUrls(at('https://hf-mirror.com/a', 'ab')), [
        'https://hf-mirror.com/a',
      ]);
    });

    test('下了一些才断的不换地址,.part 留着下次接着下', () async {
      final good = file(sha: '${sha256.convert(body)}');
      await expectLater(
        downloadFile(
          good,
          urls: ['http://127.0.0.1:${http.port}/short', good.url],
        ),
        throwsA(isA<DownloadException>()),
      );
      expect(ranges, [null]);
      expect(File('${tmp.path}/out.bin.part').lengthSync(), 400);
    });

    test('GitHub 加速关着时先直连,再走加速', () {
      const url = 'https://github.com/o/r/releases/download/v1/a.zip';
      expect(
        downloadUrls((
          url: url,
          path: 'x',
          size: null,
          sha256: 'ab',
        ), proxyFirst: false),
        [url, for (final p in githubProxies) '$p$url'],
      );
    });

    test('模型来源:选中的先试,再按官方、ModelScope、加速、自定义;没有的跳过', () {
      final wd = hfFileUrl('SmilingWolf/wd-vit-tagger-v3', 'model.onnx');
      const ms =
          'https://modelscope.cn/models/fireicewolf/wd-vit-tagger-v3/resolve/master/model.onnx';
      const mirror =
          'https://hf-mirror.com/SmilingWolf/wd-vit-tagger-v3/resolve/main/model.onnx';
      expect(modelUrls(wd, 'huggingface'), [wd, ms, mirror]);
      expect(modelUrls(wd, 'modelscope'), [ms, wd, mirror]);
      expect(modelUrls(wd, 'custom', custom: 'https://my.mirror/ '), [
        'https://my.mirror/SmilingWolf/wd-vit-tagger-v3/resolve/main/model.onnx',
        wd,
        ms,
        mirror,
      ]);
      // 地址不对的自定义来源不试;要 Token 的只发给 HuggingFace 和加速站。
      expect(modelUrls(wd, 'custom', custom: 'ftp://x'), [wd, ms, mirror]);
      expect(modelUrls(wd, 'modelscope', gated: true), [wd, mirror]);
      // ModelScope 上没有的跳过;不是 HuggingFace 文件的原样。
      final oo = hfFileUrl('Grio43/OppaiOracle', 'V1_onnx/model.onnx');
      expect(modelUrls(oo, 'modelscope'), hasLength(2));
      expect(modelUrls('https://x.com/a', 'modelscope'), ['https://x.com/a']);
    });

    test('一个地址下不了就换下一个,从头下', () async {
      File('${tmp.path}/out.bin.part').writeAsBytesSync([1, 2, 3]);
      final good = file(sha: '${sha256.convert(body)}');
      await downloadFile(
        good,
        urls: ['http://127.0.0.1:${http.port}/missing', good.url],
      );
      expect(File('${tmp.path}/out.bin').readAsBytesSync(), body);
      expect(ranges, ['bytes=3-', null]);
    });

    test('校验不对就删掉;找不到文件说人话', () async {
      await expectLater(
        downloadFile(file(sha: '00')),
        throwsA(
          isA<DownloadException>().having(
            (e) => e.message,
            'message',
            contains('校验'),
          ),
        ),
      );
      expect(File('${tmp.path}/out.bin.part').existsSync(), isFalse);
      expect(File('${tmp.path}/out.bin').existsSync(), isFalse);

      await expectLater(
        downloadFile(file(path: '/missing')),
        throwsA(
          isA<DownloadException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });
  });

  group('模型文件夹', () {
    /// 在 [root] 下放好一堆文件(路径用 / 分隔),内容随便。
    void files(Directory root, List<String> paths) {
      for (final p in paths) {
        File('${root.path}/$p')
          ..createSync(recursive: true)
          ..writeAsStringSync('x');
      }
    }

    late Directory root;
    setUp(() {
      root = Directory('${tmp.path}/models')..createSync();
      files(root, [
        // BooruDatasetTagManagerPlus 的放法
        'bdtm/Models/SmilingWolf/wd-vit-tagger-v3/model.onnx',
        'bdtm/Models/SmilingWolf/wd-vit-tagger-v3/selected_tags.csv',
        // HuggingFace 缓存
        'hf/hub/models--SmilingWolf--wd-swinv2-tagger-v3/snapshots/'
            '0123456789abcdef0123/model.onnx',
        'hf/hub/models--SmilingWolf--wd-swinv2-tagger-v3/snapshots/'
            '0123456789abcdef0123/selected_tags.csv',
        // 不在清单里的 WD 模型
        'other/my-tagger/model.onnx',
        'other/my-tagger/selected_tags.csv',
        // CL v1 放在仓库的子文件夹里
        'hf/Nonene/cl_tagger/cl_tagger_1_02/model.onnx',
        'hf/Nonene/cl_tagger/cl_tagger_1_02/tag_mapping.json',
        // 只有模型、没有标签表的不算
        'half/model.onnx',
        // NLapt 的放法
        'nlapt/toriigate-0.5/ToriiGate-0.5-Q4_K_M.gguf',
        'nlapt/toriigate-0.5/ToriiGate-0.5-fp16.mmproj.gguf',
        // 别的 GGUF,配同文件夹的视觉组件
        'llm/qwen/qwen-vl.gguf',
        'llm/qwen/mmproj-qwen.gguf',
        'llm/text-only.gguf',
        'bin/$llamaServerFileName',
        'bin/ggml.dll',
        // 别的程序也叫 llama-server,旁边没有 llama.cpp 的库,不算
        'node-tool/$llamaServerFileName',
        // ComfyUI-WD14-Tagger 的放法:名字.onnx + 名字.csv
        'comfy/models/wd-v1-4-moat-tagger-v2.onnx',
        'comfy/models/wd-v1-4-moat-tagger-v2.csv',
        'comfy/models/my-comfy-tagger.onnx',
        'comfy/models/my-comfy-tagger.csv',
        // ModelScope 缓存:名字里的点写成 ___
        'ms/hub/models/deepghs/pixai-tagger-v0___9-onnx/model.onnx',
        'ms/hub/models/deepghs/pixai-tagger-v0___9-onnx/selected_tags.csv',
        // 跳过的文件夹
        'node_modules/x/model.gguf',
      ]);
    });

    test('一层层往下找;认得清单里的模型,跳过 node_modules', () {
      final f = scanModelFolders([root.path]);

      expect(f.taggers, hasLength(7));
      expect(f.taggers.map(catalogTaggerFor).toSet(), {
        'SmilingWolf/wd-vit-tagger-v3',
        'SmilingWolf/wd-swinv2-tagger-v3',
        'SmilingWolf/wd-v1-4-moat-tagger-v2',
        'pixai:v0.9',
        'cl:Nonene/cl_tagger:1_02',
        null,
      });
      expect(f.ggufs.map(fileName).toSet(), {
        'ToriiGate-0.5-Q4_K_M.gguf',
        'qwen-vl.gguf',
        'text-only.gguf',
      });
      expect(f.mmprojs, hasLength(2));
      expect(f.servers, hasLength(1));
      expect(f.truncated, isFalse);
      expect(
        folderTitle(
          '${root.path}/hf/hub/models--SmilingWolf--wd-swinv2-tagger-v3/'
          'snapshots/0123456789abcdef0123',
        ),
        'wd-swinv2-tagger-v3',
      );
      // 条目太多时停下,说一声。
      expect(scanModelFolders([root.path], maxEntries: 3).truncated, isTrue);
    });

    test('找到的直接能用:打标模型、看图模型、llama-server,不在清单里的也列出来', () async {
      final model = LocalModel(
        dir: tmp,
        streamChat: (_) => const Stream.empty(),
      );
      expect(model.taggerPaths(taggerModels.first), isNull);

      model.addFolder(root.path);
      while (model.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // ViT v3 在 BDTM 的文件夹里找到了,不用下。
      final vit = taggerModels.firstWhere(
        (m) => m.id == 'SmilingWolf/wd-vit-tagger-v3',
      );
      expect(model.taggerPaths(vit)!.model, endsWith('model.onnx'));
      // 不在清单里的那个也能选,阈值用默认值。
      final mine = model.taggers.firstWhere((m) => m.name == '[本机] my-tagger');
      expect(
        (mine.general, mine.series, mine.kind),
        (0.35, '本机', TaggerKind.wd),
      );
      expect(model.taggerPaths(mine), isNotNull);
      // CL 的标签表是 tag_mapping.json。
      final cl = taggerModels.firstWhere((m) => m.kind == TaggerKind.clV1);
      expect(model.taggerPaths(cl)!.labels, endsWith('tag_mapping.json'));
      // ComfyUI 的:标签表是同名的 .csv。
      final moat = taggerModels.firstWhere(
        (m) => m.id == 'SmilingWolf/wd-v1-4-moat-tagger-v2',
      );
      final paths = model.taggerPaths(moat)!;
      expect(paths.model, endsWith('wd-v1-4-moat-tagger-v2.onnx'));
      expect(paths.labels, endsWith('wd-v1-4-moat-tagger-v2.csv'));
      final comfy = model.taggers.firstWhere(
        (m) => m.name == '[本机] my-comfy-tagger',
      );
      expect(comfy.kind, TaggerKind.wd);
      expect(model.taggerPaths(comfy)!.labels, endsWith('my-comfy-tagger.csv'));

      final torii = captionModels.firstWhere((m) => m.id == 'toriigate-0.5');
      expect(model.useCaption(torii), isTrue);
      expect(model.modelPath, endsWith('ToriiGate-0.5-Q4_K_M.gguf'));
      expect(model.mmprojPath, endsWith('ToriiGate-0.5-fp16.mmproj.gguf'));

      expect(
        {
          for (final g in model.foundGgufs)
            fileName(g.model): fileName(g.mmproj),
        },
        {'qwen-vl.gguf': 'mmproj-qwen.gguf', 'text-only.gguf': ''},
      );
      expect(model.serverExe, endsWith(llamaServerFileName));

      // 文件夹存盘后还在,重开时自动再扫一遍。
      final again = LocalModel(
        dir: tmp,
        streamChat: (_) => const Stream.empty(),
      );
      await again.load();
      expect(again.modelFolders, [root.path]);
      while (again.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(again.found.taggers, hasLength(7));

      model.removeFolder(root.path);
      while (model.scanning) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(model.taggerPaths(vit), isNull);
    });
  });

  group('各种打标模型', () {
    test('标签表:PixAI 的 csv 和 tags.json、CL 的两种 json、OppaiOracle 的 csv', () {
      expect(
        parseLabels(
          TaggerKind.pixai09,
          'id,tag_id,name,category\n0,5,smile,0\n1,6,miku,4',
        ),
        [(name: 'smile', category: 0), (name: 'miku', category: 4)],
      );
      expect(
        parseLabels(
          TaggerKind.pixai10,
          jsonEncode({
            'categories': [
              {
                'name': 'character',
                'offset': 1,
                'count': 1,
                'tags': ['miku'],
              },
              {
                'name': 'general',
                'offset': 0,
                'count': 1,
                'tags': ['smile'],
              },
            ],
          }),
        ),
        [
          (name: 'smile', category: tagGeneral),
          (name: 'miku', category: tagCharacter),
        ],
      );
      expect(
        parseLabels(
          TaggerKind.clV1,
          jsonEncode({
            '1': {'tag': 'miku', 'category': 'Character'},
            '0': {'tag': 'smile', 'category': 'General'},
          }),
        ),
        [
          (name: 'smile', category: tagGeneral),
          (name: 'miku', category: tagCharacter),
        ],
      );
      expect(
        parseLabels(
          TaggerKind.clV2,
          jsonEncode({
            'idx_to_tag': {'0': 'smile', '1': 'miku', '2': 'oc'},
            'tag_to_category': {
              'smile': 'General',
              'miku': 1,
              'oc': 'Copyright',
            },
          }),
        ),
        [
          (name: 'smile', category: tagGeneral),
          (name: 'miku', category: tagCharacter),
          (name: 'oc', category: tagCopyright),
        ],
      );
      final oo = parseLabels(
        TaggerKind.oppai,
        'tag_id,name\n0,<PAD>\n1,smile\n2,rating:safe',
      );
      expect([for (final l in oo) l.category], [-1, tagGeneral, -1]);
    });

    test('只留通用和角色;logits 过 sigmoid;skip 里的不要', () {
      const labels = [
        (name: 'smile', category: tagGeneral),
        (name: 'oc', category: tagCopyright),
        (name: 'gray_background', category: tagGeneral),
      ];
      final r = decodeTags(
        [3, 3, 3],
        labels,
        general: 0.5,
        character: 0.5,
        logits: true,
        skip: {'gray_background'},
      );
      expect(r.general.map((t) => t.tag), ['smile']);
      expect(r.general.single.prob, closeTo(0.9526, 1e-3));
    });

    test('预处理:PixAI v1.0 黑底、OppaiOracle 灰底加掩码、CL v1 用 BGR', () {
      // 1×1 的红点贴到 3×3 的画布正中。
      final red = Uint8List.fromList([255, 0, 0, 255]);
      double norm(int v) => (v / 255 - 0.5) / 0.5;

      final pixai = prepareTaggerInput(TaggerKind.pixai10, red, 1, 1, size: 3);
      expect(pixai.shape, [1, 3, 3, 3]);
      expect(pixai.pixels[0], norm(0)); // 角上是黑色
      expect(pixai.pixels[4], norm(255)); // 正中 R 通道是红

      final oo = prepareTaggerInput(TaggerKind.oppai, red, 1, 1, size: 3);
      expect(oo.pixels[0], closeTo(norm(114), 1e-6));
      expect(oo.mask, [true, true, true, true, false, true, true, true, true]);

      final cl = prepareTaggerInput(TaggerKind.clV1, red, 1, 1, size: 3);
      // BGR:第 0 个通道是蓝色,红点那里是 0。
      expect(cl.pixels[4], norm(0));
      expect(cl.pixels[2 * 9 + 4], norm(255));

      expect(taggerImageSize(TaggerKind.pixai10, 200, 100, 1008), (
        width: 1008,
        height: 504,
      ));
      expect(taggerImageSize(TaggerKind.oppai, 200, 100, 448), (
        width: 200,
        height: 100,
      ));
      expect(taggerImageSize(TaggerKind.clV2, 200, 100, 384), (
        width: 384,
        height: 384,
      ));
    });
  });
}
