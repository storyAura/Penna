import 'package:flutter/foundation.dart';

import '../../l10n/l10n.dart';
import 'providers/llm_http.dart' show LlmCut;

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
}

typedef LlmEvent = ({
  DateTime time,
  LlmEventKind kind,
  String model,
  String message,
});

/// 最近的模型事件,新的在前,只在内存里。
// ponytail: 全局一份;只留 [_max] 条,重启就清空。要长期留就写进 error.log 旁边的文件。
class LlmLog extends ChangeNotifier {
  static const _max = 300;

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
    if (kind != LlmEventKind.stopped) _unseen++;
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
