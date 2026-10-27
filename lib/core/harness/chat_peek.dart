// 主聊天和副聊天互相看对方的记录:回复里写 `<read-side-chat></read-side-chat>`
// (主聊天看副聊天)或 `<read-main-chat></read-main-chat>`(副聊天看主聊天),
// 程序把那边的记录交过来再接着写。

/// 主聊天要看副聊天时写的标签名。
const readSideChat = 'read-side-chat';

/// 副聊天要看主聊天时写的标签名。
const readMainChat = 'read-main-chat';

/// 拆出 [tag]:成对的、自闭合的都认。[prose] 是去掉它之后给人看的话
/// (流式生成中还没写完的那一个先不显示)。
({String prose, bool asked}) splitPeek(String reply, String tag) {
  final full = RegExp('<$tag\\s*/?>(?:\\s*</$tag>)?');
  final asked = full.hasMatch(reply);
  var prose = reply.replaceAll(full, '').replaceAll('</$tag>', '');
  final open = '<$tag';
  final half = prose.indexOf(open);
  if (half >= 0) prose = prose.substring(0, half);
  for (var n = open.length - 1; n > 1; n--) {
    if (prose.endsWith(open.substring(0, n))) {
      prose = prose.substring(0, prose.length - n);
      break;
    }
  }
  return (prose: prose.trim(), asked: asked);
}
