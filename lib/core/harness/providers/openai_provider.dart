import 'dart:convert';
import 'dart:io';

import 'llm_http.dart';
import 'reply_tool.dart';
import '../attachment.dart';
import '../llm_log.dart';
import '../thinking.dart';
import '../mcp/mcp_tools.dart';
import '../web_search.dart';
import '../../../l10n/l10n.dart';

export 'llm_http.dart';

/// 取出一行 SSE 里的增量文本;不是内容行(注释、心跳、空行)返回 null。
String? parseSseLine(String line) {
  final json = sseJson(line);
  if (json is! Map) return null;
  final error = json['error'];
  if (error != null) {
    throw LlmException(
      tr('模型返回错误:{0}', [error is Map ? error['message'] : error]),
    );
  }
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  final delta = first is Map ? first['delta'] : null;
  final content = delta is Map ? delta['content'] : null;
  return content is String ? content : null;
}

/// 一段流式数据里的思考:各家叫 `reasoning_content` 或 `reasoning`;没有是空的。
String parseSseThought(Object? json) {
  final choices = json is Map ? json['choices'] : null;
  final first = choices is List && choices.isNotEmpty ? choices.first : null;
  final delta = first is Map ? first['delta'] : null;
  if (delta is! Map) return '';
  final thought = delta['reasoning_content'] ?? delta['reasoning'];
  return thought is String ? thought : '';
}

/// `/models` 响应里的模型名;有的兼容接口不包 `data`,直接回一个数组。
List<String> parseOpenAiModels(Object? json) {
  final data = json is Map ? json['data'] : json;
  return [
    if (data is List)
      for (final m in data)
        if (m is Map && m['id'] is String) m['id'] as String,
  ];
}

/// 问 OpenAI 兼容接口有哪些模型。
Future<List<String>> listOpenAiModels(String baseUrl, String apiKey) async {
  final key = apiKey.trim();
  return parseOpenAiModels(
    await getJson(llmEndpoint(baseUrl, '/models'), {
      if (key.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $key',
    }),
  );
}

/// 请求里的消息;带图片的那条把 content 换成「文字 + 图片」的分段格式。
List<Map<String, Object?>> openAiMessages(LlmRequest req) => [
  for (final (i, m) in req.messages.indexed)
    if ((req.images[i] ?? const []).isEmpty)
      m
    else
      {
        'role': m['role'],
        'content': [
          if ((m['content'] ?? '').isNotEmpty)
            {'type': 'text', 'text': m['content']},
          for (final image in req.images[i]!)
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:${image.mime};base64,${base64Encode(image.bytes)}',
              },
            },
        ],
      },
];

/// 调用 OpenAI 兼容的 `/chat/completions`,逐段吐出回复文本。
Stream<String> streamOpenAiChat(LlmRequest req) =>
    _isLocal(req.baseUrl) && req.images.values.any((l) => l.any(_unreadable))
    ? Stream.fromFuture(localReadable(req)).asyncExpand(_stream)
    : _stream(req);

Stream<String> _stream(LlmRequest req) =>
    runLlmStream((client) => effortFallback(req, (r) => _chat(client, r)));

bool _isLocal(String baseUrl) => const {
  '127.0.0.1',
  'localhost',
  '::1',
}.contains(Uri.tryParse(baseUrl.trim())?.host);

bool _unreadable(LlmImage i) => i.mime != 'image/png' && i.mime != 'image/jpeg';

/// 本机的服务(llama.cpp、LM Studio 这类)读图只认 PNG、JPEG 这些,WebP 会被悄悄丢掉,
/// 模型当没图,乱编或出乱码(2026-11-13 用户反馈本地反推出乱码;「压缩大图」开着时大图都是
/// WebP)。发给本机地址时别的格式先转成 PNG(转不了的照原样);云端的接口都认,不动。
Future<LlmRequest> localReadable(LlmRequest req) async {
  if (!_isLocal(req.baseUrl)) return req;
  return req.withImages({
    for (final MapEntry(:key, :value) in req.images.entries)
      key: [
        for (final i in value)
          _unreadable(i)
              ? (
                  mime: 'image/png',
                  bytes: await pngOf(i.mime, i.bytes) ?? i.bytes,
                )
              : i,
      ],
  });
}

/// 写进 `reasoning_effort` 的值。DeepSeek 官方只有 low、high、max。
String? openAiEffort(LlmRequest req) =>
    Uri.tryParse(req.baseUrl.trim())?.host == 'api.deepseek.com'
    ? switch (req.effort) {
        'medium' => 'high',
        'xhigh' => 'max',
        final other => other,
      }
    : req.effort;

