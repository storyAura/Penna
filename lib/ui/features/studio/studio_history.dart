part of 'studio_view_model.dart';

/// 操作记录:记一笔、把几笔合成一笔、回到某一步之前或之后。
///
/// 记录是一棵树。每一笔拍下做之前的样子,做完之后的样子在换走时补上;
/// 回到某一步不删记录,只是把工作台换成那时的样子、把「眼前」([_head])指过去。
/// 回到前面以后再做新的,原来往后那几笔就成了另一个分支,还能切回去(用户要求:
/// 以前回滚会删掉后面的记录,只能靠「回滚」那一笔再滚回去,来回切几次就对不上了)。
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
    // 眼前这一笔做完之后的样子,就是这一笔做之前的样子。
    final head = _head;
    _actions = List.unmodifiable([
      for (final a in _actions) a.id == head ? a._withAfter(before) : a,
    ]);
    final made = ActionRecord._(
      id: _nextActionId++,
      time: DateTime.now(),
      text: text,
      parent: head,
      before: before,
      details: List.unmodifiable(details),
    );
    _actions = List.unmodifiable([made, ..._actions].take(_maxActions));
    _head = made.id;
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

  /// 回到 [actions] 里第 [index] 笔之前的样子(它和从它往后做的都撤掉,但都还留在记录里)。
  /// 生成中不能换,返回原因。
  String? rollback(int index) => _goTo(index, after: false);

  /// 回到 [actions] 里第 [index] 笔做完之后的样子:撤掉的能重做,别的分支也能切过去。
  String? restoreTo(int index) => _goTo(index, after: true);

  String? _goTo(int index, {required bool after}) {
    if (index < 0 || index >= _actions.length) return null;
    if (isStreaming) return tr('正在生成,请先停止当前回复');
    final target = _actions[index];
    if (after && target.id == _head) return null;
    // 先把眼前的样子(连同那之后手打的字)记在眼前这一笔上,切回来还在。
    final now = _snapshot();
    final head = _head;
    _actions = List.unmodifiable([
      for (final a in _actions) a.id == head ? a._withAfter(now) : a,
    ]);
    final fresh = _actions[index];
    if (after) {
      _restore(fresh._after ?? now);
      _head = fresh.id;
    } else {
      _restore(fresh._before);
      // 它的上一笔已经太旧、被删掉了:就当回到了最开始。
      final parent = fresh.parent;
      _head = _actions.any((a) => a.id == parent) ? parent : null;
    }
    // 区域控制那场对话要把这页摆回画板上。
    _changed();
    return null;
  }

  /// 第 [index] 笔和眼前的关系:就是眼前、走到眼前做过的、撤回来的、别的分支上的。
  ActionState stateOf(int index) {
    final a = _actions[index];
    if (a.id == _head) return ActionState.current;
    final byId = {for (final r in _actions) r.id: r};
    // 从眼前往回走:路上的都是做过的。
    for (var at = byId[_head]; at != null; at = byId[at.parent]) {
      if (at.id == a.id) return ActionState.done;
    }
    // 从它往回走能走到眼前(或走到最开始而眼前就是最开始):是撤回来的。
    for (ActionRecord? at = a; at != null; at = byId[at.parent]) {
      if (at.parent == _head) return ActionState.undone;
    }
    return ActionState.branch;
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
  }
}
