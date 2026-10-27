import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/mcp/mcp_client.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/config_service.dart';
import 'package:penna/data/services/dpapi.dart';
import 'package:penna/data/services/skill_store.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

File _write(String name, String content) {
  final dir = Directory.systemTemp.createTempSync('penna_src');
  return File('${dir.path}/$name')..writeAsStringSync(content);
}

const _llm = LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x', model: 'm');

void main() {
  group('Key 加密', () {
    test('加密后看不出原文,解密能还原', () {
      final plain = Uint8List.fromList(utf8.encode('sk-secret-钥匙'));

      final cipher = dpapiProtect(plain);

      expect(latin1.decode(cipher), isNot(contains('sk-secret')));
      expect(utf8.decode(dpapiUnprotect(cipher)), 'sk-secret-钥匙');
    });

    test('被改动过的密文解不开', () {
      final cipher = dpapiProtect(Uint8List.fromList([1, 2, 3]));
      cipher[cipher.length - 1] ^= 0xff;

      expect(() => dpapiUnprotect(cipher), throwsStateError);
    });

    test('Key 文件读不出来时,普通设置照常保留并给出提示', () async {
      final first = tempConfig()
        ..update(
          const AppConfig().putLlm(_llm).setSecret(llmSecretKey('a'), 'sk'),
        );
      await first.flushed();
      first.keysFile.writeAsStringSync('not-a-valid-key-file');

      final second = ConfigService(dir: first.dir);
      await second.load();

      expect(second.config.llms.single.name, 'A');
      expect(second.config.secrets, isEmpty);
      expect(second.lastError, contains('请重新填写'));
      // 读不了的那份被改名留底,不会被之后的保存覆盖。
      final names = first.dir.listSync().map((f) => f.path);
      expect(names.where((p) => p.contains('keys.dat.bad-')), hasLength(1));
    });
    // DPAPI 和 keys.dat 都是 Windows 上的做法;别的平台上机密在系统钥匙串里。
  }, skip: Platform.isWindows ? null : 'DPAPI 与 keys.dat 只在 Windows 上');

  group('从旧位置搬迁', () {
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    test('新位置没有设置时,把旧设置和 Key 搬过来并清掉旧的', () async {
      FlutterSecureStorage.setMockInitialValues({llmSecretKey('a'): 'sk-old'});
      final old = _write(
        'config.json',
        jsonEncode(const AppConfig().putLlm(_llm).toJson()),
      );
      final service = ConfigService(
        dir: Directory('${old.parent.path}/new'),
        legacyFile: old,
      );

      await service.load();

      expect(service.lastError, isNull);
      expect(service.config.llms.single.name, 'A');
      expect(service.config.llmKey('a'), 'sk-old');
      expect(service.file.existsSync(), isTrue);
      expect(old.existsSync(), isFalse);
      // 旧凭据只有 Windows 上是另一个地方;别的平台上系统钥匙串就是 Key 现在的
      // 存放处,搬完 Key 还得留在里面。
      if (Platform.isWindows) {
        expect(await const FlutterSecureStorage().readAll(), isEmpty);
      }
    });

    test('新位置已有设置时不碰旧的', () async {
      FlutterSecureStorage.setMockInitialValues({'k': 'v'});
      final old = _write('config.json', '{}');
      final service = tempConfig()..update(const AppConfig().putLlm(_llm));
      await service.flushed();

      final again = ConfigService(dir: service.dir, legacyFile: old);
      await again.load();

      expect(old.existsSync(), isTrue);
      expect(await const FlutterSecureStorage().readAll(), {'k': 'v'});
    });
  });

  group('Skill', () {
    test('解析文件头里的名字和简介,正文不含文件头', () {
      final skill = parseSkill(
        '---\nname: "Film Look"\ndescription: 胶片质感\n---\n# 标题\n\n用胶片的语言描述。',
        fallbackName: 'x',
      );

      expect(skill.name, 'Film Look');
      expect(skill.id, 'film-look');
      expect(skill.description, '胶片质感');
      expect(skill.body, '# 标题\n\n用胶片的语言描述。');
    });

    test('没有文件头时用第一个标题当名字;中文名也能得到安全的文件夹名', () {
      final skill = parseSkill('# 胶片质感\n\n正文', fallbackName: 'x');

      expect(skill.name, '胶片质感');
      expect(skill.id, matches(RegExp(r'^skill-[0-9a-f]+$')));
    });

    test('名字里的路径符号不会带进文件夹名;不与内置 Skill 重名', () {
      expect(
        skillIdFor(r'..\..\evil/../x'),
        matches(RegExp(r'^evil-x-[0-9a-f]+$')),
      );
      expect(skillIdFor('Foo Bar'), 'foo-bar');
      // 被丢掉字符后会撞名的,靠编号区分;保留名和超长名也要安全。
      expect(skillIdFor('C++'), isNot(skillIdFor('C#')));
      expect(skillIdFor('con'), 'user-con');
      expect(skillIdFor('a' * 200).length, lessThan(60));
      expect(skillIdFor('Writer'), 'user-writer');
    });

    test('导入、重新读取、删除', () async {
      final store = tempSkills();
      final source = _write('film.md', '---\nname: Film\n---\n正文内容');

      final imported = (await store.import(source)).single;
      final reloaded = SkillStore(store.dir);
      await reloaded.load();

      expect(imported.id, 'film');
      expect(reloaded.skills.single.body, '正文内容');

      await reloaded.remove('film');
      expect(reloaded.skills, isEmpty);
      expect(Directory('${store.dir.path}/film').existsSync(), isFalse);
    });

    test('空正文、超大文件都拒绝导入', () async {
      final store = tempSkills();

      await expectLater(
        store.import(_write('empty.md', '---\nname: x\n---\n')),
        throwsA(isA<SkillException>()),
      );
      await expectLater(
        store.import(_write('big.md', 'a' * (maxSkillBytes + 1))),
        throwsA(isA<SkillException>()),
      );
      expect(store.skills, isEmpty);
    });

    test('导入的自定义 Skill 默认开着,会写进系统提示;关掉的不会', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final store = tempSkills();
      await store.import(_write('a.md', '---\nname: Film\n---\n胶片指令'));
      await store.import(_write('b.md', '---\nname: Other\n---\n别的指令'));
      final config = tempConfig();
      config.update(
        const AppConfig().putLlm(_llm).setSkill('other', on: false),
      );
      late LlmRequest seen;
      final vm = StudioViewModel(
        config: config,
        skills: store,
        streamChat: (r) {
          seen = r;
          return Stream.value('ok');
        },
      );

      vm.send('你好');
      await pumpEventQueue();

      final system = seen.messages.first['content']!;
      expect(system, contains('胶片指令'));
      expect(system, isNot(contains('别的指令')));
    });

    test('穿甲弹:开着时接在系统提示最前面,关着不带', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final config = tempConfig();
      config.update(
        const AppConfig().putLlm(_llm).copyWith(piercingPrompt: '穿甲内容'),
      );
      final seen = <LlmRequest>[];
      final vm = StudioViewModel(
        config: config,
        skills: tempSkills(),
        streamChat: (r) {
          seen.add(r);
          return Stream.value('ok');
        },
      );

      vm.send('你好');
      await pumpEventQueue();
      config.update(config.config.copyWith(piercing: true));
      vm.send('再来');
      await pumpEventQueue();

      expect(seen.first.messages.first['content'], isNot(contains('穿甲内容')));
      final system = seen.last.messages.first['content']!;
      expect(system, startsWith('穿甲内容\n\n'));
      expect(seen.last.messages.first['role'], 'system');
    });
  });

  group('MCP', () {
    // 前面的测试启用了 Flutter 的测试环境,它会拦掉真实的网络请求;这里要连本机的假服务。
    setUp(() => HttpOverrides.global = null);

    test('拆命令行:引号里的空格不拆', () {
      expect(splitCommand(r'npx -y "@a/b c" --flag'), [
        'npx',
        '-y',
        '@a/b c',
        '--flag',
      ]);
    });

    test('解析环境变量:跳过空行和注释,值里可以有等号', () {
      expect(parseEnv('A=1\n\n# note\nTOKEN=a=b\nbad'), {
        'A': '1',
        'TOKEN': 'a=b',
      });
    });

    /// 起一个假的远程 MCP 服务;[sse] 决定回复用事件流还是整段 JSON。
    Future<HttpServer> serve({required bool sse, List<String>? auth}) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        auth?.add(request.headers.value('authorization') ?? '');
        final body = jsonDecode(await utf8.decodeStream(request)) as Map;
        final response = request.response;
        if (body['id'] == null) {
          response.statusCode = 202;
          return response.close();
        }
        final reply = jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': body['method'] == 'initialize'
              ? {'protocolVersion': '2025-03-26', 'capabilities': {}}
              : {
                  'tools': [
                    {'name': 'search', 'description': '搜索'},
                    {'name': 'fetch'},
                  ],
                },
        });
        response.headers.set('mcp-session-id', 's1');
        if (sse) {
          response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          // 先来一条服务端主动发的、编号相同的请求,再把回复拆成两行 data:。
          final cut = reply.indexOf(',') + 1;
          response.write(
            'data: {"jsonrpc":"2.0","id":${body['id']},"method":"ping"}\n\n'
            'event: message\n'
            'data: ${reply.substring(0, cut)}\n'
            'data: ${reply.substring(cut)}\n\n',
          );
        } else {
          response.headers.contentType = ContentType.json;
          response.write(reply);
        }
        return response.close();
      });
      return server;
    }

    for (final sse in [false, true]) {
      test('远程服务(${sse ? '事件流' : 'JSON'}回复):握手并列出工具,带上令牌', () async {
        final auth = <String>[];
        final server = await serve(sse: sse, auth: auth);
        addTearDown(server.close);

        final tools = await listHttpMcpTools(
          'http://127.0.0.1:${server.port}/mcp',
          token: 'tok',
        );

        expect(tools.map((t) => t.name), ['search', 'fetch']);
        expect(tools.first.description, '搜索');
        expect(auth, everyElement('Bearer tok'));
      });
    }

    test('远程服务:地址不对、连不上都给出明白的原因', () async {
      await expectLater(
        listHttpMcpTools('example.com'),
        throwsA(isA<McpException>()),
      );
      await expectLater(
        listHttpMcpTools(
          'http://127.0.0.1:1/mcp',
          timeout: const Duration(seconds: 5),
        ),
        throwsA(isA<McpException>()),
      );
    });

    test('本机命令:启动程序、握手、列出工具,环境变量能传进去', () async {
      final script = _write('server.dart', r'''
import 'dart:convert';
import 'dart:io';

void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final m = jsonDecode(line) as Map;
    if (m['id'] == null) return;
    final result = m['method'] == 'initialize'
        ? {'protocolVersion': '2025-03-26'}
        : {
            'tools': [
              {'name': Platform.environment['TOOL_NAME'] ?? 'none'},
            ],
          };
    stdout.writeln('some log line that is not json');
    stdout.writeln(jsonEncode({'jsonrpc': '2.0', 'id': m['id'], 'result': result}));
  });
}
''');

      final tools = await listStdioMcpTools(
        'dart "${script.path}"',
        environment: {'TOOL_NAME': 'from-env'},
        timeout: const Duration(seconds: 60),
      );

      expect(tools.single.name, 'from-env');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('本机命令:程序不存在或没填时报错', () async {
      await expectLater(listStdioMcpTools('   '), throwsA(isA<McpException>()));
      await expectLater(
        listStdioMcpTools(
          'penna-no-such-program-xyz',
          timeout: const Duration(seconds: 15),
        ),
        throwsA(isA<McpException>()),
      );
    });

    test('删除服务会连同令牌一起清掉', () {
      const server = McpServer(id: 's', name: 'S');
      final cfg = const AppConfig()
          .putMcp(server)
          .setSecret(mcpTokenKey('s'), 't')
          .setSecret(mcpEnvKey('s'), 'A=1');

      final after = cfg.removeMcp('s');

      expect(after.mcpServers, isEmpty);
      expect(after.secrets, isEmpty);
      expect(
        AppConfig.fromJson(jsonDecode(jsonEncode(cfg.toJson())))
            .mcpServers
            .single
            .name,
        'S',
      );
    });
  });
}
