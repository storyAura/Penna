import '../../data/services/soul_store.dart';

// PennaSoul 的两个标签(都在回复说完时由程序做):
// `<soul-remember kind="rule|like">一句话</soul-remember>` 记一条;
// `<soul-forget>编号</soul-forget>` 删一条(用户说取消某个约定时)。

const soulRememberTag = 'soul-remember', soulForgetTag = 'soul-forget';

final _remember = RegExp(r'<soul-remember\b([^>]*)>([\s\S]*?)</soul-remember>');
final _forget = RegExp(r'<soul-forget\s*>([\s\S]*?)</soul-forget>');

/// 回复里要记的一条。
typedef SoulNote = ({String kind, String text});

/// 拆出回复里的 PennaSoul 标签;[prose] 是去掉它们之后给人看的话
/// (还没写完的那一个先不显示)。
({String prose, List<SoulNote> remember, List<String> forget}) splitSoul(
  String reply,
) {
  final remember = <SoulNote>[
    for (final m in _remember.allMatches(reply))
      if (m[2]!.trim().isNotEmpty)
        (
          kind: RegExp(r'''kind\s*=\s*["']?rule''').hasMatch(m[1]!)
              ? soulRule
              : soulLike,
          text: m[2]!.trim(),
        ),
  ];
  final forget = [
    for (final m in _forget.allMatches(reply))
      if (m[1]!.trim().isNotEmpty) m[1]!.trim(),
  ];
  var prose = reply.replaceAll(_remember, '').replaceAll(_forget, '');
  for (final open in const ['<$soulRememberTag', '<$soulForgetTag']) {
    final half = prose.indexOf(open);
    if (half >= 0) prose = prose.substring(0, half);
  }
  // 开始标签只到了一半(流式生成中):末尾是哪一个开头的前几个字就去掉。
  final cut = [
    for (final open in const ['<$soulRememberTag', '<$soulForgetTag'])
      for (var n = open.length - 1; n > 1; n--)
        if (prose.endsWith(open.substring(0, n))) n,
  ].fold(0, (a, b) => a > b ? a : b);
  prose = prose.substring(0, prose.length - cut);
  return (prose: prose.trim(), remember: remember, forget: forget);
}

/// 用户这句话里有这些词才收 `<soul-remember>`(2026-11-23 用户反馈:模型从对话里猜着记,
/// 画面内容被记成偏好,污染了之后的提示词;只靠提示词管不住,程序把关)。
final _askedToKeep = RegExp(
  r'记住|记着|记下|别忘|以后|往后|今后|每次|一直|总是|永远|默认|記住|記著|記下|以後'
  r'|覚え|いつも|今後|毎回|ずっと'
  r'|remember|always|from now on|every time|by default|going forward',
  caseSensitive: false,
);

/// 用户这句话是不是明说了要长期记住。
bool askedToRemember(String userText) => _askedToKeep.hasMatch(userText);

/// 去掉回复里的 `<soul-remember>`(没收下的那些,免得回复下面出提示条)。
String dropSoulRemember(String reply) => reply.replaceAll(_remember, '');

/// 系统提示里的【PennaSoul】:记着的约定,以及两个标签怎么写。
/// 偏好和常用角色不进来(2026-11-23 用户反馈:它们把每次写的提示词都往同一类画面上带;
/// 只给对话点子用,见 `studio_ideas.dart`)。
/// 什么时候记照 ChatGPT / Claude 记忆的做法:用户明说要长期记住才记,不从一场对话里猜;
/// 要改一条照 mem0 的 UPDATE:删掉旧的再记新的,不叠两条。
String soulPrompt(List<SoulEntry> entries) {
  final rules = [
    for (final e in entries)
      if (e.kind == soulRule) e,
  ];
  return [
    '【PennaSoul】用户的长期约定,跨对话记着(用户没问就不要提起这个记录本身)。',
    if (rules.isNotEmpty)
      '约定(必须照办,比技能里"先问用户"的要求优先;用户这次明说的和约定冲突时照这次的):\n'
          '${rules.map((e) => '- [${e.id}] ${e.text}').join('\n')}',
    '什么时候记:只在用户明说要你长期记住时(「记住」「以后都」「每次都」「我说的 X 就是…」),'
        '在回复最后写 <$soulRememberTag kind="rule">一句话写清这个约定</$soulRememberTag>;'
        '用户明说自己长期喜欢什么时写 kind="like"(只拿来出创作点子,写提示词时不用)。'
        '这些不记:这一次、这一组画面的内容(服装、动作、情节、题材、体位);从对话里猜出来的喜好;'
        '角色的长相、服装、设定(那是角色库的事);用户要存进记事本的(他说「记事本」「存起来」时写 <save-note>,不写这个);'
        '程序已经在做的事(同名角色默认用用户自己存的,用户提到的角色程序自己数次数)。拿不准就不记。'
        '已经记着的不重复写;要改某条时先写 <$soulForgetTag>旧的编号</$soulForgetTag> 再记新的;'
        '用户要取消某条时写 <$soulForgetTag>编号</$soulForgetTag>。',
  ].join('\n');
}
