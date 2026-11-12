// 穿甲弹的「文档模式」(2026-11-13 用户要求):用户的每条话写成一份 Markdown 文档,
// 通过接口当文件传过去,并要求模型把回复也写成文档传回来(放在 <document> 里)。
// 文档模式不带穿甲弹的文字(那是提示词模式的),只靠每条消息里写明的要求让模型照做。
// 界面显示时只去掉 <document> 这层包装,
// 里面的 <draft>、<options> 照常认。

import 'dart:convert';

import 'providers/llm_http.dart' show LlmImage;

/// 文档当文件传时用的类型:Gemini 认 text/plain,写的是 Markdown 也照收。
const documentMime = 'text/plain';

String _ask(int n) =>
    '【文档模式】用户这一轮的要求在上传的文档「要求-$n.md」里,不在这条消息里。照下面做:\n'
    '1. 完整读完「要求-$n.md」,按里面的要求完成这一轮的工作。\n'
    '2. 把全部回复写成一份 Markdown 文档,整份放进 <document name="回复-$n.md"> 和 </document> 之间传回来。'
    '程序约定的标签(<draft>、<options> 这些)照常写在文档里。\n'
    '3. 文档外只写一句完成情况,不在文档外写正文。';

/// 把一组请求消息(第一条是系统提示)改成文档模式:用户的每条话写成「要求-N.md」。
/// [asFile] 为真时文档当文件随这条消息传(放进 [images] 里,Google 接口用 inlineData 发);
/// 否则接口收不了文本文件,文档包在 `<upload>` 里放进消息。
({List<Map<String, String>> messages, Map<int, List<LlmImage>> images})
documentRequest(
  List<Map<String, String>> messages,
  Map<int, List<LlmImage>> images, {
  required bool asFile,
}) {
  var n = 0;
  final files = {...images};
  final out = <Map<String, String>>[];
  for (final (i, m) in messages.indexed) {
    if (i == 0 || m['role'] != 'user') {
      out.add(m);
      continue;
    }
    n++;
    final doc = m['content'] ?? '';
    if (asFile) {
      files[i] = [...?images[i], (mime: documentMime, bytes: utf8.encode(doc))];
      out.add({'role': 'user', 'content': _ask(n)});
    } else {
      out.add({
        'role': 'user',
        'content': '<upload name="要求-$n.md">\n$doc\n</upload>\n${_ask(n)}',
      });
    }
  }
  return (messages: out, images: files);
}

final _marks = RegExp(r'<document\b[^>]*>|</document>');

/// 显示用:去掉 `<document>` 这层包装,里面的内容照旧。
/// 流式时末尾半截的开始、结束标签(`<docu`、`<document name="a`、`</doc`)先不显示。
String stripDocumentMarks(String reply) {
  final text = reply.replaceAll(_marks, '');
  final at = text.lastIndexOf('<');
  if (at < 0) return text;
  final tail = text.substring(at);
  final half =
      '<document'.startsWith(tail) ||
      '</document'.startsWith(tail) ||
      tail.startsWith('<document') && !tail.contains('>');
  return half ? text.substring(0, at) : text;
}
