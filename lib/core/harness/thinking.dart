/// 把回复里模型的思考和给人看的正文分开。
///
/// 两种写法都认:
/// - `<think>…</think>`(也认 thinking / thought / reasoning):系统提示要模型这样写,
///   有的接口也会这样把思考夹在正文里;
/// - 开头一行「思考过程:」「Thinking:」这类(2026-11-16 用户反馈:gemini 把思考直接写进正文,
///   里面引用的 `<ask-layout>`、`<draft>` 被程序当成了真标签)。这种没有结束的记号,
///   一段一段往下看:像思考的段(列表、以冒号结尾的小标题)都算思考,
///   碰到顶格的标签或一段普通的话就是正文开始了。
///
/// [done] 为假是还在流式生成:没写完的 `<think>` 后面全算思考。
// ponytail: 「思考过程」的段落是按样子猜的;正文要是紧贴着思考的最后一句写、
// 中间没空行,分不开,整段算思考,最后一行当正文显示。系统提示要它用 <think>,猜的只是兜底。
({String thinking, String rest}) splitThinking(
  String text, {
  bool done = true,
}) {
  final thoughts = <String>[];
  var rest = text;
  // 夹在正文里的 <think>…</think>,哪里都拆。
  rest = rest.replaceAllMapped(_closedThink, (m) {
    thoughts.add(m[2]!.trim());
    return '';
  });
  // 开头没写完(或忘了关)的 <think>。
  final open = _openThink.firstMatch(rest);
  if (open != null) {
    final body = rest.substring(open.end);
    final cut = done ? _firstTagLine(body) : null;
    thoughts.add((cut == null ? body : body.substring(0, cut)).trim());
    rest = cut == null ? '' : body.substring(cut);
  } else if (_head.firstMatch(rest) case final head?) {
    final (thought, answer) = _byParagraphs(rest.substring(head.end), done);
    thoughts.add(thought);
    rest = answer;
  }
  return (
    thinking: thoughts.where((t) => t.isNotEmpty).join('\n\n'),
    rest: thoughts.isEmpty ? text : rest.trimLeft(),
  );
}

final _closedThink = RegExp(
  r'<(think|thinking|thought|reasoning)>([\s\S]*?)</\1>\s*',
  caseSensitive: false,
);
final _openThink = RegExp(
  r'^\s*<(think|thinking|thought|reasoning)>',
  caseSensitive: false,
);

/// 开头一行「思考过程:」:前面可以有一两个表情、#、** 这类记号。
final _head = RegExp(
  r'^\s*[^\s\w一-鿿]{0,4}\s*(?:#+\s*)?(?:\*\*)?'
  r'(思考过程|思考|思路|分析过程|Thinking Process|Thought Process|Thinking|Reasoning)'
  r'(?:\*\*)?\s*[:：]',
  caseSensitive: false,
);

/// 顶格写的标签(`<draft`、`<options form>`…):思考里引用的标签要么包在反引号里,
/// 要么缩进着、夹在句子中间。
final _tagLine = RegExp(r'^<[a-z][\w-]*(?=[\s>])', multiLine: true);

int? _firstTagLine(String text) => _tagLine.firstMatch(text)?.start;

/// 像思考的一段:第一行是列表、编号、小标题,或以冒号结尾。
final _thoughtLine = RegExp(r'^\s*(\d+[.、)]|[-*•#]|.*[:：]\s*$)');

(String, String) _byParagraphs(String body, bool done) {
  final paras = body.split(RegExp(r'\n\s*\n'));
  var i = 1; // 第一段跟着「思考过程:」,一定是思考。
  while (i < paras.length) {
    final p = paras[i].trimLeft();
    if (_tagLine.matchAsPrefix(p) != null ||
        !_thoughtLine.hasMatch(p.split('\n').first)) {
      break;
    }
    i++;
  }
  // 第一段里就顶格写了标签:从那里起是正文。
  final first = paras.first;
  final tagAt = _firstTagLine(first);
  if (tagAt != null && i == 1) {
    return (
      first.substring(0, tagAt).trim(),
      [first.substring(tagAt), ...paras.skip(1)].join('\n\n'),
    );
  }
  final thought = paras.take(i).join('\n\n').trim();
  final answer = paras.skip(i).join('\n\n');
  if (answer.trim().isNotEmpty || !done) return (thought, answer);
  // 全都像思考:最后一行多半是贴着写的正文,拿出来显示,不留一个空回复。
  final lines = thought.split('\n');
  if (lines.length < 2) return (thought, answer);
  final last = lines.last.replaceFirst(RegExp(r'^\s*(\d+[.、)]|[-*•])\s*'), '');
  return (lines.take(lines.length - 1).join('\n').trim(), last);
}

/// 系统提示最后跟着的一条:思考写进 `<think>`,界面折起来,标签不会被误认。
const thinkRule =
    '【思考】回复里不写思考过程、规则自查、分析步骤;要先想,就整段写进回复最开头的 '
    '<think></think> 里(程序会折起来,不进成稿),写完 </think> 再写给用户的话和标签。'
    '<think> 外面提到标签名时不带尖括号。';
