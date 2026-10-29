part of 'studio_view_model.dart';

/// 和 Agent 对话:发消息、流式回复、停止、重新运行,以及把回复里的成稿和 Skill 送出去。
extension StudioChat on StudioViewModel {
  /// 发送一条消息并开始流式回复。不能发送时返回给用户看的原因,成功返回 null。
  /// [skillIds] 是用户在输入框里用 @ 引用的 Skill,[attachments] 是附上的图片和文件,
  /// 它们的内容会随这条消息一起发出。
  String? send(
    String raw, {
    DateTime? now,
    List<String> skillIds = const [],
    List<Attachment> attachments = const [],
  }) {
    final text = raw.trim();
    if (text.isEmpty && attachments.isEmpty) return tr('请输入内容后再发送');
    final message = (
      text: text,
      skillIds: List<String>.unmodifiable(skillIds),
      attachments: List<Attachment>.unmodifiable(attachments),
      quote: _quote,
    );
    // 正在生成:先排着,这条回复说完了自动发;也可以点「立刻发送」打断它。
    if (isStreaming) {
      _outbox = List.unmodifiable([..._outbox, message]);
      _quote = null;
      _changed();
      return null;
    }
    final problem = _post(message, now ?? DateTime.now());
    if (problem == null && _quote != null) {
      _quote = null;
      _changed();
    }
    return problem;
  }

  String? _post(QueuedMessage m, DateTime time) {
    _toolRounds = 0;
    _foundTags.clear();
    return _startReply([
      ..._messages,
      ChatMessage(
        fromUser: true,
        text: m.text,
        time: time,
        skillIds: m.skillIds,
        attachments: m.attachments,
        quote: m.quote,
      ),
    ], time);
  }

  /// 把排着的第 [i] 条撤掉。
  void unqueue(int i) {
    if (i < 0 || i >= _outbox.length) return;
    _outbox = List.unmodifiable([..._outbox.take(i), ..._outbox.skip(i + 1)]);
    _changed();
  }

  /// 不等了:打断正在生成的回复,马上发排着的第 [i] 条。发不了时返回原因,它留在队里。
  String? sendQueuedNow(int i) {
    if (i < 0 || i >= _outbox.length) return null;
    stop();
    final problem = _post(_outbox[i], DateTime.now());
    if (problem == null) unqueue(i);
    return problem;
  }

  /// 一条回复说完了:队里有排着的就发下一条。发不了(比如模型被删了)就留在队里。
  void _sendNext() {
    if (_outbox.isEmpty || isStreaming || _disposed) return;
    if (_post(_outbox.first, DateTime.now()) == null) unqueue(0);
  }

  void quoteSection(String? section) {
    if (_quote == section) return;
    _quote = section;
    _changed();
  }

  /// 回复正常结束后,把里面那份完整的新成稿自动送到左侧,省得用户再点一次:
  /// 这轮讨论的是选中的一段就只换那段,否则换整篇。放不进去就算了,卡片上还能手动放。
  ///
  /// 成稿是空的时直接填进去(没有东西会被盖掉,不用确认);
  /// 已经有内容时只提出待确认改动,由用户采纳或驳回。
  void _deliverDraft() {
    if (_messages.length < 2) return;
    // 中间可能隔着查标签的那几条,所以找用户自己发的最后一条。
    final quote = _messages
        .lastWhere((m) => m.fromUser && !m.tool, orElse: () => _messages.first)
        .quote;
    final drafts = splitDrafts(splitNewSkill(_messages.last.text).prose).drafts;
    // 一条回复可以有好几份,各去各的页。
    final written = <int>{};
    for (final draft in drafts) {
      if (!draft.complete) continue;
      final problem = placeDraft(
        draft.text,
        page: draft.page,
        replacing: quote,
        written: written,
        name: draft.name,
        seriesTitle: draft.series,
        replace: draft.replace,
      );
      // 放不上要说出来(以前悄悄丢掉了);系列满了时页签下面还会亮提醒。
      if (problem != null) _note(tr('成稿没放上:{0}', [problem]));
    }
    showWritten(written);
  }

