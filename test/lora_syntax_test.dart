import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/comfy_workflow.dart';
import 'package:penna/core/harness/comfyui.dart';

void main() {
  test('从文本里取出 <lora:名字:权重>,按出现顺序', () {
    expect(parseLoraTags('<lora:MOSS\\a:0.75> <lora:b:1>  <lora:a:0.5>'), [
      (name: 'MOSS\\a', strength: 0.75),
      (name: 'b', strength: 1.0),
      (name: 'a', strength: 0.5),
    ]);
    expect(parseLoraTags('没有标签'), isEmpty);
  });

  test('增、改、删、收拢都只动这一串文本', () {
    const start = '<lora:a:0.5>';
    expect(loraSyntaxAdd(start, 'b', 1), '<lora:a:0.5> <lora:b:1>');
    expect(loraSyntaxSet(start, 'a', 0.8), '<lora:a:0.8>');
    expect(loraSyntaxRemove('<lora:a:0.5> <lora:b:1>', 'a'), '<lora:b:1>');
    expect(
      loraSyntaxNormalize('  <lora:a:0.50>   <lora:b:1.00> '),
      '<lora:a:0.5> <lora:b:1>',
    );
  });

  test('写着 {{lora}} 的框认出来;文字节点喂给 lora_syntax 也认', () {
    final marked = parseApiWorkflow(
      '{"1":{"class_type":"Text Multiline","inputs":{"text":"{{lora}}"}}}',
    );
    expect(usesLoraMark(marked), isTrue);

    final slot = parseApiWorkflow(
      '{"77":{"class_type":"Text Multiline","inputs":{"text":""}},'
      '"78":{"class_type":"LoRA Text Loader (LoraManager)",'
      '"inputs":{"lora_syntax":["77",0],"model":["1",0]}}}',
    );
    expect(usesLoraMark(slot), isFalse);
    expect(loraTextSlot(slot), (node: '77', key: 'text'));
  });

  test('出图前把 {{lora}} 换成这一段语法,再把提示词填进去', () {
    final wf = parseApiWorkflow(
      '{"73":{"class_type":"Text Multiline","inputs":{"value":"{{prompt}}"}},'
      '"77":{"class_type":"Text Multiline","inputs":{"text":"{{lora}}"}}}',
    );
    final out = prepareWorkflow(
      wf,
      'a girl',
      loraSyntax: '<lora:a:0.5>',
    );
    final text = ((out['77']! as Map)['inputs']! as Map)['text'];
    expect(text, '<lora:a:0.5>');
    final prompt = ((out['73']! as Map)['inputs']! as Map)['value'];
    expect(prompt, 'a girl');
  });
}
