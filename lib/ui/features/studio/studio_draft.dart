part of 'studio_view_model.dart';

/// 成稿本身:拼出交付的提示词、分栏、固定区、待确认的改动。
extension StudioDraft on StudioViewModel {
  /// 带分段标注和中文对照的成稿全文:存档、记历史用它,放回来时分段还在。
  String get labeledPrompt => _joined(labels: true);

  /// 眼前这处处理完了,轮到下一处。
  void _nextDiff() {
    _pending = _queued.firstOrNull;
    _queued = List.unmodifiable(_queued.skip(1));
  }

  /// 开着「自动审批」时,刚提出的改动(连同排着的)直接采纳。
  void _autoAccept() {
    if (!config.config.autoApprove) return;
    while (_pending != null) {
      acceptDiff();
    }
  }

  /// 清空工作区,好开始写下一条:成稿(连固定区)、待确认改动、中文对照都清掉。
  /// 清之前先记进历史提示词,点错了能从那里放回来。对话不动。
  void clearDraft() {
    recordPrompt();
    _log(tr('清空 {0}', [_here]));
    _blocks = const [];
    _pending = null;
    _queued = const [];
    _translation = null;
    _translationBy = null;
    _quote = null;
    bodySelection = null;
    _changed();
  }

  /// 各块原样相接(固定区也在内)。选区、落点这些字符位置都按它来数。
  String get body => _blocks.map((b) => b.text).join();

  /// 交付的提示词:固定区和旁边的文字之间没有空白时补一个空格,
  /// 行首的分段标注(【主体】这类)只给人看,不带出去。
  String get finalPrompt => _joined(labels: false);

  /// 把一页的块拼起来;[blocks] 不给是眼前这页。
  String _joined({required bool labels, List<Block>? blocks}) {
    final all = blocks ?? _blocks;
    var out = '';
    for (final (i, b) in all.indexed) {
      // 采纳过改动后,一块可能从一行中间开始;固定区自成一栏,它后面算新的一行。
      final atLineStart =
          out.isEmpty || out.endsWith('\n') || all[i - 1].pinned;
      final text = labels
          ? b.text
          : stripSectionLabels(b.text, atLineStart: atLineStart || b.pinned);
      final besidePin = i > 0 && (b.pinned || all[i - 1].pinned);
      // 固定的是一整段时它自成一行,标注才还在行首;普通固定区只补空格。
      final ownLine = i > 0 && (_isSection(b) || _isSection(all[i - 1]));
      out +=
          (ownLine
              ? _lineGap(out, text)
              : besidePin
              ? _gap(out, text)
              : '') +
          text;
    }
    return out;
  }

  /// 成稿按界面上的栏来分:相邻的可编辑块并成一栏,固定区各占一栏。
  List<Part> get parts {
    final out = <Part>[];
    var offset = 0;
    for (final (i, b) in _blocks.indexed) {
      if (!b.pinned && out.isNotEmpty && !out.last.pinned) {
        final last = out.removeLast();
        out.add((
          index: last.index,
          offset: last.offset,
          text: last.text + b.text,
          pinned: false,
        ));
      } else {
        out.add((index: i, offset: offset, text: b.text, pinned: b.pinned));
      }
      offset += b.text.length;
    }
    // 全是固定区时留一个空的输入栏,不然没地方打字。
    if (out.every((p) => p.pinned)) {
      out.add((index: _blocks.length, offset: offset, text: '', pinned: false));
    }
    return out;
  }

  /// 用户手动编辑从第 [index] 块开始的那一栏文字。
  void setText(int index, String text) {
    if (_pending != null) return;
    var end = index;
    while (end < _blocks.length && !_blocks[end].pinned) {
      end++;
    }
    if (_blocks.sublist(index, end).map((b) => b.text).join() == text) return;
    _blocks = List.unmodifiable([
      ..._blocks.take(index),
      // 旁边有固定区时空栏也留着,免得正在打字的输入栏突然消失。
      if (text.isNotEmpty || _blocks.any((b) => b.pinned))
        (text: text, pinned: false),
      ..._blocks.skip(end),
    ]);
    _changed();
  }

  /// 把 body 的 [start, end) 单独切成一块,返回新列表和那块的下标。
  /// 范围碰到固定区时返回 null。
  (List<Block>, int)? _isolate(int start, int end) {
    final (head, i) = _cut(_blocks, start);
    final (all, j) = _cut(head, end);
    final inside = all.sublist(i, j);
    final text = inside.map((b) => b.text).join();
    if (inside.any((b) => b.pinned) || text.length != end - start) return null;
    return ([...all.take(i), (text: text, pinned: false), ...all.skip(j)], i);
  }

