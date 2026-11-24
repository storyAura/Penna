import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

const _first = LlmProfile(
  id: 'a',
  name: '甲',
  baseUrl: 'http://a.local/v1',
  model: 'a1, a2',
);
const _second = LlmProfile(
  id: 'b',
  name: '乙',
  baseUrl: 'http://b.local/v1',
  model: 'b1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  /// 每个模型都失败,记下依次问了谁。
  Future<List<String>> asked(String mode) async {
    final config = tempConfig();
    config.update(
      const AppConfig().putLlm(_first).putLlm(_second).copyWith(failover: mode),
    );
    final models = <String>[];
    final vm = sampleStudio(
      config: config,
      streamChat: (req) {
        models.add(req.model);
        return Stream.error(const LlmException('接口返回 500'));
      },
    );
    expect(vm.send('你好'), isNull);
    await pumpEventQueue();
    return models;
  }

  test('换其他接口(默认):这家的第一个失败就换下一家', () async {
    expect(const AppConfig().failover, failoverAll);
    expect(await asked(failoverAll), ['a1', 'b1']);
  });

  test('只在这个接口里换模型:这家填的几个挨个试,不去别家', () async {
    expect(await asked(failoverProvider), ['a1', 'a2']);
  });

  test('不换:只问选中的那一个', () async {
    expect(await asked(failoverOff), ['a1']);
  });

  test('设置存得回来,认不出的值按默认', () {
    final saved = const AppConfig().copyWith(failover: failoverOff).toJson();
    expect(AppConfig.fromJson(saved).failover, failoverOff);
    expect(
      AppConfig.fromJson({...saved, 'failover': '乱写'}).failover,
      failoverAll,
    );
  });
}
