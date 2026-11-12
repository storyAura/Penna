import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../l10n/l10n.dart';

/// 一次请求用了多少 token:发过去的([input],含其中命中缓存的 [cached])和回复的。
typedef LlmUsage = ({int input, int cached, int output});

/// 随某条消息发出的一张图片。
typedef LlmImage = ({String mime, Uint8List bytes});

/// 回复为什么没写完:到了输出上限、被接口拦下、接口没说写完连接就结束了。
enum LlmCut { length, blocked, broken }

@immutable
class LlmRequest {
  const LlmRequest({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.messages,
    this.images = const {},
    this.temperature = 0.7,
    this.topP = 1,
    this.protocol = 'openai',
    this.token,
    this.webSearch = false,
    this.onUsage,
    this.effort,
    this.onCut,
    this.serviceTier = '',
  });

  /// Google 接口的用量档位:空串是自动(不传);standard、flex、priority 见 `gemini_provider.dart`。
  final String serviceTier;

  /// 已经出了字,但这条回复没写完时调用。
  final void Function(LlmCut cut)? onCut;

  /// 思考强度:low、medium、high、xhigh;null 是不指定,用模型自己的默认。
  final String? effort;

  /// 只换思考强度的一份。
  LlmRequest withEffort(String? effort) => LlmRequest(
    baseUrl: baseUrl,
    model: model,
    apiKey: apiKey,
    messages: messages,
    images: images,
    temperature: temperature,
    topP: topP,
    protocol: protocol,
    token: token,
    webSearch: webSearch,
    onUsage: onUsage,
    effort: effort,
    onCut: onCut,
    serviceTier: serviceTier,
  );

  /// 换掉消息(测试连接用);[webSearch] 不给就照旧。
  LlmRequest copyWithMessages(
    List<Map<String, String>> messages, {
    bool? webSearch,
  }) => LlmRequest(
    baseUrl: baseUrl,
    model: model,
    apiKey: apiKey,
    messages: messages,
    temperature: temperature,
    topP: topP,
    protocol: protocol,
    token: token,
    webSearch: webSearch ?? this.webSearch,
    onUsage: onUsage,
    effort: effort,
    onCut: onCut,
    serviceTier: serviceTier,
  );

  /// 接口报了用量时调用;一条回复里可能报好几次,最后一次为准。
  final void Function(LlmUsage usage)? onUsage;

  /// Grok 账号登录:发请求前才取 token,快过期时在里面换新的。
  final Future<String> Function()? token;

  /// 让模型用它自家的联网搜索(只给能搜的接口,见 `web_search.dart`)。
  final bool webSearch;

  /// 带图片的消息:[messages] 里的下标 → 那条消息的图片。
  final Map<int, List<LlmImage>> images;

  final String baseUrl;
  final String model;

  /// 可为空(本地模型常常不需要 Key)。
  final String apiKey;

  /// 统一用 OpenAI 的消息格式:`{'role': 'system'|'user'|'assistant', 'content': '...'}`;
  /// 其他协议各自转换。
  final List<Map<String, String>> messages;
  final double temperature;

  /// 小于 1 才发给模型:有的接口不让它和温度一起给。
  final double topP;

  /// 'openai'、'google' 或 'grok'(Grok 账号登录)。
  final String protocol;
}

/// 给用户看的模型调用错误;不含 Key。
class LlmException implements Exception {
  const LlmException(this.message, {this.status});

  final String message;

  /// 接口回的状态码;不是接口回的错误时为 null。
  final int? status;

  @override
  String toString() => message;
}

typedef ChatStreamer = Stream<String> Function(LlmRequest request);

/// 各模型收的强度不一样,收不了的整条请求报 400 / 422:极高先退到高,再不行就不指定。
/// 认不出是不是这个字段惹的(中转站的说法五花八门),所以这两个状态码都重发;
/// 真是别的原因时最后还是同一个错。
// ponytail: 退回了界面上看不出来,滑块还停在原来那档;要显示就给 LlmRequest 加个回调。
Stream<String> effortFallback(
  LlmRequest req,
  Stream<String> Function(LlmRequest req) send,
) async* {
  try {
    await for (final delta in send(req)) {
      yield delta;
    }
  } on LlmException catch (e) {
    final rejected =
        e.status == HttpStatus.badRequest ||
        e.status == HttpStatus.unprocessableEntity;
    if (req.effort == null || !rejected) rethrow;
    yield* effortFallback(
      req.withEffort(req.effort == 'xhigh' ? 'high' : null),
      send,
    );
  }
}

const _maxErrorBody = 300;

/// 跑一次流式对话:[chat] 用给它的连接发请求并逐段吐字。
/// 取消订阅会立刻掐断连接,不用等下一段回复。
Stream<String> runLlmStream(Stream<String> Function(HttpClient client) chat) {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  var cancelled = false;
  late final StreamController<String> out;
  out = StreamController<String>(
    onListen: () async {
      try {
        await for (final delta in chat(client)) {
          if (cancelled) break;
          out.add(delta);
        }
      } on Object catch (e) {
        if (!cancelled) out.addError(_friendly(e));
      } finally {
        client.close(force: true);
        if (!cancelled) await out.close();
      }
    },
    onCancel: () {
      cancelled = true;
      client.close(force: true);
    },
  );
  return out.stream;
}

/// 把底层异常换成给用户看的话。原始异常文本可能带着请求头(也就是 Key),
/// 所以认不出的异常只报类型,不原样转述。
LlmException _friendly(Object e) => switch (e) {
  LlmException() => e,
  TimeoutException() => LlmException(tr('模型接口超时')),
  SocketException() => LlmException(tr('连不上模型接口:{0}', [e.message])),
  HandshakeException() => LlmException(tr('HTTPS 握手失败:{0}', [e.message])),
  HttpException() => LlmException(tr('网络请求中断:{0}', [e.message])),
  FormatException() => LlmException(tr('请求发不出去:API Key 或接口地址里有非法字符')),
  _ => LlmException(tr('调用模型失败({0})', [e.runtimeType])),
};

