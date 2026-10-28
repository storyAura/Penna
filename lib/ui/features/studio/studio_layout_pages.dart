part of 'studio_view_model.dart';

/// 区域控制工作台的分页:那场对话(`layoutOnly`)借用成稿的分页和系列(见 [StudioPages]),
/// 每一页的成稿就是一张布局(`Layout.toJson` 的 JSON,空白页是空串)。
/// 画板([StudioViewModel.layout])摆的是眼前这一页:换页时把那页的布局摆上去,
/// 画板上改了什么(拖框、Agent 放布局)写回眼前这页。
extension StudioLayoutPages on StudioViewModel {
  /// 眼前这一页存着的布局 JSON。
  String get _pageText => _blocks.map((b) => b.text).join();

  /// 页 → 画板:眼前这页的布局和画板上次对上的不一样(换了页、回滚、读档)就摆上去。
  /// 头一回对的时候眼前这页还空着,而画板上有东西(旧版只有一张画板),就把画板收进这页。
  void _syncBoard() {
    final board = layout;
    if (board == null) return;
    final text = _pageText;
    if (text == _boardText) return;
    if (_boardText == null && text.trim().isEmpty) return _pullBoard();
    _boardText = text;
    board.replace(_layoutOf(text, board.layout));
  }

  /// 画板 → 页:画板变了就写进眼前这页。只在页从空变成有、或从有变成空、
  /// 或记了一笔操作时通知界面(页签、操作记录要变样);拖框时每一帧都在变,
  /// 其余的只排一次存盘。画板标了这是哪一步操作([LayoutBoard.mark])就记进操作记录,
  /// 拖动时只有第一帧带着它。
  void _pullBoard() {
    final board = layout!;
    final action = board.takeAction();
    final l = board.layout;
    final text = l.isEmpty ? '' : jsonEncode(l.toJson());
    if (text == _boardText) return;
    _boardText = text;
    final was = _pageText;
    if (text == was) return;
    // 要在改之前记:顺手拍下的是这页原来的样子,回滚就回到这里。
    if (action != null) _log(tr('{0}({1})', [action, _here]));
    _blocks = text.isEmpty
        ? const []
        : List.unmodifiable([(text: text, pinned: false)]);
    if (action != null || was.isEmpty != text.isEmpty) return _changed();
    _scheduleSave();
  }

