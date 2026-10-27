part of 'studio_view_model.dart';

/// 成稿的一页:一条独立的提示词。[series] 相同的页是一个系列,
/// 共用一场对话,Agent 写其中一页时看得到同系列的其他页;不同系列互不相见。
/// [name] 是这页的名字(可以没有),显示在页码后面。
typedef DraftPage = ({
  int series,
  String name,
  List<Block> blocks,
  DiffProposal? pending,
  List<DiffProposal> queued,
});

DraftPage _newPage(
  int series, {
  String name = '',
  List<Block> blocks = const [],
}) => (
  series: series,
  name: name,
  blocks: blocks,
  pending: null,
  queued: const [],
);

const DraftPage _blankPage = (
  series: 0,
  name: '',
  blocks: [],
  pending: null,
  queued: [],
);

/// 成稿分页。眼前这一页的内容就是 [StudioViewModel] 原来那几个字段
/// (`_blocks`、`_pending`、`_queued`),别的页收在 `_pages` 里,换页时对调。
/// 页码是系列里的第几页(每个系列都从 1 数),界面上和 Agent 嘴里都是这个数。
// ponytail: 生成回复期间不能换页、加页、删页、挪页(回复结束时成稿要送到"当前页");
// 要放开的话得在发消息时记下目标页,而不是到时候再看当前页。
extension StudioPages on StudioViewModel {
  /// 页签上一层放几个系列、最多几层;系列最多就是这么多个。每个系列的页数不限。
  static const perLayer = 5, maxLayers = 4, maxSeries = perLayer * maxLayers;

  /// 现在有几个系列。
  int get seriesCount => {for (final p in _pages) p.series}.length;

  /// 系列满了:不能再另起系列(往已有的系列里加页不受影响)。
  bool get seriesFull => seriesCount >= maxSeries;

  /// Agent 要另起系列却满了时亮出来的提醒,叫用户清理;不满了就不显示。
  String? get seriesAlert => seriesFull ? _seriesAlert : null;

  void dismissSeriesAlert() {
    if (_seriesAlert == null) return;
    _seriesAlert = null;
    _changed();
  }

  /// 系列满了时给用户看的话。
  static String get fullMessage =>
      tr('系列满了(最多 {0} 个),删掉一些不用的系列再放', [maxSeries]);

  /// 全部的页,按显示顺序;同系列的挨在一起。
  List<DraftPage> get pages => [
    for (final (i, p) in _pages.indexed) i == _page ? _livePage : p,
  ];

  /// 眼前这一页在全部页里排第几(从 0 数)。
  int get pageIndex => _page;

  /// 眼前这一页属于哪个系列。
  int get series => _pages[_page].series;

  /// 第 [i] 页是它那个系列里的第几页(从 1 数)。
  int pageNumber(int i) =>
      _pages.take(i + 1).where((p) => p.series == _pages[i].series).length;

  /// 一个系列的名字:用户或 Agent 起的,没起就是「系列 N」(N 是它排第几)。
  String seriesName(int s) {
    final named = _seriesNames[s];
    if (named != null) return named;
    final order = <int>[];
    for (final p in _pages) {
      if (!order.contains(p.series)) order.add(p.series);
    }
    return tr('系列 {0}', [order.indexOf(s) + 1]);
  }

  /// 眼前这个系列有几页。
  int get seriesLength => _pages.where((p) => p.series == series).length;

  DraftPage get _livePage => (
    series: _pages[_page].series,
    name: _pages[_page].name,
    blocks: _blocks,
    pending: _pending,
    queued: _queued,
  );

  /// 把第 [i] 页摆到眼前;换了系列,对话也跟着换。
  void _show(int i) {
    final from = series;
    _pages = List.unmodifiable(pages);
    _page = i;
    final next = _pages[i];
    _blocks = next.blocks;
    _pending = next.pending;
    _queued = next.queued;
    if (next.series == from) return;
    final chat = _seriesChats[next.series];
    _seriesChats = Map.unmodifiable({
      for (final e in _seriesChats.entries)
        if (e.key != next.series) e.key: e.value,
      if (_messages.isNotEmpty) from: (id: _chatId, messages: _messages),
    });
    _chatId = chat?.id ?? _newId();
    _messages = chat?.messages ?? const [];
    _toolRounds = 0;
    _foundTags.clear();
  }

