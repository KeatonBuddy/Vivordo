import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/home_stress_card_logic.dart';

void main() {
  group('home stress card drivers', () {
    test('parses and labels backend driver maps', () {
      final drivers = homeStressDrivers([
        {'name': 'sleep_duration', 'direction': 'better'},
        {'metric': 'resting_heart_rate', 'status': 'elevated'},
      ]);

      expect(drivers, hasLength(2));
      expect(drivers.first.label, 'Better sleep');
      expect(drivers.first.type, HomeStressDriverType.sleep);
      expect(drivers.last.label, 'Elevated heart rate');
      expect(drivers.last.type, HomeStressDriverType.heartRate);
    });

    test('recognizes heart rate variability as HRV', () {
      final driver = homeStressDrivers([
        {'name': 'heart rate variability', 'status': 'lower'},
      ]).single;

      expect(driver.type, HomeStressDriverType.hrv);
      expect(driver.label, 'Lower HRV');
    });
  });

  group('home stress card copy', () {
    test('compares the score with the seven-day average', () {
      expect(
        homeStressComparison(48, 54),
        '6 points below your 7-day average.',
      );
      expect(
        homeStressRangeMessage(48, 54),
        'Your stress is below your usual range.',
      );
    });

    test('recommends a walk when activity is low and stress is not high', () {
      expect(
        homeStressAction(score: 48, drivers: const [], steps: 940),
        'A short walk may help keep stress down.',
      );
    });

    test('prioritizes recovery advice for short sleep', () {
      expect(
        homeStressAction(
          score: 65,
          drivers: const [
            HomeStressDriver(
              label: 'Short sleep',
              type: HomeStressDriverType.sleep,
            ),
          ],
          steps: 8000,
        ),
        'A lighter day and an earlier bedtime may support recovery.',
      );
    });
  });
}
