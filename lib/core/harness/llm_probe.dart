import 'dart:async';

import '../../l10n/l10n.dart';
import 'providers/llm_http.dart';
import 'web_search.dart';

// 测接口通不通、多快:「API 管理」卡片上的「测试连接」和右边的「全部测试」共用。

/// 一次测试的结果:通了 [ms] 是毫秒,没通 [error] 是原因。
typedef ProbeResult = ({int? ms, String? error});

/// 对话等到第一个字就算通,最多等这么久。
const probeChatLimit = Duration(seconds: 30);

/// 发一句 hi,等到第一个字;拿到就取消订阅,请求随之掐断。
Future<ProbeResult> probeChat(
  LlmRequest request,
  Stream<String> Function(LlmRequest) stream, {
  Duration limit = probeChatLimit,
}) => _timed(
  limit,
  () => stream(
    request.copyWithMessages(const [
      {'role': 'user', 'content': 'hi'},
    ]),
  ).first.timeout(limit),
);

/// 让它用自家的搜索工具查一件小事,等到说完;最多等 [webSearchDeadline]。
Future<ProbeResult> probeSearch(
  LlmRequest request,
  Stream<String> Function(LlmRequest) stream, {
  Duration limit = webSearchDeadline,
}) => _timed(limit, () async {
  final text = await joinWithin(
    stream(
      request.copyWithMessages(const [
        {'role': 'system', 'content': webSearchSystem},
        {'role': 'user', 'content': '今天的日期'},
      ], webSearch: true),
    ),
    limit,
  );
  if (text.trim().isEmpty) throw StateError('empty');
});

Future<ProbeResult> _timed(Duration limit, Future<void> Function() run) async {
  final watch = Stopwatch()..start();
  try {
    await run();
    return (ms: watch.elapsedMilliseconds, error: null);
  } on LlmException catch (e) {
    return (ms: null, error: e.message);
  } on TimeoutException {
    return (ms: null, error: tr('{0} 秒没有回应', [limit.inSeconds]));
  } on StateError {
    // `.first` 遇到空的流,或搜完一个字没有。
    return (ms: null, error: tr('模型没有返回内容'));
  } on Object catch (e) {
    // 只报类型,原文可能带着 Key。
    return (ms: null, error: tr('测试失败({0})', [e.runtimeType]));
  }
}

/// 毫秒写成给人看的:不到 1 秒写毫秒,否则写一位小数的秒。
String formatMs(int ms) =>
    ms < 1000 ? '$ms ms' : '${(ms / 1000).toStringAsFixed(1)} s';