  void _restructure(Iterable<Block> blocks) {
    _blocks = _tidy(blocks);
    bodySelection = null;
    _changed();
  }

  /// 把从第 [index] 块开始的那一栏里的第 [from] 段挪到第 [to] 段的位置上。
  void moveSection(int index, int from, int to) {
    if (_pending != null || from == to) return;
    final part = parts.where((p) => p.index == index && !p.pinned).firstOrNull;
    if (part == null) return;
    final text = part.text;
    final spans = sectionSpans(text);
    if (from < 0 || to < 0 || from >= spans.length || to >= spans.length) {
      return;
    }
    final sections = [for (final s in spans) text.substring(s.start, s.end)];
    final moved = sections.removeAt(from);
    sections.insert(to, moved);
    _log(tr('拖动「{0}」({1})', [sectionTitle(moved), _here]));
    // 第一段前面、最后一段后面的空白(比如挨着固定区的那个换行)原样留着。
    setText(
      index,
      text.substring(0, spans.first.start) +
          sections.join('\n') +
          text.substring(spans.last.end),
    );
  }

  /// 让一段脱离分段:从第 [index] 块开始的那一栏里的第 [span] 段去掉标注和中文对照,
  /// 留在原处变成普通文字(行首换成 [freeMark]),不并进别的段。
  void detachSection(int index, int span) {
    if (_pending != null) return;
    final part = parts.where((p) => p.index == index && !p.pinned).firstOrNull;
    if (part == null) return;
    final text = part.text;
    final spans = sectionSpans(text);
    if (span < 0 || span >= spans.length) return;
    final s = spans[span];
    if (s.label.isEmpty) return;
    _log(tr('「{0}」脱离分段({1})', [s.label, _here]));
    bodySelection = null;
    setText(
      index,
      text.replaceRange(
        s.start,
        s.end,
        // 这一栏最开头的文字本来就不算哪一段,不用记号。
        '${s.start == 0 ? '' : freeMark}'
        '${text.substring(s.textStart, s.textEnd)}',
      ),
    );
  }

  /// 把选中的文字从它那一段里拿出来,紧跟在那段后面变成普通文字。
  /// 没有选区、或选的不是某一段里的提示词时返回 false。
  bool detachSelection() {
    final sel = bodySelection;
    if (_pending != null || sel == null) return false;
    for (final p in parts.where((p) => !p.pinned)) {
      final a = sel.$1 - p.offset;
      final b = sel.$2 - p.offset;
      for (final (i, s) in sectionSpans(p.text).indexed) {
        if (s.label.isEmpty || a < s.textStart || b > s.textEnd) continue;
        final picked = p.text.substring(a, b).trim();
        if (picked.isEmpty) return false;
        final rest =
            '${p.text.substring(s.textStart, a).trimRight()} '
                    '${p.text.substring(b, s.textEnd).trimLeft()}'
                .trim();
        // 整段都选上了:就是这一段脱离。
        if (rest.isEmpty) {
          detachSection(p.index, i);
          return true;
        }
        _log(tr('「{0}」里选中的文字脱离分段({1})', [s.label, _here]));
        bodySelection = null;
        setText(
          p.index,
          p.text.replaceRange(
            s.textStart,
            s.end,
            '$rest${p.text.substring(s.textEnd, s.end)}\n$freeMark$picked',
          ),
        );
        return true;
      }
    }
    return false;
  }

  /// 当前页能改的各段(固定的不算):标注和提示词。同名的只算第一个。
  List<({String label, String text})> get sectionsHere {
    final seen = <String>{};
    return [
      for (final p in parts.where((p) => !p.pinned))
        for (final s in sectionSpans(p.text))
          if (s.label.isNotEmpty && seen.add(s.label))
            (label: s.label, text: p.text.substring(s.textStart, s.textEnd)),
    ];
  }

  /// 这一页(连固定的段)已经有叫 [label] 的段了。
  /// 同名的段会让按标注并入的改动只认第一个,所以起名时不让重名。
  bool sectionNameTaken(String label) {
    final name = sectionLabel(label);
    return parts.any((p) => sectionSpans(p.text).any((s) => s.label == name));
  }

