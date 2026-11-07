import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import 'gemini_provider.dart';
import 'openai_provider.dart';
import 'responses_provider.dart';
import '../web_search.dart';
import '../../../l10n/l10n.dart';

/// 按请求里的协议选对应的接口。
Stream<String> streamChat(LlmRequest request) => switch (request.protocol) {
  'google' => streamGeminiChat(request),
  'grok' => streamResponsesChat(request),
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
  final models = protocol == 'google'
      ? await listGeminiModels(baseUrl, apiKey)
      : await listOpenAiModels(baseUrl, apiKey);
  return models.toSet().toList()..sort();
}

/// 按 [chain] 的顺序请求模型:某个模型还没吐出任何内容就失败,换下一个;
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

  Future<void> run() async {
    final failures = <String>[];
    for (final (name, request) in chain) {
      if (cancelled) return;
      onTrying?.call(name);
      final (started, error) = await runOne(name, request);
      if (cancelled) return;
      if (started) {
        if (error != null) out.addError(error);
        return out.close();
      }
      failures.add('$name:${error ?? '没有返回内容'}');
      // 后面的模型接上了,这条原因就不会显示出来;记进 error.log 好查为什么换了。
      // ponytail: 只记日志,界面上不提示;要提示时在回复上加一行「X 失败,换成 Y」。
      debugPrint('换下一个模型:${failures.last}');
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
