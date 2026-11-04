import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/layout.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/skill_store.dart';
import 'package:penna/ui/core/theme.dart';
import 'package:penna/ui/features/studio/mention.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';
import 'package:penna/ui/features/studio/studio_page.dart';
import 'package:penna/ui/shell.dart';

import 'fixtures.dart';

/// 在临时目录里造一个 ZIP,[files] 是「包内路径 → 内容」。
File _zip(Map<String, String> files, {String name = 'pack.zip'}) {
  final archive = Archive();
  files.forEach((path, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  });
  final dir = Directory.systemTemp.createTempSync('penna_zip');
  return File('${dir.path}/$name')
    ..writeAsBytesSync(ZipEncoder().encode(archive));
}

const _llm = LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x', model: 'm');

/// 真实写盘,只在最后把 staging 换到目标目录时模拟文件系统故障。
final class _FailStagingRename extends IOOverrides {
  @override
  Directory createDirectory(String path) {
    final dir = super.createDirectory(path);
    return path.contains('.tmp-') ? _RenameFailingDirectory(dir) : dir;
  }
}

class _RenameFailingDirectory implements Directory {
  _RenameFailingDirectory(this.dir);
  final Directory dir;

  @override
  String get path => dir.path;
  @override
  Future<bool> exists() => dir.exists();
  @override
  Future<Directory> create({bool recursive = false}) =>
      dir.create(recursive: recursive);
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      dir.delete(recursive: recursive);
  @override
  Future<Directory> rename(String newPath) =>
      Future.error(FileSystemException('模拟替换失败', path));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('压缩包导入', () {
    test('一个包里多个 Skill:各自成一个文件夹,附带的文件一起保存', () async {
      final store = tempSkills();

      final imported = await store.import(
        _zip({
          'pack/film/SKILL.md': '---\nname: Film\n---\n胶片指令',
          'pack/film/refs/stocks.md': '柯达 Portra',
          'pack/anime/skill.md': '# Anime Style\n\n动画指令',
          'pack/README.md': '说明,不属于任何 Skill',
          '__MACOSX/pack/._film': 'junk',
        }),
      );

      expect(imported.map((s) => s.name).toSet(), {'Film', 'Anime Style'});
      expect(store.skills.map((s) => s.id).toSet(), {'film', 'anime-style'});
      final sep = Platform.pathSeparator;
      expect(
        File('${store.dir.path}${sep}film${sep}refs${sep}stocks.md')
            .readAsStringSync(),
        '柯达 Portra',
      );
      // 大小写不标准的 skill.md 统一存成 SKILL.md。
      expect(
        File('${store.dir.path}${sep}anime-style${sep}SKILL.md').existsSync(),
        isTrue,
      );
      expect(
        store.dir.listSync(recursive: true).map((f) => f.path),
        isNot(contains(contains('README'))),
      );
    });

    test('SKILL.md 直接在包的根目录、又没写名字时,用压缩包的文件名', () async {
      final store = tempSkills();

      final skill = (await store.import(
        _zip({'SKILL.md': '只有正文,没有标题'}, name: 'Night City.zip'),
      )).single;

      expect(skill.name, 'Night City');
      expect(skill.id, 'night-city');
    });

    test('没写名字时用 Skill 所在的文件夹名', () async {
      final store = tempSkills();

      final skill = (await store.import(_zip({'my-skill/SKILL.md': '正文'})))
          .single;

      expect(skill.name, 'my-skill');
    });

    test('想跳出目录的路径:整个包拒收,一个文件都不写', () async {
      final store = tempSkills();
      final outside = Directory.systemTemp.createTempSync('penna_out');

      for (final bad in ['../evil.md', r'a\..\..\evil.md', '/abs.md', 'C:/x']) {
        await expectLater(
          store.import(_zip({'ok/SKILL.md': '正文', bad: 'x'})),
          throwsA(isA<SkillException>()),
          reason: bad,
        );
      }
      expect(store.dir.listSync(), isEmpty);
      expect(outside.listSync(), isEmpty);
    });

    test('没有 SKILL.md、不是压缩包、解开后太大,都说明原因', () async {
      final store = tempSkills();
      final fake = File(
        '${Directory.systemTemp.createTempSync('penna_zip').path}/x.zip',
      )..writeAsStringSync('not a zip');

      await expectLater(
        store.import(_zip({'a/readme.md': 'x'})),
        throwsA(
          isA<SkillException>().having((e) => e.message, 'm', contains('没有')),
        ),
      );
      await expectLater(store.import(fake), throwsA(isA<SkillException>()));
      await expectLater(
        store.import(
          _zip({'a/SKILL.md': '正文', 'a/big.bin': 'x' * (maxUnpackedBytes + 1)}),
        ),
        throwsA(
          isA<SkillException>().having((e) => e.message, 'm', contains('太大')),
        ),
      );
      expect(store.skills, isEmpty);
    });

    test('包里有一个 Skill 不合格时,整个包都不导入,已有的同名 Skill 原样保留', () async {
      final store = tempSkills();
      await store.import(_zip({'film/SKILL.md': '旧内容'}));

      await expectLater(
        store.import(
          _zip({
            'film/SKILL.md': '新内容',
            'broken/SKILL.md': '---\nname: x\n---\n',
          }),
        ),
        throwsA(isA<SkillException>()),
      );
      await store.load();

      expect(store.skills.single.body, '旧内容');
    });

    test('两个 Skill 重名、文件只差大小写、SKILL.md 超大,都拒收', () async {
      final store = tempSkills();

      for (final files in [
        {
          'a/SKILL.md': '---\nname: Same\n---\n一',
          'b/SKILL.md': '---\nname: Same\n---\n二',
        },
        {'a/SKILL.md': '正文', 'a/Ref.txt': '1', 'a/ref.txt': '2'},
        {'a/SKILL.md': 'x' * (maxSkillBytes + 1)},
      ]) {
        await expectLater(
          store.import(_zip(files)),
          throwsA(isA<SkillException>()),
        );
      }
      expect(store.dir.listSync(), isEmpty);
    });

    test('重新导入同名 Skill 会整个替换,旧的附带文件不残留', () async {
      final store = tempSkills();
      await store.import(_zip({'film/SKILL.md': '旧', 'film/old.txt': 'x'}));

      await store.import(_zip({'film/SKILL.md': '新'}));

      expect(store.skills.single.body, '新');
      expect(File('${store.dir.path}/film/old.txt').existsSync(), isFalse);
    });

    test('最后替换 Skill 失败时,旧正文和附带文件都保留', () async {
      final store = tempSkills();
      await store.import(_zip({'film/SKILL.md': '旧正文', 'film/ref.txt': '旧资料'}));
      final next = _zip({'film/SKILL.md': '新正文'});
      await expectLater(
        IOOverrides.runWithIOOverrides(
          () => store.import(next),
          _FailStagingRename(),
        ),
        throwsA(isA<SkillException>()),
      );
      await store.load();
      expect(store.skills.single.body, '旧正文');
      expect(File('${store.dir.path}/film/ref.txt').readAsStringSync(), '旧资料');
      expect(store.dir.listSync().whereType<Directory>(), hasLength(1));
    });
  });

