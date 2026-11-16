import 'package:flutter/foundation.dart';

import '../../../data/models/app_config.dart';
import '../providers/llm_http.dart' show LlmTool;
import 'mcp_client.dart';
import 'mcp_tools.dart';

/// 问一个服务有哪些工具 / 调它的一个工具(测试里换成假的)。
typedef McpLister = Future<List<McpTool>> Function(
  McpServer server,
  Map<String, String> secrets,
);
typedef McpCaller = Future<String> Function(
  McpServer server,
  Map<String, String> secrets,
  String tool,
  Map<String, Object?> args,
);

/// 一次最多交给模型多少个工具(多了系统提示太长,模型也挑不准)。
const mcpMaxTools = 40;

/// 一个工具的结果最多留多少字交还给模型。
const mcpMaxResult = 20000;

/// 列工具失败的服务隔多久再试。
const _retryAfter = Duration(minutes: 1);

Future<List<McpTool>> _list(McpServer s, Map<String, String> secrets) =>
    s.transport == mcpStdio
    ? listStdioMcpTools(
        s.command,
        environment: parseEnv(secrets[mcpEnvKey(s.id)] ?? ''),
      )
    : listHttpMcpTools(s.url, token: secrets[mcpTokenKey(s.id)] ?? '');

Future<String> _callTool(
  McpServer s,
  Map<String, String> secrets,
  String tool,
  Map<String, Object?> args,
) => s.transport == mcpStdio
    ? callStdioMcpTool(
        s.command,
        tool,
        args,
        environment: parseEnv(secrets[mcpEnvKey(s.id)] ?? ''),
      )
    : callHttpMcpTool(
        s.url,
        tool,
        args,
        token: secrets[mcpTokenKey(s.id)] ?? '',
        timeout: const Duration(seconds: 60),
      );

/// 用户添加并启用的 MCP 服务的工具(2026-11-16 用户要求 Agent 能调):
/// 记着每个服务有哪些工具,翻译成交给模型的 [LlmTool],模型要调时替它调。
/// 启用一个服务就是同意 Agent 用它的工具:调用不再逐次确认,调了哪些记在回复上。
// ponytail: 不分 Preset、不能单独关某个工具;工具有副作用(写文件之类)也照调。
// 要细管时用 Preset 的工具白名单,或按 MCP 的 readOnlyHint 先问用户。
class McpHub {
  McpHub(this._config, {McpLister? list, McpCaller? call})
    : _lister = list ?? _list,
      _caller = call ?? _callTool;

  final AppConfig Function() _config;
  final McpLister _lister;
  final McpCaller _caller;

  /// 列过工具的服务:服务的样子([_sig])→ 它的工具。地址、命令改了算另一个,要重列。
  final _listed = <String, List<McpTool>>{};
  final _failedAt = <String, DateTime>{};
  final _busy = <String>{};

  static String _sig(McpServer s) =>
      '${s.id}|${s.transport}|${s.url}|${s.command}';

  bool _usable(McpServer s) =>
      s.enabled &&
      (s.transport == mcpStdio
          ? s.command.trim().isNotEmpty
          : s.url.trim().isNotEmpty);

  /// 把还没列过工具的服务列一遍(启动时、每次发消息时调;都列过了什么也不做)。
  /// 连不上的不报错,过一会儿再试。
  Future<void> refresh() async {
    final cfg = _config();
    await Future.wait([
      for (final s in cfg.mcpServers)
        if (_usable(s) && _due(_sig(s))) _refreshOne(s, cfg.secrets),
    ]);
  }

  bool _due(String sig) {
    if (_listed.containsKey(sig) || _busy.contains(sig)) return false;
    final failed = _failedAt[sig];
    return failed == null || DateTime.now().difference(failed) > _retryAfter;
  }

  Future<void> _refreshOne(McpServer s, Map<String, String> secrets) async {
    final sig = _sig(s);
    _busy.add(sig);
    try {
      _listed[sig] = await _lister(s, secrets);
      _failedAt.remove(sig);
    } on Object catch (e) {
      // 只记类型和认得的原因:原文可能带着令牌。
      _failedAt[sig] = DateTime.now();
      debugPrint(
        'MCP 服务「${s.name}」的工具没列出来:'
        '${e is McpException ? e.message : e.runtimeType}',
      );
    } finally {
      _busy.remove(sig);
    }
  }

  /// 启用着、列过工具的服务的全部工具:交给模型的函数名 → 哪个服务的哪个工具。
  Map<String, ({McpServer server, McpTool tool})> get _all {
    final out = <String, ({McpServer server, McpTool tool})>{};
    for (final (i, s) in _config().mcpServers.indexed) {
      if (!_usable(s)) continue;
      for (final t in _listed[_sig(s)] ?? const <McpTool>[]) {
        if (out.length >= mcpMaxTools) return out;
        var name = _functionName(s.name, i, t.name);
        // 两个服务起出了同一个名字:后来的带上序号。
        for (var n = 2; out.containsKey(name); n++) {
          name = '${_functionName(s.name, i, t.name, room: 3)}_$n';
        }
        out[name] = (server: s, tool: t);
      }
    }
    return out;
  }

  /// 交给模型的工具表;一个都没有是空的。
  List<LlmTool> get tools => [
    for (final MapEntry(:key, :value) in _all.entries)
      (
        name: key,
        description: value.tool.description.isEmpty
            ? '${value.server.name}:${value.tool.name}'
            : '${value.tool.description}(来自 ${value.server.name})',
        schema: value.tool.schema,
      ),
  ];

  /// 替模型调一次;调不成的把原因当结果交还,不抛错。
  Future<McpResult> call(McpCall call) async {
    McpResult failed(String why) => (tool: call.tool, text: why, failed: true);
    if (call.problem != null) return failed(call.problem!);
    final found = _all[call.tool];
    if (found == null) return failed('没有叫这个名字的工具');
    try {
      final text = await _caller(
        found.server,
        _config().secrets,
        found.tool.name,
        call.args,
      );
      return (
        tool: call.tool,
        text: text.length > mcpMaxResult
            ? '${text.substring(0, mcpMaxResult)}\n(太长,后面截掉了)'
            : text,
        failed: false,
      );
    } on McpException catch (e) {
      return failed(e.message);
    } on Object catch (e) {
      // 认不出的错只报类型,原文可能带着令牌。
      return failed('调用失败(${e.runtimeType})');
    }
  }
}

final _unsafe = RegExp('[^A-Za-z0-9]+');

/// 交给模型的函数名:各家接口只收字母、数字、下划线,最长 64,字母开头。
/// 服务名全是中文时用它排第几个。[room] 是末尾留给序号的位置。
String _functionName(String server, int index, String tool, {int room = 0}) {
  String slug(String s) =>
      s.replaceAll(_unsafe, '_').replaceAll(RegExp(r'^_+|_+$'), '');
  final from = slug(server).isEmpty ? 's${index + 1}' : slug(server);
  final name = 'mcp_${from}_${slug(tool).isEmpty ? 'tool' : slug(tool)}';
  final max = 64 - room;
  return name.length > max ? name.substring(0, max) : name;
}
