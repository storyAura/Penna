import 'package:flutter_test/flutter_test.dart';
import 'package:penna/ui/features/archive/archive_page.dart';

void main() {
  test('同一组开头一样的那一截:停在词的边界上', () {
    final lead = commonLead([
      'anime illustration of a fox, sitting by the bed',
      'anime illustration of a fox, standing in the rain',
    ]);

    expect(
      'anime illustration of a fox, sitting by the bed'.substring(lead),
      'sitting by the bed',
    );
  });

  test('只有一条、开头不一样、一样的太短时不省', () {
    expect(commonLead(['anime illustration of a fox']), 0);
    expect(commonLead(['a red fox in snow', 'the blue bird at dawn']), 0);
    expect(commonLead(['a fox runs', 'a fox sleeps']), 0);
    // 两条一模一样:一样的那截停在最后一个词前面,那个词留着给人看。
    expect(
      commonLead([
        'anime illustration of a fox',
        'anime illustration of a fox',
      ]),
      'anime illustration of a '.length,
    );
  });
}