  group('自动识别名字和简介', () {
    test('简介写成多行(> 或换行缩进)时接成一句;嵌套的 name 不会盖掉外层的', () {
      final skill = parseSkill(
        '---\n'
        'name: Film\n'
        'description: >\n'
        '  第一行\n'
        '  第二行\n'
        'metadata:\n'
        '  name: 不该用这个\n'
        '---\n'
        '正文',
        fallbackName: 'x',
      );

      expect(skill.name, 'Film');
      expect(skill.description, '第一行 第二行');
    });

    test('开头的 --- 只是分隔线时不当成文件头,正文不丢', () {
      final skill = parseSkill(
        '---\n\n第一段\n\n---\n\n第二段',
        fallbackName: 'Notes',
      );

      expect(skill.name, 'Notes');
      expect(skill.body, contains('第一段'));
      expect(skill.body, contains('第二段'));
    });

    test('没写简介时用正文第一句', () {
      final skill = parseSkill(
        '# 标题\n\n用胶片的语言描述画面。\n\n更多内容',
        fallbackName: 'x',
      );

      expect(skill.description, '用胶片的语言描述画面。');
    });

    test('内置 Skill 都有正文', () {
      expect(builtinSkillList, hasLength(14));
      expect(builtinSkillList.every((s) => s.body.trim().isNotEmpty), isTrue);
    });

    test('漫画分格:例子程序读得出来,有斜切的格,人物和气泡都落在自己那一格的形状里', () {
      final body = builtinSkillList
          .firstWhere((s) => s.id == 'comic-page')
          .body;
      // 用户画好了格时的做法、不排成一样高的通栏条带。
      expect(body, contains('用户画好了格'));
      expect(body, contains('通栏'));
      // 正文里也提到 <layout> 这个标签,例子是后面紧跟着 JSON 的那一处。
      final made = splitLayout(body.substring(body.indexOf('<layout>\n{')));
      expect(made.complete, isTrue);
      final read = readMossLayout(
        made.json!,
        width: 832,
        height: 1216,
        ownSize: true,
      )!;
      final l = read.layout;
      expect(read.fixes, isEmpty);
      expect(l.canvas, 'multi_panel');
      expect(read.hints, hasLength(l.boxes.length));
      final panels = [
        for (final b in l.boxes)
          if (b.name.startsWith('第')) b,
      ];
      expect(panels.length, greaterThanOrEqualTo(3));
      expect(panels.where((p) => p.shape != null), isNotEmpty);
      // 角色卡写在 summary.cast 里,每个人物块都对得上。
      expect(l.cast, isNotEmpty);
      expect(castMisses(l), isEmpty);
      for (final b in l.boxes.where((b) => !panels.contains(b))) {
        final corners = [
          (b.left, b.top),
          (b.right, b.top),
          (b.left, b.bottom),
          (b.right, b.bottom),
        ];
        expect(
          panels.where(
            (p) => corners.every(
              (c) => p.covers(c.$1.toDouble(), c.$2.toDouble()),
            ),
          ),
          hasLength(1),
          reason: b.name,
        );
      }
    });
  });

