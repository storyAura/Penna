import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/characters/character_dict.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/character_store.dart';
import 'package:penna/ui/core/widgets.dart';
import 'package:penna/ui/features/characters/characters_page.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

const _tsv =
    'hatsune miku\tvocaloid\t1girl, aqua eyes, twintails\tdetached sleeves\t初音ミク, 初音未来, Miku\n'
    'ganyu (genshin impact)\tgenshin impact\t1girl, goat horns, blue hair\tneck bell\t甘雨, 甘雨(原神)\n'
    'ganyu (twilight blossom) (genshin impact)\tgenshin impact\t1girl\tblue dress\n'
    'nobody\toriginal\t\t';

/// 模型按顺序说出 [replies] 里的话;发给它的请求记在 [seen] 里。
StudioViewModel _studio(
  List<String> replies, {
  List<LlmRequest>? seen,
  CharacterStore? store,
}) {
  final service = tempConfig();
  service.update(
    service.config.putLlm(
      const LlmProfile(id: 'a', name: 'A', baseUrl: 'http://a', model: 'm'),
    ),
  );
  var turn = 0;
  return StudioViewModel(
    config: service,
    characters: store ?? CharacterStore(),
    characterDict: CharacterDict.parse(_tsv),
    streamChat: (req) {
      seen?.add(req);
      return Stream.value(replies[turn++]);
    },
  );
}

