import 'dart:convert';
import 'dart:io';

import '../llm_log.dart';
import '../mcp/mcp_tools.dart';
import 'llm_http.dart';
import 'reply_tool.dart';
import 'responses_provider.dart' show sourcesText;
import '../../../l10n/l10n.dart';

const _normalFinish = {'STOP', 'MAX_TOKENS', 'FINISH_REASON_UNSPECIFIED'};

/// 放宽安全筛选时给的四类(1.5 起的模型都认这些;更新的一类没有把握就不给)。
const _harmCategories = [
  'HARM_CATEGORY_HARASSMENT',
  'HARM_CATEGORY_HATE_SPEECH',
  'HARM_CATEGORY_SEXUALLY_EXPLICIT',
  'HARM_CATEGORY_DANGEROUS_CONTENT',
];
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
  // 回复写在工具调用里:多给一个 reply 工具,只准它被调用。
  final reply = req.replyTool;
  final functions = [
    for (final t in req.tools)
      {
        'name': t.name,
        'description': t.description,
        'parametersJsonSchema': t.schema,
      },
    if (reply)
      {
        'name': replyToolName,
        'description': tr('把这一轮回复的全部内容写在 text 里,正文留空。'),
        'parametersJsonSchema': const {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': '回复的全部内容,格式照要求'},
          },
          'required': ['text'],
          'additionalProperties': false,
        },
      },
  ];
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
    if (req.webSearch || functions.isNotEmpty)
      'tools': [
        if (req.webSearch) {'google_search': <String, Object>{}},
        // 外接工具(MCP):参数表原样给(`parametersJsonSchema` 收完整的 JSON Schema)。
        if (functions.isNotEmpty) {'functionDeclarations': functions},
      ],
    // 钉死在 reply 上:模型只能用这个工具回话。
    if (reply)
      'toolConfig': {
        'functionCallingConfig': {
          'mode': 'ANY',
          'allowedFunctionNames': [replyToolName],
        },
      },
    // Google 自己的安全筛选会把整段回复掐掉(报 PROHIBITED_CONTENT / SAFETY)。
    // 这个开关打开时一起放宽:内容要不要写由用户和模型决定,不是接口替用户决定。
    if (reply)
      'safetySettings': [
        for (final c in _harmCategories) {'category': c, 'threshold': 'BLOCK_NONE'},
      ],
    // 用量档位:Developer API 放在请求体最外层;Vertex 走请求头(见 [geminiHeaders])。
    if (req.serviceTier.isNotEmpty &&
        geminiTransport(req.baseUrl) == GeminiTransport.developer)
      'service_tier': req.serviceTier,
  };
}

/// Google 接口走哪条线。三条线的认证、地址、档位写法都不一样,不能混用
/// (2026-11-13 用户给的《Gemini 用量方案与 Penna 适配》)。
enum GeminiTransport {
  /// AI Studio 的 Gemini API(generativelanguage.googleapis.com),API Key。
  developer,

  /// Vertex Express:aiplatform.googleapis.com 不带项目的路径,API Key。
  vertexExpress,

  /// Vertex 项目路径(带 `/projects/{项目}/locations/{地区}`),认 OAuth 令牌。
  vertexProject,
}

GeminiTransport geminiTransport(String baseUrl) {
  final uri = Uri.tryParse(geminiBase(baseUrl));
  if (uri == null || !_isVertex(uri)) return GeminiTransport.developer;
  return uri.path.contains('/projects/')
      ? GeminiTransport.vertexProject
      : GeminiTransport.vertexExpress;
}

/// 这条线能不能选档位:Vertex Express 官方没写 Flex / Priority,不传。
bool geminiTierSupported(String baseUrl) =>
    geminiTransport(baseUrl) != GeminiTransport.vertexExpress;

/// 请求头:Key 放头里(不进网址);Vertex 项目路径填的是 OAuth 令牌(`ya29.` 开头,
/// `gcloud auth print-access-token` 给的)时用 Bearer。档位在 Vertex 项目路径上走头:
/// 先用已买的 Provisioned Throughput,溢出再按选的档位(不加 `Request-Type: shared`,
/// 免得跳过已买的容量)。
// ponytail: 没做「只用 PayGo」开关和 Vertex 的 OAuth 登录,令牌一小时过期要重填。
Map<String, String> geminiHeaders(LlmRequest req) {
  final key = req.apiKey.trim();
  final transport = geminiTransport(req.baseUrl);
  final project = transport == GeminiTransport.vertexProject;
  final tier = req.serviceTier;
  return {
    if (key.isNotEmpty && project && key.startsWith('ya29.'))
      'authorization': 'Bearer $key'
    else if (key.isNotEmpty)
      'x-goog-api-key': key,
    if (project && (tier == 'flex' || tier == 'priority'))
      'X-Vertex-AI-LLM-Shared-Request-Type': tier,
    // 服务端最多排队多久(秒),官方建议 Flex 给 600。
    if (project && tier == 'flex') 'X-Server-Timeout': '600',
  };
}

/// 一行 SSE 里接口说的实际档位(standard、flex、priority);这一行没写是 null。
/// Developer API 看 `usageMetadata.serviceTier`,Vertex 看 `usageMetadata.trafficType`。
String? parseGeminiTier(String line) {
  final json = sseJson(line);
  final usage = json is Map ? json['usageMetadata'] : null;
  if (usage is! Map) return null;
  final tier = usage['serviceTier'];
  if (tier is String) {
    final t = tier.toLowerCase().replaceFirst('service_tier_', '');
    return geminiTierNames.contains(t) ? t : null;
  }
  return switch (usage['trafficType']) {
    'ON_DEMAND_PRIORITY' => 'priority',
    'ON_DEMAND_FLEX' => 'flex',
    'ON_DEMAND' => 'standard',
    _ => null,
  };
}

