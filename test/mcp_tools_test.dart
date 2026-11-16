import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/mcp/mcp_client.dart';
import 'package:penna/core/harness/mcp/mcp_hub.dart';
import 'package:penna/core/harness/mcp/mcp_tools.dart';
import 'package:penna/core/harness/providers/gemini_provider.dart';
import 'package:penna/core/harness/providers/llm_router.dart';
import 'package:penna/core/harness/providers/openai_provider.dart';
import 'package:penna/core/harness/providers/responses_provider.dart';
import 'package:penna/data/models/app_config.dart';
import 'package:penna/ui/features/studio/studio_view_model.dart';

import 'fixtures.dart';

// 2026-11-16:Agent 调用户添加的 MCP 工具。原生函数调用和文字标签两条路
// 最后都是同一个 <mcp-call> 标签。

const _llm = LlmProfile(id: 'a', name: 'A', baseUrl: 'http://x/v1', model: 'm');

const LlmTool _weather = (
  name: 'mcp_wx_weather',
  description: '查天气',
  schema: {
    'type': 'object',
    'properties': {
      'city': {'type': 'string'},
    },
  },
);

LlmRequest _req({String protocol = 'openai'}) => LlmRequest(
  baseUrl: 'http://x/v1',
  model: 'm',
  apiKey: '',
  protocol: protocol,
  messages: const [
    {'role': 'system', 'content': 'S'},
    {'role': 'user', 'content': 'hi'},
  ],
  tools: const [_weather],
  toolsPrompt: mcpTextPrompt(const [_weather]),
  toolsNote: mcpNativeNote,
);

