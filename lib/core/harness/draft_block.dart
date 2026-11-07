import 'dart:convert';

/// 新成稿里的一段:[label] 是这段写的是什么(没标就是空串),
/// [zh] 是这段的中文对照(没有就是空串)。
typedef DraftSection = ({String label, String text, String zh});

/// Agent 回复里另出的那份新成稿,供用户放到左侧。
class AgentDraft {
  const AgentDraft({
    required this.sections,
    required this.complete,
    this.page,
    this.name,
    this.series,
    this.replace = false,
  });

  final List<DraftSection> sections;

  /// `<draft replace>`:整篇重写,放进去时整篇换掉,没写到的旧段都删掉(不按标注并进去)。
  final bool replace;

  /// 这份成稿要去哪一页:null 是当前页,数字是系列里的第几页,别的(如「新」)是新开一页。
  final String? page;

  /// 模型给这一页、给这个系列起的名字;没起就是 null。
  final String? name;
  final String? series;

  /// 结束标签已经到了;为 false 表示还在生成,或被停在半路。
  final bool complete;

  /// 放进成稿的文字:每段一行,行首带【标注】;有中文对照的在下一行,行首是〔译〕。
  String get text => sections
      .map(
        (s) =>
            '${s.label.isEmpty ? '' : '【${s.label}】'}${s.text}'
            '${s.zh.isEmpty ? '' : '\n$zhMark${s.zh}'}',
      )
      .join('\n');
}

/// 成稿里一段的中文对照那一行的开头。
const zhMark = '〔译〕';

/// 成稿里的中文对照行,连同它前面的换行。
final _zhInBody = RegExp('(?:^|\n)$zhMark[^\n]*');

/// 模型写的中文对照行;繁体、日文的〔譯〕〔訳〕和「译:」这种写法也认。
final _zhLine = RegExp(r'^(?:〔[译譯訳]〕|[译譯訳][::])[ \t]*');

/// 写在提示词同一行里的〔译〕(模型常这样):拆成单独一行。
final _zhInline = RegExp(r'[ \t]*(?=〔[译譯訳]〕)');

/// 成稿的开始标签,可以带页码和名字:
/// `<draft>`、`<draft page="3">`、`<draft page="新" name="远景" series="午后客厅">`。
final _open = RegExp(r'<draft((?:\s+(?:[a-z]+\s*=\s*"[^"\n]*"|replace))*)\s*>');
final _attr = RegExp(r'([a-z]+)\s*=\s*"([^"\n]*)"');
const _close = '</draft>';

/// 流式生成时开始标签可能只到了一半(`<dra`、`<draft page="`),先不显示出来。
final _halfOpen = RegExp(r'<(?:d(?:r(?:a(?:f(?:t[^>\n]*)?)?)?)?)?$');

/// 行首的分段标注,例如「【主体】」。里面没有字的是 [freeMark]。
final _label = RegExp(r'^【([^】\n]{0,12})】[ \t]*', multiLine: true);

/// 脱离了分段的文字那一行的开头:它自己占一处,但不画成分段框,也没有标注。
const freeMark = '【】';

/// 回复正文里照成稿格式写的行(行首【标注】后面跟着提示词,或〔译〕行)去掉。
/// 模型有时把成稿在正文里再抄一遍,回复里已经有成稿卡片时这些行是重复的。
/// 「【主体】这段改了」这种在说话的行也会去掉,所以只在有成稿卡片时用。
String dropDraftLines(String prose) => prose
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !_zhLine.hasMatch(t) &&
          !RegExp(r'^【[^】\n]{1,12}】\s*\S').hasMatch(t);
    })
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// 用户起的标注整理成 [_label] 认得的样子:去掉【】和换行,最多 12 个字。
String sectionLabel(String name) {
  final clean = name.replaceAll(RegExp(r'[【】\r\n]'), '').trim();
  return clean.length > 12 ? clean.substring(0, 12).trim() : clean;
}

/// 去掉每行开头的分段标注和中文对照行:它们只给人看,不进交付的提示词。
/// [atLineStart] 为 false 表示 [text] 是从一行中间开始的,开头那个【】不算标注。
String stripSectionLabels(String text, {bool atLineStart = true}) => text
    .replaceAll(_zhInBody, '')
    .replaceAllMapped(_label, (m) => m.start == 0 && !atLineStart ? m[0]! : '');

