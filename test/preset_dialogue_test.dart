import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/preset_dialogue.dart';

const _text = '''
你是故事主持人
<<assistant>>
要我主持吗
<<user>>
要
<<user>>
这是之前聊的:
<<history>>
<<assistant>>
看完了,有什么要求
<<user>>
写短一点''';

Map<String, String> _m(String role, String content) => {
  'role': role,
  'content': content,
};

void main() {
  test('没写对话标记的系统提示不处理', () {
    expect(presetDialogue('你是一个写提示词的助手'), isNull);
    expect(presetDialogue('句子中间的 <<user>> 不算标记'), isNull);
  });

  test('标记分出几轮对话,聊天记录前后各一段,同一边连着说的并成一轮', () {
    final d = presetDialogue(_text)!;

    expect(d.lead, '你是故事主持人');
    expect(d.head, [
      (role: 'assistant', content: '要我主持吗'),
      (role: 'user', content: '要\n\n这是之前聊的:'),
    ]);
    expect(d.tail, [
      (role: 'assistant', content: '看完了,有什么要求'),
      (role: 'user', content: '写短一点'),
    ]);
  });

  test('没写 <<history>> 时对话都排在聊天记录前面', () {
    final d = presetDialogue('<<user>>\n你好\n<<assistant>>\n你好呀')!;

    expect(d.lead, '');
    expect(d.head.length, 2);
    expect(d.tail, isEmpty);
  });

  test('聊天记录放在两段中间,用户最后一句话压在最后', () {
    final out = withPresetDialogue(presetDialogue(_text)!, [
      _m('user', '第一句'),
      _m('assistant', '回复'),
      _m('user', '最后一句'),
    ]);

    expect(out.at, [1, 2, 3]);
    expect(out.messages, [
      _m('assistant', '要我主持吗'),
      _m('user', '要\n\n这是之前聊的:\n\n第一句'),
      _m('assistant', '回复\n\n看完了,有什么要求'),
      _m('user', '写短一点\n\n最后一句'),
    ]);
  });

  test('收尾的规则放在最后一条用户消息里,用户的话跟在后面', () {
    final out = withPresetDialogue(
      presetDialogue('<<user>>\n你好\n<<assistant>>\n你好呀')!,
      [_m('user', '画一只猫')],
      closing: '【这次的工作】写提示词',
    );

    expect(out.messages.last, _m('user', '【这次的工作】写提示词\n\n【用户这次的话】\n画一只猫'));
  });
}