  /// 换页之后,只属于上一页的零碎状态作废。
  void _leftPage() {
    _translation = null;
    _translationBy = null;
    _quote = null;
    bodySelection = null;
    _changed();
  }

  /// 换到第 [i] 页。不能换时返回给用户看的原因。
  String? openPage(int i) {
    if (i == _page || i < 0 || i >= _pages.length) return null;
    if (isStreaming) return tr('正在生成,稍后再换页');
    _show(i);
    _leftPage();
    return null;
  }

  /// 新开一页并换过去:默认加在眼前这个系列的最后;[toSeries] 指定加到哪个系列,
  /// [newSeries] 为真则另起一个系列(它有自己的对话)。
  String? addPage({int? toSeries, bool newSeries = false}) {
    if (isStreaming) return tr('正在生成,稍后再加页');
    final before = _snapshot();
    final at = _insertPage(
      newSeries
          ? _pages.map((p) => p.series).reduce((a, b) => a > b ? a : b) + 1
          : toSeries ?? series,
    );
    if (at == null) return StudioPages.fullMessage;
    _show(at);
    _log(
      newSeries ? tr('新建「{0}」', [seriesName(series)]) : tr('新增 {0}', [_here]),
      before: before,
    );
    _leftPage();
    return null;
  }

  /// 在 [inSeries] 这个系列的最后插一张空白页,返回它的下标;它是个新系列而系列满了
  /// 时返回 null。眼前这一页不变。
  int? _insertPage(int inSeries) {
    if (seriesFull && !_pages.any((p) => p.series == inSeries)) return null;
    final last = _pages.lastIndexWhere((p) => p.series == inSeries);
    final at = last < 0 ? _pages.length : last + 1;
    final current = pages;
    _pages = List.unmodifiable([
      ...current.take(at),
      _newPage(inSeries),
      ...current.skip(at),
    ]);
    if (at <= _page) _page++;
    return at;
  }

  /// 删掉第 [i] 页。一个系列的最后一页没了,它的对话收进对话历史。
  String? removePage(int i) {
    if (i < 0 || i >= _pages.length) return null;
    if (isStreaming) return tr('正在生成,稍后再删');
    if (_pages.length == 1) return tr('只剩这一页了');
    _log(tr('删除 {0} · 第 {1} 页', [seriesName(_pages[i].series), pageNumber(i)]));
    // 先换到留下来的邻居上,再把这一页拿掉。
    if (i == _page) _show(i > 0 ? i - 1 : 1);
    final gone = _pages[i].series;
    final current = pages;
    _pages = List.unmodifiable([...current.take(i), ...current.skip(i + 1)]);
    if (i < _page) _page--;
    if (_pages.every((p) => p.series != gone)) _forgetSeries(gone);
    _leftPage();
    return null;
  }

  /// 删掉整个系列:它的每一页都删,对话收进对话历史。
  String? removeSeries(int s) {
    if (isStreaming) return tr('正在生成,稍后再删');
    final stay = _pages.indexWhere((p) => p.series != s);
    _log(tr('删除「{0}」', [seriesName(s)]));
    if (stay < 0) {
      // 这是最后一个系列:删完留一张空白页,对话收进历史,从头开始。
      if (_messages.isNotEmpty) {
        _archive = List.unmodifiable(
          [(id: _chatId, messages: _messages), ..._archive].take(_maxChats),
        );
      }
      _pages = List.unmodifiable([_newPage(s + 1)]);
      _page = 0;
      _blocks = const [];
      _pending = null;
      _queued = const [];
      _chatId = _newId();
      _messages = const [];
      _forgetSeries(s);
      _leftPage();
      return null;
    }
    if (series == s) _show(stay);
    final current = pages;
    // 眼前这页前面被删掉了几页,它就往前挪几位。
    final before = current.take(_page).where((p) => p.series == s).length;
    _pages = List.unmodifiable(current.where((p) => p.series != s));
    _page -= before;
    _forgetSeries(s);
    _leftPage();
    return null;
  }

