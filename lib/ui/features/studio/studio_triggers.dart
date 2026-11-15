part of 'studio_view_model.dart';

/// 触发器:回复说完后程序自己检查,发现没做完就叫醒 Agent 接着干,不等用户开口
/// (2026-11-16 用户要求:真实的 Agent 要能自己叫醒自己、自己循环和确认)。
///
/// 每种触发器看一件事,接手了返回 true(那条回复只是中间一步,交货等下一条)。
/// 一条用户消息之后最多叫醒 [_maxWakes] 次,免得来回打转;用户发新消息、重新回复时清零。
/// 已有的:
/// - [_autoContinue]:写到上限、断线,只写了半截 → 接着写;
/// - [_checkHandoff]:主工作区转来的任务没交出布局 → 让它补上;
/// - `_fixCast`(`studio_layout_pages.dart`):人物块对不上角色卡 → 让它改(算一轮工具)。
// ponytail: 只有这几种看得出来的情况;出的图模型看不到,不做看图自检。
extension StudioTriggers on StudioViewModel {
  /// 写了半截(到了长度上限、断线;被拦、用户停下的不算):自己接着写,写的接在后面。
  bool _autoContinue() {
    if (_wakes >= _maxWakes || _messages.isEmpty) return false;
    final last = _messages.last;
    if (last.stopped || last.cut == LlmCut.blocked) return false;
    if (last.cut == null && !last.failed) return false;
    if (partialLast == null) return false;
    _wakes++;
    llmLog.add(LlmEventKind.cut, last.by ?? '', tr('自动接着写'));
    return _resume(DateTime.now()) == null;
  }

  /// 区域控制这边收到主工作区转来的任务,回复里却没有完整的布局(提问了、只说了话):
  /// 用户不在这边看,没人回答,所以自己叫醒它直接排。
  bool _checkHandoff() {
    if (!layoutOnly || _wakes >= _maxWakes || _messages.length < 2) {
      return false;
    }
    final ask = _messages.lastWhere(
      (m) => m.fromUser && !m.tool,
      orElse: () => _messages.first,
    );
    if (!ask.text.startsWith(handoffMark)) return false;
    final reply = splitNewSkill(_messages.last.text).prose;
    if (splitLayout(reply).complete) return false;
    final asked = splitOptions(reply).options.isNotEmpty;
    return _wake(
      '【程序检查:没交出布局】这是主工作区转来的任务,用户不在这边,没人回答。'
      '${asked ? '不要提问,选项都按第一个(推荐的)定,' : ''}'
      '直接给出一份完整的 <layout>;正文只写一句话。',
      tr('没交出布局,已让 Agent 补上'),
    );
  }

  /// 程序叫醒 Agent:接一条程序写的消息(发给模型时算用户说的),马上开始下一条回复。
  bool _wake(String text, String note) {
    _wakes++;
    final time = DateTime.now();
    final problem = _startReply([
      ..._messages,
      ChatMessage(
        fromUser: true,
        tool: true,
        time: time,
        text: text,
        toolSummary: note,
      ),
    ], time);
    if (problem != null) {
      _updateReply(
        (m) => m.copyWith(
          text: tr('{0}\n[出错] {1}', [m.text, problem]),
          failed: true,
        ),
      );
    }
    return true;
  }
}

/// 主工作区转给区域控制的任务开头的记号(`_askLayout`)。
const handoffMark = '【主工作区转来的任务】';

/// 一条用户消息之后程序最多自己叫醒 Agent 几次。
const _maxWakes = 2;
