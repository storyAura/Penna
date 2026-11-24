import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';
import 'providers/llm_http.dart' show LlmCut, LlmRequest;

// 模型日志(2026-11-13 用户要求):自动换接口时前一个为什么失败、回复中途出错、
// 写到一半被截断、用户停止、联网搜索换接口,都记一条,左侧栏「模型日志」里看。

enum LlmEventKind {
  /// 还没出字就失败,换下一个。
  failover,

  /// 全部失败,或已经出字后出错。
  error,

  /// 写到一半没写完(到上限、被拦、连接提前结束)。
  cut,

  /// 用户点了停止。
  stopped,

  /// 联网搜索的一个接口没搜成,换下一个。
  search,

  /// 同一个模型、同一个档位等一会儿再试(Google 的 Flex 排不上时)。
  retry,

  /// 接口实际用的用量档位和选的不一样(Google 的 Priority 被降成 Standard)。
  tier,

  /// 回复写在工具调用里:这次回话到底有没有走工具、还是模型照旧写在正文。
  replyTool,
}

typedef LlmEvent = ({
  DateTime time,
  LlmEventKind kind,
  String model,
  String message,
});

/// 一次发给模型的请求:发了什么、回了什么(2026-11-24 用户要求:日志里要看得到
/// 每次请求的输入、输出和思考)。只在内存里,不写进任何文件。
class LlmCall {
  LlmCall({
    required this.time,
    required this.name,
    required this.model,
    required this.messages,
    required this.images,
  });

  final DateTime time;

  /// 接口的名字(带模型名)和实际请求的模型。
  final String name;
  final String model;

  /// 实际发出去的消息(系统提示、对话),和随消息发的图有几张。
  final List<Map<String, String>> messages;
  final int images;

  /// 模型回的全部文字;接口单独给的思考包在 `<think>` 里。
  final output = StringBuffer();

  /// 出错的原因;没出错是 null。
  String? error;

  /// 从发出到结束用了多久;还没结束是 null。
  Duration? took;
}

/// 最近的模型事件,新的在前,只在内存里。
// ponytail: 全局一份;只留 [_max] 条,重启就清空。要长期留就写进 error.log 旁边的文件。
class LlmLog extends ChangeNotifier {
  static const _max = 300;
  static const _maxCalls = 40;

  /// 最近的请求,新的在前。
  List<LlmCall> _calls = const [];
  List<LlmCall> get calls => _calls;

  /// 记下一次刚发出的请求;结束时调 [finishCall]。
  LlmCall startCall(String name, LlmRequest request) {
    final call = LlmCall(
      time: DateTime.now(),
      name: name,
      model: request.model,
      messages: request.messages,
      images: request.images.values.fold(0, (n, list) => n + list.length),
    );
    _calls = List.unmodifiable([call, ..._calls.take(_maxCalls - 1)]);
    notifyListeners();
    return call;
  }

  void finishCall(LlmCall call, {String? error}) {
    call
      ..error = error
      ..took = DateTime.now().difference(call.time);
    notifyListeners();
  }

  List<LlmEvent> _events = const [];
  List<LlmEvent> get events => _events;

  /// 上次打开面板之后新出的问题(不算停止)。
  int _unseen = 0;
  int get unseen => _unseen;

  void add(LlmEventKind kind, String model, String message) {
    _events = List.unmodifiable([
      (time: DateTime.now(), kind: kind, model: model, message: message),
      ..._events.take(_max - 1),
    ]);
    // 停止和「回覆走工具呼叫」不是问题,不点亮左侧栏的提醒。
    if (kind != LlmEventKind.stopped && kind != LlmEventKind.replyTool) {
      _unseen++;
    }
    debugPrint('模型日志 [${kind.name}] $model:$message');
    notifyListeners();
  }

  void markSeen() {
    if (_unseen == 0) return;
    _unseen = 0;
    notifyListeners();
  }

  void clear() {
    _events = const [];
    _calls = const [];
    _unseen = 0;
    notifyListeners();
  }
}

final llmLog = LlmLog();

/// 回复没写完的原因,给人看的一句话(回复下面和模型日志里共用)。
String cutReason(LlmCut cut) => switch (cut) {
  LlmCut.length => tr('没写完:到了输出上限'),
  LlmCut.blocked => tr('没写完:被接口拦下了'),
  LlmCut.broken => tr('没写完:连接提前结束了'),
};