Stream<String> _chat(HttpClient client, LlmRequest req) async* {
  try {
    await for (final delta in _send(client, req, usage: true)) {
      yield delta;
    }
  } on LlmException catch (e) {
    final rejected =
        e.status == HttpStatus.badRequest ||
        e.status == HttpStatus.unprocessableEntity;
    // 有的中转站不认这个字段、整条请求报错:不要用量也得能用。
    if (rejected && e.message.contains('stream_options')) {
      yield* _send(client, req, usage: false);
      return;
    }
    // 接口不收 tool_choice 或工具表:退回普通请求,回复照旧能出来。
    if (rejected && req.replyTool) {
      llmLog.add(LlmEventKind.retry, req.model, tr('接口不支持工具调用,已改用普通回复'));
      yield* _send(client, req.withReplyTool(false), usage: true);
      return;
    }
    rethrow;
  }
}

Stream<String> _send(
  HttpClient client,
  LlmRequest req, {
  required bool usage,
}) async* {
  final apiKey = req.apiKey.trim();
  final lines = postForLines(
    client,
    llmEndpoint(req.baseUrl, '/chat/completions'),
    {if (apiKey.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $apiKey'},
    {
      'model': req.model,
      'messages': openAiMessages(req),
      'temperature': req.temperature,
      if (req.topP < 1) 'top_p': req.topP,
      'stream': true,
      if (usage) 'stream_options': {'include_usage': true},
      'reasoning_effort': ?openAiEffort(req),
      if (req.webSearch) ...?chatSearchBody(req.baseUrl),
      if (req.tools.isNotEmpty || req.replyTool)
        'tools': [
          ...openAiTools(req.tools),
          if (req.replyTool) openAiReplyTool(),
        ],
      // 钉死在 reply 上:模型只能用它回话,正文留空。
      if (req.replyTool)
        'tool_choice': {
          'type': 'function',
          'function': {'name': replyToolName},
        },
    },
    stall: llmStallFor(req),
  );

  var yielded = false;
  var done = false;
  String? finish;
  final plain = StringBuffer();
  final calls = OpenAiToolCalls();
  final thoughts = ThoughtStream();
  // 回复写在工具调用里时,参数一段段解成文字,当普通回复吐出去。
  final reply = req.replyTool ? ReplyTextReader() : null;
  await for (final line in lines) {
    // 排队时发的 `: keep-alive`,不是内容。
    if (line.startsWith(':')) continue;
    if (!line.startsWith('data:')) {
      plain.writeln(line);
      continue;
    }
    if (line.substring(5).trim() == '[DONE]') {
      done = true;
      break;
    }
    final json = sseJson(line);
    reportUsage(req, json);
    finish = _finishReason(json) ?? finish;
    calls.add(json);
    if (reply != null) {
      for (final args in _toolArgDeltas(json)) {
        final text = reply.add(args);
        if (text.isNotEmpty) {
          yielded = true;
          yield text;
        }
      }
    }
    final said = parseSseLine(line) ?? '';
    // 思考(reasoning_content)也给用户看,但不算出了字。
    final delta = thoughts.add(
      thought: req.thoughts ? parseSseThought(json) : '',
      text: said,
    );
    if (said.isNotEmpty) yielded = true;
    if (delta.isNotEmpty) yield delta;
  }
  if (reply != null) {
    final tail = reply.flush();
    if (tail.isNotEmpty) {
      yielded = true;
      yield tail;
    }
    if (yielded) _logReplyTool(req, reply.emitted > 0);
  }
  // 模型发的函数调用:换成 <mcp-call> 标签接在回复后面,后面的工具循环只认标签。
  // reply 是这个开关自己的工具,不当成外接工具。
  final tags = calls.text(skip: req.replyTool ? replyToolName : null);
  if (tags.isNotEmpty) {
    yielded = true;
    yield tags;
  }
  if (yielded) {
    // 有的中转站不给结束原因,但见到 [DONE] 就是说完了。
    final cut = finish != null || done ? openAiCut(finish) : LlmCut.broken;
    if (cut != null) req.onCut?.call(cut);
    return;
  }
  // 有的接口无视 stream:true,直接回一整个 JSON。
  final whole = _wholeReply(plain.toString(), req);
  if (whole == null) throw LlmException(tr('模型没有返回可识别的内容'));
  yield whole;
}

/// 让用户看得见这次到底有没有走工具:模型日志里一条,左侧栏不亮提醒。
void _logReplyTool(LlmRequest req, bool used) => llmLog.add(
  LlmEventKind.replyTool,
  req.model,
  used ? tr('回复来自工具调用') : tr('模型没用工具,回复在正文'),
);

/// 流式回来的这一行里,工具参数的文字片段(reply 那个工具的)。
Iterable<String> _toolArgDeltas(Object? json) sync* {
  final choices = json is Map ? json['choices'] : null;
  final first = choices is List && choices.isNotEmpty ? choices.first : null;
  final delta = first is Map ? first['delta'] : null;
  final list = delta is Map ? delta['tool_calls'] : null;
  if (list is! List) return;
  for (final c in list) {
    final fn = c is Map ? c['function'] : null;
    if (fn is! Map) continue;
    // 名字只在第一段有;还没给名字时先当成 reply(钉死了 tool_choice,只会有它)。
    final name = fn['name'] is String ? fn['name'] as String : '';
    if (name.isNotEmpty && name != replyToolName) continue;
    final args = fn['arguments'];
    if (args is String && args.isNotEmpty) yield args;
  }
}

/// 一整段参数(`{"text":"..."}`)解出来的话;解不出来是空串。
String _replyArgsText(String? args) {
  if (args == null || args.isEmpty) return '';
  final reader = ReplyTextReader();
  return reader.add(args) + reader.flush();
}

String? _finishReason(Object? json) {
  final choices = json is Map ? json['choices'] : null;
  final first = choices is List && choices.isNotEmpty ? choices.first : null;
  final reason = first is Map ? first['finish_reason'] : null;
  return reason is String ? reason : null;
}

/// 结束原因对应的没写完;写完了是 null。
LlmCut? openAiCut(String? reason) => switch (reason) {
  'length' => LlmCut.length,
  'content_filter' => LlmCut.blocked,
  'insufficient_system_resource' || 'aborted' => LlmCut.broken,
  _ => null,
};

String? _wholeReply(String body, LlmRequest req) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (json is! Map) return null;
  reportUsage(req, json);
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = choices.first;
  final message = first is Map ? first['message'] : null;
  final said = message is Map ? message['content'] : null;
  final calls = OpenAiToolCalls()
    ..add({
      'choices': [
        {'delta': message},
      ],
    });
  final reply = req.replyTool
      ? _replyArgsText(calls.argumentsOf(replyToolName))
      : '';
  final content = reply.isNotEmpty
      ? reply
      : '${said is String ? said : ''}'
            '${calls.text(skip: req.replyTool ? replyToolName : null)}';
  if (content.isEmpty) return null;
  if (req.replyTool) _logReplyTool(req, reply.isNotEmpty);
  if (openAiCut(_finishReason(json)) case final cut?) req.onCut?.call(cut);
  return content;
}

/// 工具表写成 `/chat/completions` 的 `tools`。
List<Map<String, Object?>> openAiTools(List<LlmTool> tools) => [
  for (final t in tools)
    {
      'type': 'function',
      'function': {
        'name': t.name,
        'description': t.description,
        'parameters': t.schema,
      },
    },
];

/// 攒流式回复里的函数调用:名字在第一段,参数的 JSON 一段段到,按 index 拼起来。
class OpenAiToolCalls {
  final _calls = <int, ({String name, StringBuffer args})>{};

  /// 读一行 SSE 的 JSON(或整段回复的 message 包成的 delta)。
  void add(Object? json) {
    final choices = json is Map ? json['choices'] : null;
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final delta = first is Map ? first['delta'] : null;
    final list = delta is Map ? delta['tool_calls'] : null;
    if (list is! List) return;
    for (final (i, c) in list.indexed) {
      if (c is! Map) continue;
      final index = c['index'] is int ? c['index'] as int : i;
      final fn = c['function'];
      final name = fn is Map && fn['name'] is String
          ? fn['name'] as String
          : '';
      final had = _calls[index];
      final call = _calls[index] = (
        name: (had?.name ?? '').isNotEmpty ? had!.name : name,
        args: had?.args ?? StringBuffer(),
      );
      if (fn is Map && fn['arguments'] is String) {
        call.args.write(fn['arguments']);
      }
    }
  }

  /// 攒好的调用写成 `<mcp-call>` 标签;没有是空串。[skip] 是不写进标签的调用名
  /// (回复写在工具调用里时,reply 不是外接工具)。
  String text({String? skip}) => [
    for (final c in _calls.values)
      if (c.name.isNotEmpty && c.name != skip)
        mcpCallText(c.name, c.args.toString()),
  ].join();

  /// 某个调用攒好的参数;没有是 null。
  String? argumentsOf(String name) {
    for (final c in _calls.values) {
      if (c.name == name) return c.args.toString();
    }
    return null;
  }
}
