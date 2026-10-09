import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/daily_outlook_score.dart';

void main() {
  group('calculateDailyCapacity', () {
    test('combines the available capacity signals', () {
      final result = calculateDailyCapacity(
        sleepHours: 5.8,
        stressScore: 68,
        heartRate: 72,
      );

      expect(result.score, 57);
      expect(result.label, 'Moderate');
      expect(result.availableSignals, 3);
    });

    test('rebalances weights when signals are missing', () {
      final result = calculateDailyCapacity(sleepHours: 8);

      expect(result.score, 100);
      expect(result.label, 'High');
      expect(result.availableSignals, 1);
    });

    test('does not invent a score without health data', () {
      final result = calculateDailyCapacity();

      expect(result.score, isNull);
      expect(result.label, 'Not enough data');
    });
  });
}