  /// 把从第 [index] 块开始的那一栏里第 [span] 段的标注改成 [label]。
  /// 名字是空的、和别的段重名、或这段已经不在了时返回 false。
  bool renameSection(int index, int span, String label) {
    final name = sectionLabel(label);
    if (_pending != null || name.isEmpty) return false;
    final part = parts.where((p) => p.index == index && !p.pinned).firstOrNull;
    if (part == null) return false;
    final spans = sectionSpans(part.text);
    if (span < 0 || span >= spans.length) return false;
    final s = spans[span];
    if (s.label.isEmpty) return false;
    if (s.label == name) return true;
    if (sectionNameTaken(name)) return false;
    _log(tr('「{0}」改名为「{1}」({2})', [s.label, name, _here]));
    setText(index, part.text.replaceRange(s.start, s.textStart, '【$name】'));
    return true;
  }

  /// 把选中的普通文字(不在任何分段里的)建成一段,标注是 [label]。
  /// 选区前后剩下的文字留在原处,仍是普通文字。做不了时返回 false。
  bool sectionSelection(String label) {
    final sel = bodySelection;
    final name = sectionLabel(label);
    if (_pending != null || sel == null || name.isEmpty) return false;
    if (sectionNameTaken(name)) return false;
    for (final p in parts.where((p) => !p.pinned)) {
      final a = sel.$1 - p.offset;
      final b = sel.$2 - p.offset;
      if (a < 0 || b > p.text.length) continue;
      final spans = sectionSpans(p.text);
      // 一个标注都没有的栏整栏都是普通文字。
      final free = spans.isEmpty
          ? (start: 0, textStart: 0, textEnd: p.text.length, end: p.text.length)
          : spans
                .where(
                  (s) => s.label.isEmpty && a >= s.textStart && b <= s.textEnd,
                )
                .map(
                  (s) => (
                    start: s.start,
                    textStart: s.textStart,
                    textEnd: s.textEnd,
                    end: s.end,
                  ),
                )
                .firstOrNull;
      if (free == null) continue;
      final picked = p.text.substring(a, b).trim();
      if (picked.isEmpty) return false;
      final before = p.text.substring(free.textStart, a).trim();
      final after = p.text.substring(b, free.textEnd).trim();
      _log(tr('选中的文字建成「{0}」({1})', [name, _here]));
      bodySelection = null;
      setText(
        p.index,
        p.text.replaceRange(
          free.start,
          free.end,
          [
            // 这一栏最开头的文字本来就不算哪一段,不用记号。
            if (before.isNotEmpty) '${free.start == 0 ? '' : freeMark}$before',
            '【$name】$picked',
            if (after.isNotEmpty) '$freeMark$after',
          ].join('\n'),
        ),
      );
      return true;
    }
    return false;
  }

  /// 去掉这一页的分段:标注和中文对照都拿掉,各段连成普通的文字(一段一行)。
  /// 拿掉之前先记进历史提示词,后悔了能从那里放回来。固定的段不动。
  /// 没有可去的分段时返回 false。
  bool unsection() {
    if (_pending != null) return false;
    final next = [
      for (final b in _blocks)
        b.pinned ? b : (text: stripSectionLabels(b.text), pinned: false),
    ];
    if (next.indexed.every((e) => e.$2.text == _blocks[e.$1].text)) {
      return false;
    }
    recordPrompt();
    _log(tr('取消分段({0})', [_here]));
    _restructure(next);
    return true;
  }

  /// 把选中的文字就地设为固定区。没有选区、或选区不能固定时返回 false。
  bool pinSelection() {
    final sel = bodySelection;
    if (_pending != null || sel == null) return false;
    final cut = _isolate(sel.$1, sel.$2);
    if (cut == null) return false;
    final (blocks, at) = cut;
    if (blocks[at].text.trim().isEmpty) return false;
    _log(tr('固定选中的文字({0})', [_here]));
    _restructure([
      for (final (i, b) in blocks.indexed)
        i == at ? (text: b.text, pinned: true) : b,
    ]);
    return true;
  }

  /// 把成稿里的一段就地固定:[start]、[end] 是这段(连标注和中文对照)在 [body] 里的范围,
  /// [text] 是其中的提示词。整段原样留着(标注、对照都在),只是从此改不到它;
  /// 交付时和别的段一样去掉标注和对照。
  /// 固定中间的段会把成稿隔成几栏,之后 Agent 的成稿要分几处确认(见 [proposeDraft])。
  // ponytail: Agent 的成稿里要是有和固定段同名的标注,会被当成新段接在最后;
  // 要拦的话在 mergeAcross 里把固定段的标注剔掉。
  bool pinSection(int start, int end, String text) {
    if (_pending != null || text.trim().isEmpty) return false;
    final pin = body.substring(start, end);
    // 和上一段之间的换行一起拿掉,免得上一段末尾多出一个空行。
    // 那个换行要是属于前面的固定区就拿不掉,只切这一段。
    final cut =
        (start > 0 && body[start - 1] == '\n'
            ? _isolate(start - 1, end)
            : null) ??
        _isolate(start, end);
    if (cut == null) return false;
    final (blocks, at) = cut;
    _log(tr('固定「{0}」({1})', [sectionTitle(pin), _here]));
    _restructure([
      for (final (i, b) in blocks.indexed)
        i == at ? (text: pin, pinned: true) : b,
    ]);
    return true;
  }

