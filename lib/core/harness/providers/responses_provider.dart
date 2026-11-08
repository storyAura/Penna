import 'dart:convert';
import 'dart:io';

import '../../../l10n/l10n.dart';
import 'grok_auth.dart';
import 'llm_http.dart';

/// OpenAI 风格的 Responses 接口:Grok 账号登录和这类接口的联网搜索都走它。
/// 带图片的那条把 content 换成分段格式。
List<Map<String, Object?>> responsesInput(LlmRequest req) => [
  for (final (i, m) in req.messages.indexed)
    if ((req.images[i] ?? const []).isEmpty)
      {'role': m['role'], 'content': m['content'] ?? ''}
    else
      {
        'role': m['role'],
        'content': [
          if ((m['content'] ?? '').isNotEmpty)
            {'type': 'input_text', 'text': m['content']},
          for (final image in req.images[i]!)
            {
              'type': 'input_image',
              'image_url':
                  'data:${image.mime};base64,${base64Encode(image.bytes)}',
            },
        ],
      },
];

Map<String, Object?> responsesBody(LlmRequest req) => {
  'model': req.model,
  'input': responsesInput(req),
  'stream': true,
  'store': false,
  // 搜索用的模型五花八门,有的不收温度。
  if (!req.webSearch) ...{
    'temperature': req.temperature,
    if (req.topP < 1) 'top_p': req.topP,
  },
  if (req.effort case final effort?) 'reasoning': {'effort': effort},
  if (req.webSearch)
    'tools': [
      {'type': 'web_search'},
    ],
};

/// 一行 SSE 里的一件事:增量文字,或结束时带的来源(网址 → 标题)。出错时抛错。
({String? delta, Map<String, String> sources}) parseResponsesLine(
  String line,
) => _event(sseJson(line));

({String? delta, Map<String, String> sources}) _event(Object? json) {
  const none = (delta: null, sources: <String, String>{});
  if (json is! Map) return none;
  switch (json['type']) {
    case 'response.output_text.delta':
      final delta = json['delta'];
      return (delta: delta is String ? delta : null, sources: const {});
    case 'response.completed':
      return (delta: null, sources: _sources(json['response']));
    case 'response.failed':
      final response = json['response'];
      final error = response is Map ? response['error'] : null;
      throw LlmException(
        tr('模型返回错误:{0}', [
          clipLlmError(error is Map ? error['message'] : error),
        ]),
      );
    case 'error':
      throw LlmException(tr('模型返回错误:{0}', [clipLlmError(json['message'])]));
  }
  return none;
}

Map<String, String> _sources(Object? response) {
  final found = <String, String>{};
  if (response is! Map) return found;
  // xAI 还会直接给一张网址表。
  for (final url in response['citations'] as List? ?? const []) {
    if (url is String) found[url] = '';
  }
  for (final item in response['output'] as List? ?? const []) {
    if (item is! Map) continue;
    for (final part in item['content'] as List? ?? const []) {
      if (part is! Map) continue;
      for (final note in part['annotations'] as List? ?? const []) {
        if (note is Map && note['url'] is String) {
          found[note['url'] as String] = '${note['title'] ?? ''}';
        }
      }
    }
  }
  return found;
}

/// 搜索结果后面列的来源。
String sourcesText(Map<String, String> sources) => sources.isEmpty
    ? ''
    : '\n\nSources:\n${[for (final e in sources.entries) '- ${e.value.isEmpty ? e.key : '${e.value} ${e.key}'}'].join('\n')}';

Stream<String> streamResponsesChat(LlmRequest req) =>
    runLlmStream((client) => effortFallback(req, (r) => _chat(client, r)));

Stream<String> _chat(HttpClient client, LlmRequest req) async* {
  final login = req.token != null;
  final key = login ? await req.token!() : req.apiKey.trim();
  final lines = postForLines(
    client,
    llmEndpoint(login ? grokApiBase : req.baseUrl, '/responses'),
    {if (key.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $key'},
    responsesBody(req),
    stall: llmStallFor(req),
  );
  var yielded = false;
  LlmCut? cut = LlmCut.broken;
  final sources = <String, String>{};
  try {
    await for (final line in lines) {
      final json = sseJson(line);
      final event = _event(json);
      reportUsage(req, json);
      cut = switch (json) {
        {'type': 'response.completed'} => null,
        {'type': 'response.incomplete', 'response': final Object? response} =>
          responsesCut(response),
        _ => cut,
      };
      sources.addAll(event.sources);
      final delta = event.delta;
      if (delta != null && delta.isNotEmpty) {
        yielded = true;
        yield delta;
      }
      // 说完了就走,不等服务器关连接:有的服务(中转站)不关,要干等到超时。
      if (json case {'type': 'response.completed' || 'response.incomplete'}) {
        break;
      }
    }
  } on LlmException catch (e) {
    if (login && e.status == HttpStatus.forbidden) {
      throw LlmException(grokNoAccess);
    }
    if (login && e.status == HttpStatus.unauthorized) {
      throw LlmException(grokExpired);
    }
    rethrow;
  }
  if (!yielded) throw LlmException(tr('模型没有返回内容'));
  if (cut != null) req.onCut?.call(cut);
  if (req.webSearch && sources.isNotEmpty) yield sourcesText(sources);
}

/// `response.incomplete` 带的原因。
LlmCut responsesCut(Object? response) => switch (response) {
  {'incomplete_details': {'reason': 'content_filter'}} => LlmCut.blocked,
  {'incomplete_details': {'reason': 'max_output_tokens'}} => LlmCut.length,
  _ => LlmCut.broken,
};