  /// 成稿只写到了别的页(比如新开的一页):换过去,让用户看到刚写好的。
  /// 副聊天写的也走这里;正在生成时不换。
  void showWritten(Set<int> written) {
    if (written.isEmpty || written.contains(_page) || isStreaming) return;
    _show(written.last);
    _leftPage();
  }

  /// 回复里写完了一个新 Skill:直接加进用户的 Skills。
  /// 已经有同名的就不动,等用户在卡片上点替换,免得把他原来的盖掉。
  Future<void> _deliverSkill() async {
    final store = skills;
    if (store == null || _messages.isEmpty) return;
    final made = splitNewSkill(_messages.last.text);
    if (made.skill == null || !made.complete) return;
    try {
      final id = parseSkill(made.skill!, fallbackName: '').id;
      if (store.skills.any((s) => s.id == id)) return;
      await store.addText(made.skill!);
      if (!_disposed) _changed();
    } on SkillException {
      // 加不了的原因卡片上会显示。
    }
  }

  /// 重新运行:丢掉最后一条回复,把最后一条用户消息原样再发一次。
  /// 不能运行时返回给用户看的原因,成功返回 null。
  String? regenerate({DateTime? now}) {
    if (isStreaming) return tr('正在生成,请先停止当前回复');
    final at = _messages.lastIndexWhere((m) => m.fromUser);
    if (at < 0) return tr('还没有可以重新运行的消息');
    _toolRounds = 0;
    _foundTags.clear();
    return _startReply(_messages.sublist(0, at + 1), now ?? DateTime.now());
  }

  /// 以 [history](最后一条是用户消息)为上文开始一条新的流式回复。
  String? _startReply(List<ChatMessage> history, DateTime time) {
    final cfg = config.config;
    final chain = _usable(cfg.agentChain);
    if (chain.isEmpty) return tr('请先在设置里添加模型并填写模型名称');

    // 出错的、被停在开头的空回复不算历史,有的接口会拒收空内容。
    final sent = [
      for (final m in history)
        if (m.fromUser || !m.failed && m.text.isNotEmpty) m,
    ];
    // 用户这次的话里提到的角色,先替模型查好,接在那条消息后面(查工具那几轮也一直带着)。
    final ask = sent.where((m) => m.fromUser && !m.tool).lastOrNull;
    final found = ask == null
        ? const <String, List<CharacterHit>>{}
        : _mentioned(ask);
    final auto = _autoLookupText(found);
    _messages = List.unmodifiable([
      ...history,
      ChatMessage(
        fromUser: false,
        text: '',
        time: time,
        toolSummary: found.isEmpty
            ? null
            : tr('已按名字查了角色库:{0}', [found.keys.join(tr('、'))]),
      ),
    ]);
    final preset = cfg.activePreset;
    final enabled = {
      for (final s in skills?.all ?? const <UserSkill>[])
        if (!cfg.disabledSkills.contains(s.id)) s.id,
    };
    final requests = _requests(cfg, chain, preset, [
      {
        'role': 'system',
        'content': layoutOnly
            ? _layoutSystemPrompt(cfg, preset)
            : _systemPrompt(cfg, preset),
      },
      for (final (i, m) in sent.indexed)
        {
          'role': m.fromUser ? 'user' : 'assistant',
          'content': switch (identical(m, ask) && auto.isNotEmpty
              ? '${_withReferences(m, enabled)}\n\n$auto'
              : _withReferences(m, enabled)) {
            // 自己以前写的布局、透视、灯光不重发:画板可能已被用户改过。
            // 后面紧跟着工具结果的是查资料的那条,里面的布局没放上画板。
            final text when !m.fromUser => forgetLighting(
              forgetPerspectives(
                forgetLayers(
                  forgetLayouts(
                    text,
                    placed: i + 1 >= sent.length || !sent[i + 1].tool,
                  ),
                ),
              ),
            ),
            // 布局页里刚发的这条带着参考图:就在这里提醒画布多大,
            // 模型看了图常照图的比例写宽高(系统提示里说了也会忘)。
            final text
                when layoutOnly &&
                    i == sent.length - 1 &&
                    m.attachments.any((a) => a.isImage) =>
              '$text${_canvasReminder()}',
            final text => text,
          },
        },
    ], images: _imagesOf(sent));
    _reply =
        streamWithFailover(
          requests,
          this.streamChat,
          // 还在等的时候也标上正在问哪个模型,轮换到哪一个看得见。
          onTrying: (name) => _updateReply((m) => m.copyWith(by: name)),
        ).listen(
          (delta) => _updateReply((m) => m.copyWith(text: m.text + delta)),
          onError: (Object e) {
            _updateReply(
              (m) => m.copyWith(
                text: tr('{0}\n[出错] {1}', [m.text, e]),
                failed: true,
              ),
            );
            _finishReply();
            _sendNext();
          },
          onDone: () {
            _finishReply();
            // 模型要先查标签:查完它会接着写,成稿等那一条。
            if (_searchTags()) return;
            // 布局页的对话只往布局画板上放,不碰成稿。
            if (!layoutOnly) {
              _deliverDraft();
              _checkTags();
            }
            _deliverCharacters();
            // 透视在 _deliverLayout 里先放(没有布局时它自己放)。
            _deliverLayout();
            _deliverLayers();
            // 放在布局后面:换布局时灯光照旧,这条回复写的灯光才不会被盖回去。
            _deliverLighting();
            unawaited(_deliverSkill());
            // 人物块对不上角色卡:让 Agent 接着改,改完那一条再发排着的消息。
            if (_fixCast()) return;
            _sendNext();
          },
          cancelOnError: true,
        );
    _changed();
    return null;
  }

