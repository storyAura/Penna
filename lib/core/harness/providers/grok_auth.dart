import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../data/models/app_config.dart';
import '../../../data/services/config_service.dart';
import '../../../l10n/l10n.dart';
import 'llm_http.dart';

// 用 Grok 账号登录(OAuth 设备码):程序拿到一个短码,用户在浏览器里确认,程序等着换 token。
// ponytail: client_id 是 Grok CLI 的公开 ID,xAI 只放行登记过的客户端,OpenCode 等开源工具也用它;
// xAI 开放第三方登记后换成 Penna 自己的。账号有没有 API 权限由 xAI 决定,没有时回 403。
const _clientId = 'b1a00492-073a-47ea-816f-4c329264a828';
const _issuer = 'https://auth.x.ai/oauth2';
const _scope = 'openid profile email offline_access grok-cli:access api:access';
const _deviceGrant = 'urn:ietf:params:oauth:grant-type:device_code';
const _httpTimeout = Duration(seconds: 20);

/// 提前这么久换新 token,免得发到一半过期。
const _refreshEarly = Duration(minutes: 5);

/// 等用户确认时,连续这么多次连不上才算失败。
const _maxDroppedPolls = 5;

/// 有的回复不写有效期时按这个算。
const _defaultLifetime = 3600;

/// token 只发给这个地址,不看用户填的 Base URL。
const grokApiBase = 'https://api.x.ai/v1';

/// 登录时交给用户确认的短码和网页。
typedef GrokDevice = ({
  String deviceCode,
  String userCode,
  Uri page,
  Duration interval,
  Duration lifetime,
});

/// POST 一个表单,回状态码和 JSON。读不了的回复算空表。
Future<(int, Map<String, dynamic>)> _postForm(
  String url,
  Map<String, String> form,
) async {
  final client = HttpClient()..connectionTimeout = _httpTimeout;
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.add(utf8.encode(Uri(queryParameters: form).query));
    final response = await request.close().timeout(_httpTimeout);
    final text = await utf8.decodeStream(response).timeout(_httpTimeout);
    try {
      final json = jsonDecode(text);
      return (
        response.statusCode,
        json is Map<String, dynamic> ? json : <String, dynamic>{},
      );
    } on FormatException {
      return (response.statusCode, <String, dynamic>{});
    }
  } on SocketException {
    throw LlmException(tr('连不上 Grok 登录服务'));
  } on TimeoutException {
    throw LlmException(tr('连不上 Grok 登录服务'));
  } on HandshakeException {
    throw LlmException(tr('连不上 Grok 登录服务'));
  } finally {
    client.close(force: true);
  }
}

/// 确认页要在浏览器里打开:只认 x.ai 的 https 地址。
Uri? grokLoginPage(Object? url) {
  final uri = url is String ? Uri.tryParse(url) : null;
  if (uri == null || !uri.isScheme('https')) return null;
  return uri.host == 'x.ai' || uri.host.endsWith('.x.ai') ? uri : null;
}

/// 要一个设备码。
Future<GrokDevice> startGrokLogin() async {
  final (status, json) = await _postForm('$_issuer/device/code', {
    'client_id': _clientId,
    'scope': _scope,
    'referrer': 'penna',
  });
  final code = json['device_code'], user = json['user_code'];
  final page = grokLoginPage(
    json['verification_uri_complete'] ?? json['verification_uri'],
  );
  if (status != HttpStatus.ok || code is! String || user is! String) {
    throw LlmException(tr('Grok 登录没能开始({0})', [status]));
  }
  if (page == null) throw LlmException(tr('Grok 返回的登录地址不对'));
  return (
    deviceCode: code,
    userCode: user,
    page: page,
    interval: Duration(seconds: _positive(json['interval'], 5)),
    lifetime: Duration(seconds: _positive(json['expires_in'], 900)),
  );
}

int _positive(Object? value, int fallback) =>
    value is num && value > 0 ? value.toInt() : fallback;

