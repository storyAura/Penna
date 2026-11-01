import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/ui/features/studio/option_pick.dart';

void main() {
  testWidgets('多选:勾几个发那几个,全选了发「全部」,没勾不能发', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiPick(
            items: const [
              (label: '主体', detail: '1girl, solo'),
              (label: '服装', detail: ''),
              (label: '场景', detail: 'outdoors'),
            ],
            onSubmit: sent.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text('确定'));
    expect(sent, isEmpty);

    // 先勾后面的再勾前面的:发出去按原来的先后。
    await tester.tap(find.text('场景'));
    await tester.tap(find.text('主体'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 / 3'), findsOneWidget);
    await tester.tap(find.text('确定'));
    expect(sent, ['主体、场景']);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    expect(sent.last, '全部');
    // 段的预览跟在标注后面。
    expect(find.text('1girl, solo'), findsOneWidget);
  });

  testWidgets('多选:分类小标题点不了,也不算进发出去的字和个数', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiPick(
            items: const [
              (label: '按推荐写', detail: ''),
              (label: '风格A', detail: ''),
              (label: '背景甲', detail: ''),
            ],
            headings: const {1: '风格', 2: '背景'},
            onSubmit: sent.add,
          ),
        ),
      ),
    );

    expect(find.text('风格'), findsOneWidget);
    expect(find.text('背景'), findsOneWidget);
    await tester.tap(find.text('风格'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 / 3'), findsOneWidget);

    await tester.tap(find.text('风格A'));
    await tester.tap(find.text('背景甲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    expect(sent, ['风格A、背景甲']);
  });
}
