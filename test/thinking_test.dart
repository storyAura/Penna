import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/thinking.dart';

void main() {
  test('没有思考的回复原样', () {
    const text = '好的,已经改好了。\n\n<draft>【主体】a cat</draft>';
    expect(splitThinking(text).rest, text);
    expect(splitThinking(text).thinking, '');
  });

  test('<think> 拆出来,里面引用的标签不留在正文', () {
    final s = splitThinking(
      '<think>要不要写 <ask-layout>?先问。</think>\n下面几项你定一下:\n<options>\nA\n</options>',
    );
    expect(s.thinking, '要不要写 <ask-layout>?先问。');
    expect(s.rest, startsWith('下面几项你定一下'));
    expect(s.rest, isNot(contains('ask-layout')));
  });

  test('流式时没写完的 <think> 全算思考', () {
    final s = splitThinking('<think>想一想 <draft', done: false);
    expect(s.thinking, '想一想 <draft');
    expect(s.rest, '');
  });

  test('「思考过程:」后面一段普通的话是正文', () {
    final s = splitThinking(
      '思考过程:\n1. 用户发了参考图。\n2. 不写 `<draft>`。\n\n'
      '我按参考图新开了一页。\n\n<draft page="新">【主体】x</draft>',
    );
    expect(s.thinking, contains('不写 `<draft>`'));
    expect(s.rest, startsWith('我按参考图'));
  });

  test('几段小标题都算思考,顶格的标签起是正文', () {
    final s = splitThinking(
      '🫧思考过程：\n用户说继续。\n\n设计新的 5 个维度：\n1. 介质\n\n'
      '检查格式：\n- 不输出 `<draft>`。下面这几项你定一下：\n\n'
      '<options form>\n# 比例\n竖构图\n</options>',
    );
    expect(s.thinking, contains('设计新的 5 个维度'));
    expect(s.rest, startsWith('<options form>'));
  });

  test('思考里缩进引用的标签不算正文开头', () {
    final s = splitThinking(
      '思考过程:\n1. 规则:\n   <ask-layout name="系列名">任务说明\n'
      '2. 一次排几页?\n\n<ask-layout name="早餐">五页</ask-layout>',
    );
    expect(s.rest, '<ask-layout name="早餐">五页</ask-layout>');
  });

  test('全都像思考时最后一行当正文,不留空回复', () {
    final s = splitThinking('思考过程:\n1. 布局排好了。\n2. 告诉用户。已放在第 3 页。');
    expect(s.rest, '告诉用户。已放在第 3 页。');
    expect(s.thinking, '1. 布局排好了。');
  });
}
