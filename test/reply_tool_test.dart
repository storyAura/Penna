import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/providers/gemini_provider.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/core/harness/providers/reply_tool.dart';
import 'package:penna/data/models/app_config.dart';

/// 一段 SSE 的 tool_call 增量。
String _arg(String args, {int index = 0, String? name}) {
  final function = {'name': ?name, 'arguments': args};
  return 'data: ${jsonEncode({
    'choices': [
      {
        'delta': {
          'tool_calls': [
            {'index': index, 'function': function},
          ],
        },
      },
    ],
  })}\n\n';
}

LlmRequest _request(String baseUrl, {bool replyTool = true}) => LlmRequest(
  baseUrl: baseUrl,
  model: 'm',
  apiKey: 'k',
  messages: const [
    {'role': 'user', 'content': 'hi'},
  ],
  replyTool: replyTool,
);

void main() {
  group('ReplyTextReader', () {
    test('一整段参数解出 text', () {
      final reader = ReplyTextReader();
      final text = reader.add('{"text":"你好"}') + reader.flush();
      expect(text, '你好');
    });

    test('分好几段到,转义被切开也接得回去', () {
      final reader = ReplyTextReader();
      final out = StringBuffer();
      for (final chunk in ['{"te', 'xt":"第一', r'行\n第二\', 'u4e2d文', '\\"引号', '"}']) {
        out.write(reader.add(chunk));
      }
      out.write(reader.flush());
      expect(out.toString(), '第一行\n第二中文"引号');
    });

    test('前面有别的参数、键名之间隔着空白也认', () {
      final reader = ReplyTextReader();
      final text =
          reader.add('{"other": 1, "text" :  "好"}') + reader.flush();
      expect(text, '好');
    });

    test('没发收尾的引号时,flush 按整段 JSON 补上', () {
      final reader = ReplyTextReader();
      final out = StringBuffer()..write(reader.add('{"text":"写到一半'));
      out.write(reader.flush());
      expect(out.toString(), '写到一半');
    });

    test('解不出来的参数不吐出乱码', () {
      final reader = ReplyTextReader();
      expect(reader.add('{"foo":1}') + reader.flush(), '');
    });
  });

  group('回复写在工具调用里', () {
    test('请求带着 reply 工具,tool_choice 钉在它上面', () async {
      late Map<String, dynamic> sent;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        sent = jsonDecode(await utf8.decodeStream(request)) as Map<String, dynamic>;
        request.response.write(
          '${_arg('{"text":"好"}', name: replyToolName)}'
          'data: [DONE]\n\n',
        );
        await request.response.close();
      });

      await streamOpenAiChat(
        _request('http://127.0.0.1:${server.port}'),
      ).toList();

      final tools = sent['tools'] as List;
      expect((tools.single as Map)['function']['name'], replyToolName);
      expect(sent['tool_choice'], {
        'type': 'function',
        'function': {'name': replyToolName},
      });
    });

    test('流式回来的参数当普通回复吐出去,不再变成 <mcp-call>', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        await utf8.decodeStream(request);
        request.response
          ..write(_arg('{"text":"你', name: replyToolName))
          ..write(_arg(r'好\n世界'))
          ..write(_arg('"}'))
          ..write('data: [DONE]\n\n');
        await request.response.close();
      });

      final chunks = await streamOpenAiChat(
        _request('http://127.0.0.1:${server.port}'),
      ).toList();

      expect(chunks.join(), '你好\n世界');
      expect(chunks.join(), isNot(contains('<mcp-call>')));
    });

    test('接口无视 stream、整段回 JSON 时也解得出来', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        await utf8.decodeStream(request);
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'c1',
                      'type': 'function',
                      'function': {
                        'name': replyToolName,
                        'arguments': '{"text":"整段"}',
                      },
                    },
                  ],
                },
                'finish_reason': 'stop',
              },
            ],
          }),
        );
        await request.response.close();
      });

      final chunks = await streamOpenAiChat(
        _request('http://127.0.0.1:${server.port}'),
      ).toList();

      expect(chunks.join(), '整段');
    });

    test('接口不收 tool_choice 时退回普通回复,不是整条失败', () async {
      var calls = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request)) as Map;
        calls++;
        if (body.containsKey('tool_choice')) {
          request.response.statusCode = 400;
          request.response.write('{"error":{"message":"unknown field tool_choice"}}');
        } else {
          request.response.write(
            'data: {"choices":[{"delta":{"content":"普通回复"}}]}\n\n'
            'data: [DONE]\n\n',
          );
        }
        await request.response.close();
      });

      final chunks = await streamOpenAiChat(
        _request('http://127.0.0.1:${server.port}'),
      ).toList();

      expect(chunks.join(), '普通回复');
      expect(calls, 2);
    });
  });

  group('Google 接口', () {
    LlmRequest gemini(String baseUrl, {bool replyTool = true}) => LlmRequest(
      baseUrl: baseUrl,
      model: 'm',
      apiKey: 'k',
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
      replyTool: replyTool,
    );

    test('请求体带 reply 工具,toolConfig 钉死,同时放宽安全筛选', () {
      final body = geminiBody(gemini(''));

      final tools = body['tools'] as List;
      final declarations =
          (tools.single as Map)['functionDeclarations'] as List;
      expect((declarations.single as Map)['name'], replyToolName);
      expect(body['toolConfig'], {
        'functionCallingConfig': {
          'mode': 'ANY',
          'allowedFunctionNames': [replyToolName],
        },
      });
      final safety = body['safetySettings'] as List;
      expect(safety, hasLength(4));
      expect((safety.first as Map)['threshold'], 'BLOCK_NONE');
    });

    test('关着时不带工具和放宽的安全设定', () {
      final body = geminiBody(gemini('', replyTool: false));
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('toolConfig'), isFalse);
      expect(body.containsKey('safetySettings'), isFalse);
    });

    test('流式回来的 functionCall.text 当普通回复,不写成 <mcp-call>', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        await utf8.decodeStream(request);
        request.response
          ..write(
            'data: {"candidates":[{"content":{"parts":[{"functionCall":'
            '{"name":"$replyToolName","args":{"text":"你好"}}}]}}]}\n\n',
          )
          ..write(
            'data: {"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}\n\n',
          );
        await request.response.close();
      });

      final chunks = await streamGeminiChat(
        gemini('http://127.0.0.1:${server.port}'),
      ).toList();

      expect(chunks.join(), '你好');
      expect(chunks.join(), isNot(contains('<mcp-call>')));
    });

    test('接口不收 toolConfig 时退回普通回复,不是整条失败', () async {
      var calls = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request)) as Map;
        calls++;
        if (body.containsKey('toolConfig')) {
          request.response.statusCode = 400;
          request.response.write('{"error":{"message":"unknown field toolConfig"}}');
        } else {
          request.response.write(
            'data: {"candidates":[{"content":{"parts":[{"text":"普通回复"}]},'
            '"finishReason":"STOP"}]}\n\n',
          );
        }
        await request.response.close();
      });

      final chunks = await streamGeminiChat(
        gemini('http://127.0.0.1:${server.port}'),
      ).toList();

      expect(chunks.join(), '普通回复');
      expect(calls, 2);
    });
  });

  group('Preset 的开关', () {
    test('默认关,打开后存进设置再读回来还是开的', () {
      const preset = AgentPreset(
        id: 'p',
        name: 'p',
        systemPrompt: 'x',
        tools: {},
      );
      expect(preset.replyTool, isFalse);

      final back = AgentPreset.fromJson(
        jsonDecode(jsonEncode(preset.copyWith(replyTool: true).toJson()))
            as Map<String, dynamic>,
      );
      expect(back.replyTool, isTrue);
    });

    test('旧存档没有这一项时算关', () {
      final back = AgentPreset.fromJson({
        'id': 'p',
        'name': 'p',
        'systemPrompt': 'x',
        'tools': <String>[],
      });
      expect(back.replyTool, isFalse);
    });
  });
}