  /// 停止当前回复,保留已生成的部分。
  void stop() {
    if (!isStreaming) return;
    if (_toolBusy) {
      // 正在查标签:作废这一次,查回来的结果不要了。
      _toolRun++;
      _toolBusy = false;
      _updateReply((m) => m.copyWith(stopped: true));
      return;
    }
    unawaited(_reply!.cancel());
    _reply = null;
    _updateReply((m) => m.copyWith(stopped: true));
  }

  /// 发一条消息,等这条回复彻底说完(查标签那几轮也算)。主工作区把排布局的活
  /// 交给区域控制的 Agent 时用。正在生成、发不出去时抛 [LlmException]。
  Future<void> sendAndWait(
    String text, {
    List<Attachment> attachments = const [],
  }) async {
    if (isStreaming) throw LlmException(tr('区域控制的 Agent 正在忙'));
    final problem = send(text, attachments: attachments);
    if (problem != null) throw LlmException(problem);
    final done = Completer<void>();
    // 一轮说完到下一轮查标签之间会有一下子不在生成:等这一刻过去再看。
    void check() => scheduleMicrotask(() {
      if (!isStreaming && !done.isCompleted) done.complete();
    });
    addListener(check);
    check();
    try {
      await done.future;
    } finally {
      removeListener(check);
    }
  }

  /// 只问 [llm] 接口的 [model] 一次,等它说完,不换后备模型(本地反推页的 LLM 反推用)。
  /// 失败时抛 [LlmException]。
  Future<String> askModel(
    LlmProfile llm,
    String model,
    List<Map<String, String>> messages, {
    Map<int, List<LlmImage>> images = const {},
  }) {
    final cfg = config.config;
    return streamWithFailover(
      _requests(
        cfg,
        [llm.copyWith(model: model)],
        cfg.activePreset,
        messages,
        images: images,
      ),
      this.streamChat,
    ).join();
  }

  /// 没填模型名称的接口发出去也只会报错,直接跳过。
  List<LlmProfile> _usable(List<LlmProfile> chain) => [
    for (final l in chain)
      if (l.models.isNotEmpty) l,
  ];
}
