import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/characters/character_dict.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/character_store.dart';
import 'package:penna/data/services/soul_store.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

const _llm = LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x/v1', model: 'm');

void main() {
  test('从回复里取点子:去掉编号、符号、引号和思考,最多 4 条', () {
    expect(
      parseIdeas(
        '<think>想想</think>\n1. 给初音未来画泳装\n- 「用芙莉莲画四格」\n\n'
        '• 3D 风格的猫\n2、第四条\n五\n六',
      ),
      ['给初音未来画泳装', '用芙莉莲画四格', '3D 风格的猫', '第四条'],
    );
  });

  test('空对话要一次点子:不随便抽角色,带上 Preset;有话后作废,关掉就不要', () async {
    LlmRequest? seen;
    var asked = 0;
    final characters = CharacterStore()..put(name: '希罗', prompt: 'x');
    final config = tempConfig()..update(const AppConfig().putLlm(_llm));
    final vm = StudioViewModel(
      config: config,
      characters: characters,
      characterDict: CharacterDict.parse(
        'hatsune_miku\tvocaloid\tlooks\toutfit\t初音未来\t\n',
      ),
      ideas: true,
      streamChat: (r) {
        asked++;
        seen = r;
        return Stream.value('雨夜的车站\n清晨的面包店');
      },
    );
    addTearDown(vm.dispose);

    vm.wantIdeas();
    vm.wantIdeas();
    expect(vm.ideasBusy, isTrue);
    await pumpEventQueue();
    expect(asked, 1);
    expect(vm.ideaList, ['雨夜的车站', '清晨的面包店']);
    final ask = seen!.messages.last['content']!;
    // 自己存的、内置热门的角色都不再随手抽进来。
    expect(ask, isNot(contains('希罗')));
    expect(ask, isNot(contains('初音未来')));
    expect(ask, contains('不要点名具体的作品角色'));
    final system = seen!.messages.first['content']!;
    expect(
      system,
      contains(config.config.activePreset.systemPrompt.trim().substring(0, 20)),
    );
    expect(system, contains('不要赛博朋克'));

    // 换一批:出过的叫模型别重复。
    vm.refreshIdeas();
    await pumpEventQueue();
    expect(seen!.messages.last['content'], contains('雨夜的车站'));

    vm.forgetIdeas();
    expect(vm.ideaList, isNull);

    config.update(config.config.copyWith(chatIdeas: false));
    vm.wantIdeas();
    expect(vm.ideasBusy, isFalse);
    expect(asked, 2);
  });

  test('常用角色三成的机会抽一个,次数越多越容易抽中', () {
    const cast = [(name: '希罗', count: 30), (name: '艾玛', count: 10)];
    // 骰子掷到三成以外:不带角色。
    expect(pickIdeaCast(cast, _Dice(0.3, 0)), isNull);
    expect(pickIdeaCast(const [], _Dice(0, 0)), isNull);
    // 签号 0–29 是希罗,30–39 是艾玛。
    expect(pickIdeaCast(cast, _Dice(0.29, 29)), '希罗');
    expect(pickIdeaCast(cast, _Dice(0.1, 30)), '艾玛');
    final random = Random(1);
    final picks = [for (var i = 0; i < 4000; i++) pickIdeaCast(cast, random)];
    final some = picks.whereType<String>();
    expect(some.length / picks.length, closeTo(ideaCastChance, 0.03));
    expect(
      some.where((n) => n == '希罗').length / some.length,
      closeTo(0.75, 0.05),
    );
  });

  test('点子里的常用角色名字照界面语言;没开 PennaSoul 不用', () async {
    LlmRequest? seen;
    final config = tempConfig()
      ..update(const AppConfig(soulOn: true).putLlm(_llm));
    final vm = StudioViewModel(
      config: config,
      characterDict: CharacterDict.parse(
        'kaname madoka\tmahou shoujo madoka magica\tl\to\tアルティメットまどか, 鹿目圆\t\n',
      ),
      ideas: true,
      streamChat: (r) {
        seen = r;
        return Stream.value('一');
      },
    );
    addTearDown(vm.dispose);
    final soul = SoulStore();
    vm.soul = soul;
    for (var i = 0; i < 6; i++) {
      soul.noteCharacters(['kaname madoka']);
    }

    // 三成的机会才带角色:换几批总会抽到(连着 60 批都没抽到的机会不到十亿分之一)。
    Future<String> askWithCast() async {
      for (var i = 0; i < 60; i++) {
        vm.refreshIdeas();
        await pumpEventQueue();
        final ask = seen!.messages.last['content']!;
        if (!ask.contains('不要点名具体的作品角色')) return ask;
      }
      fail('60 批都没带角色');
    }

    var ask = await askWithCast();
    expect(ask, contains('鹿目圆'));
    expect(ask, isNot(contains('アルティメット')));

    config.update(config.config.copyWith(language: 'ja'));
    ask = await askWithCast();
    expect(ask, contains('アルティメットまどか'));

    config.update(config.config.copyWith(soulOn: false));
    for (var i = 0; i < 10; i++) {
      vm.refreshIdeas();
      await pumpEventQueue();
      expect(seen!.messages.last['content'], contains('不要点名具体的作品角色'));
    }
  });
}

/// 掷出固定点数的骰子:[roll] 给 nextDouble,[ticket] 给 nextInt。
class _Dice implements Random {
  _Dice(this.roll, this.ticket);

  final double roll;
  final int ticket;

  @override
  double nextDouble() => roll;

  @override
  int nextInt(int max) => ticket;

  @override
  bool nextBool() => false;
}
