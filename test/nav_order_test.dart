import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/nav_pages.dart';

void main() {
  test('图标栏顺序:排过的在前,认不出的跳过,没排到的照默认接在后面;存盘读回', () {
    final ids = [for (final p in navPages) p.id];
    expect(orderedNav(const []).map((p) => p.id), ids);
    final mine = orderedNav(const ['notebook', 'gone', 'studio', 'notebook']);
    expect(mine.map((p) => p.id).take(2), ['notebook', 'studio']);
    expect(mine.map((p) => p.id).toSet(), ids.toSet());
    expect(mine, hasLength(ids.length));

    const cfg = AppConfig(navOrder: ['poses', 'studio']);
    expect(AppConfig.fromJson(cfg.toJson()).navOrder, ['poses', 'studio']);
    expect(const AppConfig().toJson().containsKey('navOrder'), isFalse);
  });
}