/// 成稿一栏文字里的一段:[start] 是标注的开头,[textStart] 是标注后面正文的开头,
/// [textEnd] 是提示词正文的末尾,[end] 是这段的末尾(含中文对照,不含和下一段之间的换行)。
/// [zh] 是中文对照,没有就是空串。
typedef SectionSpan = ({
  String label,
  int start,
  int textStart,
  int textEnd,
  int end,
  String zh,
});

/// 英文后面括号里只有中日文的注释:`Si (小葱)`。
final _hanNote = RegExp(
  r'(?<=[A-Za-z0-9.])\s*[(（]\s*[぀-ヿ一-鿿]'
  r'[぀-ヿ一-鿿·・、,，\s]*[)）]',
);

/// 去掉英文提示词里 `Si (小葱)` 这样的中文注释(用户反馈:模型把角色的中文名夹进了提示词,
/// 只靠系统提示管不住)。引号里的是要画出来的字,不动;〔译〕行和整行都是中文的不动。
// ponytail: 只管括号里的。不带括号直接写「小葱 stands」的认不出来,靠 Skill 里的要求。
String stripHanNotes(String text) => text
    .split('\n')
    .map((line) {
      if (line.startsWith(zhMark) || _isHan(line)) return line;
      return line.replaceAllMapped(_hanNote, (m) {
        final quotes = RegExp('["“”]').allMatches(line.substring(0, m.start));
        return quotes.length.isOdd ? m[0]! : '';
      });
    })
    .join('\n');

/// 布局 JSON 的描述和角色卡做同样的清理;name(给人看的)和 text(要画出来的字)不动。
String _cleanLayoutJson(String json) {
  final Object? read;
  try {
    read = jsonDecode(json);
  } on FormatException {
    return json;
  }
  if (read is! Map) return json;
  Object? clean(Object? v) => v is String ? stripHanNotes(v) : v;
  Map<dynamic, dynamic> caption(Map<dynamic, dynamic> m) => {
    ...m,
    if (m.containsKey('caption')) 'caption': clean(m['caption']),
  };
  final summary = read['summary'];
  final items = read['items'];
  final next = jsonEncode({
    ...read,
    if (summary is Map)
      'summary': {
        ...caption(summary),
        if (summary['cast'] is Map)
          'cast': (summary['cast'] as Map).map((k, v) => MapEntry(k, clean(v))),
      },
    if (items is List)
      'items': [for (final i in items) i is Map ? caption(i) : i],
  });
  // 没东西可清时原样留着,不把模型排好的版式改掉。
  return next == jsonEncode(read) ? json : next;
}

final _draftBlock = RegExp(r'(<draft\b[^>]*>)([\s\S]*?)(</draft>)');
final _layoutBlock = RegExp(r'(<layout\b[^>]*>)([\s\S]*?)(</layout>)');

/// 回复说完后,清理里面每一份 `<draft>` 和 `<layout>`。写 Skill 的回复不动:
/// 它正文里的例子不是成稿。
String cleanReplyPrompts(String reply) {
  if (reply.contains('<new-skill')) return reply;
  return reply
      .replaceAllMapped(
        _draftBlock,
        (m) => '${m[1]}${stripHanNotes(m[2]!)}${m[3]}',
      )
      .replaceAllMapped(
        _layoutBlock,
        (m) => '${m[1]}\n${_cleanLayoutJson(m[2]!.trim())}\n${m[3]}',
      );
}

/// 这份成稿并进 [current] 后,旧的段一段都不会留下:同标注的全写了,或两边一个标注都对不上。
bool rewritesAllSections(String current, String draft) {
  final old = {
    for (final s in sectionSpans(current))
      if (s.label.isNotEmpty) s.label,
  };
  final fresh = {for (final s in sectionSpans(draft)) s.label};
  return old.isEmpty ||
      fresh.containsAll(old) ||
      old.intersection(fresh).isEmpty;
}

final _wordOrHan = RegExp(r'[a-z]{5,}|[一-鿿]{2,}');
final _han = RegExp(r'[一-鿿]');

