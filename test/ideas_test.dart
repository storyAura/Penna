import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/characters/character_dict.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/data/services/character_store.dart';
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

  test('空对话要一次点子:角色从自己的和内置库里抽,带上 Preset;有话后作废,关掉就不要', () async {
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
        return Stream.value('给希罗画一套泳装\n用希罗画四格');
      },
    );
    addTearDown(vm.dispose);

    vm.wantIdeas();
    vm.wantIdeas();
    expect(vm.ideasBusy, isTrue);
    await pumpEventQueue();
    expect(asked, 1);
    expect(vm.ideaList, ['给希罗画一套泳装', '用希罗画四格']);
    final ask = seen!.messages.last['content']!;
    expect(ask, contains('希罗'));
    expect(ask, contains('初音未来(vocaloid)'));
    final system = seen!.messages.first['content']!;
    expect(
      system,
      contains(config.config.activePreset.systemPrompt.trim().substring(0, 20)),
    );
    expect(system, contains('不要赛博朋克'));

    vm.forgetIdeas();
    expect(vm.ideaList, isNull);

    config.update(config.config.copyWith(chatIdeas: false));
    vm.wantIdeas();
    expect(vm.ideasBusy, isFalse);
    expect(asked, 1);
  });
}
