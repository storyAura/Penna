import 'package:flutter_test/flutter_test.dart';
import 'package:penna/ui/features/studio/lora_strength.dart';

void main() {
  test('LoRA 滑条:0 在正中、两头 ±10,小权重拉得开', () {
    expect(loraPosOf(0), 0);
    expect(loraPosOf(10), closeTo(1, 1e-9));
    expect(loraPosOf(-10), closeTo(-1, 1e-9));
    for (final w in [-3.5, -0.2, 0.3, 1.0, 7.25]) {
      expect(loraWeightAt(loraPosOf(w)), closeTo(w, 1e-9));
    }
    // 0.2 和 0.3 在半边上差约 4%,均匀刻度时只差 1%
    expect(loraPosOf(0.3) - loraPosOf(0.2), greaterThan(0.03));
  });
}