/// 等用户在浏览器里确认,确认了返回存进设置用的三项机密。
/// [cancelled] 为真时返回 null。网络断一下不算失败:用户可能还在浏览器里确认,接着等。
Future<Map<String, String>?> waitGrokLogin(
  GrokDevice device, {
  required bool Function() cancelled,
}) async {
  var interval = device.interval;
  var dropped = 0;
  final deadline = DateTime.now().add(device.lifetime);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(interval);
    if (cancelled()) return null;
    final int status;
    final Map<String, dynamic> json;
    try {
      (status, json) = await _postForm('$_issuer/token', {
        'grant_type': _deviceGrant,
        'client_id': _clientId,
        'device_code': device.deviceCode,
      });
    } on LlmException {
      if (++dropped > _maxDroppedPolls) rethrow;
      continue;
    }
    dropped = 0;
    if (cancelled()) return null;
    if (status == HttpStatus.ok) return _tokensFrom(json, '');
    switch (json['error']) {
      case 'authorization_pending':
        break;
      case 'slow_down':
        interval += const Duration(seconds: 5);
      case 'access_denied' || 'authorization_denied':
        throw LlmException(tr('Grok 登录被拒绝了'));
      case 'expired_token':
        throw LlmException(tr('Grok 登录码过期了,请重新登录'));
      default:
        throw LlmException(tr('Grok 登录失败({0})', [status]));
    }
  }
  throw LlmException(tr('Grok 登录码过期了,请重新登录'));
}

/// 回复里的 token 换成存进设置的三项。没给新的 refresh token 就留着旧的。
Map<String, String> _tokensFrom(Map<String, dynamic> json, String oldRefresh) {
  final access = json['access_token'];
  final refresh = json['refresh_token'];
  final kept = refresh is String && refresh.isNotEmpty ? refresh : oldRefresh;
  if (access is! String || access.isEmpty || kept.isEmpty) {
    throw LlmException(tr('Grok 登录没有返回 token'));
  }
  final lifetime = _positive(json['expires_in'], _defaultLifetime);
  final expires = DateTime.now().add(Duration(seconds: lifetime));
  return {
    'access': access,
    'refresh': kept,
    'expires': '${expires.millisecondsSinceEpoch}',
  };
}

/// 正在换新 token 的:同一个 refresh token 只能用一次,两边同时换会把登录弄丢。
final _refreshing = <String, Future<String>>{};

/// 发请求前取能用的 token,快过期时先换新的。没登录、登录失效时抛 [LlmException]。
Future<String> grokAccessToken(ConfigService service, String llmId) async {
  final cfg = service.config;
  if (!cfg.grokSignedIn(llmId)) throw LlmException(tr('Grok 账号还没登录'));
  final expires = cfg.grokExpires(llmId);
  if (DateTime.now().add(_refreshEarly).isBefore(expires)) {
    return cfg.llmKey(llmId);
  }
  return _refreshing[llmId] ??= _refresh(
    service,
    llmId,
  ).whenComplete(() => _refreshing.remove(llmId));
}

Future<String> _refresh(ConfigService service, String llmId) async {
  final refresh = service.config.secrets[llmRefreshKey(llmId)]!;
  final (status, json) = await _postForm('$_issuer/token', {
    'grant_type': 'refresh_token',
    'client_id': _clientId,
    'refresh_token': refresh,
  });
  switch (status) {
    case HttpStatus.ok:
      break;
    case HttpStatus.forbidden:
      throw LlmException(grokNoAccess);
    case HttpStatus.badRequest || HttpStatus.unauthorized:
      throw LlmException(grokExpired);
    default:
      throw LlmException(tr('Grok 登录失败({0})', [status]));
  }
  final tokens = _tokensFrom(json, refresh);
  service.update(keepRefreshedTokens(service.config, llmId, refresh, tokens));
  return tokens['access']!;
}

/// 换新 token 要等网络,这期间设置可能变了:接口被删、换成了别的协议、退出或重新登录过。
/// 这些情况不写回去,否则 token 会留在别的协议的 Key 那一栏,被发给用户填的地址。
AppConfig keepRefreshedTokens(
  AppConfig cfg,
  String llmId,
  String usedRefresh,
  Map<String, String> tokens,
) {
  final llm = cfg.llms.where((l) => l.id == llmId).firstOrNull;
  return llm?.protocol == protocolGrok &&
          cfg.secrets[llmRefreshKey(llmId)] == usedRefresh
      ? cfg.withGrokTokens(llmId, tokens)
      : cfg;
}

String get grokNoAccess => tr('这个 Grok 账号没有 API 权限,可以改用 API Key');
String get grokExpired => tr('Grok 登录已失效,请到设置里重新登录');
