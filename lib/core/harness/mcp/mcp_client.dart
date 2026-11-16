import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../l10n/l10n.dart';

/// 没写参数表的工具当成不要参数。
const _noParams = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{},
};

/// MCP 服务提供的一个工具;[schema] 是它的参数表(JSON Schema)。
class McpTool {
  const McpTool(this.name, this.description, [this.schema = _noParams]);

  final String name;
  final String description;
  final Map<String, Object?> schema;
}

/// 给用户看的 MCP 错误;不含令牌。
class McpException implements Exception {
  const McpException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _protocolVersion = '2025-03-26';

Map<String, Object?> _request(int id, String method, [Object? params]) => {
  'jsonrpc': '2.0',
  'id': id,
  'method': method,
  'params': ?params,
};

const _initializeParams = {
  'protocolVersion': _protocolVersion,
  'capabilities': <String, Object?>{},
  'clientInfo': {'name': 'Penna', 'version': '1.0.0'},
};

const _initialized = {'jsonrpc': '2.0', 'method': 'notifications/initialized'};

/// 取出 JSON-RPC 回复里的 result;回复是错误时抛 [McpException]。
Map<String, Object?> _result(Map<String, Object?> reply) {
  final error = reply['error'];
  if (error != null) {
    final message = error is Map ? error['message'] : error;
    final text = '$message';
    // 服务端的原文可能很长,也可能回显令牌,只留开头。
    throw McpException(
      tr('服务报错:{0}', [text.length > 120 ? text.substring(0, 120) : text]),
    );
  }
  final result = reply['result'];
  return result is Map ? result.cast<String, Object?>() : const {};
}

List<McpTool> _tools(Map<String, Object?> result) {
  final list = result['tools'];
  return [
    if (list is List)
      for (final t in list)
        if (t is Map && t['name'] is String)
          McpTool(
            t['name'] as String,
            t['description'] is String ? t['description'] as String : '',
            t['inputSchema'] is Map
                ? (t['inputSchema'] as Map).cast<String, Object?>()
                : _noParams,
          ),
  ];
}

/// 把一行命令拆成程序名和参数;双引号里的空格不拆。
List<String> splitCommand(String command) => [
  for (final m in RegExp(r'"([^"]*)"|(\S+)').allMatches(command))
    m.group(1) ?? m.group(2)!,
];

/// 把 `KEY=VALUE` 一行一个的文本解析成环境变量;空行和 # 开头的行跳过。
Map<String, String> parseEnv(String text) => {
  for (final line in const LineSplitter().convert(text))
    if (line.trim().isNotEmpty &&
        !line.trim().startsWith('#') &&
        line.indexOf('=') > 0)
      line.substring(0, line.indexOf('=')).trim(): line
          .substring(line.indexOf('=') + 1)
          .trim(),
};

/// 连上远程 MCP 服务(Streamable HTTP),握手并列出它的工具。
Future<List<McpTool>> listHttpMcpTools(
  String url, {
  String token = '',
  Duration timeout = const Duration(seconds: 20),
}) => _httpSession(
  url,
  token,
  timeout,
  (ask) async => _tools(await ask('tools/list', null)),
);

/// 连上远程 MCP 服务,调用它的一个工具,返回结果里的文字。
/// 工具自己报错、或连不上时抛 [McpException]。
Future<String> callHttpMcpTool(
  String url,
  String name,
  Map<String, Object?> arguments, {
  String token = '',
  Duration timeout = const Duration(seconds: 45),
}) => _httpSession(
  url,
  token,
  timeout,
  (ask) async => _callText(
    await ask('tools/call', {'name': name, 'arguments': arguments}),
  ),
);

/// `tools/call` 结果里的文字;工具自己报错时抛 [McpException]。
String _callText(Map<String, Object?> result) {
  final content = result['content'];
  final text = [
    if (content is List)
      for (final c in content)
        if (c is Map && c['text'] is String) c['text'] as String,
  ].join('\n');
  if (result['isError'] == true) {
    throw McpException(
      tr('工具报错:{0}', [text.length > 120 ? text.substring(0, 120) : text]),
    );
  }
  return text;
}

/// 握手之后把「发一个请求、拿回它的 result」交给 [body] 用,用完断开。
Future<T> _httpSession<T>(
  String url,
  String token,
  Duration timeout,
  Future<T> Function(
    Future<Map<String, Object?>> Function(String method, Object? params) ask,
  )
  body,
) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.isScheme('http') && !uri.isScheme('https')) {
    throw McpException(tr('地址要以 http:// 或 https:// 开头'));
  }
  final client = HttpClient()..connectionTimeout = timeout;
  String? session;
  String? version;

  /// 发一条消息;[id] 非空时等它对应的回复。
  Future<Map<String, Object?>> post(Map<String, Object?> body, int? id) async {
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/json, text/event-stream',
    );
    if (token.trim().isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${token.trim()}',
      );
    }
    if (session != null) request.headers.set('Mcp-Session-Id', session!);
    if (version != null) request.headers.set('MCP-Protocol-Version', version!);
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    session ??= response.headers.value('mcp-session-id');
    if (id == null) {
      await response.drain<void>();
      return const {};
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw McpException('HTTP ${response.statusCode}');
    }
    // 回复可能是一整个 JSON,也可能是事件流里的一行 data:。
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    // 事件流里一个事件可以有多行 data:,空行表示这个事件结束;
    // 整段 JSON 则一直攒到能解析为止。
    final event = StringBuffer();
    final whole = StringBuffer();
    await for (final line in lines) {
      Map<String, Object?>? reply;
      if (line.startsWith('data:')) {
        event.writeln(line.substring(5));
        reply = _tryJson(event.toString());
      } else if (line.isEmpty) {
        event.clear();
      } else {
        whole.write(line);
        reply = _tryJson(whole.toString());
      }
      if (_isReplyTo(reply, id)) return reply!;
    }
    throw McpException(tr('服务没有按 MCP 协议回复'));
  }

  try {
    return await () async {
      final init = _result(
        await post(_request(1, 'initialize', _initializeParams), 1),
      );
      final negotiated = init['protocolVersion'];
      if (negotiated is String) version = negotiated;
      await post(_initialized, null);
      var id = 1;
      return body(
        (method, params) async =>
            _result(await post(_request(++id, method, params), id)),
      );
    }().timeout(timeout);
  } on TimeoutException {
    throw McpException(tr('连接超时'));
  } on SocketException {
    throw McpException(tr('连不上这个地址'));
  } on HandshakeException {
    throw McpException(tr('HTTPS 握手失败'));
  } on HttpException {
    throw McpException(tr('连接中断'));
  } on FormatException {
    throw McpException(tr('地址或令牌里有非法字符'));
  } finally {
    client.close(force: true);
  }
}