/// 一段提示词的词:英文取 5 个字母以上的(with、hair 这种到处都有),中文两个字两个字地取。
Set<String> _promptWords(String text) => {
  for (final m in _wordOrHan.allMatches(text.toLowerCase()))
    if (_han.hasMatch(m[0]!))
      for (var i = 0; i + 2 <= m[0]!.length; i++) m[0]!.substring(i, i + 2)
    else
      m[0]!,
};

bool _isTags(String text) {
  final parts = text.split(',');
  return parts.length >= 4 &&
      text.trim().split(RegExp(r'\s+')).length / parts.length <= 3.5;
}

bool _isHan(String text) =>
    _han.allMatches(text).length * 3 >
    text.replaceAll(RegExp(r'\s'), '').length;

/// 整篇重写的 [next] 是不是和 [current] 已经不是一张画:写法相同(都是标签或都是句子、
/// 语言相同),用词却几乎不重合。转标签、翻译虽然也整篇变,但写法变了,不算。
/// [newImage] 是用户这次发了图:这时门槛放宽,用词一半以上还在才算同一张画
/// (照图改发色、服装时大部分词不变;照新图复刻时词大多换了,角色、风格的词还会留一些)。
// ponytail: 按用词估的。同一张画换一套说法、或两张画碰巧用词相近时会认错;
// 认错的后果只是多开一页,或者照旧提出待确认改动,都不丢东西。
bool looksLikeAnotherPicture(
  String current,
  String next, {
  bool newImage = false,
}) {
  final a = stripSectionLabels(current), b = stripSectionLabels(next);
  if (_isTags(a) != _isTags(b) || _isHan(a) != _isHan(b)) return false;
  final x = _promptWords(a), y = _promptWords(b);
  if (x.length < _minPromptWords || y.length < _minPromptWords) return false;
  final smaller = x.length < y.length ? x.length : y.length;
  return x.intersection(y).length / smaller <
      (newImage ? _samePictureWithImage : _samePictureOverlap);
}

const _minPromptWords = 8;
const _samePictureOverlap = 0.25;
const _samePictureWithImage = 0.5;

/// 按行首的标注把一栏文字切成几段;一个标注都没有时返回空列表。
/// 第一个标注前面的文字自成一段(标注为空串)。
List<SectionSpan> sectionSpans(String text) {
  final marks = _label.allMatches(text).toList();
  if (marks.isEmpty) return const [];
  SectionSpan span(String label, int start, int textStart, int end) {
    final at = text.substring(textStart, end).indexOf('\n$zhMark');
    final textEnd = at < 0 ? end : textStart + at;
    return (
      label: label,
      start: start,
      textStart: textStart,
      textEnd: textEnd,
      end: end,
      zh: at < 0 ? '' : text.substring(textEnd + 1 + zhMark.length, end),
    );
  }

  final first = marks.first.start;
  return [
    if (first > 0 && text.substring(0, first).trim().isNotEmpty)
      span('', 0, 0, first - 1),
    for (final (i, m) in marks.indexed)
      span(
        m[1]!.trim(),
        m.start,
        m.end,
        i + 1 < marks.length ? marks[i + 1].start - 1 : text.length,
      ),
  ];
}

/// 把 Agent 给的 [draft] 并进成稿的一栏文字 [current],按标注对号入座:
/// 标注相同的段换成新的,没见过的标注接在最后,只写了标注、后面留空的段删掉,
/// [draft] 里没提到的段原样保留。两边没有一个标注对得上时算整篇重写,直接用 [draft]。
String mergeSections(String current, String draft) {
  final old = sectionSpans(current);
  final fresh = sectionSpans(draft);
  final known = {
    for (final s in old)
      if (s.label.isNotEmpty) s.label,
  };
  if (!fresh.any((s) => known.contains(s.label))) return draft;
  final out = [
    for (final s in old)
      (label: s.label, text: current.substring(s.start, s.end)),
  ];
  for (final s in fresh) {
    final empty = draft.substring(s.textStart, s.end).trim().isEmpty;
    final at = s.label.isEmpty ? -1 : out.indexWhere((o) => o.label == s.label);
    final piece = (label: s.label, text: draft.substring(s.start, s.end));
    if (at < 0) {
      if (!empty) out.add(piece);
    } else if (empty) {
      out.removeAt(at);
    } else {
      out[at] = piece;
    }
  }
  return out.map((o) => o.text).join('\n');
}

