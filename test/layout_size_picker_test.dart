import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/layout/layout_board.dart';
import 'package:penna/ui/features/layout/layout_size_picker.dart';

void main() {
  test('宽高比约得简单就写成整数比', () {
    expect(aspectLabel(832, 1216), '13:19');
    expect(aspectLabel(1024, 1024), '1:1');
    expect(aspectLabel(1000, 997), '1.00:1');
  });

  test('分辨率对齐默认 16,存下读回,超出范围的截到 1 到 256', () {
    expect(const AppConfig().layoutSnap, 16);
    final c = const AppConfig().copyWith(layoutSnap: 64);
    expect(AppConfig.fromJson(c.toJson()).layoutSnap, 64);
    expect(AppConfig.fromJson({'layoutSnap': 999}).layoutSnap, 256);
    expect(AppConfig.fromJson({'layoutSnap': 0}).layoutSnap, 1);
  });

  testWidgets('拖右上角松手才换画布,存下的尺寸点一下换过去', (tester) async {
    final board = LayoutBoard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: LayoutSizePicker(board: board, snap: () => 16),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.aspect_ratio));
    await tester.pumpAndSettle();

    // 拖动板 240 宽,默认范围 ≤ 2048:一像素约 8.5,拖到正中间是 1024×1024。
    final box = tester.getRect(find.byKey(sizePadKey));
    final gesture = await tester.startGesture(
      box.bottomLeft + const Offset(5, -5),
    );
    await gesture.moveTo(box.center);
    await tester.pump();
    expect(board.layout.width, isNot(1024), reason: '拖着时还没换');
    await gesture.up();
    await tester.pump();
    expect((board.layout.width, board.layout.height), (1024, 1024));

    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pump();
    expect(board.sizes.last, (width: 1024, height: 1024));

    board.setSize(832, 1216);
    await tester.pump();
    await tester.tap(find.text('1024×1024'));
    await tester.pump();
    expect((board.layout.width, board.layout.height), (1024, 1024));
  });
}
