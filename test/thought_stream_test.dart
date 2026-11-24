import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/gemini_provider.dart';
import 'package:penna/core/harness/providers/llm_router.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/core/harness/thinking.dart';
import 'package:penna/ui/features/studio/chat_message.dart';

LlmRequest _req(String key) => LlmRequest(
  baseUrl: 'https://$key.example',
  model: 'm',
  apiKey: key,
  messages: const [
    {'role': 'user', 'content': 'q'},
  ],
);

void main() {
  test('接口单独给的思考包成 <think>,正文一来就关上', () {
    final t = ThoughtStream();

    final text = [
      t.add(thought: '先想'),
      t.add(thought: '再想'),
      t.add(text: '回答'),
      t.add(text: '完'),
    ].join();

    expect(text, '<think>先想再想</think>\n\n回答完');
    expect(splitThinking(text).thinking, '先想再想');
    expect(splitThinking(text).rest, '回答完');
  });

  test('读得出 Gemini 的思考摘要和 OpenAI 兼容接口的 reasoning_content', () {
    const gemini =
        'data: {"candidates":[{"content":{"parts":['
        '{"text":"想法","thought":true},{"text":"正文"}]}}]}';
    expect(parseGeminiThought(gemini), '想法');
    expect(parseGeminiLine(gemini), '正文');

    expect(
      parseSseThought({
        'choices': [
          {
            'delta': {'reasoning_content': '想法'},
          },
        ],
      }),
      '想法',
    );
    expect(parseSseThought({'choices': <Object>[]}), '');
  });

  test('只出了思考就失败:照样换下一个模型,半截的思考替它关上', () async {
    final out = await streamWithFailover(
      [('甲', _req('a')), ('乙', _req('b'))],
      (req) => req.apiKey == 'a'
          ? Stream.fromFuture(Future<String>.value('<think>想到一半')).asyncExpand(
              (s) => Stream<String>.multi((c) {
                c.add(s);
                c.addError(const LlmException('被拦了'));
              }),
            )
          : Stream.value('乙的回答'),
    ).join();

    expect(out, '<think>想到一半</think>\n\n乙的回答');
    expect(splitThinking(out).rest, '乙的回答');
  });

  test('回复说完时记下用了多久,存得回来', () {
    final started = DateTime.now().subtract(const Duration(seconds: 3));
    final m = settleThinking(
      ChatMessage(fromUser: false, text: '好', time: started),
    );

    expect(m.took!.inSeconds, greaterThanOrEqualTo(3));
    expect(
      ChatMessage.fromJson(m.toJson()).took!.inMilliseconds,
      m.took!.inMilliseconds,
    );
    // 已经记过的不再改。
    expect(settleThinking(m).took, m.took);
  });
}
