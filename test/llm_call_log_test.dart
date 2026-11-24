import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/llm_log.dart';
import 'package:penna/core/harness/providers/llm_router.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/ui/core/llm_log_view.dart';
import 'package:penna/ui/core/theme.dart';

LlmRequest _req(String key) => LlmRequest(
  baseUrl: 'https://$key.example',
  model: 'm-$key',
  apiKey: key,
  messages: const [
    {'role': 'system', 'content': '你是助手'},
    {'role': 'user', 'content': '画一只猫'},
  ],
);

void main() {
  setUp(llmLog.clear);

  test('每次请求都记下发了什么、回了什么、出没出错', () async {
    final out = await streamWithFailover(
      [('甲', _req('a')), ('乙', _req('b'))],
      (req) => req.apiKey == 'a'
          ? Stream.error(const LlmException('接口返回 500'))
          : Stream.fromIterable(['<think>想一下</think>\n\n', '好的']),
    ).join();

    expect(out, contains('好的'));
    // 新的在前。
    final [second, first] = llmLog.calls;
    expect(first.name, '甲');
    expect(first.error, '接口返回 500');
    expect(first.took, isNotNull);
    expect(second.name, '乙');
    expect(second.model, 'm-b');
    expect(second.error, isNull);
    expect(second.messages.last['content'], '画一只猫');
    expect('${second.output}', '<think>想一下</think>\n\n好的');

    llmLog.clear();
    expect(llmLog.calls, isEmpty);
  });

  testWidgets('模型日志的「请求」里点一条:看得到发出去的话、思考和回复', (tester) async {
    await tester.runAsync(
      () => streamWithFailover([
        ('甲', _req('a')),
      ], (_) => Stream.fromIterable(['<think>想一下</think>\n\n', '好的'])).join(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: pennaTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLlmLog(context),
            child: const Text('开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('请求'));
    await tester.pumpAndSettle();
    expect(find.text('甲'), findsOneWidget);

    await tester.tap(find.text('甲'));
    await tester.pumpAndSettle();

    expect(find.text('你是助手'), findsOneWidget);
    expect(find.text('画一只猫'), findsOneWidget);
    expect(find.text('想一下'), findsOneWidget);
    expect(find.text('好的'), findsOneWidget);
  });
}
