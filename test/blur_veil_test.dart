import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/core/blur_veil.dart';
import 'package:penna/ui/core/look_switcher.dart';

void main() {
  tearDown(() => blurImages.value = false);

  test('默认关,存进设置能读回,applyLook 跟着改', () {
    expect(const AppConfig().blurImages, isFalse);
    final on = const AppConfig().copyWith(blurImages: true);
    expect(AppConfig.fromJson(on.toJson()).blurImages, isTrue);

    TestWidgetsFlutterBinding.ensureInitialized();
    applyLook(on);
    expect(blurImages.value, isTrue);
  });

  group('BlurVeil', () {
    var opened = 0;
    const picture = Key('picture');

    Future<void> pump(WidgetTester tester) {
      opened = 0;
      return tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: BlurVeil(
              onOpen: () => opened++,
              child: const ColoredBox(
                key: picture,
                color: Colors.red,
                child: SizedBox.square(dimension: 100),
              ),
            ),
          ),
        ),
      );
    }

    bool blurred(WidgetTester tester) => tester
        .widgetList<ImageFiltered>(find.byType(ImageFiltered))
        .single
        .enabled;

    testWidgets('关着时点一下就是看大图,不模糊', (tester) async {
      await pump(tester);
      expect(find.byType(ImageFiltered), findsNothing);
      await tester.tap(find.byKey(picture));
      expect(opened, 1);
    });

    testWidgets('开着时先糊着,点一下看清,再点一下糊回去', (tester) async {
      blurImages.value = true;
      await pump(tester);
      expect(blurred(tester), isTrue);

      await tester.tap(find.byKey(picture));
      await tester.pumpAndSettle();
      expect(blurred(tester), isFalse);
      expect(opened, 0);

      // 看清之后右上角的按钮才是看大图。
      await tester.tap(find.byIcon(Icons.open_in_full));
      expect(opened, 1);

      await tester.tap(find.byKey(picture));
      await tester.pumpAndSettle();
      expect(blurred(tester), isTrue);
      expect(find.byIcon(Icons.open_in_full), findsNothing);
    });
  });
}
