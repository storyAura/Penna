import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('很久没用的系列算过期:眼前这个、固定的、刚用过的不算', () {
    final vm = sampleStudio(config: tempConfig());
    final first = vm.series;
    expect(vm.addPage(newSeries: true), isNull);
    final second = vm.series;
    expect(vm.addPage(newSeries: true), isNull);
    final third = vm.series;
    const idle = Duration(days: 14);
    final later = DateTime.now().add(const Duration(days: 15));

    // 刚建的都不过期。
    expect(vm.staleSeries(idle), isEmpty);
    // 十五天后:眼前的第三个留着,另外两个过期。
    expect(vm.staleSeries(idle, now: later), {first, second});

    vm.pinSeries(first, on: true);
    expect(vm.seriesPinned(first), isTrue);
    expect(vm.staleSeries(idle, now: later), {second});

    vm.pinSeries(first, on: false);
    expect(vm.staleSeries(idle, now: later), {first, second});
    expect(third, isNot(first));
  });

  test('固定和用过的时间存得回来;旧存档没记时间的不会一读进来就过期', () {
    final vm = sampleStudio(config: tempConfig());
    final first = vm.series;
    expect(vm.addPage(newSeries: true), isNull);
    vm.pinSeries(first, on: true);
    final saved = vm.toJson();
    expect(saved['seriesPinned'], [first]);
    expect((saved['seriesUsed'] as Map).keys, contains('${vm.series}'));

    final old = {...saved}
      ..remove('seriesUsed')
      ..remove('seriesPinned');
    final again = sampleStudio(config: tempConfig())..restore(old);
    expect(again.seriesPinned(first), isFalse);
    expect(again.staleSeries(const Duration(days: 14)), isEmpty);
  });

  test('自动归档的天数存得回来,默认 14 天', () {
    expect(const AppConfig().autoArchiveDays, 14);
    final saved = const AppConfig().copyWith(autoArchiveDays: 0).toJson();
    expect(AppConfig.fromJson(saved).autoArchiveDays, 0);
  });
}
