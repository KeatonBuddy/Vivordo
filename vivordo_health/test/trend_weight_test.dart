import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/trend_weight.dart';

void main() {
  DateTime day(int d) => DateTime(2026, 10, d, 7);

  test('daily weigh-ins move the trend a tenth of the way each day', () {
    final trend = trendWeights([
      (date: day(1), value: 180),
      (date: day(2), value: 182),
      (date: day(3), value: 178),
    ]);
    expect(trend[0], 180);
    expect(trend[1], closeTo(180.2, 1e-9));
    expect(trend[2], closeTo(180.2 - .22, 1e-9));
  });

  test('a long gap lets the trend catch up with the scale', () {
    final trend = trendWeights([
      (date: day(1), value: 180),
      (date: day(31), value: 170),
    ]);
    // 30 days: 1 - 0.9^30 ≈ 96% of the way.
    expect(trend[1], closeTo(170.42, .01));
  });

  test('a second weigh-in the same morning barely moves it', () {
    final trend = trendWeights([
      (date: day(1), value: 180),
      (date: day(1).add(const Duration(minutes: 5)), value: 185),
    ]);
    expect(trend[1], closeTo(180, .01));
  });
}
