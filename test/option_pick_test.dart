import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/draft_block.dart';
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

  test('问卷:<options form> 认得出,标题不算选项', () {
    final asked = splitOptions(
      '先定三件事。\n<options form>\n# 主体\n小绿\n小绿和千夏\n# 场景\n厨房\n阳台\n</options>',
    );
    expect((asked.form, asked.multi, asked.prose), (true, false, '先定三件事。'));
    expect(asked.options, ['小绿', '小绿和千夏', '厨房', '阳台']);
    expect(asked.headings, {0: '主体', 2: '场景'});
  });

  testWidgets('问卷:每项默认选第一个;点别的换过去,再点一下是「你定」;一次交', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormPick(
            options: const ['小绿', '小绿和千夏', '厨房', '阳台', '暖光', '冷光'],
            headings: const {0: '主体', 2: '场景', 4: '光线'},
            onSubmit: sent.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text('阳台'));
    await tester.tap(find.text('暖光'));
    await tester.pumpAndSettle();
    expect(find.text('你定'), findsOneWidget);
    await tester.tap(find.text('确定'));
    expect(sent, ['主体:小绿\n场景:阳台\n光线:你定']);
  });
}
