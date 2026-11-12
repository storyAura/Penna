// Agent 读写记事本用的两个标签(2026-11-13 用户要求):
// `<read-notebook>本子名</read-notebook>` 走工具循环,程序取来那个本子的全部条目交还;
// `<save-note book="本子名" title="条目名">内容</save-note>` 在回复说完时存进去。

const readNotebookTag = 'read-notebook';
const _saveOpen = '<save-note';

final _saveBlock = RegExp(r'<save-note\b([^>]*)>([\s\S]*?)</save-note>');

String? _attr(String attrs, String name) =>
    RegExp('$name\\s*=\\s*"([^"\\n]*)"').firstMatch(attrs)?[1]?.trim();

/// 一条要存的:[title] 可以空着(那就新加一条)。
typedef NoteSave = ({String book, String title, String text});

/// 拆出回复里的 `<save-note>`;[prose] 是去掉它们之后给人看的话
/// (还没写完的那一个先不显示)。没写 book 或内容是空的不算。
({String prose, List<NoteSave> saves}) splitSaveNote(String reply) {
  final saves = <NoteSave>[
    for (final m in _saveBlock.allMatches(reply))
      if ((_attr(m[1]!, 'book') ?? '').isNotEmpty && m[2]!.trim().isNotEmpty)
        (
          book: _attr(m[1]!, 'book')!,
          title: _attr(m[1]!, 'title') ?? '',
          text: m[2]!.trim(),
        ),
  ];
  var prose = reply.replaceAll(_saveBlock, '');
  final half = prose.indexOf(_saveOpen);
  if (half >= 0) prose = prose.substring(0, half);
  // 开始标签只到了一半(流式生成中)。
  for (var n = _saveOpen.length - 1; n > 1; n--) {
    if (prose.endsWith(_saveOpen.substring(0, n))) {
      prose = prose.substring(0, prose.length - n);
      break;
    }
  }
  return (prose: prose.trim(), saves: saves);
}
