import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/characters/character_dict.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/core/harness/soul_tags.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/character_store.dart';
import 'package:penna/data/services/soul_store.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

// 2026-11-16:PennaSoul(记着用户的约定和偏好)、按 Preset 出的对话点子。

const _llm = LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x/v1', model: 'm');

void main() {
  test('记一条:同样的话加分量;约定排在偏好前,偏好按分量排;删掉', () {
    final soul = SoulStore();
    soul.remember(soulLike, '喜欢厚涂');
    soul.remember(soulLike, '喜欢水彩');
    soul.remember(soulLike, ' 喜欢水彩 ');
    final rule = soul.remember(soulRule, '提到小绿就是自己存的小绿');
    expect(soul.entries.map((e) => e.text), ['提到小绿就是自己存的小绿', '喜欢水彩', '喜欢厚涂']);
    expect(soul.find('喜欢水彩')!.hits, 2);
    soul.forget(rule.id);
    expect(soul.find('提到小绿就是自己存的小绿'), isNull);
  });

  test('同一个角色提到够三次才记成偏好,之后再提加分量', () {
    final soul = SoulStore();
    expect(soul.noteCharacters(['芙莉莲']), isEmpty);
    expect(soul.noteCharacters(['芙莉莲', '希罗']), isEmpty);
    final added = soul.noteCharacters(['芙莉莲']);
    expect(added.single.text, '常用角色:芙莉莲');
    expect(soul.entries.single.kind, soulLike);
    soul.noteCharacters(['芙莉莲']);
    expect(soul.find('常用角色:芙莉莲')!.hits, 2);
  });

  test('存盘读回一样;读不了的文件留底', () async {
    final dir = Directory.systemTemp.createTempSync('penna-soul');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/soul.json');
    final soul = SoulStore(file)
      ..remember(soulRule, '约定 A')
      ..noteCharacters(['x']);
    final back = SoulStore(file);
    await back.load();
    expect(back.entries.single.text, '约定 A');
    // 次数也记着:再提两次就够三次。
    expect(back.noteCharacters(['x']), isEmpty);
    expect(back.noteCharacters(['x']), hasLength(1));
    expect(soul.entries, hasLength(1));

    file.writeAsStringSync('坏的');
    final broken = SoulStore(file);
    await broken.load();
    expect(broken.entries, isEmpty);
    expect(
      dir.listSync().any((f) => f.path.contains('soul.json.bad-')),
      isTrue,
    );
  });

  test('拆出 PennaSoul 标签:种类、要删的编号;半截的先不显示', () {
    final s = splitSoul(
      '好的。<soul-remember kind="rule">小绿是自己存的</soul-remember>'
      '<soul-remember>喜欢水彩</soul-remember><soul-forget> s2 </soul-forget>',
    );
    expect(s.prose, '好的。');
    expect(s.remember.map((n) => (n.kind, n.text)), [
      (soulRule, '小绿是自己存的'),
      (soulLike, '喜欢水彩'),
    ]);
    expect(s.forget, ['s2']);
    expect(splitSoul('写完了<soul-rem').prose, '写完了');
    expect(splitSoul('写完了<soul-remember kind="rule">半').prose, '写完了');
  });

  test('系统提示带着约定和偏好;回复里记的说完存上,删的删掉并记在回复上', () async {
    final seen = <LlmRequest>[];
    final replies = [
      '记住了。<soul-remember kind="rule">提到小绿就是用户自己存的小绿</soul-remember>',
      '取消了。<soul-forget>s1</soul-forget>',
    ];
    final config = tempConfig()..update(const AppConfig().putLlm(_llm));
    final vm = StudioViewModel(
      config: config,
      streamChat: (r) {
        seen.add(r);
        return Stream.value(replies[seen.length - 1]);
      },
    );
    addTearDown(vm.dispose);
    final soul = SoulStore()..remember(soulLike, '喜欢水彩');
    vm.soul = soul;

    vm.send('以后我说小绿就是我自己存的那个');
    await pumpEventQueue();
    final system = seen.first.messages.first['content']!;
    expect(system, contains('【PennaSoul】'));
    expect(system, contains('[s1] 喜欢水彩(1 次)'));
    expect(system, contains('<soul-remember kind="rule">'));
    final rule = soul.find('提到小绿就是用户自己存的小绿')!;
    expect(rule.kind, soulRule);

    vm.send('取消小绿那个约定');
    await pumpEventQueue();
    expect(seen.last.messages.first['content'], contains('[${rule.id}]'));
    // 回复里写的是 s1:删的是「喜欢水彩」那条。
    expect(soul.find('喜欢水彩'), isNull);
    expect(vm.messages.last.toolSummary, contains('喜欢水彩'));
  });

  test('用户提到角色就记一次,够三次记成偏好', () async {
    final config = tempConfig()..update(const AppConfig().putLlm(_llm));
    final vm = StudioViewModel(
      config: config,
      characters: CharacterStore()..put(name: '希罗', prompt: 'x'),
      streamChat: (_) => Stream.value('好'),
    );
    addTearDown(vm.dispose);
    final soul = SoulStore();
    vm.soul = soul;
    for (var i = 0; i < 3; i++) {
      vm.send('画希罗 $i');
      await pumpEventQueue();
    }
    expect(soul.find('常用角色:希罗'), isNotNull);
  });

  test('对话点子照眼前的 Preset 出,带上偏好;换了 Preset 重想', () async {
    final seen = <LlmRequest>[];
    final config = tempConfig()..update(const AppConfig().putLlm(_llm));
    final vm = StudioViewModel(
      config: config,
      characterDict: CharacterDict.parse(
        'hatsune_miku\tvocaloid\tl\to\t初音未来\t\n',
      ),
      ideas: true,
      streamChat: (r) {
        seen.add(r);
        return Stream.value('点子一\n点子二');
      },
    );
    addTearDown(vm.dispose);
    vm.soul = SoulStore()..remember(soulLike, '喜欢雨夜');

    vm.wantIdeas();
    await pumpEventQueue();
    expect(seen, hasLength(1));
    final first = seen.single.messages.first['content']!;
    expect(first, contains('喜欢雨夜'));
    expect(first, contains('照它的用途来'));

    // 同一个 Preset:不重想。
    vm.wantIdeas();
    expect(seen, hasLength(1));
    // 换成写视频的 Preset:重想,系统提示里是它。
    config.update(config.config.copyWith(activePresetId: minimaxH3PresetId));
    vm.wantIdeas();
    await pumpEventQueue();
    expect(seen, hasLength(2));
    expect(seen.last.messages.first['content'], contains('MiniMax H3'));
  });
}
