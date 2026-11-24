import '../../../data/models/app_config.dart';
import '../preset_dialogue.dart';

// 把 SillyTavern 的 Chat Completion 预设(酒馆预设 JSON)转成 Penna 的 Preset。
// 只做机械转换:温度、Top P 照搬;系统提示按 prompt_order 里启用的条目依次拼接,
// 条目的角色(user / assistant)和聊天记录的位置写成对话标记(见 preset_dialogue.dart)。
// Penna 没有对应的东西(top_k、各种 penalty、角色卡与世界书的占位、扩展脚本)一律略过,
// 条目里的 {{user}}、{{char}} 等宏原样留在文字里,由用户自己改。

/// 单个条目超过这么多字就当成扩展存的配置数据,不拼进系统提示。
const _maxEntryChars = 20000;

/// 去掉酒馆里展开后什么都不留的宏:`{{// 注释}}` 和 `{{trim}}`。
/// 注释可以跨行,里面还可以写着别的宏(`{{// 只改 {{user}} 的部分}}`),所以按括号配对找结尾。
String _dropEmptyMacros(String text) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final start = text.indexOf('{{//', i);
    if (start < 0) break;
    out.write(text.substring(i, start));
    var depth = 0;
    var end = text.length;
    for (var k = start; k < text.length - 1; k++) {
      final pair = text.substring(k, k + 2);
      if (pair == '{{') {
        depth++;
        k++;
      } else if (pair == '}}') {
        depth--;
        k++;
        if (depth == 0) {
          end = k + 1;
          break;
        }
      }
    }
    i = end;
  }
  out.write(text.substring(i));
  return out.toString().replaceAll('{{trim}}', '');
}

/// [json] 是解析好的酒馆预设,[name] 是新 Preset 的名字。
/// 不是酒馆预设、或里面没有可用的提示词时抛 [FormatException]。
AgentPreset sillyTavernToPreset(
  Map<String, dynamic> json, {
  required String name,
}) {
  if (json['prompts'] is! List) {
    throw const FormatException('没有 prompts,不是 SillyTavern 预设');
  }
  final systemPrompt = _systemPrompt(json);
  if (systemPrompt.isEmpty) {
    throw const FormatException('预设里没有启用的提示词');
  }
  final temperature = (json['temperature'] as num?) ?? 0.7;
  final topP = (json['top_p'] as num?) ?? 1;
  return AgentPreset(
    id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
    name: name,
    systemPrompt: systemPrompt,
    tools: {for (final o in builtinTools) o.id},
    temperature: temperature.clamp(0, 2).toDouble(),
    topP: topP.clamp(0.1, 1).toDouble(),
  );
}

/// 启用的条目按顺序拼成一段系统提示。
String _systemPrompt(Map<String, dynamic> json) {
  final prompts = [
    for (final p in json['prompts'] as List)
      if (p is Map<String, dynamic>) p,
  ];
  final order = _enabledOrder(json);
  final byId = {
    for (final p in prompts)
      if (p['identifier'] is String) p['identifier'] as String: p,
  };
  // 没有 prompt_order 的预设按条目本身的顺序全部算启用。
  final chosen = order.isEmpty ? prompts : [for (final id in order) ?byId[id]];
  // 有条目是以用户或模型的身份说话的,才写对话标记;全是系统提示的预设照旧拼成一段。
  final spoken = chosen.any((p) => p['marker'] != true && _speaker(p) != null);
  final parts = <String>[];
  // 上一段是谁说的:null 是还在开头的系统提示里。
  String? side;
  for (final p in chosen) {
    // marker 是聊天记录、角色卡、世界书的占位,Penna 只认聊天记录的位置。
    if (p['marker'] == true) {
      if (spoken && p['identifier'] == 'chatHistory') {
        parts.add(historyMark);
        side = historyMark;
      }
      continue;
    }
    final content = _dropEmptyMacros('${p['content'] ?? ''}').trim();
    if (content.isEmpty || content.length > _maxEntryChars) continue;
    // 对话开始以后的系统条目算用户这一边:多数接口不收夹在对话中间的系统消息。
    final next = _speaker(p) ?? (side == null ? null : userMark);
    if (next != null && next != side) parts.add(next);
    side = next ?? side;
    parts.add(content);
  }
  return parts.join('\n\n');
}

/// 条目是谁说的,写成对话标记;系统条目返回 null。
String? _speaker(Map<String, dynamic> prompt) => switch (prompt['role']) {
  'user' => userMark,
  'assistant' => assistantMark,
  _ => null,
};

/// prompt_order 里启用的条目 id。有好几组(每组对应一个 character_id)时取启用条目最多的
/// 那一组:预设作者实际在用的就是它,另一组通常是酒馆留下的默认顺序。
List<String> _enabledOrder(Map<String, dynamic> json) {
  final groups = json['prompt_order'];
  if (groups is! List) return const [];
  var best = const <String>[];
  for (final g in groups) {
    final order = g is Map<String, dynamic> ? g['order'] : null;
    if (order is! List) continue;
    final enabled = [
      for (final o in order)
        if (o is Map<String, dynamic> &&
            o['enabled'] == true &&
            o['identifier'] is String)
          o['identifier'] as String,
    ];
    if (enabled.length >= best.length) best = enabled;
  }
  return best;
}
