part of 'studio_view_model.dart';

/// 存盘与读回、对话历史、历史提示词。
extension StudioStorage on StudioViewModel {
  /// 读回上次的工作台。文件读不了时改名留底,从空白开始。
  Future<void> load() async {
    final file = saveFile;
    if (file == null || !await file.exists()) return;
    try {
      restore(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      _files?.sweep();
    } on Object catch (e) {
      debugPrint(tr('读取工作台失败:{0}', [e.runtimeType]));
      try {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        await file.rename('${file.path}.bad-$stamp');
      } on FileSystemException catch (e) {
        debugPrint(tr('给工作台文件留底失败:{0}', [e.message]));
      }
    }
  }

  /// 要存盘的全部内容。待确认的改动和没发出去的引用不存;
  /// 存盘时(有 [saveFile])顺带把消息附件写成文件。
  Map<String, dynamic> toJson() => {
    ..._pagesJson(),
    'translation': ?_translation,
    'translationBy': ?_translationBy,
    'chatId': _chatId,
    // 已经不在历史里的就不用记了。
    'closedTabs': [
      for (final c in _archive)
        if (_closedTabs.contains(c.id)) c.id,
    ],
    'messages': [for (final m in _messages) m.toJson(files: _files)],
    'chats': [
      for (final c in _archive)
        {
          'id': c.id,
          'messages': [for (final m in c.messages) m.toJson(files: _files)],
        },
    ],
    'prompts': [
      for (final p in _promptLog)
        {'time': p.time.toIso8601String(), 'text': p.text},
    ],
  };

  /// 用 [toJson] 存下的内容换掉当前的工作台。格式不对时抛异常,什么都不改。
  void restore(Map<String, dynamic> j) {
    List<ChatMessage> messages(Object? list) => List.unmodifiable([
      for (final m in (list as List?) ?? const [])
        ChatMessage.fromJson(m as Map<String, dynamic>, files: _files),
    ]);
    List<Block> blocksOf(Object? list) => List.unmodifiable([
      for (final b in (list as List?) ?? const [])
        (text: b['text'] as String, pinned: b['pinned'] as bool),
    ]);
    // 旧版只有一页,成稿直接存在 blocks 里。
    final pages = List<DraftPage>.unmodifiable([
      for (final p in (j['pages'] as List?) ?? const [])
        _newPage(
          p['series'] as int,
          name: (p['name'] as String?) ?? '',
          blocks: blocksOf(p['blocks']),
        ),
      if (j['pages'] == null) _newPage(0, blocks: blocksOf(j['blocks'])),
    ]);
    final seriesNames = Map<int, String>.unmodifiable({
      for (final e in ((j['seriesNames'] as Map?) ?? const {}).entries)
        int.parse(e.key as String): e.value as String,
    });
    if (pages.isEmpty) throw const FormatException('没有页');
    final page = ((j['page'] as int?) ?? 0).clamp(0, pages.length - 1);
    final seriesChats = Map<int, ChatSession>.unmodifiable({
      for (final e in ((j['seriesChats'] as Map?) ?? const {}).entries)
        int.parse(e.key as String): (
          id: e.value['id'] as String,
          messages: messages(e.value['messages']),
        ),
    });
    final current = messages(j['messages']);
    final archive = List<ChatSession>.unmodifiable([
      for (final c in (j['chats'] as List?) ?? const [])
        (id: c['id'] as String, messages: messages(c['messages'])),
    ]);
    final prompts = List<PromptRecord>.unmodifiable([
      for (final p in (j['prompts'] as List?) ?? const [])
        (time: DateTime.parse(p['time'] as String), text: p['text'] as String),
    ]);
    _pages = pages;
    _page = page;
    _seriesChats = seriesChats;
    _seriesNames = seriesNames;
    _blocks = pages[page].blocks;
    _pending = null;
    _queued = const [];
    _translation = j['translation'] as String?;
    _translationBy = j['translationBy'] as String?;
    _chatId = (j['chatId'] as String?) ?? _newId();
    _closedTabs = Set.unmodifiable(
      ((j['closedTabs'] as List?) ?? const []).cast<String>(),
    );
    _messages = current;
    _archive = archive;
    _promptLog = prompts;
    _changed();
  }

  /// 以前的对话,新的在前;不含正在进行的这一场。最多留 [_maxChats] 场。
  List<ChatSession> get pastChats => _archive;

  /// 收起当前对话,开一场新的。生成中不能换,返回 false。
  bool newChat() => _switchChat(null);

  /// 收起当前对话,接着聊以前的某一场。
  bool openChat(String id) => _switchChat(id);

  bool _switchChat(String? id) {
    if (isStreaming) return false;
    final next = _archive.where((c) => c.id == id).firstOrNull;
    if (id != null && next == null) return false;
    _archive = List.unmodifiable(
      [
        if (_messages.isNotEmpty) (id: _chatId, messages: _messages),
        for (final c in _archive)
          if (c.id != id) c,
      ].take(_maxChats),
    );
    _chatId = next?.id ?? _newId();
    _messages = next?.messages ?? const [];
    _quote = null;
    // 重新打开的对话又占一个标签。
    _closedTabs = Set.unmodifiable({..._closedTabs}..remove(_chatId));
    _changed();
    return true;
  }

  /// 标签行上的对话,按开始的先后排(编号就是开始的时刻),所以换来换去位置不动:
  /// 眼前这场,加上历史里没被关掉标签的那些。
  List<ChatSession> get chatTabs => <ChatSession>[
    (id: _chatId, messages: _messages),
    for (final c in _archive)
      if (!_closedTabs.contains(c.id)) c,
  ]..sort((a, b) => a.id.compareTo(b.id));

  /// 关掉一个对话的标签:对话还在历史里,能从那里再打开;要真删得去历史里删。
  /// 关的是眼前这场时,换到另一个开着的标签上(没有就开一场新的)。生成中关不了眼前这场。
  bool closeChat(String id) {
    if (id == _chatId) {
      if (isStreaming) return false;
      final next = _archive
          .where((c) => !_closedTabs.contains(c.id))
          .firstOrNull;
      if (!_switchChat(next?.id)) return false;
    }
    _closedTabs = Set.unmodifiable({..._closedTabs, id});
    _changed();
    return true;
  }

  /// 眼前这场对话的编号;对话标签用它认出哪个是当前的。
  String get chatId => _chatId;

  /// 删掉一场对话。删的是眼前这场时,换到最近的另一场上(没有就开一场新的);
  /// 生成中删不了眼前这场,返回 false。
  bool deleteChat(String id) {
    final before = _snapshot();
    if (id == _chatId) {
      if (isStreaming) return false;
      final next = _archive.firstOrNull;
      _archive = List.unmodifiable(_archive.skip(1));
      _chatId = next?.id ?? _newId();
      _messages = next?.messages ?? const [];
      _quote = null;
    } else {
      _archive = List.unmodifiable(_archive.where((c) => c.id != id));
    }
    _closedTabs = Set.unmodifiable({..._closedTabs}..remove(id));
    _log(tr('删除一场对话'), before: before);
    _changed();
    return true;
  }

  /// 把当前成稿记进历史提示词;和最新一条一样就不重复记。
  void recordPrompt({DateTime? now}) {
    final text = labeledPrompt;
    if (text.trim().isEmpty ||
        _promptLog.isNotEmpty && _promptLog.first.text == text) {
      return;
    }
    _promptLog = List.unmodifiable(
      [
        (time: now ?? DateTime.now(), text: text),
        ..._promptLog,
      ].take(_maxPrompts),
    );
    _changed();
  }

  void deletePrompt(PromptRecord record) {
    _promptLog = List.unmodifiable(_promptLog.where((p) => p != record));
    _changed();
  }

  /// 把一条历史提示词放回成稿:成稿是空的直接填,有内容就等用户确认。
  /// 不能放时返回给用户看的原因。
  // ponytail: 记录里含当时的固定区文字;现在还有固定区时放回来会重复,
  // 要处理的话得把记录按块存而不是存成一整段。
  String? restorePrompt(PromptRecord record, {String? title}) {
    title ??= tr('历史提示词');
    final wasEmpty = body.trim().isEmpty;
    final before = _snapshot();
    final problem = proposeDraft(record.text, merge: false, title: title);
    if (problem == null) {
      _log(tr('把「{0}」放回 {1}', [title, _here]), before: before);
    }
    if (problem == null && wasEmpty) acceptDiff();
    return problem;
  }
}