  /// 新增一个固定区,放在最前面;之后可以拖到别处。
  void addPin(String text) {
    final pin = text.trim();
    if (_pending != null || pin.isEmpty) return;
    _log(tr('新增固定区({0})', [_here]));
    _restructure([(text: pin, pinned: true), ..._blocks]);
  }

  /// 取消第 [index] 块的固定,文字留在原处。
  void unpin(int index) {
    if (_pending != null || !_blocks[index].pinned) return;
    final text = _blocks[index].text;
    // 邻居也是固定区时不用管:拼成稿时那边照样会补空格。
    String beside(int i) => i < 0 || i >= _blocks.length || _blocks[i].pinned
        ? ''
        : _blocks[i].text;
    final before = beside(index - 1);
    final after = beside(index + 1);
    // 固定区两边的空格(整段固定的是换行)是拼成稿时才补的,解除后要落进文字里,
    // 否则会和邻居粘在一起。
    final gap = _isSection(_blocks[index]) ? _lineGap : _gap;
    final freed = '${gap(before, text)}$text${gap(text, after)}';
    _log(tr('取消固定({0})', [_here]));
    _restructure([
      for (final (i, b) in _blocks.indexed)
        i == index ? (text: freed, pinned: false) : b,
    ]);
  }

  /// 把第 [index] 块固定区挪到 body 的第 [offset] 个字符处。
  void movePin(int index, int offset) {
    if (_pending != null || !_blocks[index].pinned) return;
    final pin = _blocks[index];
    final (cut, at) = _cut(_blocks, offset);
    // 切开一块文字后,它后面各块的下标都后移一位。
    final old = cut.length > _blocks.length && index >= at ? index + 1 : index;
    _log(tr('拖动固定区({0})', [_here]));
    _restructure([
      for (var i = 0; i <= cut.length; i++) ...[
        if (i == at) pin,
        if (i < cut.length && i != old) cut[i],
      ],
    ]);
  }

  void acceptDiff() {
    final p = _pending;
    if (p == null) return;
    final before = _snapshot();
    _blocks = List.unmodifiable([
      for (final (i, b) in _blocks.indexed)
        i == p.segmentIndex ? (text: p.added, pinned: false) : b,
    ]);
    _log(tr('采纳「{0}」({1})', [p.title, _here]), before: before);
    _nextDiff();
    _changed();
    recordPrompt();
  }

  /// 只采纳待确认改动里标注为 [label] 的那一段,其余的继续等确认。
  void acceptSection(String label) {
    final p = _pending;
    if (p == null) return;
    final before = _snapshot();
    final text = applySection(p.removed, p.added, label);
    _blocks = List.unmodifiable([
      for (final (i, b) in _blocks.indexed)
        i == p.segmentIndex ? (text: text, pinned: false) : b,
    ]);
    _pending = _remaining(p, removed: text, added: p.added);
    _log(tr('采纳「{0}」这一段({1})', [label, _here]), before: before);
    if (_pending == null) _nextDiff();
    _changed();
    recordPrompt();
  }

  /// 只驳回待确认改动里标注为 [label] 的那一段,其余的继续等确认。
  void rejectSection(String label) {
    final p = _pending;
    if (p == null) return;
    final before = _snapshot();
    _pending = _remaining(
      p,
      removed: p.removed,
      added: applySection(p.added, p.removed, label),
    );
    _log(tr('驳回「{0}」这一段({1})', [label, _here]), before: before);
    if (_pending == null) _nextDiff();
    _changed();
  }

  void rejectDiff() {
    if (_pending == null) return;
    _log(tr('驳回「{0}」({1})', [_pending!.title, _here]));
    _nextDiff();
    _changed();
  }

