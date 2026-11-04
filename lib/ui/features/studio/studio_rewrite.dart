part of 'studio_view_model.dart';

/// 润色和翻译:整篇的,和只对一段的。
extension StudioRewrite on StudioViewModel {
  /// 把当前成稿机翻成中文对照;[selection] 为真时只翻选中的那一截。
  /// 失败时返回给用户看的原因,成功返回 null。
  Future<String?> translateDraft({bool selection = false}) async {
    final whole = finalPrompt;
    final sel = selection ? bodySelection : null;
    final text = sel == null
        ? whole
        : body.substring(sel.$1, sel.$2.clamp(sel.$1, body.length)).trim();
    if (text.isEmpty) return sel == null ? tr('成稿为空') : tr('选中的内容为空');
    if (_translating) return tr('正在翻译');
    final pageEpoch = _pageEpoch;
    _translating = true;
    _changed();
    try {
      final result = await translate(config.config, text);
      // 等译文的时候成稿被清空或改了:这份译文对不上了,不要。
      if (_disposed || pageEpoch != _pageEpoch || finalPrompt != whole) {
        return null;
      }
      _translation = result.text;
      _translationBy = mtLabel(result.engineId);
      return null;
    } on TranslateException catch (e) {
      return e.message;
    } finally {
      _translating = false;
      if (!_disposed) _changed();
    }
  }

  /// 翻译成稿里的一段,把译文写成它的中文对照那一行(原来有就换掉)。
  /// [section] 是这段现在的全文(带标注),[text] 是其中的提示词。
  /// 对照只给人看、不进交付的提示词,所以不用走待确认。失败时返回原因。
  Future<String?> translateSection(String section, String text) async {
    if (text.trim().isEmpty) return tr('这段是空的');
    if (_pending != null) return tr('先处理待确认的改动');
    if (_translating) return tr('正在翻译');
    final pageEpoch = _pageEpoch;
    _translating = true;
    _changed();
    try {
      final result = await translate(config.config, text);
      if (_disposed || pageEpoch != _pageEpoch) return null;
      // 等译文的这会儿成稿可能变了:按这段的原文重新找位置。
      final at = body.indexOf(section);
      final cut = at < 0 || _pending != null
          ? null
          : _isolate(at, at + section.length);
      if (cut == null) return tr('这段已经变了');
      final (blocks, i) = cut;
      final zh = result.text.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
      // 从后往前找:提示词和标注有相同的字时(【光影】光),不会找到标注上去。
      final head = section.substring(
        0,
        section.lastIndexOf(text) + text.length,
      );
      // 后面的文字都往后挪了,原来的选区对不上了。
      bodySelection = null;
      _blocks = _tidy([
        for (final (k, b) in blocks.indexed)
          k == i ? (text: '$head\n$zhMark$zh', pinned: false) : b,
      ]);
      return null;
    } on TranslateException catch (e) {
      return e.message;
    } finally {
      _translating = false;
      if (!_disposed) _changed();
    }
  }

  /// 润色时会处理的那段文字:有选区就是选区,否则是第一栏有内容的可编辑文字
  /// (没有固定区时就是全文)。
  (int, int) get polishRange {
    final length = body.length;
    final (start, end) = bodySelection ?? (0, 0);
    final s = start.clamp(0, length);
    final e = end.clamp(0, length);
    if (s < e) return (s, e);
    for (final p in parts) {
      if (!p.pinned && p.text.trim().isNotEmpty) {
        return (p.offset, p.offset + p.text.length);
      }
    }
    return (0, 0);
  }

  /// 用润色模型改写选中的一段(没选见 [polishRange]),结果作为待确认 diff。
  /// [instruction] 为空表示单纯润色。失败时返回给用户看的原因,成功返回 null。
  Future<String?> polish(String instruction) async {
    final text = body;
    if (text.trim().isEmpty) return tr('成稿为空');
    if (_pending != null) return tr('先处理待确认的改动');
    if (_polishing) return tr('正在润色');
    final cfg = config.config;
    final chain = _usable(cfg.polishChain);
    if (chain.isEmpty) return tr('请先在设置里添加模型并填写模型名称');

    final (start, end) = polishRange;
    final target = text.substring(start, end);
    if (target.trim().isEmpty) return tr('选中的内容为空');
    if (_isolate(start, end) == null) return tr('固定区不能改写');
    final ask = instruction.trim();
    final pageEpoch = _pageEpoch;
    _polishing = true;
    _changed();
    try {
      final raw = await streamWithFailover(
        _requests(cfg, chain, cfg.activePreset, [
          {'role': 'system', 'content': _polishSystemPrompt},
          {
            'role': 'user',
            'content':
                '【全文,仅供参考】\n$finalPrompt\n\n【要改写的部分】\n$target\n\n'
                '【要求】\n${ask.isEmpty ? '润色这部分:更具体、更有画面感,不改变原意。' : ask}',
          },
        ]),
        this.streamChat,
      ).join();
      final out = stripHanNotes(raw).trim();
      if (out.isEmpty) return tr('模型没有返回内容');
      if (_disposed || pageEpoch != _pageEpoch) return null;
      if (body != text) return tr('成稿在润色期间被改动了,请重试');
      if (_pending != null) return tr('先处理待确认的改动');
      // 等回复的这段时间里用户可能把目标固定了,所以这里再切一次、再查一次。
      final cut = _isolate(start, end);
      if (cut == null) return tr('固定区不能改写');
      // 原文首尾的空白不交给模型决定,原样保留。
      final lead = target.substring(
        0,
        target.length - target.trimLeft().length,
      );
      final tail = target.substring(target.trimRight().length);
      _blocks = List.unmodifiable(cut.$1);
      _pending = DiffProposal(
        title: ask.isEmpty ? tr('润色') : tr('修改:{0}', [ask]),
        segmentIndex: cut.$2,
        removed: target,
        added: '$lead$out$tail',
      );
      // 有待确认改动时编辑框会被换成只读视图,旧选区随之作废。
      bodySelection = null;
      _autoAccept();
      return null;
    } on LlmException catch (e) {
      return e.message;
    } finally {
      _polishing = false;
      if (!_disposed) _changed();
    }
  }
}

const _polishSystemPrompt =
    '你是文生图正面提示词的润色助手。只输出改写后的那部分文本本身:'
    '不要解释,不要加引号、标题或前后缀,不要输出全文。保持原文的语言。';
