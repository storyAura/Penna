import 'package:flutter_test/flutter_test.dart';
import 'package:penna/core/harness/draft_block.dart';
import 'package:penna/data/models/comfy_settings.dart';

void main() {
  test('只出横图、只出竖图时方向不对就对调宽高,别的情况不动', () {
    expect(orientedSize(orientationLandscape, 832, 1216), (
      width: 1216,
      height: 832,
    ));
    expect(orientedSize(orientationPortrait, 1216, 832), (
      width: 832,
      height: 1216,
    ));
    expect(orientedSize(orientationLandscape, 1216, 832), isNull);
    expect(orientedSize(orientationPortrait, 1024, 1024), isNull);
    expect(orientedSize(orientationKeep, 832, 1216), isNull);
    expect(orientedSize(orientationAuto, 832, 1216), isNull);
  });

  test('画面方向存得回来,认不出的值按照工作流的大小', () {
    const base = ComfySettings();
    expect(base.orientation, orientationKeep);
    final saved = base.copyWith(orientation: orientationAuto).toJson();
    expect(ComfySettings.fromJson(saved).orientation, orientationAuto);
    expect(
      ComfySettings.fromJson({...saved, 'orientation': '乱写'}).orientation,
      orientationKeep,
    );
  });

  test('单选的题最后多一个「让 AI 自己决定」', () {
    final asked = withAiChoice(
      splitOptions('要哪种?\n<options>\n竖构图\n横构图\n</options>'),
      '让 AI 自己决定',
    );

    expect(asked.options, ['竖构图', '横构图', '让 AI 自己决定']);
  });

  test('表单里每道题各多一个,题目还对着自己的选项', () {
    final asked = withAiChoice(
      splitOptions('<options form>\n# 比例\n竖\n横\n# 光线\n逆光\n</options>'),
      '让 AI 自己决定',
    );

    expect(asked.options, ['竖', '横', '让 AI 自己决定', '逆光', '让 AI 自己决定']);
    expect(asked.headings, {0: '比例', 3: '光线'});
  });

  test('模型自己给了这种选项、多选、没有选项时不加', () {
    const label = '让 AI 自己决定';
    expect(
      withAiChoice(
        splitOptions('<options>\n竖构图\n你决定就好\n</options>'),
        label,
      ).options,
      ['竖构图', '你决定就好'],
    );
    expect(
      withAiChoice(
        splitOptions('<options multi>\n甲\n乙\n</options>'),
        label,
      ).options,
      ['甲', '乙'],
    );
    expect(withAiChoice(splitOptions('没有选项'), label).options, isEmpty);
  });
}
