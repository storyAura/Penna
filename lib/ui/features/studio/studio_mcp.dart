part of 'studio_view_model.dart';

/// 一条回复最多调几次外接工具。
const _maxMcpCalls = 6;

/// Agent 调用户添加的 MCP 工具(见 `core/harness/mcp/mcp_tools.dart`):
/// 请求上带着工具表([_requests] 的 `tools:`),回复里的 `<mcp-call>`
/// (模型自己写的,或接口把原生函数调用换成的)在工具循环里调完交还。
/// 工作台、区域控制、漫画分镜的对话和副聊天(借 [lookupFor])都能用。
extension StudioMcp on StudioViewModel {
  /// 回复里写了 `<mcp-call>`(接了工具总台才算)。
  bool _wantsMcp(String prose) =>
      mcp != null && splitMcpCalls(prose).calls.isNotEmpty;

  /// 把回复里的调用一个个做完:交还给模型的那段话([text])、记在回复上的一句([note])
  /// 和没调成的原因([details])。没写调用是 null。
  Future<({String text, String note, List<String> details})?> _callMcp(
    String prose,
  ) async {
    final hub = mcp;
    if (hub == null) return null;
    final calls = splitMcpCalls(prose).calls.take(_maxMcpCalls).toList();
    if (calls.isEmpty) return null;
    // 一个个调:有的工具前后有关系(先建后改),不并发。
    final results = <McpResult>[];
    for (final call in calls) {
      results.add(await hub.call(call));
    }
    final done = [
      for (final r in results)
        if (!r.failed) r.tool,
    ];
    final failed = results.where((r) => r.failed).toList();
    return (
      text: formatMcpResults(results),
      note: done.isNotEmpty
          ? tr('调用了外接工具 · {0}', [done.join(tr('、'))])
          : tr('外接工具没调成 · {0}', [failed.map((r) => r.tool).join(tr('、'))]),
      details: [
        for (final r in failed) tr('「{0}」没调成:{1}', [r.tool, r.text]),
      ],
    );
  }
}