  /// 让第 [i] 页脱离它的系列,自己成为一个新系列(排到最后,对话从空白开始)。
  /// 眼前就是这一页的话,人跟着它过去。
  String? detachPage(int i) {
    if (i < 0 || i >= _pages.length) return null;
    if (isStreaming) return tr('正在生成,稍后再试');
    final from = _pages[i].series;
    final mates = [
      for (final (k, p) in _pages.indexed)
        if (p.series == from && k != i) k,
    ];
    if (mates.isEmpty) return tr('这一页已经自成一个系列了');
    if (seriesFull) return StudioPages.fullMessage;
    _log(tr('{0} · 第 {1} 页脱离系列', [seriesName(from), pageNumber(i)]));
    final follow = i == _page;
    // 先站到同系列的邻居上,这一页才好拿走。
    if (follow) _show(mates.first);
    final current = pages;
    final p = current[i];
    final fresh = current.map((p) => p.series).reduce((a, b) => a > b ? a : b);
    _pages = List.unmodifiable([
      ...current.take(i),
      ...current.skip(i + 1),
      (
        series: fresh + 1,
        name: p.name,
        blocks: p.blocks,
        pending: p.pending,
        queued: p.queued,
      ),
    ]);
    if (i < _page) _page--;
    if (follow) _show(_pages.length - 1);
    _leftPage();
    return null;
  }

  /// 一个系列已经没有页了:名字不要了,对话收进对话历史。
  void _forgetSeries(int s) {
    final chat = _seriesChats[s];
    if (chat != null) {
      _archive = List.unmodifiable([chat, ..._archive].take(_maxChats));
    }
    _seriesChats = Map.unmodifiable({
      for (final e in _seriesChats.entries)
        if (e.key != s) e.key: e.value,
    });
    _seriesNames = Map.unmodifiable({
      for (final e in _seriesNames.entries)
        if (e.key != s) e.key: e.value,
    });
  }

  /// 把第 [from] 页挪到第 [to] 页的位置上;只能在同一个系列里挪。
  String? movePage(int from, int to) {
    if (from == to || from < 0 || to < 0) return null;
    if (from >= _pages.length || to >= _pages.length) return null;
    if (isStreaming) return tr('正在生成,稍后再挪');
    if (_pages[from].series != _pages[to].series) return tr('只能在同一个系列里调顺序');
    _log(
      tr(
        '拖动 {0}:'
        '第 {1} 页 → 第 {2} 页',
        [seriesName(_pages[from].series), pageNumber(from), pageNumber(to)],
      ),
    );
    final moved = pages;
    moved.insert(to, moved.removeAt(from));
    _pages = List.unmodifiable(moved);
    // 眼前这页还是那一页,只是位置可能跟着变了。
    if (_page == from) {
      _page = to;
    } else if (from < _page && _page <= to) {
      _page--;
    } else if (to <= _page && _page < from) {
      _page++;
    }
    _changed();
    return null;
  }

  /// 给一个系列起名;空串就是改回「系列 N」。
  void renameSeries(int s, String name) {
    final clean = name.trim();
    if (clean == (_seriesNames[s] ?? '')) return;
    _log(
      tr('系列改名:{0} → {1}', [seriesName(s), clean.isEmpty ? tr('默认') : clean]),
    );
    _seriesNames = Map.unmodifiable({
      for (final e in _seriesNames.entries)
        if (e.key != s) e.key: e.value,
      if (clean.isNotEmpty) s: clean,
    });
    _changed();
  }

