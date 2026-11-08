import 'dart:convert';
import 'dart:io';

import 'llm_http.dart';
import 'responses_provider.dart' show sourcesText;
import '../../../l10n/l10n.dart';

const _normalFinish = {'STOP', 'MAX_TOKENS', 'FINISH_REASON_UNSPECIFIED'};
const _defaultBase = 'https://generativelanguage.googleapis.com/v1beta';

/// 把 OpenAI 格式的消息转成 Google 的请求体:system 单独放,
/// assistant 改叫 model,连续同一方的消息合并(Google 要求一问一答交替)。
Map<String, Object?> geminiBody(LlmRequest req) {
  final system = <String>[];
  final contents =
      <({String role, List<String> texts, List<LlmImage> images})>[];
  for (final (i, m) in req.messages.indexed) {
    final text = m['content'] ?? '';
    final images = req.images[i] ?? const <LlmImage>[];
    // Google 不接受空白的文字段;只有图片的消息照发。
    final blank = text.trim().isEmpty;
    if (blank && images.isEmpty) continue;
    if (m['role'] == 'system') {
      if (!blank) system.add(text);
      continue;
    }
    final role = m['role'] == 'assistant' ? 'model' : 'user';
    if (contents.isEmpty || contents.last.role != role) {
      contents.add((role: role, texts: [], images: []));
    }
    if (!blank) contents.last.texts.add(text);
    contents.last.images.addAll(images);
  }
  return {
    if (system.isNotEmpty)
      'systemInstruction': {
        'parts': [
          {'text': system.join('\n\n')},
        ],
      },
    'contents': [
      for (final c in contents)
        {
          'role': c.role,
          'parts': [
            if (c.texts.isNotEmpty) {'text': c.texts.join('\n\n')},
            for (final image in c.images)
              {
                'inlineData': {
                  'mimeType': image.mime,
                  'data': base64Encode(image.bytes),
                },
              },
          ],
        },
    ],
    'generationConfig': {
      'temperature': req.temperature,
      if (req.topP < 1) 'topP': req.topP,
      'thinkingConfig': ?_thinkingConfig(req),
    },
    if (req.webSearch)
      'tools': [
        {'google_search': <String, Object>{}},
      ],
  };
}

/// Gemini 2.x 按 token 数给思考预算,更新的模型按档位给;两个字段不能同时给。
/// 没有「极高」这一档,按最高的算。
///
/// 带上 `includeThoughts`:不带时模型默默想完才回第一个字,想得久(看图、长文)时
/// 一个字节都没有,用户的代理约 47 秒就把连接掐了(2026-11-07 实测);带上后
/// 边想边发思考摘要,连接一直有数据。摘要由 [parseGeminiLine] 去掉,不进回复。
Map<String, Object>? _thinkingConfig(LlmRequest req) {
  final effort = req.effort;
  if (effort == null) return null;
  return {
    if (req.model.startsWith('gemini-2'))
      'thinkingBudget': switch (effort) {
        'low' => 1024,
        'medium' => 8192,
        _ => 24576,
      }
    else
      'thinkingLevel': effort == 'xhigh' ? 'high' : effort,
    'includeThoughts': true,
  };
}

/// 一行 SSE 里 Google 搜索用到的网页:网址 → 标题。
Map<String, String> parseGeminiSources(String line) => _sources(sseJson(line));

Map<String, String> _sources(Object? json) {
  final candidates = json is Map ? json['candidates'] : null;
  final first = candidates is List && candidates.isNotEmpty
      ? candidates.first
      : null;
  final grounding = first is Map ? first['groundingMetadata'] : null;
  final chunks = grounding is Map ? grounding['groundingChunks'] : null;
  return {
    if (chunks is List)
      for (final c in chunks)
        if (c is Map && c['web'] is Map && c['web']['uri'] is String)
          c['web']['uri'] as String: '${c['web']['title'] ?? ''}',
  };
}

/// 取出一行 SSE 里的增量文本;被安全策略拦截时抛错。
String? parseGeminiLine(String line) => _delta(sseJson(line));

String? _delta(Object? json) {
  if (json is! Map) return null;
  final error = json['error'];
  if (error != null) {
    throw LlmException(
      tr('模型返回错误:{0}', [error is Map ? error['message'] : error]),
    );
  }
  final feedback = json['promptFeedback'];
  final blocked = feedback is Map ? feedback['blockReason'] : null;
  if (blocked != null) throw LlmException(tr('请求被 Google 拦截:{0}', [blocked]));
  final candidates = json['candidates'];
  if (candidates is! List || candidates.isEmpty) return null;
  final first = candidates.first;
  final content = first is Map ? first['content'] : null;
  final parts = content is Map ? content['parts'] : null;
  final text = [
    if (parts is List)
      for (final p in parts)
        // 思考摘要不是回复。
        if (p is Map && p['text'] is String && p['thought'] != true)
          p['text'] as String,
  ].join();
  // 被安全策略等原因中止时往往一个字都没有,把原因报出来而不是只说"没内容"。
  final reason = first is Map ? first['finishReason'] : null;
  if (text.isEmpty && reason is String && !_normalFinish.contains(reason)) {
    throw LlmException(tr('Google 中止了回复:{0}', [reason]));
  }
  return text;
}

