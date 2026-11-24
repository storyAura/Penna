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

  test('自动归档的天数存得回来,默认关', () {
    expect(const AppConfig().autoArchiveDays, 0);
    expect(AppConfig.fromJson(<String, dynamic>{}).autoArchiveDays, 0);
    final saved = const AppConfig().copyWith(autoArchiveDays: 14).toJson();
    expect(AppConfig.fromJson(saved).autoArchiveDays, 14);
  });

  test('整个系列从档案库放回工作台:另起一个同名的系列,一条一页,页名跟着', () {
    final vm = sampleStudio(config: tempConfig());
    final before = vm.seriesCount;
    final time = DateTime(2026, 11, 8);

    final problem = vm.restoreSeries('旅馆', [
      (title: '第 1 页 · 床边', text: '【主体】a fox by the bed', time: time),
      (title: '第 2 页 · 解扣', text: '【主体】a fox by the door', time: time),
      (title: '', text: 'plain text', time: time),
    ]);

    expect(problem, isNull);
    expect(vm.seriesCount, before + 1);
    expect(vm.seriesName(vm.series), '旅馆');
    final pages = [
      for (final p in vm.pages)
        if (p.series == vm.series) p,
    ];
    expect(pages.map((p) => p.name), ['床边', '解扣', '']);
    expect(
      pages.first.blocks.map((b) => b.text).join(),
      contains('a fox by the bed'),
    );
    expect(pages.last.blocks.map((b) => b.text).join(), contains('plain text'));
    // 停在这个系列的第一页。
    expect(vm.pageNumber(vm.pageIndex), 1);

    expect(vm.restoreSeries('空', const []), isNotNull);
  });
}
