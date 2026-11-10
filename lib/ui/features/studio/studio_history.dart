part of 'studio_view_model.dart';

/// 操作记录:记一笔、把几笔合成一笔、回到某一步之前或之后。
///
/// 记录是一条线,和撤销 / 重做一样:每一笔拍下做之前的样子,做完之后的样子在换走时补上;
/// 回到某一步不删记录,只是把工作台换成那时的样子、把「眼前」([_head])指过去,
/// 后面那几笔变灰(撤回来的),点它们能重做;这时再做新的操作,灰的就扔掉。
/// (2026-11-11 用户反馈以前那棵带分支的树看着乱,改成这样。)
extension StudioHistory on StudioViewModel {
  /// 工作台现在的样子。里面都是不可变的东西,所以只是记个引用,不费地方。
  _Snapshot _snapshot() => (
    pages: List.unmodifiable(pages),
    page: _page,
    seriesNames: _seriesNames,
    seriesChats: _seriesChats,
    messages: _messages,
    chatId: _chatId,
    archive: _archive,
    closedTabs: _closedTabs,
  );

  /// 记一笔操作。**要在动手改之前调**:它顺手拍下现在的样子,回到这一步之前就是回到这里。
  /// 来不及在改之前调的,先自己 [_snapshot] 一份从 [before] 传进来。
  /// 正在合成一笔时([_asOneStep])只记下这一步的说明。
  void _log(String text, {_Snapshot? before}) {
    final steps = _steps;
    if (steps != null) {
      steps.add(text);
      return;
    }
    _record(text, before ?? _snapshot());
  }

  void _record(
    String text,
    _Snapshot before, {
    List<String> details = const [],
  }) {
    // 撤回来的那几笔扔掉(新的在前,所以是眼前这一笔前面的那些);
    // 眼前这一笔做完之后的样子,就是这一笔做之前的样子。
    final kept = _actions.skip(_headIndex).toList();
    final made = ActionRecord._(
      id: _nextActionId++,
      time: DateTime.now(),
      text: text,
      before: before,
      details: List.unmodifiable(details),
    );
    _actions = List.unmodifiable(
      [
        made,
        for (final (i, a) in kept.indexed) i == 0 ? a._withAfter(before) : a,
      ].take(_maxActions),
    );
    _head = made.id;
  }

  /// 眼前这一笔在 [actions] 里的位置;在最开始时是 [actions] 的长度。
  int get _headIndex {
    final i = _actions.indexWhere((a) => a.id == _head);
    return i < 0 ? _actions.length : i;
  }

  /// 把 [run] 里记的几笔合成一笔,回到它之前时一起撤(用户反馈:Agent 一条回复里的
  /// 新开页、起名、采纳各记一笔,撤一笔只撤了一半)。一笔都没记的就不记;只有一步时就记那一步,
  /// 不然用 [label] 拿各步起名,各步列在 [ActionRecord.details] 里。已经在合的时候照常跑。
  T _asOneStep<T>(String Function(List<String> steps) label, T Function() run) {
    if (_steps != null) return run();
    final before = _snapshot();
    final steps = <String>[];
    _steps = steps;
    try {
      return run();
    } finally {
      _steps = null;
      if (steps.length == 1) {
        _record(steps.single, before);
      } else if (steps.isNotEmpty) {
        _record(label(steps), before, details: steps);
      }
    }
  }

  /// Agent 一条回复里写进成稿的那几步合成一笔(副聊天写的也走这里)。
  /// [written] 是这条回复写到的页,跑完 [run] 才知道,所以起名时再看。
  T asAgentStep<T>(Set<int> written, T Function() run) => _asOneStep(
    (steps) => written.isEmpty
        ? tr('Agent 改了成稿 · {0} 步', [steps.length])
        : tr('Agent 写入 {0}', [
            written
                .where((i) => i < _pages.length)
                .map(_pageTitle)
                .join(tr('、')),
          ]),
    run,
  );

  /// 第 [i] 页叫什么:「系列 1 · 第 2 页」。
  String _pageTitle(int i) =>
      tr('{0} · 第 {1} 页', [seriesName(_pages[i].series), pageNumber(i)]);

  /// 回到 [actions] 里第 [index] 笔之前的样子(它和它之后的都算撤回来的,记录还留着)。
  /// 生成中不能换,返回原因。
  String? rollback(int index) => index + 1 < _actions.length
      ? restoreTo(index + 1)
      : _goTo(index, start: true);

  /// 回到 [actions] 里第 [index] 笔做完之后的样子。
  String? restoreTo(int index) => _goTo(index);

  /// 撤销眼前这一笔。已经在最开始时什么也不做。
  String? undo() => _headIndex < _actions.length ? rollback(_headIndex) : null;

  /// 重做撤回来的下一笔。
  String? redo() => _headIndex > 0 ? restoreTo(_headIndex - 1) : null;

  bool get canUndo => _headIndex < _actions.length;
  bool get canRedo => _headIndex > 0;

  /// 换到第 [index] 笔做完之后;[start] 为真时换到最早那一笔做之前(最开始)。
  String? _goTo(int index, {bool start = false}) {
    if (index < 0 || index >= _actions.length) return null;
    if (isStreaming) return tr('正在生成,请先停止当前回复');
    final target = _actions[index];
    if (!start && target.id == _head) return null;
    // 先把眼前的样子(连同那之后手打的字)记在眼前这一笔上,切回来还在。
    final now = _snapshot();
    final head = _head;
    _actions = List.unmodifiable([
      for (final a in _actions) a.id == head ? a._withAfter(now) : a,
    ]);
    final fresh = _actions[index];
    if (start) {
      _restore(fresh._before);
      _head = null;
    } else {
      _restore(fresh._after ?? now);
      _head = fresh.id;
    }
    // 区域控制那场对话要把这页摆回画板上。
    _changed();
    return null;
  }

  /// 第 [index] 笔和眼前的关系。
  ActionState stateOf(int index) {
    final head = _headIndex;
    if (index == head) return ActionState.current;
    return index > head ? ActionState.done : ActionState.undone;
  }

  /// 把工作台整个换成 [s] 那时的样子。
  void _restore(_Snapshot s) {
    _pages = s.pages;
    _page = s.page;
    _seriesNames = s.seriesNames;
    _seriesChats = s.seriesChats;
    _messages = s.messages;
    _chatId = s.chatId;
    _archive = s.archive;
    _closedTabs = s.closedTabs;
    _blocks = _pages[_page].blocks;
    _pending = _pages[_page].pending;
    _queued = _pages[_page].queued;
    _translation = null;
    _translationBy = null;
    _quote = null;
    bodySelection = null;
    _toolRounds = 0;
    _foundTags.clear();
    _pageEpoch++;
  }
}