  /// 把 Agent 另出的那份新成稿变成待确认 diff(不直接改成稿)。
  /// 固定区留在原位,换掉的是那一栏可编辑文字。不能放时返回给用户看的原因。
  // ponytail: 成稿被固定区隔成几栏时,每栏的改动排着队一处一处确认([_queued]),
  // 不是同时摆出来;嫌麻烦的话得让界面能同时显示多处待确认改动。
  ///
  /// [replacing] 非空时只换成稿里的那一段(用户选来讨论的那段),其余不动。
  /// 否则按分段标注并进现有成稿(见 [mergeSections]);[merge] 为 false 时整栏换掉。
  String? proposeDraft(
    String text, {
    String? replacing,
    bool merge = true,
    String? title,
  }) {
    title ??= tr('Agent 新成稿');
    if (_pending != null) return tr('先处理待确认的改动');
    if (text.trim().isEmpty) return tr('新成稿是空的');
    if (replacing != null) {
      final at = body.indexOf(replacing);
      final cut = at < 0 ? null : _isolate(at, at + replacing.length);
      if (cut == null) return tr('选中的那段已经变了');
      _blocks = List.unmodifiable(cut.$1);
      _pending = DiffProposal(
        title: tr('Agent 改「{0}」', [sectionTitle(replacing)]),
        segmentIndex: cut.$2,
        removed: replacing,
        added: text,
      );
      bodySelection = null;
      _changed();
      _autoAccept();
      return null;
    }
    // 一栏并成一块,这样一处改动正好指向一栏(固定区各是一块,留在原位)。
    final columns = parts;
    final editable = [
      for (final p in columns)
        if (!p.pinned) p.text,
    ];
    final next = merge
        ? mergeAcross(editable, text)
        : [text, for (var i = 1; i < editable.length; i++) ''];
    var k = 0;
    final diffs = [
      for (final (i, p) in columns.indexed)
        if (!p.pinned)
          DiffProposal(
            title: title,
            segmentIndex: i,
            removed: p.text,
            added: next[k++],
          ),
    ].where((d) => d.removed != d.added).toList();
    if (diffs.isEmpty) return tr('成稿已经是这样了');
    _blocks = List.unmodifiable([
      for (final p in columns) (text: p.text, pinned: p.pinned),
    ]);
    // 成稿被固定区隔成几栏时每栏一处改动,一处一处给用户确认。
    _pending = diffs.first;
    _queued = List.unmodifiable(diffs.skip(1));
    bodySelection = null;
    _changed();
    _autoAccept();
    return null;
  }
}

/// 这块是被整段固定下来的(带着分段标注)。
bool _isSection(Block b) => b.pinned && b.text.startsWith('【');

/// [a]、[b] 相接处还没有换行时返回一个换行。
String _lineGap(String a, String b) =>
    a.isEmpty || b.isEmpty || a.endsWith('\n') || b.startsWith('\n')
    ? ''
    : '\n';

/// [a]、[b] 相接处两边都不是空白时返回一个空格,否则返回空串。
String _gap(String a, String b) =>
    a.isEmpty ||
        b.isEmpty ||
        a[a.length - 1].trim().isEmpty ||
        b[0].trim().isEmpty
    ? ''
    : ' ';

/// 在 body 的第 [offset] 个字符处切开,返回新的块列表和切口后面那块的下标。
/// 切口落在固定区里面时不切,算在它前面。
(List<Block>, int) _cut(List<Block> blocks, int offset) {
  var pos = 0;
  for (final (i, b) in blocks.indexed) {
    final end = pos + b.text.length;
    if (offset <= pos || b.pinned && offset < end) return (blocks, i);
    if (offset < end) {
      final at = offset - pos;
      return (
        [
          ...blocks.take(i),
          (text: b.text.substring(0, at), pinned: false),
          (text: b.text.substring(at), pinned: false),
          ...blocks.skip(i + 1),
        ],
        i + 1,
      );
    }
    pos = end;
  }
  return (blocks, blocks.length);
}

/// 去掉空块,把相邻的可编辑块并成一块。
List<Block> _tidy(Iterable<Block> blocks) {
  final out = <Block>[];
  for (final b in blocks) {
    if (b.text.isEmpty) continue;
    if (!b.pinned && out.isNotEmpty && !out.last.pinned) {
      out.add((text: out.removeLast().text + b.text, pinned: false));
    } else {
      out.add(b);
    }
  }
  return List.unmodifiable(out);
}

/// 逐段处理之后还剩下的改动;前后已经一样了就是没有了。
DiffProposal? _remaining(
  DiffProposal p, {
  required String removed,
  required String added,
}) => removed == added
    ? null
    : DiffProposal(
        title: p.title,
        segmentIndex: p.segmentIndex,
        removed: removed,
        added: added,
      );
