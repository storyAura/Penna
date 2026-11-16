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

/// 系统提示里偏好最多列几条(按分量从重到轻)。
const _maxLikesInPrompt = 20;

/// 系统提示里的【PennaSoul】:记着的约定和偏好,以及两个标签怎么写。
String soulPrompt(List<SoulEntry> entries) {
  final rules = [
    for (final e in entries)
      if (e.kind == soulRule) e,
  ];
  final likes = [
    for (final e in entries)
      if (e.kind != soulRule) e,
  ].take(_maxLikesInPrompt);
  return [
    '【PennaSoul】用户的长期约定和偏好,跨对话记着(用户没问就不要提起这个记录本身)。',
    if (rules.isNotEmpty)
      '约定(必须照办,比技能里"先问用户"的要求优先;用户这次明说的和约定冲突时照这次的):\n'
          '${rules.map((e) => '- [${e.id}] ${e.text}').join('\n')}',
    if (likes.isNotEmpty)
      '偏好(出点子、给建议、排 <options> 的推荐项时往这些上靠,次数多的更重;用户这次说的优先):\n'
          '${likes.map((e) => '- [${e.id}] ${e.text}(${e.hits} 次)').join('\n')}',
    '用户明说"以后都这样""记住""我说的 X 就是…",或纠正你、做了长期的决定时,'
        '在回复最后写 <$soulRememberTag kind="rule">一句话写清这个约定</$soulRememberTag>;'
        '看出用户反复用同一种画风、题材、构图或提示词写法时,写 '
        '<$soulRememberTag kind="like">一句话写清偏好</$soulRememberTag>。'
        '只记以后还用得上的,不记这一次的具体需求;已经记着的不重复写。'
        '用户要取消某条时写 <$soulForgetTag>编号</$soulForgetTag>。',
  ].join('\n');
}
