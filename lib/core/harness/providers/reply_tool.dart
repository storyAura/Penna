import 'dart:convert';

import '../../../l10n/l10n.dart';
import 'llm_http.dart';

// 「回复写在工具调用里」:Preset 打开这一项时,请求多带一个只有 text 一个参数的工具,
// 并把 tool_choice 钉在它上面。模型把这一轮要说的话写进参数,正文留空;
// 这边把流式回来的参数一段段解成文字,当成普通回复交给上层。
// 有的接口只审查正文,参数里的字不会被拦;也让模型先把话想完整再一次交出来。

/// 这个工具的名字。外接工具(MCP)里同名的会被跳过,不会当成外接工具去调。
const replyToolName = 'reply';

/// 请求里带的那个工具:`{"text": "..."}`。
LlmTool replyToolSpec() => (
  name: replyToolName,
  description: tr('把这一轮回复的全部内容写在 text 里,正文留空。'),
  schema: const {
    'type': 'object',
    'properties': {
      'text': {'type': 'string', 'description': '回复的全部内容,格式照要求'},
    },
    'required': ['text'],
    'additionalProperties': false,
  },
);

/// `tools` 里的一项(OpenAI 兼容接口的写法)。
Map<String, Object?> openAiReplyTool() {
  final t = replyToolSpec();
  return {
    'type': 'function',
    'function': {
      'name': t.name,
      'description': t.description,
      'parameters': t.schema,
    },
  };
}

/// 把流式回来的工具参数解成文字。
///
/// 参数是一段 JSON(`{"text":"..."}`),分好几段到:这里只认 `text` 的值,
/// 半截的转义(`\` 或 `\u12`)留到下一段接着解。
class ReplyTextReader {
  String _raw = '';
  int _pos = 0;
  int _emitted = 0;
  bool _inValue = false;
  bool _closed = false;

  /// 已经吐出去的字数。
  int get emitted => _emitted;

  /// 吃进一段参数,返回这一段能解出来的文字。
  String add(String chunk) {
    if (_closed) return '';
    _raw += chunk;
    final out = _pump();
    _emitted += out.length;
    return out;
  }

  /// 参数到齐了:还没解出来的补上(有的接口最后不发收尾的引号)。
  String flush() {
    if (_closed) return '';
    final rest = add('');
    final text = _whole();
    if (text == null || text.length <= _emitted) return rest;
    final tail = text.substring(_emitted);
    _emitted = text.length;
    _closed = true;
    return rest + tail;
  }

  /// 整段参数解出来的 `text`;解不出来是 null。
  String? _whole() {
    try {
      final json = jsonDecode(_raw);
      return json is Map && json['text'] is String
          ? json['text'] as String
          : null;
    } on FormatException {
      return null;
    }
  }

  String _pump() {
    if (_closed) return '';
    final out = StringBuffer();
    if (!_inValue) {
      // 找 `"text"` 这个键:参数可能先有空白,也可能这一段还没到齐。
      final at = _raw.indexOf('"text"', _pos);
      if (at < 0) {
        // 留着最后几个字,免得下次把刚到的半个键名跳过去。
        if (_raw.length > 8) _pos = _raw.length - 8;
        return '';
      }
      var i = at + 6;
      while (i < _raw.length && _space(_raw.codeUnitAt(i))) {
        i++;
      }
      if (i >= _raw.length || _raw[i] != ':') {
        _pos = at + 6;
        return '';
      }
      i++;
      while (i < _raw.length && _space(_raw.codeUnitAt(i))) {
        i++;
      }
      if (i >= _raw.length || _raw[i] != '"') {
        _pos = at + 6;
        return '';
      }
      _pos = i + 1;
      _inValue = true;
    }
    var i = _pos;
    while (i < _raw.length) {
      final c = _raw[i];
      if (c == '"') {
        _closed = true;
        i++;
        break;
      }
      if (c != r'\') {
        out.write(c);
        i++;
        continue;
      }
      // 转义:这一段就到反斜线为止时,等下一段。
      if (i + 1 >= _raw.length) break;
      final e = _raw[i + 1];
      if (e == 'u') {
        if (i + 6 > _raw.length) break;
        final code = int.tryParse(_raw.substring(i + 2, i + 6), radix: 16);
        if (code == null) {
          i += 2;
          continue;
        }
        out.writeCharCode(code);
        i += 6;
        continue;
      }
      out.write(switch (e) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        'b' => '\b',
        'f' => '\f',
        _ => e,
      });
      i += 2;
    }
    _pos = i;
    return out.toString();
  }
}

bool _space(int c) => c == 0x20 || c == 0x0a || c == 0x0d || c == 0x09;