void main() {
  test('拆 <mcp-call>:参数是 JSON 对象;写错的带原因;半截的先不显示', () {
    final s = splitMcpCalls(
      '我查一下。<mcp-call tool="mcp_wx_weather">{"city": "上海"}</mcp-call>'
      "<mcp-call tool='b'>不是 JSON</mcp-call><mcp-call>{}</mcp-call>",
    );
    // 没写 tool 的也从正文里藏掉,不调。
    expect(s.prose, '我查一下。');
    expect(s.calls.map((c) => c.tool), ['mcp_wx_weather', 'b']);
    expect(s.calls.first.args, {'city': '上海'});
    expect(s.calls.first.problem, isNull);
    expect(s.calls.last.problem, isNotNull);
    expect(splitMcpCalls('好<mcp-ca').prose, '好');
    expect(splitMcpCalls('好<mcp-call tool="x">{"a"').prose, '好');
  });

  test('文字标签的说明列出工具和参数表;结果交还时标明是资料', () {
    final prompt = mcpTextPrompt(const [_weather]);
    expect(prompt, contains('mcp_wx_weather:查天气'));
    expect(prompt, contains('"city"'));
    expect(mcpTextPrompt(const []), '');
    final back = formatMcpResults([
      (tool: 'a', text: '晴', failed: false),
      (tool: 'b', text: '连不上', failed: true),
    ]);
    expect(back, contains('<mcp-result tool="a">'));
    expect(back, contains('<mcp-result tool="b" failed="true">'));
    expect(mcpToolsIn(back), ['a', 'b']);
  });

  test('两条路:原生的发工具表、系统提示只多一句;文字的不发表、说明接进系统提示', () {
    final native = _req().asNativeTools();
    expect(native.tools.single.name, 'mcp_wx_weather');
    expect(native.messages.first['content'], 'S\n\n$mcpNativeNote');
    final text = _req().asTextTools();
    expect(text.tools, isEmpty);
    expect(text.messages.first['content'], contains('<mcp-call tool='));
    expect(text.messages.last['content'], 'hi');
  });

  test('OpenAI:流式的函数调用按 index 拼好,换成标签', () {
    final calls = OpenAiToolCalls();
    for (final chunk in [
      {
        'tool_calls': [
          {
            'index': 0,
            'function': {'name': 'mcp_wx_weather', 'arguments': '{"ci'},
          },
        ],
      },
      {
        'tool_calls': [
          {
            'index': 0,
            'function': {'arguments': 'ty":"上海"}'},
          },
        ],
      },
    ]) {
      calls.add({
        'choices': [
          {'delta': chunk},
        ],
      });
    }
    final s = splitMcpCalls(calls.text);
    expect(s.calls.single.tool, 'mcp_wx_weather');
    expect(s.calls.single.args, {'city': '上海'});
    expect(openAiTools(const [_weather]).single['type'], 'function');
  });

  test('Google、Responses:函数调用换成标签,工具表写进请求', () {
    final gemini = parseGeminiCalls(
      'data: ${jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'name': 'mcp_wx_weather',
                    'args': {'city': '北京'},
                  },
                },
              ],
            },
          },
        ],
      })}',
    );
    expect(splitMcpCalls(gemini).calls.single.args, {'city': '北京'});
    final body = geminiBody(_req(protocol: 'google').asNativeTools());
    final decl =
        ((body['tools'] as List).single as Map)['functionDeclarations'];
    expect((decl as List).single['name'], 'mcp_wx_weather');

    final responses = parseResponsesCall(
      'data: ${jsonEncode({
        'type': 'response.output_item.done',
        'item': {'type': 'function_call', 'name': 'mcp_wx_weather', 'arguments': '{"city":"广州"}'},
      })}',
    );
    expect(splitMcpCalls(responses).calls.single.args, {'city': '广州'});
    final tools = responsesBody(_req().asNativeTools())['tools'] as List;
    expect((tools.single as Map)['name'], 'mcp_wx_weather');
  });

  test('接口不收工具表(400)就退回文字标签,之后这个模型直接用文字标签', () async {
    final sent = <LlmRequest>[];
    Stream<String> send(LlmRequest r) async* {
      sent.add(r);
      if (r.tools.isNotEmpty) {
        throw const LlmException('tools not supported', status: 400);
      }
      yield 'ok';
    }

    final req = LlmRequest(
      baseUrl: 'http://fallback-test/v1',
      model: 'm1',
      apiKey: '',
      messages: const [
        {'role': 'system', 'content': 'S'},
      ],
      tools: const [_weather],
      toolsPrompt: 'TEXT TOOLS',
      toolsNote: 'NATIVE',
    );
    expect(await toolsFallback(req, send).join(), 'ok');
    expect(sent.map((r) => r.tools.length), [1, 0]);
    expect(sent.last.messages.first['content'], 'S\n\nTEXT TOOLS');
    // 记住了:第二次直接走文字标签。
    sent.clear();
    expect(await toolsFallback(req, send).join(), 'ok');
    expect(sent.map((r) => r.tools.length), [0]);
  });

  test('工具总台:列启用的服务,起各家都认的函数名;调不成的把原因当结果', () async {
    final listed = <String>[];
    final config = const AppConfig().copyWith(
      mcpServers: const [
        McpServer(id: '1', name: '天气 Weather', url: 'http://w'),
        McpServer(id: '2', name: '关掉的', url: 'http://off', enabled: false),
        McpServer(id: '3', name: '中文名', url: 'http://c'),
      ],
    );
    final hub = McpHub(
      () => config,
      list: (s, _) async {
        listed.add(s.id);
        if (s.id == '3') throw const McpException('连不上');
        return const [McpTool('get-weather', '查天气')];
      },
      call: (s, _, tool, args) async {
        if (args['city'] == '火星') throw const McpException('工具报错:没有这个城市');
        return '${s.name}/$tool:${args['city']} 晴';
      },
    );
    await hub.refresh();
    await hub.refresh();
    // 关掉的不列;列过的不再列;失败的过一会儿才再试。
    expect(listed, ['1', '3']);
    final name = hub.tools.single.name;
    expect(name, 'mcp_Weather_get_weather');
    expect(RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(name), isTrue);

    final ok = await hub.call((
      tool: name,
      args: {'city': '上海'},
      problem: null,
    ));
    expect(ok.text, '天气 Weather/get-weather:上海 晴');
    expect(ok.failed, isFalse);
    final bad = await hub.call((
      tool: name,
      args: {'city': '火星'},
      problem: null,
    ));
    expect(bad.failed, isTrue);
    expect(bad.text, contains('没有这个城市'));
    final missing = await hub.call((tool: 'nope', args: {}, problem: null));
    expect(missing.failed, isTrue);
  });

  test('对话里:请求带着工具表,回复里的调用替模型做完,结果交还,模型接着写', () async {
    final seen = <LlmRequest>[];
    final replies = [
      '查一下。<mcp-call tool="mcp_Weather_get_weather">{"city":"上海"}</mcp-call>',
      '上海今天晴。',
    ];
    final config = tempConfig()
      ..update(
        const AppConfig()
            .putLlm(_llm)
            .copyWith(
              mcpServers: const [
                McpServer(id: '1', name: 'Weather', url: 'http://w'),
              ],
            ),
      );
    final hub = McpHub(
      () => config.config,
      list: (_, _) async => const [McpTool('get_weather', '查天气')],
      call: (_, _, _, args) async => '${args['city']}:晴',
    );
    await hub.refresh();
    final vm = StudioViewModel(
      config: config,
      streamChat: (r) {
        seen.add(r);
        return Stream.value(replies[seen.length - 1]);
      },
    );
    addTearDown(vm.dispose);
    vm.mcp = hub;

    vm.send('上海天气怎么样');
    await pumpEventQueue();
    expect(seen, hasLength(2));
    expect(seen.first.tools.single.name, 'mcp_Weather_get_weather');
    expect(seen.first.toolsPrompt, contains('mcp_Weather_get_weather'));
    final back = seen.last.messages.last['content']!;
    expect(back, contains('<mcp-result tool="mcp_Weather_get_weather">'));
    expect(back, contains('上海:晴'));
    expect(vm.messages.last.text, '上海今天晴。');
  });
}