/// 是不是编号为 [id] 的那条回复。服务端主动发来的请求也可能用同一个编号,
/// 那种带 method,不算。
bool _isReplyTo(Map<String, Object?>? message, int id) =>
    message != null && message['id'] == id && message['method'] == null;

Map<String, Object?>? _tryJson(String text) {
  try {
    final json = jsonDecode(text);
    return json is Map ? json.cast<String, Object?>() : null;
  } on FormatException {
    return null;
  }
}

/// 关掉启动的程序。它是经命令行启动的,只杀命令行会把真正的服务程序留在后台,
/// 所以 Windows 上连同它启动的子程序一起结束。
Future<void> _stop(Process process) async {
  try {
    await process.stdin.close();
  } on IOException {
    // 程序已经自己退出了。
  }
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
  } else {
    process.kill();
  }
}

/// 在本机启动一个 MCP 服务程序(stdio),握手并列出它的工具,然后关掉它。
Future<List<McpTool>> listStdioMcpTools(
  String command, {
  Map<String, String> environment = const {},
  Duration timeout = const Duration(seconds: 20),
}) => _stdioSession(
  command,
  environment,
  timeout,
  (ask) async => _tools(await ask('tools/list', null)),
);

/// 在本机启动一个 MCP 服务程序,调用它的一个工具,返回结果里的文字,然后关掉它。
// ponytail: 每次调用都重新启动一遍程序(npx、uvx 这类要几秒);嫌慢再让它常驻。
Future<String> callStdioMcpTool(
  String command,
  String name,
  Map<String, Object?> arguments, {
  Map<String, String> environment = const {},
  Duration timeout = const Duration(seconds: 60),
}) => _stdioSession(
  command,
  environment,
  timeout,
  (ask) async => _callText(
    await ask('tools/call', {'name': name, 'arguments': arguments}),
  ),
);

/// 启动程序、握手之后把「发一个请求、拿回它的 result」交给 [body] 用,用完关掉程序。
Future<T> _stdioSession<T>(
  String command,
  Map<String, String> environment,
  Duration timeout,
  Future<T> Function(
    Future<Map<String, Object?>> Function(String method, Object? params) ask,
  )
  body,
) async {
  final parts = splitCommand(command);
  if (parts.isEmpty) throw McpException(tr('没有填启动命令'));
  final Process process;
  try {
    // runInShell:Windows 上 npx、uvx 这类其实是 .cmd 脚本,要经过命令行才能启动。
    process = await Process.start(
      parts.first,
      parts.sublist(1),
      environment: environment,
      runInShell: true,
    );
  } on ProcessException {
    throw McpException(tr('启动不了:{0}', [parts.first]));
  }
  // 不读走错误输出的话,程序写满缓冲区会卡住。
  unawaited(process.stderr.drain<void>());
  // 程序提前退出后再往里写,错误会从这里冒出来;不接住就成了没人管的异常。
  unawaited(process.stdin.done.catchError((Object _) {}));
  final lines = StreamIterator(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );

  Future<Map<String, Object?>> send(Map<String, Object?> body, int id) async {
    process.stdin.writeln(jsonEncode(body));
    while (await lines.moveNext()) {
      final reply = _tryJson(lines.current);
      if (_isReplyTo(reply, id)) return reply!;
    }
    throw McpException(tr('程序没有按 MCP 协议回复就退出了'));
  }

  try {
    return await () async {
      _result(await send(_request(1, 'initialize', _initializeParams), 1));
      process.stdin.writeln(jsonEncode(_initialized));
      var id = 1;
      return body(
        (method, params) async =>
            _result(await send(_request(++id, method, params), id)),
      );
    }().timeout(timeout);
  } on TimeoutException {
    throw McpException(tr('等待程序回复超时'));
  } on IOException {
    throw McpException(tr('和程序的通信中断'));
  } finally {
    unawaited(lines.cancel());
    await _stop(process);
  }
}
