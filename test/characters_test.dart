import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/core/harness/characters/character_dict.dart';
import 'package:penna/core/harness/characters/character_mentions.dart';
import 'package:penna/core/harness/tags/tag_dictionary.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/character_store.dart';
import 'package:penna/ui/core/theme.dart';
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

    test('变身、换装后另起名字的形态:查到一个,本体和其他形态一起带出来', () {
      final dict = CharacterDict.parse(
        'moria luluka\tmeitantei precure!\t1girl, grey hair\tblack dress\n'
        'cure arcana shadow\tmeitantei precure!\t\tmagical girl\t\tmoria luluka\n'
        'akechi anna\tmeitantei precure!\t1girl, orange hair\t\n'
        'cure arcana\tmeitantei precure!\t1girl, blonde hair\t\t\tmoria luluka\n',
      );
      expect(dict.parentOf('cure arcana'), 'moria luluka');
      expect(dict.parentOf('moria luluka'), isNull);
      expect(dict.formsOf('moria luluka').map((h) => h.name), [
        'cure arcana shadow',
        'cure arcana',
      ]);
      // 查的是形态:先给本体,再给兄弟形态。
      expect(dict.formsOf('cure arcana').map((h) => h.name), [
        'moria luluka',
        'cure arcana shadow',
      ]);
      expect(dict.formsOf('akechi anna'), isEmpty);

      // 已经列过的不重复;用户自己存的原样留着,不找形态。
      final mine = (
        name: 'moria luluka',
        series: '',
        looks: '',
        outfit: '',
        prompt: 'my luluka',
        intro: '',
        outfits: const <({String name, String prompt})>[],
        alias: '',
      );
      final hits = dict.withForms([
        mine,
        ...dict.search('cure arcana'),
      ], perHit: 5);
      expect(hits.map((h) => h.name), [
        'moria luluka',
        'cure arcana',
        'moria luluka',
        'cure arcana shadow',
      ]);
      expect(hits.first.prompt, 'my luluka');

      final text = formatCharacterResults({
        'cure arcana': dict.withForms(dict.search('cure arcana')),
      }, formOf: dict.parentOf);
      expect(text, contains('形态:moria luluka 的另一个样子'));
      expect(
        RegExp('形态:').allMatches(text).length,
        2, // cure arcana 和 cure arcana shadow 两个形态
      );
    });

    testWidgets('角色卡:「只要服装」只复制服装,形态标出是谁的', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      final dict = CharacterDict.parse(
        'moria luluka\tmeitantei precure!\t1girl, grey hair\tblack dress, veil\n'
        'cure arcana\tmeitantei precure!\t1girl, blonde hair\tmagical girl\t\tmoria luluka\n',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: pennaTheme(),
          home: Scaffold(
            body: CharactersPage(store: CharacterStore(), dict: dict),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(PennaChip, '内置'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'moria luluka');
      await tester.pumpAndSettle();
      expect(find.text('moria luluka 的形态'), findsOneWidget);
      await tester.tap(find.text('只要服装').first);
      await tester.pump();
      expect(copied, 'black dress, veil');
      await tester.pumpAndSettle(const Duration(seconds: 3));
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
      // 形态:名字对不上的变身(来自 wiki)和挂着父标签的换装都认。
      expect(
        real.formsOf('moria luluka').map((h) => h.name),
        contains('cure arcana shadow'),
      );
      expect(real.parentOf('yuki miku'), 'hatsune miku');
      // 更正版里形态继承了本体的别名:按译名也找得到。
      expect(
        real.search('露露卡', limit: 10).map((h) => h.name),
        containsAll(['moria luluka', 'moria luluka (civilian)']),
      );
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

  group('程序替模型先查角色库', () {
    test('从一句话里认出角色:中日文别名、英文整词;普通的词不当人名', () {
      final dict = CharacterDict.parse(
        '$_tsv\n'
        'ninja (final fantasy)\tfinal fantasy\t1boy\t\t忍者, 忍者(FF)\n'
        'tenma\tinazuma eleven\t1boy\t\t松風天馬, 拓天, 雨天\n',
      );
      final mentions = CharacterMentions(
        dict,
        tags: TagDictionary.parse('ninja\t100\t忍者, しのび\n'),
      );
      expect(mentions.inText('画一张初音未来和甘雨的合照'), [
        'hatsune miku',
        'ganyu (genshin impact)',
      ]);
      expect(mentions.inText('draw Ganyu at the beach'), [
        'ganyu (genshin impact)',
      ]);
      // ganyuu 不是 ganyu;「忍者」是通用标签的意思;「雨天」排在后面的别名里不算。
      expect(mentions.inText('ganyuu, 一个忍者在雨天奔跑'), isEmpty);
      expect(mentions.inText('松風天馬踢球'), ['tenma']);
      expect(mentions.inText('甘雨 初音未来 松風天馬', limit: 2), hasLength(2));
    });

    test('模型不查也拿得到:提到的角色查好接在消息后面,回复上记一笔;系统提示最后钉着先查再写', () async {
      final seen = <LlmRequest>[];
      final store = CharacterStore()
        ..put(name: '小绿', prompt: 'green hair girl');
      final vm = _studio(['好了', '好了', '好了'], seen: seen, store: store);

      vm.send('画初音未来在雨里唱歌');
      await pumpEventQueue();
      final system = seen.last.messages.first['content']!;
      expect(system, contains('【先查再写】'));
      expect(system.indexOf('【先查再写】'), greaterThan(system.indexOf('【可用的技能】')));
      final asked = seen.last.messages.last['content']!;
      expect(asked, startsWith('画初音未来在雨里唱歌'));
      expect(asked, contains('【程序已按用户这句话里的名字查了角色库】'));
      expect(asked, contains('触发词:hatsune miku, vocaloid'));
      expect(vm.messages.last.toolSummary, '已按名字查了角色库:hatsune miku');

      // 用户自己存的也认;没提到角色的就不带。
      vm.send('给小绿画一张');
      await pumpEventQueue();
      expect(
        seen.last.messages.last['content'],
        contains('提示词:green hair girl'),
      );
      // 上一条的查询结果不再重发。
      expect(
        seen.last.messages[1]['content'],
        isNot(contains('【程序已按用户这句话里的名字查了角色库】')),
      );

      vm.config.update(
        vm.config.config.copyWith(disabledSkills: const {'character-lib'}),
      );
      vm.send('再画一张初音未来');
      await pumpEventQueue();
      expect(seen.last.messages.last['content'], '再画一张初音未来');
      expect(vm.messages.last.toolSummary, isNull);
    });

    test('点了上一条的选项:查回来的资料里写明这是回答,不要再问一遍', () async {
      final seen = <LlmRequest>[];
      final store = CharacterStore()..put(name: 'ganyu', prompt: 'my ganyu');
      final vm = _studio(
        ['<options>\nganyu(自己存的)\nganyu (genshin impact)\n</options>', '好了'],
        seen: seen,
        store: store,
      );

      vm.send('画 ganyu');
      await pumpEventQueue();
      expect(seen.last.messages.last['content'], isNot(contains('在回答你上一条')));

      vm.send('ganyu(自己存的)');
      await pumpEventQueue();
      final asked = seen.last.messages.last['content']!;
      expect(asked, contains('用户这句话是在回答你上一条用 <options> 问的问题'));
      expect(asked, contains('不要再问一遍'));
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