/// 成稿被固定区隔成几栏时用的 [mergeSections]:[draft] 里的每一段去它标注所在的那一栏,
/// 哪一栏都没有的新标注接在最后一栏后面。返回每一栏并好之后的文字,没被提到的栏原样返回。
/// 和 [mergeSections] 一样,一个标注都对不上时算整篇重写:第一栏换成 [draft],其余清空。
List<String> mergeAcross(List<String> columns, String draft) {
  final labels = [
    for (final c in columns)
      {
        for (final s in sectionSpans(c))
          if (s.label.isNotEmpty) s.label,
      },
  ];
  // 每一栏分到的那几段;-1 是哪一栏都没有的新标注。
  final mine = <int, List<String>>{};
  for (final s in sectionSpans(draft)) {
    final owner = labels.indexWhere((l) => l.contains(s.label));
    // 只写了标注、后面留空是"删掉这段",找不到主人的就没有可删的。
    if (owner < 0 && draft.substring(s.textStart, s.end).trim().isEmpty) {
      continue;
    }
    mine.putIfAbsent(owner, () => []).add(draft.substring(s.start, s.end));
  }
  if (!mine.keys.any((k) => k >= 0)) {
    return [draft, for (var i = 1; i < columns.length; i++) ''];
  }
  final extra = mine[-1]?.join('\n');
  return [
    for (final (i, c) in columns.indexed)
      switch ((mine[i], i == columns.length - 1 ? extra : null)) {
        (null, null) => c,
        // 这一栏没有要换的段,只是来了新的:接在后面。
        (null, final added?) => c.trim().isEmpty ? added : '$c\n$added',
        // 固定区后面那一栏是以换行开头的,并完要留着:
        // 不然这栏第一段的标注就不在行首了,换行也丢了。
        (final own?, final added) =>
          c.substring(0, c.length - c.trimLeft().length) +
              mergeSections(c, [...own, ?added].join('\n')),
      },
  ];
}

/// 让 [base] 里标注为 [label] 的那一段变得和 [target] 里的一样,别的段不动:
/// 两边都有就换成 [target] 的;只有 [target] 有就加进来,位置跟着 [target] 里的先后;
/// 只有 [base] 有就删掉。逐段采纳、逐段驳回都靠它。
String applySection(String base, String target, String label) {
  final theirs = sectionSpans(target);
  final pieces = [
    for (final s in sectionSpans(base))
      (label: s.label, text: base.substring(s.start, s.end)),
  ];
  final mine = pieces.indexWhere((p) => p.label == label);
  final at = theirs.indexWhere((s) => s.label == label);
  if (at < 0) {
    if (mine >= 0) pieces.removeAt(mine);
  } else {
    final piece = (
      label: label,
      text: target.substring(theirs[at].start, theirs[at].end),
    );
    if (mine >= 0) {
      pieces[mine] = piece;
    } else {
      // 插在 [target] 里排它前面、这边也有的最近那一段后面;找不到就放最前。
      var slot = 0;
      for (var k = at - 1; k >= 0 && slot == 0; k--) {
        slot = pieces.indexWhere((p) => p.label == theirs[k].label) + 1;
      }
      pieces.insert(slot, piece);
    }
  }
  return pieces.map((p) => p.text).join('\n');
}

/// [text] 的每一行(空行不算)是不是都已经在 [body] 里了。
bool containsLines(String body, String text) {
  final have = body.split('\n').toSet();
  return text.split('\n').every((l) => l.trim().isEmpty || have.contains(l));
}

/// 一段的短名,显示在引用标签上:有标注用标注,没有就截开头一小截。
String sectionTitle(String section) {
  final m = _label.matchAsPrefix(section);
  final label = m?[1]?.trim() ?? '';
  if (label.isNotEmpty) return label;
  final text = m == null ? section : section.substring(m.end);
  return text.length > 12 ? '${text.substring(0, 12)}…' : text;
}

/// 流式生成时 [tag] 可能只到了一半(比如 `<dra`),先不显示出来。
String _withoutPartial(String text, String tag) {
  for (var n = tag.length - 1; n > 0; n--) {
    if (text.endsWith(tag.substring(0, n))) {
      return text.substring(0, text.length - n);
    }
  }
  return text;
}