  /// 给第 [i] 页起名;空串就是不要名字。
  void renamePage(int i, String name) {
    if (i < 0 || i >= _pages.length) return;
    final current = pages;
    final p = current[i];
    if (name.trim() == p.name) return;
    _log(
      tr(
        '{0} · 第 {1} 页改名:'
        '{2}',
        [
          seriesName(p.series),
          pageNumber(i),
          name.trim().isEmpty ? tr('去掉名字') : name.trim(),
        ],
      ),
    );
    _pages = List.unmodifiable([
      ...current.take(i),
      (
        series: p.series,
        name: name.trim(),
        blocks: p.blocks,
        pending: p.pending,
        queued: p.queued,
      ),
      ...current.skip(i + 1),
    ]);
    _changed();
  }

  /// 眼前这页的名字(Agent 写成稿时起的,或用户改的),存档案库时先填进名称。
  String get pageName => _pages[_page].name;

  /// 眼前这个系列每一页带标注的成稿(空白页不算),存档案库用。
  List<({String title, String text})> get seriesPrompts => [
    for (final (i, p) in pages.indexed)
      if (p.series == series && p.blocks.any((b) => b.text.trim().isNotEmpty))
        (
          title: tr('第 {0} 页{1}', [
            pageNumber(i),
            p.name.isEmpty ? '' : ' · ${p.name}',
          ]),
          text: _onPage(i, () => labeledPrompt),
        ),
  ];

  /// 暂时把第 [i] 页(和眼前这页同系列)摆到眼前做一件事,做完换回来。
  T _onPage<T>(int i, T Function() run) {
    if (i == _page) return run();
    final back = _page;
    _show(i);
    try {
      return run();
    } finally {
      _show(back);
      _changed();
    }
  }

  /// [page] 是成稿标签上写的页:null 是眼前这页,数字是这个系列里的第几页
  /// (还没有那一页就新开一页),别的(如「新」)也是新开一页。
  /// 返回它指的那一页的下标;去不了就返回原因。
  /// [written] 是这条回复已经写过的页:要新的一页时,眼前这页空着且没被写过就先用它。
  (int?, String?) _pageFor(String? page, Set<int> written) {
    if (page == null) return (_page, null);
    final mine = [
      for (final (i, p) in _pages.indexed)
        if (p.series == series) i,
    ];
    final n = int.tryParse(page);
    if (n != null && n >= 1 && n <= mine.length) return (mine[n - 1], null);
    // 刚另起的系列只有一张空白页,「新系列」指的就是它。
    if (page.contains('系列') && body.trim().isEmpty && _pending == null) {
      return (_page, null);
    }
    if (body.trim().isEmpty && _pending == null && !written.contains(_page)) {
      return (_page, null);
    }
    final at = _insertPage(series);
    return at == null ? (null, StudioPages.fullMessage) : (at, null);
  }

  /// 这份成稿是不是要另起一个系列:标签上写了 `page="新系列"`(换了主题)。
  /// 眼前这个系列还一个字都没有时不算:直接用它,不用另起。
  // ponytail: 只认模型明说的;它忘了写、只是换了个系列名时不另起
  // (系列名对不上也可能只是它随口改了名)。要更稳得让模型每次都报它写的是哪个系列。
  bool _wantsNewSeries(String? page) {
    return (page?.contains('系列') ?? false) &&
        pages.any(
          (p) =>
              p.series == series &&
              p.blocks.any((b) => b.text.trim().isNotEmpty),
        );
  }

  /// 另起一个系列并换过去,**眼前这场对话跟着过去**:用户是在这场对话里换的主题,
  /// 接下来还要接着聊它。原来那个系列的页都留着,只是不再连着这场对话。
  String? _startSeries(String title) {
    final before = _snapshot();
    final fresh =
        _pages.map((p) => p.series).reduce((a, b) => a > b ? a : b) + 1;
    final at = _insertPage(fresh);
    if (at == null) {
      // Agent 要换主题却放不下:亮出提醒,叫用户清理(见 seriesAlert)。
      _seriesAlert = StudioPages.fullMessage;
      _changed();
      return StudioPages.fullMessage;
    }
    // 不走 _show:它会把对话换成新系列的(空的),这里要的是带着走。
    _pages = List.unmodifiable(pages);
    _page = at;
    _blocks = const [];
    _pending = null;
    _queued = const [];
    if (title.isNotEmpty) {
      _seriesNames = Map.unmodifiable({..._seriesNames, fresh: title});
    }
    _log(tr('新建「{0}」', [seriesName(fresh)]), before: before);
    _leftPage();
    return null;
  }

