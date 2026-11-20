import 'dart:async';

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

  test('只有占比很大的常用角色才用,名字照界面语言', () async {
    LlmRequest? seen;
    final config = tempConfig()..update(const AppConfig().putLlm(_llm));
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
    // 只提过三次、占比不到四分之一的不用。
    for (var i = 0; i < 3; i++) {
      soul.noteCharacters(['希罗']);
    }
    for (var i = 0; i < 10; i++) {
      soul.noteCharacters(['路人 $i']);
    }

    vm.wantIdeas();
    await pumpEventQueue();
    var ask = seen!.messages.last['content']!;
    expect(ask, contains('鹿目圆'));
    expect(ask, isNot(contains('アルティメット')));
    expect(ask, isNot(contains('希罗')));

    config.update(config.config.copyWith(language: 'ja'));
    vm.refreshIdeas();
    await pumpEventQueue();
    ask = seen!.messages.last['content']!;
    expect(ask, contains('アルティメットまどか'));
  });
}