/// 拼出接口地址;[baseUrl] 不是 http(s) 地址时报错。
Uri llmEndpoint(String baseUrl, String path) {
  final base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse('$base$path');
  if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
    throw LlmException(tr('Base URL 无效:要以 http:// 或 https:// 开头'));
  }
  return uri;
}

/// POST 一段 JSON,把成功响应按行吐出来;非 200 时抛出带状态码的错误。
Stream<String> postForLines(
  HttpClient client,
  Uri uri,
  Map<String, String> headers,
  Map<String, Object?> body, {
  Duration stall = llmStallTimeout,
}) async* {
  final request = await client.postUrl(uri);
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
  headers.forEach(request.headers.set);
  request.add(utf8.encode(jsonEncode(body)));
  // 模型卡住不说话时不能一直等:超时算失败,还没出字就会换下一个模型。
  final response = await request.close().timeout(stall);
  if (response.statusCode != HttpStatus.ok) {
    throw _statusError(response.statusCode, await utf8.decodeStream(response));
  }
  yield* response
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      // 推理模型思考时也一直在发数据,隔这么久一行都没有才算卡住。
      .timeout(stall);
}

/// 等模型回话最多等多久(从发出请求到收到回应,或两段数据之间)。
const llmStallTimeout = Duration(seconds: 60);

/// 这个请求等多久。用户把思考强度调高时,模型可能好几分钟不说话。
// ponytail: 5 分钟是估的;调高强度后模型真卡住,要等这么久才换下一个模型。
Duration llmStallFor(LlmRequest req) => req.serviceTier == 'flex'
    // Google 的 Flex 要排队,官方说延迟 1–15 分钟、客户端至少等 10 分钟。
    ? const Duration(minutes: 15)
    : req.effort == 'high' || req.effort == 'xhigh'
    ? const Duration(minutes: 5)
    : llmStallTimeout;

LlmException _statusError(int status, String body) {
  // 回来的是一张网页:多半是地址填错了,打到了网站而不是接口上。
  if (body.trimLeft().startsWith('<')) {
    return LlmException(
      tr('模型接口返回 {0}:地址不对,返回的是网页。请检查 Base URL', [status]),
      status: status,
    );
  }
  // 多数接口把原因放在 error.message 里;取得到就只显示这一句,不显示整坨 JSON。
  var reason = body;
  try {
    final decoded = jsonDecode(body);
    final json = decoded is List && decoded.isNotEmpty
        ? decoded.first
        : decoded;
    final error = json is Map ? json['error'] ?? json : null;
    final message = error is Map ? error['message'] : error;
    if (message is String && message.trim().isNotEmpty) reason = message.trim();
  } on FormatException {
    // 不是 JSON,原样显示。
  }
  return LlmException(
    tr('模型接口返回 {0}:{1}', [status, clipLlmError(reason)]),
    status: status,
  );
}

/// 服务端返回的错误原文,截断后才给用户看。
String clipLlmError(Object? reason) {
  final text = '$reason';
  return text.length > _maxErrorBody ? text.substring(0, _maxErrorBody) : text;
}

const _getTimeout = Duration(seconds: 30);

/// GET 一个 JSON 接口(拉取模型列表用);出错时和对话一样换成给用户看的话。
Future<Object?> getJson(Uri uri, Map<String, String> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final String text;
  try {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(_getTimeout);
    text = await utf8.decodeStream(response).timeout(_getTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw _statusError(response.statusCode, text);
    }
  } on TimeoutException {
    throw LlmException(tr('模型接口超时'));
  } on Object catch (e) {
    throw _friendly(e);
  } finally {
    client.close(force: true);
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    throw LlmException(tr('接口返回的不是模型列表'));
  }
}

/// 从回复里取用量:OpenAI(`usage`)、Responses(`response.usage`)、Google(`usageMetadata`)。
/// 缓存的叫法各家不同,DeepSeek 是 `prompt_cache_hit_tokens`。不带用量时返回 null。
LlmUsage? parseUsage(Object? json) {
  if (json is! Map) return null;
  final response = json['response'];
  final u =
      json['usage'] ??
      json['usageMetadata'] ??
      (response is Map ? response['usage'] : null);
  if (u is! Map) return null;
  int count(Object? v) => v is num ? v.toInt() : 0;
  final details = u['prompt_tokens_details'] ?? u['input_tokens_details'];
  final input = count(
    u['prompt_tokens'] ?? u['input_tokens'] ?? u['promptTokenCount'],
  );
  final output =
      count(
        u['completion_tokens'] ??
            u['output_tokens'] ??
            u['candidatesTokenCount'],
      ) +
      count(u['thoughtsTokenCount']);
  if (input == 0 && output == 0) return null;
  return (
    input: input,
    cached: count(
      (details is Map ? details['cached_tokens'] : null) ??
          u['prompt_cache_hit_tokens'] ??
          u['cachedContentTokenCount'],
    ),
    output: output,
  );
}

/// 回复里带着用量就告诉 [req] 的 `onUsage`。
void reportUsage(LlmRequest req, Object? json) {
  final usage = parseUsage(json);
  if (usage != null) req.onUsage?.call(usage);
}

/// 一行 SSE 的 JSON 内容;不是数据行、是结束标记或解析不了时返回 null。
Object? sseJson(String line) {
  if (!line.startsWith('data:')) return null;
  try {
    return jsonDecode(line.substring(5).trim());
  } on FormatException {
    return null;
  }
}