const geminiTierNames = {'standard', 'flex', 'priority'};

/// Flex 排不上(429 / 503)时同一档位最多再试几次,每次等的时间翻倍。
const _flexRetries = 3;
const _flexBackoff = Duration(seconds: 5);

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
Map<String, String> parseGeminiSources(String line) {
  final json = sseJson(line);
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
String? parseGeminiLine(String line) {
  final json = sseJson(line);
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
String? parseGeminiFinish(String line) {
  final json = sseJson(line);
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

/// 一行里的函数调用(`functionCall` 分段),写成 `<mcp-call>` 标签;没有是空串。
/// [skip] 是不写进标签的调用名(回复写在工具调用里时,reply 不是外接工具)。
String parseGeminiCalls(String line, {String? skip}) {
  final json = sseJson(line);
  final candidates = json is Map ? json['candidates'] : null;
  final first = candidates is List && candidates.isNotEmpty
      ? candidates.first
      : null;
  final content = first is Map ? first['content'] : null;
  final parts = content is Map ? content['parts'] : null;
  return [
    if (parts is List)
      for (final p in parts)
        if (p is Map)
          if (p['functionCall'] case {'name': final String name} && final call)
            if (name != skip)
              mcpCallText(name, jsonEncode(call['args'] ?? const {})),
  ].join();
}

/// 一行里 reply 工具的参数(`{"text": "..."}` 里的 text);这一行没有是 null。
String? geminiReplyText(String line) {
  final json = sseJson(line);
  final candidates = json is Map ? json['candidates'] : null;
  final first = candidates is List && candidates.isNotEmpty
      ? candidates.first
      : null;
  final content = first is Map ? first['content'] : null;
  final parts = content is Map ? content['parts'] : null;
  if (parts is! List) return null;
  for (final p in parts) {
    if (p is! Map) continue;
    final call = p['functionCall'];
    if (call is! Map || call['name'] != replyToolName) continue;
    final args = call['args'];
    if (args is Map && args['text'] is String) return args['text'] as String;
  }
  return null;
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
  var yielded = false;
  var replyUsed = false;
  String? finish;
  String? served;
  final sources = <String, String>{};
  for (var attempt = 0; ; attempt++) {
    // Key 放请求头而不是网址里,免得出现在任何报错或日志中。
    final lines = postForLines(
      client,
      uri,
      geminiHeaders(req),
      geminiBody(req),
      stall: llmStallFor(req),
    );
    try {
      await for (final line in lines) {
        // 回复写在工具调用里:参数就是这一轮要说的话,当普通回复吐出去。
        final replyText = req.replyTool ? geminiReplyText(line) : null;
        if (replyText != null && replyText.isNotEmpty) replyUsed = true;
        // 模型发的函数调用:换成 <mcp-call> 标签接在回复里。
        final calls = req.tools.isEmpty && !req.replyTool
            ? ''
            : parseGeminiCalls(
                line,
                skip: req.replyTool ? replyToolName : null,
              );
        final delta = '${parseGeminiLine(line) ?? ''}$calls${replyText ?? ''}';
        reportUsage(req, sseJson(line));
        finish = parseGeminiFinish(line) ?? finish;
        served = parseGeminiTier(line) ?? served;
        if (req.webSearch) sources.addAll(parseGeminiSources(line));
        if (delta.isNotEmpty) {
          yielded = true;
          yield delta;
        }
      }
      break;
    } on LlmException catch (e) {
      // 接口不收 toolConfig、或者不认放宽的安全设定:退回普通请求,别让整条回复失败。
      if (!yielded &&
          (e.status == 400 || e.status == 422) &&
          req.replyTool) {
        llmLog.add(
          LlmEventKind.retry,
          req.model,
          tr('接口不支持把回复写在工具调用里,改用普通回复'),
        );
        yield* _chat(client, req.withReplyTool(false));
        return;
      }
      // Flex 容量不够(503)、限速(429):还是用 Flex 退避重试,不换成 Standard(会涨价)。
      final busy = e.status == 429 || e.status == 503;
      if (yielded ||
          !busy ||
          req.serviceTier != 'flex' ||
          attempt >= _flexRetries) {
        rethrow;
      }
      final wait = _flexBackoff * (1 << attempt);
      llmLog.add(
        LlmEventKind.retry,
        req.model,
        tr('Flex 排不上({0}),{1} 秒后再试', [e.status!, wait.inSeconds]),
      );
      await Future<void>.delayed(wait);
    }
  }
  if (!yielded) throw LlmException(tr('模型没有返回内容'));
  // 让用户看得见这次到底有没有走工具:模型日志里一条,左侧栏不亮提醒。
  if (req.replyTool) {
    llmLog.add(
      LlmEventKind.replyTool,
      req.model,
      replyUsed ? tr('回覆走工具呼叫') : tr('模型没照工具呼叫,回覆在正文'),
    );
  }
  // 实际档位和选的不一样(比如 Priority 被降成 Standard,按 Standard 计费):记一笔。
  if (req.serviceTier.isNotEmpty &&
      served != null &&
      served != req.serviceTier) {
    llmLog.add(
      LlmEventKind.tier,
      req.model,
      tr('选的是 {0},实际按 {1} 处理', [req.serviceTier, served]),
    );
  }
  if (geminiCut(finish) case final cut?) req.onCut?.call(cut);
  if (sources.isNotEmpty) yield sourcesText(sources);
}
