import 'dart:convert';
import 'dart:io';

import 'llm_http.dart';
import '../attachment.dart';
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
      'reasoning_effort': ?openAiEffort(req),
      if (req.webSearch) ...?chatSearchBody(req.baseUrl),
    },
    stall: llmStallFor(req),
  );

  var yielded = false;
  var done = false;
  String? finish;
  final plain = StringBuffer();
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
    reportUsage(req, sseJson(line));
    finish = _finishReason(sseJson(line)) ?? finish;
    final delta = parseSseLine(line);
    if (delta != null && delta.isNotEmpty) {
      yielded = true;
      yield delta;
    }
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
  final content = message is Map ? message['content'] : null;
  if (content is! String || content.isEmpty) return null;
  if (openAiCut(_finishReason(json)) case final cut?) req.onCut?.call(cut);
  return content;
}