  group('@ 引用', () {
    test('只在开头或空白后的 @ 才算,关键词到光标为止', () {
      expect(mentionQueryAt('@', 1), (start: 0, query: ''));
      expect(mentionQueryAt('改一下 @fi', 7), (start: 4, query: 'fi'));
      expect(mentionQueryAt('改一下 @fi 再说', 10), isNull);
      expect(mentionQueryAt('a@b.com', 7), isNull);
      expect(mentionQueryAt('@film', 2), (start: 0, query: 'f'));
    });

    test('按名字或编号筛选,不分大小写', () {
      const skills = [
        UserSkill(
          id: 'film-look',
          name: 'Film Look',
          description: '',
          body: 'b',
        ),
        UserSkill(id: 'writer', name: '写提示词', description: '', body: 'b'),
      ];

      expect(matchSkills(skills, 'FILM').single.id, 'film-look');
      expect(matchSkills(skills, '写').single.id, 'writer');
      expect(matchSkills(skills, ''), hasLength(2));
    });

    test('引用的 Skill 内容跟着那条消息发出,后续几轮仍然带着', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final store = tempSkills();
      await store.import(_zip({'film/SKILL.md': '---\nname: Film\n---\n胶片指令'}));
      final config = tempConfig()
        ..update(const AppConfig().putLlm(_llm).setSkill('film', on: false));
      final seen = <LlmRequest>[];
      final vm = StudioViewModel(
        config: config,
        skills: store,
        streamChat: (r) {
          seen.add(r);
          return Stream.value('ok');
        },
      );

      vm.send('写一条', skillIds: ['film']);
      await pumpEventQueue();
      vm.send('再来');
      await pumpEventQueue();

      expect(vm.messages.first.skillIds, ['film']);
      expect(seen[0].messages.last['content'], contains('胶片指令'));
      // 它被关掉了,所以系统提示里没有它,只跟着被引用的那条消息。
      expect(seen[1].messages.first['content'], isNot(contains('胶片指令')));
      expect(seen[1].messages[1]['content'], contains('胶片指令'));

      // 引用一个开着的:系统提示里已有,消息里不再重复带一份。
      vm.send('改开头', skillIds: ['local-edit']);
      await pumpEventQueue();
      expect(seen[2].messages.first['content'], contains('最小必要改动'));
      expect(seen[2].messages.last['content'], '改开头');
      expect(seen[1].messages.last['content'], '再来');
    });

    test('内置 Skill 默认都开着:正文带着"什么时候用"写进系统提示,换 Preset 也一样', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final config = tempConfig()..update(const AppConfig().putLlm(_llm));
      late LlmRequest seen;
      final vm = StudioViewModel(
        config: config,
        skills: tempSkills(),
        streamChat: (r) {
          seen = r;
          return Stream.value('ok');
        },
      );

      vm.send('你好');
      await pumpEventQueue();

      expect(seen.messages.first['content'], contains('最小必要改动'));
      expect(
        seen.messages.first['content'],
        contains('<skill name="写 Skill" when="聊着写出一个新 Skill'),
      );

      config.update(config.config.copyWith(activePresetId: 'translate'));
      vm.send('再来');
      await pumpEventQueue();
      expect(seen.messages.first['content'], contains('最小必要改动'));
    });

    test('旧配置里 Preset 带着的 skills 字段读得进来,只是不再用', () {
      final old = const AppConfig().toJson();
      (old['presets'] as List).first['skills'] = ['writer'];

      final loaded = AppConfig.fromJson(old);

      expect(loaded.presets, hasLength(const AppConfig().presets.length));
      expect(loaded.disabledSkills, isEmpty);
    });

    testWidgets('输入 @ 弹出列表,回车选中变成标签,发送后标签跟着消息', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final config = tempConfig()..update(const AppConfig().putLlm(_llm));
      final vm = StudioViewModel(
        config: config,
        skills: tempSkills(),
        streamChat: (_) => const Stream.empty(),
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: pennaTheme(),
          home: AppShell(vm: vm, config: config, skills: vm.skills!),
        ),
      );
      // 布局页也有一个同样的对话框:只找工作台的。
      final input = find.descendant(
        of: find.byType(StudioPage),
        matching: find.widgetWithText(
          TextField,
          'Enter 发送 · Shift+Enter 换行 · @ 引用 Skill',
        ),
      );

      await tester.enterText(input, '帮我 @局部');
      await tester.pump();
      expect(find.text('局部修改'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('@局部修改'), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, '帮我 ');
      expect(vm.messages, isEmpty);

      await tester.enterText(input, '帮我改开头');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(vm.messages.first.skillIds, ['local-edit']);
      expect(find.text('@局部修改'), findsOneWidget);
    });
  });
}