  /// 一页存着的布局;空白页(或读不了)是一张空画布,尺寸沿用 [now] 的。
  static Layout _layoutOf(String text, Layout now) {
    final blank = Layout(width: now.width, height: now.height);
    if (text.trim().isEmpty) return blank;
    try {
      return Layout.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on Object {
      return blank;
    }
  }

  /// 回复里写了布局(`<layout>`):放到布局画板上,并在这条回复上记一笔。
  /// 区域控制那场对话里按标签上的 `page` 放到该去的页(另起系列、新开一页),
  /// 并换到那一页,用户一眼就看得到。读不了的不记:这一栏前面是个对勾,
  /// 读不了由布局卡片自己标红。
  void _deliverLayout() {
    if (layout == null || _messages.isEmpty) return;
    final placed = placeLayout(
      splitNewSkill(_messages.last.text).prose,
      keep: _layoutKeep,
      // 透视先放:3D 视图里它会转镜头,框和体块要照转好的镜头立起来。
      // 后放的话已立好的体块跟着镜头一转,框挪了位置、人物也转成侧身。
      first: _deliverPerspective,
    );
    if (placed == null) return _deliverPerspective();
    if (placed.isNotEmpty) _note(placed);
  }

  /// 把 [reply] 里完整的 `<layout>` 放到画板上(区域控制那边照 `page` 换页),
  /// 返回记在回复上的一句;没写完、读不了是 null,放不上的原因也在那一句里。
  /// [first] 在真正放布局之前调。副聊天写的布局也走这里。
  String? placeLayout(
    String reply, {
    LayoutKeep keep = LayoutKeep.none,
    VoidCallback? first,
  }) {
    final board = layout;
    if (board == null) return null;
    final made = splitLayout(reply);
    final json = made.json;
    if (!made.complete || json == null) return null;
    final l0 = board.layout;
    // 先看读不读得了,免得读不了还白开一页。
    if (parseMossLayout(json, width: l0.width, height: l0.height) == null) {
      return null;
    }
    final where = layoutOnly
        ? _layoutPageFor(made.page, name: made.name, title: made.series)
        : null;
    if (where != null && where.problem != null) {
      return tr('布局没放上:{0}', [where.problem!]);
    }
    first?.call();
    final before = (board.layout.width, board.layout.height);
    final style = _seriesStyle;
    final cast = _seriesCast;
    if (!board.apply(json, keep: keep)) return '';
    // 换到本系列的新一页时画板是空的,Agent 没写画风就接上本系列的。
    if (board.layout.style.trim().isEmpty && style.isNotEmpty) {
      board.setSummary(style: style);
    }
    // 角色卡也接上;Agent 这次写的(新角色、换装)盖在上面。
    if (cast.keys.any((k) => !board.layout.cast.containsKey(k))) {
      board.setCast({...cast, ...board.layout.cast});
    }
    final l = board.layout;
    final clipped = board.fixes.where((f) => f.clipped).length;
    final dropped = board.fixes.length - clipped;
    return [
      tr('已放到区域控制工作台 · {0} 个框', [l.boxes.length]),
      if (where?.moved ?? false)
        tr('「{0}」第 {1} 页', [seriesName(series), pageNumber(_page)]),
      if ((l.width, l.height) != before)
        tr('画布换成 {0}×{1}', [l.width, l.height]),
      if (board.refit case final r?)
        tr('按画布比例摆放:{0}×{1} → {2}×{3}', [r.width, r.height, l.width, l.height]),
      if (clipped > 0) tr('{0} 个超出画布,已截掉', [clipped]),
      if (dropped > 0) tr('{0} 个读不了,已去掉', [dropped]),
      if (castMisses(l) case final m when m.isNotEmpty)
        tr('{0} 个人物块没对上角色卡', [m.length]),
    ].join(' · ');
  }

  /// 这条回复交出的布局里有人物块对不上角色卡时,程序自己让 Agent 改一次(算一轮工具),
  /// 不等出图时特征串了才发现。返回是否接手了。
  bool _fixCast() {
    final board = layout;
    if (board == null || _toolRounds >= _maxToolRounds) return false;
    if (!splitLayout(splitNewSkill(_messages.last.text).prose).complete) {
      return false;
    }
    final misses = castMisses(board.layout);
    if (misses.isEmpty) return false;
    _toolRounds++;
    final names = misses
        .map((b) => '「${b.name.isEmpty ? '(没起名)' : b.name}」')
        .join('、');
    final time = DateTime.now();
    final problem = _startReply([
      ..._messages,
      ChatMessage(
        fromUser: true,
        tool: true,
        time: time,
        text:
            '【程序检查:角色卡没对上】刚交出的布局里,人物块 $names 的名字对不上【本系列角色卡】'
            '(现有:${board.layout.cast.keys.join('、')}),程序没法给它们接上角色卡,出图时特征会串到别人身上。'
            '改好后重新给出完整的 <layout>:已有角色卡的人,name 改成那张卡的名字(「名字·格号」);'
            '新出场的角色在 summary 的 "cast" 里各加一张卡,长相照角色库查到的写,和别人分得开;'
            '一个人物块只放一个角色;路人这类不进角色卡的,label 改成 object。正文只写一句话。',
        toolSummary: tr('{0} 个人物块没对上角色卡,已让 Agent 补上', [misses.length]),
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

  /// 这条回复答的是哪句话:「按视角改描述」「估体块」时只收那一样(见 [LayoutKeep])。
  LayoutKeep get _layoutKeep {
    final asked = _messages.lastWhere(
      (m) => m.fromUser && !m.tool,
      orElse: () => _messages.last,
    );
    return asked.fromUser ? layoutKeepFor(asked.text) : LayoutKeep.none;
  }

  /// 照 `<layout>` 标签上的 page / series / name 定好放到哪一页并换过去
  /// (同 [placeDraft])。[moved] 是换了页或另起了系列。
  ({bool moved, String? problem}) _layoutPageFor(
    String? page, {
    String? name,
    String? title,
  }) {
    final from = _page;
    if (_wantsNewSeries(page)) {
      final failed = _startSeries(title?.trim() ?? '');
      if (failed != null) return (moved: false, problem: failed);
    }
    final (at, problem) = _pageFor(page, {});
    if (at == null) return (moved: false, problem: problem);
    if (at != _page) {
      _show(at);
      _leftPage();
    }
    final pageName = name?.trim() ?? '';
    if (pageName.isNotEmpty && _pages[_page].name.isEmpty) {
      renamePage(_page, pageName);
    }
    final seriesTitle = title?.trim() ?? '';
    if (seriesTitle.isNotEmpty && !_seriesNames.containsKey(series)) {
      renameSeries(series, seriesTitle);
    }
    return (moved: _page != from || page != null, problem: null);
  }

  /// 接在带参考图的那条用户消息后面(只发给模型,不存):画布多大、只能怎么写宽高。
  String _canvasReminder() {
    final l = layout?.layout;
    if (l == null) return '';
    final (w, h) = (l.width, l.height);
    return '\n\n(程序提示:画布是 $w×$h。参考图只看画面内容和横竖,不照它的比例:'
        '<layout> 的 width / height 写 $w×$h'
        '${w == h ? '' : ',用户要横竖对调时写 $h×$w'};'
        '照这张图的构图排时,bbox 直接在参考图上量 0–1000 的比例([x_min, y_min, x_max, y_max],'
        '"bbox_coord_space" 写 "ref1000",程序换算到画布):图里每样东西都要框上(小字、日期、标志也算),'
        '大小贴着图里的实际轮廓,不缩小、不往中间挪,贴边或被边裁掉的那一边写 0 或 1000;'
        '只借图里的元素、不照它构图时才用画布像素。'
        '排框之前先照图把关系看清:谁在前、谁挡着谁、各挡住哪部分;哪些东西被画面的边裁掉;'
        '机位高低和俯仰、透视线往哪收;各元素之间的大小比例。框照这些摆(有遮挡的地方框要重叠,'
        '被裁掉的贴着画面边),前后写进 layer,透视写 <perspective>,'
        '这些关系还要写进 summary.caption 和每块的 caption。)';
  }

  /// 在最后一条回复的记录上添一笔。
  void _note(String text) => _updateReply(
    (m) => m.copyWith(toolSummary: [?m.toolSummary, text].join(' · ')),
  );

  /// 把一份布局 JSON 放到布局画板上(聊天里布局卡片上的按钮),放进眼前这一页。
  /// 读不了返回 false。
  bool adoptLayout(String json) => layout?.apply(json) ?? false;

  /// 本系列定下的一样东西(画风、角色卡):眼前这页的,没有就取同系列别的页的。
  /// 换了系列就不算。
  T _fromSeries<T>(
    T Function(Layout l) pick,
    bool Function(T v) isSet,
    T none,
  ) {
    final here = layout?.layout;
    if (here != null && isSet(pick(here))) return pick(here);
    for (final (i, p) in pages.indexed) {
      if (i == _page || p.series != series) continue;
      final v = pick(
        _layoutOf(p.blocks.map((b) => b.text).join(), const Layout()),
      );
      if (isSet(v)) return v;
    }
    return none;
  }

  String get _seriesStyle =>
      _fromSeries((l) => l.style.trim(), (s) => s.isNotEmpty, '');

  Map<String, String> get _seriesCast =>
      _fromSeries((l) => l.cast, (c) => c.isNotEmpty, const {});

  /// 本系列的角色卡怎么写:定了就照名字对上,没定就让 Agent 写进 summary.cast。
  static String _castPrompt(Map<String, String> cast) => cast.isEmpty
      ? '【本系列角色卡】还没定。这次的布局里有人物时,在 summary 里加一个 "cast":'
            '{"名字": "英文角色卡"},每个出场的角色一张,名字用中文短名(维尔汀、凛)。'
            '角色卡是一句 25 到 50 词的英文:是谁(作品角色写英文名加作品名)、看上去的年龄和体型、'
            '发色和发型、瞳色、头上戴的和标志物、服装的主色和款式;只写长在身上、每格都不变的,'
            '不写表情、动作和姿势。作品里的角色先查角色库,特征照查到的写成句子。'
            '几个角色的发色、发型、帽子、衣服颜色要写得分得开,相近的地方写明区别。'
            '人物块的 name 写成「名字·格号」(维尔汀·3),程序交出去时把这张卡原样接在那块描述的最前面,'
            '整体描述末尾也列一遍,每格、每页的特征才一样。'
      : '【本系列角色卡】已定,程序交出去时把卡原样接在对得上的人物块描述最前面,'
            '整体描述末尾也列一遍:\n${castText(cast)}\n'
            '人物块的 name 写成「名字·格号」(名字照上面写),一个人物块只放一个角色,几个人同在一格就各画一块。'
            '人物块的 caption 不再写发色、瞳色、发型、服装这些角色卡里有的,只写这一格的景别、表情、动作、'
            '视线和跟别人的位置;一个角色的描述里不写别人的长相,提到别人只写名字。'
            '新角色出场、或用户要给谁换装时,在 summary 里写 "cast",只写要加的或要改的那几个,没写到的照旧。';

  /// 本系列的画风怎么写:定了就沿用,没定就让 Agent 反推一段写进 summary.style。
  static String _stylePrompt(String style) => style.isEmpty
      ? '【本系列画风】还没定。这次写 <layout> 时在 summary 里加一个 "style":'
            '照用户给的参考图或描述反推画风,写成一段 40 到 100 词的英文,只写画风,不写画面内容:'
            '媒介和画法、线条、上色方式、明暗和光的处理、质感,最后一句 "Palette: …" 列出四五个主色。'
            '程序把它记在这个系列上,之后同系列的每一张都沿用它,画风才统一。'
      : '【本系列画风】已定,程序会把它放在每张布局的整体描述前面:\n$style\n'
            '继续这个系列时 <layout> 里不写 "style",也不要在 caption 里改写画风;'
            '用户明说要换画风、发了新的参考图要照它做,或另起新系列(page="新系列")时,'
            '才在 summary 里写一个新的 "style"。';

  /// 告诉区域控制的 Agent 有哪些页、眼前是哪一页;同系列的别的页只列名字和各块。
  String get _layoutPagesPrompt {
    final others = [
      for (final (i, p) in pages.indexed)
        if (i != _page && p.series == series)
          '第 ${pageNumber(i)} 页${p.name.isEmpty ? '' : '「${p.name}」'}:'
              '${_layoutOf(p.blocks.map((b) => b.text).join(), const Layout()).boxes.map((b) => b.name.isEmpty ? b.label : b.name).join('、')}',
    ];
    return '【分页】区域控制工作台分系列、分页(最多 ${StudioPages.maxSeries} 个系列,每个系列的页数不限),'
        '每页是一张独立的布局,【布局画板】摆的是眼前这一页。'
        '【当前系列】「${seriesName(series)}」,共 $seriesLength 页,眼前是第 ${pageNumber(_page)} 页'
        '${_pages[_page].name.isEmpty ? '' : '「${_pages[_page].name}」'}。'
        '${others.isEmpty ? '' : '同系列的其他页(各块的名字):\n${others.join('\n')}'}'
        '\n${_stylePrompt(_seriesStyle)}'
        '\n${_castPrompt(_seriesCast)}';
  }
}
