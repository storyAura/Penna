// Preset 的系统提示里可以写几轮「事先说好的对话」,发请求时拆成真正的一轮一轮消息:
//
//   开头不属于任何一轮的话(照旧是系统提示)
//   <<user>>
//   用户这一边说的话
//   <<assistant>>
//   模型这一边说的话
//   <<history>>
//   <<assistant>>
//   排在聊天记录后面的几轮
//
// 三种标记各占一行。<<history>> 是聊天记录的位置,不写就排在所有对话后面。

/// 一轮对话:[role] 是 `user` 或 `assistant`。
typedef PresetTurn = ({String role, String content});

/// 一份 Preset 拆开后的样子:[lead] 是不属于任何一轮的开头,
/// [head] 排在聊天记录前面,[tail] 排在聊天记录后、用户最后一句话前面。
class PresetDialogue {
  const PresetDialogue({
    required this.lead,
    required this.head,
    required this.tail,
  });

  final String lead;
  final List<PresetTurn> head;
  final List<PresetTurn> tail;
}

const userMark = '<<user>>';
const assistantMark = '<<assistant>>';
const historyMark = '<<history>>';

final _mark = RegExp(
  r'^[ \t]*<<(user|assistant|history)>>[ \t]*$',
  multiLine: true,
);

/// 把系统提示拆成开头和前后两段对话。没写对话标记的返回 null。
PresetDialogue? presetDialogue(String text) {
  final marks = _mark.allMatches(text).toList();
  if (marks.isEmpty) return null;
  final head = <PresetTurn>[];
  final tail = <PresetTurn>[];
  var turns = head;
  for (final (i, m) in marks.indexed) {
    final end = i + 1 < marks.length ? marks[i + 1].start : text.length;
    final body = text.substring(m.end, end).trim();
    if (m[1] == 'history') {
      turns = tail;
      // <<history>> 后面直接跟着的话没说是谁讲的,算用户这一边。
      if (body.isNotEmpty) _add(turns, 'user', body);
    } else if (body.isNotEmpty) {
      _add(turns, m[1]!, body);
    }
  }
  return PresetDialogue(
    lead: text.substring(0, marks.first.start).trim(),
    head: head,
    tail: tail,
  );
}

/// 同一边连着说的并成一轮:多数接口要求两边轮流。
void _add(List<PresetTurn> turns, String role, String content) {
  if (turns.isNotEmpty && turns.last.role == role) {
    turns[turns.length - 1] = (
      role: role,
      content: '${turns.last.content}\n\n$content',
    );
  } else {
    turns.add((role: role, content: content));
  }
}

/// 把 [dialogue] 的前后两段装进 [chat](系统提示之后的真实对话,最后一条是用户的话):
/// 前段在最前,后段在最后一条用户消息前面。相邻同一边的消息并成一条。
/// [closing] 放在最后一条用户消息的开头:事先说好的对话越长,写在最前面的规则越容易被冲淡,
/// 模型最后读到的才压得住。
///
/// 返回的 `at[i]` 是 [chat] 的第 i 条落在 `messages` 的第几条(随消息发的图要跟着挪)。
({List<Map<String, String>> messages, List<int> at}) withPresetDialogue(
  PresetDialogue dialogue,
  List<Map<String, String>> chat, {
  String closing = '',
}) {
  final turns = <PresetTurn>[];
  final at = <int>[];
  for (final t in dialogue.head) {
    _add(turns, t.role, t.content);
  }
  for (final m in chat.take(chat.isEmpty ? 0 : chat.length - 1)) {
    _add(turns, m['role']!, m['content']!);
    at.add(turns.length - 1);
  }
  for (final t in dialogue.tail) {
    _add(turns, t.role, t.content);
  }
  if (chat.isNotEmpty) {
    final text = chat.last['content']!;
    _add(
      turns,
      chat.last['role']!,
      closing.isEmpty ? text : '$closing\n\n【用户这次的话】\n$text',
    );
    at.add(turns.length - 1);
  }
  return (
    messages: [
      for (final t in turns) {'role': t.role, 'content': t.content},
    ],
    at: at,
  );
}