const _skillOpen = '<new-skill>';
const _skillClose = '</new-skill>';

/// 把回复里新写的 Skill(整篇 SKILL.md)拆出来;没有时 skill 为 null。
/// [complete] 为 false 表示结束标签还没到(还在生成,或被停在半路)。
/// 拆剩下的 [prose] 再交给 [splitDraft]:Skill 正文里举例用的 `<draft>` 不能被当成成稿。
({String prose, String? skill, bool complete}) splitNewSkill(String reply) {
  final end = reply.lastIndexOf(_skillClose);
  // 开始标签要独占一行的开头,而且取结束标签前最近的那个:
  // 模型在前面的话里提到这个标签时,不会被当成 Skill 的开头。
  // 前面垫一个换行后,找到的换行位置正好就是标签在 [reply] 里的位置。
  final start = '\n$reply'.lastIndexOf(
    '\n$_skillOpen',
    end < 0 ? reply.length : end,
  );
  if (start < 0) {
    return (
      prose: _withoutPartial(reply, _skillOpen),
      skill: null,
      complete: false,
    );
  }
  final from = start + _skillOpen.length;
  final closed = end >= from;
  var inner =
      (closed
              ? reply.substring(from, end)
              : _withoutPartial(reply.substring(from), _skillClose))
          .trim();
  // 有的模型会把整篇再套一层代码块。
  if (inner.startsWith('```')) {
    final firstBreak = inner.indexOf('\n');
    inner = firstBreak < 0 ? '' : inner.substring(firstBreak + 1);
    if (inner.trimRight().endsWith('```')) {
      inner = inner.trimRight();
      inner = inner.substring(0, inner.length - 3);
    }
    inner = inner.trim();
  }
  return (
    prose: [
      reply.substring(0, start).trim(),
      if (closed) reply.substring(end + _skillClose.length).trim(),
    ].where((s) => s.isNotEmpty).join('\n\n'),
    skill: inner,
    complete: closed,
  );
}

/// 把一条回复拆成给人看的话和其中的新成稿;没有成稿时 draft 为 null。
/// 回复里有好几份时取最后一份,要全部的用 [splitDrafts]。
({String prose, AgentDraft? draft}) splitDraft(String reply) {
  final (:prose, :drafts) = splitDrafts(reply);
  return (prose: prose, draft: drafts.lastOrNull);
}

/// 把一条回复拆成给人看的话和其中的每一份新成稿(一份去一页)。
/// 只有最后一份可能是不完整的(还在生成,或被停在半路)。
({String prose, List<AgentDraft> drafts}) splitDrafts(String reply) {
  final prose = <String>[];
  final drafts = <AgentDraft>[];
  var pos = 0;
  while (true) {
    final end = reply.indexOf(_close, pos);
    final rest = reply.substring(pos, end < 0 ? reply.length : end);
    // 取离结束标签最近的那个开头:模型在前面的话里提到这个标签时,不会被当成成稿的开头。
    final open = _open.allMatches(rest).lastOrNull;
    if (open == null) {
      prose.add(end < 0 ? rest.replaceFirst(_halfOpen, '') : rest);
      if (end < 0) break;
      pos = end + _close.length;
      continue;
    }
    prose.add(rest.substring(0, open.start));
    final inner = rest.substring(open.end);
    final sections = _draftSections(
      end < 0 ? _withoutPartial(inner, _close) : inner,
    );
    if (sections.isNotEmpty || end < 0) {
      final attrs = {
        for (final a in _attr.allMatches(open[1] ?? '')) a[1]!: a[2]!.trim(),
      };
      drafts.add(
        AgentDraft(
          sections: sections,
          complete: end >= 0,
          page: attrs['page'],
          name: attrs['name'],
          series: attrs['series'],
          replace: (open[1] ?? '')
              .replaceAll(_attr, '')
              .trim()
              .split(RegExp(r'\s+'))
              .contains('replace'),
        ),
      );
    }
    if (end < 0) break;
    pos = end + _close.length;
  }
  return (
    prose: prose.map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n\n'),
    drafts: List.unmodifiable(drafts),
  );
}

