import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/attachment.dart';
import 'package:penna/ui/features/studio/image_viewer.dart';

void main() {
  testWidgets('大图:箭头、← →、左右滑动换图,点空白处关掉', (tester) async {
    final album = [
      for (final n in ['a', 'b', 'c'])
        Attachment.image(
          name: '$n.png',
          mime: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showImageViewer(context, album[0], album: album),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tap(find.byTooltip('下一张'));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('c.png'), findsOneWidget);

    // 往右拖是前一张,拖动不算点空白。
    await tester.dragFrom(const Offset(300, 300), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tapAt(const Offset(100, 120));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsNothing);
  });

  testWidgets('大图:放大后快速拖动,松手就停,不顺着惯性漂', (tester) async {
    final a = Attachment.image(
      name: 'a.png',
      mime: 'image/png',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showImageViewer(context, a),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    Rect picture() => tester.getRect(find.byIcon(Icons.broken_image_outlined));

    const at = Offset(500, 300);
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(at));
    for (var i = 0; i < 4; i++) {
      await tester.sendEventToBinding(wheel.scroll(const Offset(0, -60)));
      await tester.pump();
    }
    final drag = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 5; i++) {
      await drag.moveBy(
        const Offset(-40, 0),
        timeStamp: Duration(milliseconds: 16 * i),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up(timeStamp: const Duration(milliseconds: 96));
    await tester.pump();
    final released = picture();
    await tester.pumpAndSettle();
    expect(picture().left, moreOrLessEquals(released.left, epsilon: 5));
  });
}