  /// 把一份新成稿放到它该去的那一页:那页是空的直接填,有内容就提出待确认改动。
  /// [replacing] 只对眼前这页有用(用户选来讨论的那一段)。放不了时返回原因。
  /// [name] 是 Agent 给这页起的名字,[seriesTitle] 是它给这个系列起的名字;
  /// 已经有名字的不改。[replace] 为真时整篇换掉,不按标注并进去(固定区照旧留着)。
  String? placeDraft(
    String text, {
    String? page,
    String? replacing,
    Set<int>? written,
    String? name,
    String? seriesTitle,
    bool replace = false,
  }) {
    if (_wantsNewSeries(page)) {
      final failed = _startSeries(seriesTitle?.trim() ?? '');
      if (failed != null) return failed;
    }
    final (at, problem) = _pageFor(page, written ?? const {});
    if (at == null) return problem;
    written?.add(at);
    if (name != null && name.trim().isNotEmpty && _pages[at].name.isEmpty) {
      renamePage(at, name);
    }
    if (seriesTitle != null &&
        seriesTitle.trim().isNotEmpty &&
        !_seriesNames.containsKey(series)) {
      renameSeries(series, seriesTitle);
    }
    return _onPage(at, () {
      // 已经是这份了(比如重新运行得到一样的结果)就不用再提。
      if (containsLines(body, text)) return tr('成稿已经是这样了');
      final wasEmpty = body.trim().isEmpty;
      final failed = proposeDraft(
        text,
        replacing: page == null && !replace ? replacing : null,
        merge: !replace,
      );
      if (failed == null && wasEmpty) acceptDiff();
      return failed;
    });
  }

  /// 眼前这页或这个系列还没名字时,要 Agent 这次写 `<[tag]>` 时起上;都有名字时是空串。
  /// 用户反馈:写单页时常只剩「系列 N」和页码,存进档案库时名称是空的。
  String _namingNote(String tag) {
    final noPage = pageName.isEmpty;
    final noSeries = !_seriesNames.containsKey(series);
    if (!noPage && !noSeries) return '';
    final what = [if (noPage) '这一页', if (noSeries) '这个系列'].join('和');
    final attrs = [
      if (noPage) 'name="两到六个字的页名"',
      if (noSeries) 'series="两到六个字的系列名"',
    ].join(' ');
    return '【还没起名】$what还没有名字:这次写 <$tag> 时一定带上 $attrs,'
        '概括画的是什么(用户存进档案库时当名称)。';
  }

  /// 发给 Agent 看的同系列其他页;只有一页时是空串。
  String get _siblingPages {
    final others = [
      for (final (i, p) in pages.indexed)
        if (i != _page && p.series == series)
          '第 ${pageNumber(i)} 页${p.name.isEmpty ? '' : '(${p.name})'}:\n'
              '${p.blocks.map((b) => b.text).join().trim()}',
    ];
    if (others.isEmpty) return '';
    return '【分页】成稿区现在有好几页,每页是一条独立的提示词。'
        '【当前成稿】是第 ${pageNumber(_page)} 页;同一个系列的其他页如下,'
        '要保持一致的设定(角色、场景、画风)照它们来:\n${others.join('\n\n')}';
  }

  Map<String, dynamic> _pagesJson() => {
    'pages': [
      for (final p in pages)
        {
          'series': p.series,
          if (p.name.isNotEmpty) 'name': p.name,
          'blocks': [
            for (final b in p.blocks) {'text': b.text, 'pinned': b.pinned},
          ],
        },
    ],
    'page': _page,
    'seriesNames': {for (final e in _seriesNames.entries) '${e.key}': e.value},
    'seriesChats': {
      for (final e in _seriesChats.entries)
        '${e.key}': {
          'id': e.value.id,
          'messages': [for (final m in e.value.messages) m.toJson()],
        },
    },
  };
}