/// 选项的开始标签:`<options>` 是挑一个,`<options multi>` 是可以勾好几个,
/// `<options sections>` 是从成稿的各段里勾:界面自己读出当前页的各段,标签里可以不写。
final _optionsOpen = RegExp(r'<options(?:\s+(multi|sections|form))?\s*>');
const _optionsHalves = [
  '<options multi>',
  '<options sections>',
  '<options form>',
];
const _optionsClose = '</options>';

/// 一张问卷最多几个选项(6 组 × 4 个,多出来的不显示)。
const _maxFormOptions = 24;

/// 模型有时会顺手加上列表符号或序号。
final _optionMark = RegExp(r'^(?:[-*•]|\d+[.、)])\s*');

/// 选项里的分类小标题:`# 风格`。
final _optionHeading = RegExp(r'^#+\s*(.+)$');

/// 回复里给用户点的选项。[sections] 为真时是挑成稿里的哪几段(也算多选)。
/// [headings] 是分类小标题:排在第几个选项前面 → 标题(多选和问卷才画)。
/// [form] 为真时是一张问卷(`<options form>`):每个小标题下面单选一个,一次交。
typedef AskedOptions = ({
  String prose,
  List<String> options,
  Map<int, String> headings,
  bool multi,
  bool sections,
  bool form,
});

/// 把回复里给用户点的选项拆出来:一行一个,显示成按钮,点了就当成用户的回答发出去。
/// [multi] 为真时是多选:勾上几个(或全选)再一起发。
/// 没写完(还在生成、被停在半路)的不算,免得按钮一个个蹦出来又变。
AskedOptions splitOptions(String reply) {
  final open = _optionsOpen.allMatches(reply).lastOrNull;
  if (open == null) {
    return (
      prose: _optionsHalves.fold(reply, _withoutPartial),
      options: const [],
      headings: const {},
      multi: false,
      sections: false,
      form: false,
    );
  }
  final start = open.start;
  final from = open.end;
  final form = open[1] == 'form';
  final multi = open[1] != null && !form;
  final sections = open[1] == 'sections';
  final end = reply.indexOf(_optionsClose, from);
  final prose = [
    reply.substring(0, start).trim(),
    if (end >= 0) reply.substring(end + _optionsClose.length).trim(),
  ].where((s) => s.isNotEmpty).join('\n\n');
  if (end < 0) {
    return (
      prose: prose,
      options: const [],
      headings: const {},
      multi: multi,
      sections: sections,
      form: form,
    );
  }
  final options = <String>[];
  final headings = <int, String>{};
  for (final raw in reply.substring(from, end).split('\n')) {
    final line = raw.trim().replaceFirst(_optionMark, '');
    if (line.isEmpty) continue;
    final heading = _optionHeading.firstMatch(line);
    if (heading != null) {
      headings[options.length] = heading[1]!;
    } else if (options.length <
        (form
            ? _maxFormOptions
            : multi
            ? 12
            : 6)) {
      options.add(line);
    }
  }
  return (
    multi: multi,
    sections: sections,
    form: form,
    prose: prose,
    options: List.unmodifiable(options),
    headings: Map.unmodifiable(headings),
  );
}

/// 成稿标签里的文字按行拆成几段。
List<DraftSection> _draftSections(String inner) {
  final sections = <DraftSection>[];
  for (final raw in inner.replaceAll(_zhInline, '\n').split('\n')) {
    final line = raw.trim();
    // 有的模型会顺手套一层代码块。
    if (line.isEmpty || line.startsWith('```')) continue;
    final m = _label.matchAsPrefix(line);
    final z = _zhLine.matchAsPrefix(line);
    String join(String a, String b) => a.isEmpty ? b : '$a $b';
    if (m != null) {
      sections.add((label: m[1]!.trim(), text: line.substring(m.end), zh: ''));
    } else if (sections.isEmpty) {
      sections.add((label: '', text: line, zh: ''));
    } else if (z != null || sections.last.zh.isNotEmpty) {
      // 中文对照,以及它后面折下来的行。
      final last = sections.removeLast();
      final more = z == null ? line : line.substring(z.end);
      sections.add((
        label: last.label,
        text: last.text,
        zh: join(last.zh, more),
      ));
    } else {
      // 没有标注的行接在上一段后面。
      final last = sections.removeLast();
      sections.add((label: last.label, text: join(last.text, line), zh: ''));
    }
  }
  return List.unmodifiable(sections);
}
