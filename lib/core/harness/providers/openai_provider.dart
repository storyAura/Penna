import 'dart:convert';
import 'dart:io';

import 'llm_http.dart';
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
    runLlmStream((client) => _chat(client, req));

Stream<String> _chat(HttpClient client, LlmRequest req) async* {
  try {
    await for (final delta in _send(client, req, usage: true)) {
      yield delta;
    }
  } on LlmException catch (e) {
    // 有的中转站不认这个字段、整条请求报错:不要用量也得能用。
    final rejected =
        e.status == HttpStatus.badRequest ||
        e.status == HttpStatus.unprocessableEntity;
    if (!rejected || !e.message.contains('stream_options')) rethrow;
    yield* _send(client, req, usage: false);
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
      if (req.webSearch) ...?chatSearchBody(req.baseUrl),
    },
  );

  var yielded = false;
  final plain = StringBuffer();
  await for (final line in lines) {
    if (!line.startsWith('data:')) {
      plain.writeln(line);
      continue;
    }
    if (line.substring(5).trim() == '[DONE]') break;
    reportUsage(req, sseJson(line));
    final delta = parseSseLine(line);
    if (delta != null && delta.isNotEmpty) {
      yielded = true;
      yield delta;
    }
  }
  if (yielded) return;
  // 有的接口无视 stream:true,直接回一整个 JSON。
  final whole = _wholeReply(plain.toString(), req);
  if (whole == null) throw LlmException(tr('模型没有返回可识别的内容'));
  yield whole;
}

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
  final content = message is Map ? message['content'] : null;
  return content is String && content.isNotEmpty ? content : null;
}