void main() {
  group('内置角色库', () {
    final dict = CharacterDict.parse(_tsv);

    test('按名字找:完全对上的最前,再是去掉括号对上的;下划线、词序、作品名都认', () {
      expect(dict.search('hatsune_miku').single.outfit, 'detached sleeves');
      expect(dict.search('miku vocaloid').single.name, 'hatsune miku');
      expect(dict.search('ganyu').map((c) => c.name), [
        'ganyu (genshin impact)',
        'ganyu (twilight blossom) (genshin impact)',
      ]);
      expect(dict.search('  '), isEmpty);
      // 中文、日文的别名也认;别名完全对上的排在只是沾边的前面。
      expect(dict.search('初音未来').single.name, 'hatsune miku');
      expect(dict.search('miku').single.name, 'hatsune miku');
      expect(dict.search('甘雨').first.name, 'ganyu (genshin impact)');
      expect(dict.search('查无此人'), isEmpty);
    });

    test('按名字找系列:完全对上的最前,下划线和大小写不分', () {
      expect(dict.searchSeries('GENSHIN_impact').single.name, 'genshin impact');
      expect(dict.searchSeries('voca').single.name, 'vocaloid');
      expect(dict.searchSeries('原神'), isEmpty);
      expect(dict.searchSeries(' '), isEmpty);
    });

    test('按系列分组:角色多的系列在前,系列里图多的角色在前', () {
      expect(dict.series, [
        (name: 'genshin impact', count: 2),
        (name: 'vocaloid', count: 1),
        (name: 'original', count: 1),
      ]);
      expect(dict.inSeries('genshin impact').map((c) => c.name), [
        'ganyu (genshin impact)',
        'ganyu (twilight blossom) (genshin impact)',
      ]);
    });

    testWidgets('页面上先列系列,点一个进去看角色,再点回来', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CharactersPage(store: CharacterStore(), dict: dict),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(PennaChip, '内置'));
      await tester.pumpAndSettle();
      expect(find.text('genshin impact'), findsOneWidget);

      await tester.tap(find.text('genshin impact'));
      await tester.pumpAndSettle();
      expect(
        find.text('ganyu (genshin impact), genshin impact'),
        findsOneWidget,
      );
      expect(find.text('vocaloid'), findsNothing);

      await tester.tap(find.text('全部系列'));
      await tester.pumpAndSettle();
      expect(find.text('vocaloid'), findsOneWidget);
    });

    test('随程序打包的那份:合并好了,外貌和服装分开', () {
      final real = CharacterDict.parse(
        utf8.decode(
          gzip.decode(
            File('assets/danbooru_characters.tsv.gz').readAsBytesSync(),
          ),
        ),
      );
      expect(real.length, greaterThan(60000));
      final miku = real.search('hatsune miku').first;
      expect(characterTrigger(miku), 'hatsune miku, vocaloid');
      expect(miku.looks, contains('twintails'));
      expect(miku.looks, isNot(contains('sleeves')));
      expect(miku.outfit, contains('detached sleeves'));
      expect(real.search('初音未来').first.name, 'hatsune miku');
      expect(real.search('甘雨').first.name, 'ganyu (genshin impact)');
    });
  });

  test('回复里的两种标签拆得出来,给人看的话里不带;没写完的先不显示', () {
    final made = splitCharacterTags(
      '我查一下。\n<search-character>ganyu</search-character>\n'
      '<save-character name="小蓝">blue hair girl</save-character>',
    );
    expect(made.prose, '我查一下。');
    expect(made.queries, ['ganyu']);
    expect(made.saves, [(name: '小蓝', prompt: 'blue hair girl')]);

    expect(splitCharacterTags('好\n<search-character>gan').prose, '好');
    expect(splitCharacterTags('好 <save-char').prose, '好');
    expect(splitCharacterTags('好 <s').prose, '好');
  });

  group('用户自己存的角色', () {
    test('存、同名换掉、带图、删;重开读得回来', () async {
      final dir = Directory.systemTemp.createTempSync('penna_chars');
      final store = CharacterStore(dir);
      final first = store.put(
        name: '小蓝',
        prompt: 'blue hair',
        image: (bytes: [1, 2, 3], ext: 'png'),
      )!;
      expect(File(first.image).readAsBytesSync(), [1, 2, 3]);

      // 同名:换掉提示词,图留着。
      store.put(name: '小蓝', prompt: 'long blue hair');
      expect(store.cards.single.prompt, 'long blue hair');
      expect(store.cards.single.image, first.image);
      expect(store.put(name: ' ', prompt: 'x'), isNull);

      final again = CharacterStore(dir);
      await again.load();
      expect(again.find('画一张小蓝').single.prompt, 'long blue hair');

      again.remove(first.id);
      expect(again.cards, isEmpty);
      expect(File(first.image).existsSync(), isFalse);
    });

    test('别名能搜到;简介和几套服装重开读得回来;只换提示词时服装留着', () async {
      final dir = Directory.systemTemp.createTempSync('penna_chars');
      final store = CharacterStore(dir);
      store.put(
        name: 'phoenix reffaella',
        alias: '菲欧妮,小菲',
        intro: '王女',
        prompt: 'blonde hair',
        outfits: [
          (name: '礼服', prompt: 'white dress'),
          (name: '原装', prompt: ''),
          (name: ' ', prompt: ' '),
        ],
      );
      expect(store.find('画小菲').single.name, 'phoenix reffaella');
      // Agent 存同名角色只换提示词,别名、简介、服装不丢。
      store.put(name: 'phoenix reffaella', prompt: 'long blonde hair');

      final again = CharacterStore(dir);
      await again.load();
      final card = again.cards.single;
      expect(
        (card.alias, card.intro, card.prompt),
        ('菲欧妮,小菲', '王女', 'long blonde hair'),
      );
      expect(card.outfits, [
        (name: '礼服', prompt: 'white dress'),
        (name: '原装', prompt: ''),
      ]);
    });

    test('拖着换顺序;改一个不挪位置;只换图时存成 WebP', () {
      final dir = Directory.systemTemp.createTempSync('penna_chars');
      final store = CharacterStore(dir);
      for (final n in ['a', 'b', 'c']) {
        store.put(name: n, prompt: n);
      }
      String order() => store.cards.map((c) => c.name).join();
      expect(order(), 'cba');
      store.move(store.cards.last.id, store.cards.first.id);
      expect(order(), 'acb');
      store.put(name: 'b', prompt: 'bb');
      expect(order(), 'acb');
      store.setImage(store.cards.first.id, [9]);
      expect(store.cards.first.image, endsWith('.webp'));
      expect(store.cards.first.prompt, 'a');
    });
  });

  group('收藏内置的系列和角色', () {
    test('点一下收藏、再点取消;新收藏的在前;重开读得回来;坏文件留底', () async {
      final dir = Directory.systemTemp.createTempSync('penna_chars');
      final store = CharacterStore(dir)..put(name: '小蓝', prompt: 'blue');
      store.toggleSeries('vocaloid');
      store.toggleSeries('genshin impact');
      store.toggleCharacter('hatsune miku');
      expect(store.favoriteSeries, ['genshin impact', 'vocaloid']);
      expect(store.isFavoriteCharacter('hatsune miku'), isTrue);
      store.toggleSeries('vocaloid');
      expect(store.favoriteSeries, ['genshin impact']);

      final again = CharacterStore(dir);
      await again.load();
      expect(again.favoriteSeries, ['genshin impact']);
      expect(again.favoriteCharacters, ['hatsune miku']);
      // 收藏另存一个文件,「我的」那份没被改成别的格式。
      expect(
        jsonDecode(File('${dir.path}/characters.json').readAsStringSync()),
        isList,
      );

      File('${dir.path}/character_favorites.json').writeAsStringSync('{坏');
      final broken = CharacterStore(dir);
      await broken.load();
      expect(broken.favoriteSeries, isEmpty);
      expect(
        dir.listSync().where((f) => f.path.contains('favorites.json.bad-')),
        hasLength(1),
      );
    });

    test('按名字取回内置的角色和系列的角色数', () {
      final dict = CharacterDict.parse(_tsv);
      expect(dict.byName('hatsune miku')!.series, 'vocaloid');
      expect(dict.byName('没有这个'), isNull);
      expect(dict.countOf('genshin impact'), 2);
      expect(dict.countOf('没有这个'), 0);
    });

    testWidgets('「我的」「内置」「收藏」分开;收藏的系列和角色在收藏里', (tester) async {
      final store = CharacterStore()..put(name: '小蓝', prompt: 'blue hair');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CharactersPage(store: store, dict: CharacterDict.parse(_tsv)),
          ),
        ),
      );
      expect(find.text('小蓝'), findsOneWidget);
      expect(find.text('vocaloid'), findsNothing);

      await tester.tap(find.widgetWithText(PennaChip, '内置'));
      await tester.pumpAndSettle();
      expect(find.text('小蓝'), findsNothing);
      await tester.tap(find.byTooltip('收藏').first);
      await tester.tap(find.text('vocaloid'));
      await tester.pumpAndSettle();
      // 系列头上一颗星,角色卡上一颗星。
      await tester.tap(find.byTooltip('收藏').last);
      await tester.pump();
      expect(store.favoriteSeries, isNotEmpty);
      expect(store.favoriteCharacters, isNotEmpty);

      await tester.tap(find.widgetWithText(PennaChip, '收藏'));
      await tester.pumpAndSettle();
      expect(find.text('hatsune miku, vocaloid'), findsOneWidget);
      expect(find.text('genshin impact'), findsOneWidget);
    });
  });

  group('Agent 用角色库', () {
    test('查:结果交还给模型,外貌和服装分开,自己存的排在前面', () async {
      final seen = <LlmRequest>[];
      final store = CharacterStore()
        ..put(
          name: 'ganyu',
          alias: '小甘',
          intro: '秘书',
          prompt: 'my ganyu',
          outfits: [(name: '泳装', prompt: 'blue bikini')],
        );
      final vm = _studio(
        ['<search-character>ganyu</search-character>', '好了'],
        seen: seen,
        store: store,
      );

      vm.send('画甘雨,换一身泳装');
      await pumpEventQueue();

      expect(seen, hasLength(2));
      // 自己存了哪些角色,一开始就告诉了模型。
      expect(seen.first.messages.first['content'], contains('ganyu(别名:小甘)'));
      final handed = seen.last.messages.last['content']!;
      expect(handed, contains('提示词:my ganyu'));
      expect(handed, contains('别名:小甘'));
      expect(handed, contains('简介:秘书'));
      expect(handed, contains('服装·泳装:blue bikini'));
      expect(handed, contains('触发词:ganyu (genshin impact), genshin impact'));
      expect(handed, contains('外貌:1girl, goat horns, blue hair'));
      expect(handed, contains('服装:neck bell'));
      // 自己存的和内置的撞了名:要先问用户是哪一个。
      expect(handed, contains('先用 <options> 问用户指的是哪一个'));
      expect(vm.messages[2].toolSummary, '查了角色库 · 3 个');
      expect(vm.messages.last.text, '好了');
      expect(vm.isStreaming, isFalse);
    });

    test('只查到内置的:不用问', () async {
      final seen = <LlmRequest>[];
      final vm = _studio([
        '<search-character>miku</search-character>',
        '好了',
      ], seen: seen);

      vm.send('画初音');
      await pumpEventQueue();

      final handed = seen.last.messages.last['content']!;
      expect(handed, contains('hatsune miku'));
      expect(handed, isNot(contains('<options> 问用户')));
    });

    test('存:写进角色库,用户这次发来的图一起存;回复上记一笔', () async {
      final dir = Directory.systemTemp.createTempSync('penna_chars');
      final store = CharacterStore(dir);
      final vm = _studio([
        '存好了。<save-character name="小蓝">blue hair girl</save-character>',
      ], store: store);

      vm.send(
        '把她存进角色库,叫小蓝',
        attachments: [
          Attachment.image(
            name: 'a.png',
            mime: 'image/png',
            bytes: Uint8List.fromList([9]),
          ),
        ],
      );
      await pumpEventQueue();

      final card = store.cards.single;
      expect((card.name, card.prompt), ('小蓝', 'blue hair girl'));
      expect(File(card.image).readAsBytesSync(), [9]);
      expect(vm.messages.last.toolSummary, '已存进角色库:小蓝');
    });
  });
}
