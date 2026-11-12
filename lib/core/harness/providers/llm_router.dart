import 'dart:async';

import '../../../data/models/app_config.dart';
import 'cli_provider.dart';
import 'gemini_provider.dart';
import 'openai_provider.dart';
import 'responses_provider.dart';
import '../llm_log.dart';
import '../web_search.dart';
import '../../../l10n/l10n.dart';

/// 按请求里的协议选对应的接口。
Stream<String> streamChat(LlmRequest request) => switch (request.protocol) {
  'google' => streamGeminiChat(request),
  'grok' => streamResponsesChat(request),
  protocolClaudeCode || protocolCodex => streamCliChat(request),
  _ when request.webSearch && searchesByResponses(request.baseUrl) =>
    streamResponsesChat(request),
  _ => streamOpenAiChat(request),
};

/// 问接口有哪些模型可用,按名字排序;出错抛 [LlmException]。
Future<List<String>> listModels({
  required String protocol,
  required String baseUrl,
  required String apiKey,
}) async {
  if (isCliProtocol(protocol)) return cliModels(protocol);
  final models = protocol == 'google'
      ? await listGeminiModels(baseUrl, apiKey)
      : await listOpenAiModels(baseUrl, apiKey);
  return models.toSet().toList()..sort();
}

/// 给人看的错误:认得的说原因,认不出的只报类型(原文可能带着 Key)。
String _brief(Object error) =>
    error is LlmException ? error.message : '${error.runtimeType}';

/// 按 [chain] 的顺序请求模型:某个模型还没吐出任何内容就失败,换下一家的模型;
/// 已经开始回复后再出错,就把错误原样抛出(不能接着另一个模型的话往下说)。
/// [onTrying] 在开始问某个模型时调用,[onAnswering] 在它开始回复时调用,都告知名字。
///
/// 取消订阅会立刻停掉正在请求的模型,也不会再去问后面的模型。
Stream<String> streamWithFailover(
  List<(String name, LlmRequest request)> chain,
  ChatStreamer stream, {
  void Function(String name)? onTrying,
  void Function(String name)? onAnswering,
}) {
  StreamSubscription<String>? inner;
  Completer<Object?>? waiting;
  var cancelled = false;
  late final StreamController<String> out;

  /// 跑完一个模型:返回它是否出过字,以及出错时的错误。
  Future<(bool started, Object? error)> runOne(
    String name,
    LlmRequest request,
  ) async {
    var started = false;
    final done = waiting = Completer<Object?>();
    inner = stream(request).listen(
      (delta) {
        if (!started) {
          started = true;
          onAnswering?.call(name);
        }
        out.add(delta);
      },
      onError: (Object e) {
        if (!done.isCompleted) done.complete(e);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(null);
      },
      cancelOnError: true,
    );
    // 先等它跑完再读 started;写成一行会在等待之前就把 started 读走。
    final error = await done.future;
    return (started, error);
  }

  // 同一家(协议、地址、Key 都一样)的一个模型没出字就失败了,这家剩下的模型不再试,
  // 直接换下一家(2026-11-12 用户要求)。
  String vendor(LlmRequest r) => '${r.protocol}|${r.baseUrl}|${r.apiKey}';

  Future<void> run() async {
    final failures = <String>[];
    final failed = <String>{};
    for (final (name, request) in chain) {
      if (cancelled) return;
      if (failed.contains(vendor(request))) continue;
      onTrying?.call(name);
      final (started, error) = await runOne(name, request);
      if (cancelled) return;
      if (started) {
        if (error != null) {
          llmLog.add(LlmEventKind.error, name, _brief(error));
          out.addError(error);
        }
        return out.close();
      }
      failed.add(vendor(request));
      failures.add('$name:${error ?? '没有返回内容'}');
      // 后面的模型接上了,这条原因就不会显示在回复上:记进模型日志(左侧栏能看)。
      llmLog.add(
        LlmEventKind.failover,
        name,
        error == null ? tr('模型没有返回内容') : _brief(error),
      );
    }
    out.addError(
      LlmException(failures.isEmpty ? tr('没有可用的模型') : failures.join('\n')),
    );
    return out.close();
  }

  out = StreamController<String>(
    onListen: run,
    onCancel: () {
      cancelled = true;
      final done = waiting;
      if (done != null && !done.isCompleted) done.complete(null);
      return inner?.cancel();
    },
  );
  return out.stream;
}