/// 一行 SSE 里的结束原因;这一行没写是 null。
String? parseGeminiFinish(String line) => _finish(sseJson(line));

String? _finish(Object? json) {
  final candidates = json is Map ? json['candidates'] : null;
  final first = candidates is List && candidates.isNotEmpty
      ? candidates.first
      : null;
  final reason = first is Map ? first['finishReason'] : null;
  return reason is String ? reason : null;
}

/// 结束原因对应的没写完;写完了是 null。一直没给原因就断了算没写完。
LlmCut? geminiCut(String? reason) => switch (reason) {
  null => LlmCut.broken,
  'STOP' || 'FINISH_REASON_UNSPECIFIED' => null,
  'MAX_TOKENS' => LlmCut.length,
  _ => LlmCut.blocked,
};

/// 实际用的接口地址:没填用默认的;填的是 Vertex AI(`aiplatform.googleapis.com`)
/// 时补到 Google 模型所在的那一层,后面拼 `/models/...` 的写法就两边通用。
String geminiBase(String baseUrl) {
  final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  if (base.isEmpty) return _defaultBase;
  final uri = Uri.tryParse(base);
  if (uri == null || !_isVertex(uri) || uri.path.contains('/publishers/')) {
    return base;
  }
  return '${uri.path.isEmpty ? '$base/v1' : base}/publishers/google';
}

/// 含各地区的写法,例如 `us-central1-aiplatform.googleapis.com`。
bool _isVertex(Uri uri) => uri.host.endsWith('aiplatform.googleapis.com');

/// `/models` 响应里能对话的模型名(去掉 `models/` 前缀)。
List<String> parseGeminiModels(Object? json) {
  final models = json is Map ? json['models'] : null;
  return [
    if (models is List)
      for (final m in models)
        if (m is Map && m['name'] is String && _canChat(m))
          (m['name'] as String).replaceFirst('models/', ''),
  ];
}

/// 没写支持哪些方法的当作能对话;写了的要有 generateContent(排除向量模型等)。
bool _canChat(Map<Object?, Object?> model) {
  final methods = model['supportedGenerationMethods'];
  return methods is! List || methods.contains('generateContent');
}

/// 问 Google 接口有哪些模型。
Future<List<String>> listGeminiModels(String baseUrl, String apiKey) async {
  final key = apiKey.trim();
  final plain = llmEndpoint(geminiBase(baseUrl), '/models');
  // Vertex AI 的模型列表不收 API Key(只认 OAuth 登录),问了也是 401。
  if (_isVertex(plain)) {
    throw LlmException(tr('Vertex AI 不能拉取模型,请手动填模型名'));
  }
  // ponytail: 只取第一页(上限 1000 个),目前远够用;不够时跟着 nextPageToken 翻页。
  final uri = plain.replace(queryParameters: {'pageSize': '1000'});
  return parseGeminiModels(
    await getJson(uri, {if (key.isNotEmpty) 'x-goog-api-key': key}),
  );
}

/// 调用 Google Gemini 原生接口 `models/{model}:streamGenerateContent`。
Stream<String> streamGeminiChat(LlmRequest req) =>
    runLlmStream((client) => effortFallback(req, (r) => _chat(client, r)));

Stream<String> _chat(HttpClient client, LlmRequest req) async* {
  final model = Uri.encodeComponent(req.model);
  final uri = llmEndpoint(
    geminiBase(req.baseUrl),
    '/models/$model:streamGenerateContent',
  ).replace(queryParameters: {'alt': 'sse'});
  final apiKey = req.apiKey.trim();
  // Key 放请求头而不是网址里,免得出现在任何报错或日志中。
  final lines = postForLines(
    client,
    uri,
    {if (apiKey.isNotEmpty) 'x-goog-api-key': apiKey},
    geminiBody(req),
    stall: llmStallFor(req),
  );

  var yielded = false;
  String? finish;
  final sources = <String, String>{};
  await for (final line in lines) {
    final json = sseJson(line);
    final delta = _delta(json);
    reportUsage(req, json);
    finish = _finish(json) ?? finish;
    if (req.webSearch) sources.addAll(_sources(json));
    if (delta != null && delta.isNotEmpty) {
      yielded = true;
      yield delta;
    }
  }
  if (!yielded) throw LlmException(tr('模型没有返回内容'));
  if (geminiCut(finish) case final cut?) req.onCut?.call(cut);
  if (sources.isNotEmpty) yield sourcesText(sources);
}
