import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/achievement_service.dart';

void main() {
  group('countMoodCheckIns', () {
    test('counts every mood entry across metric days', () {
      final count = countMoodCheckIns(
        metricDays: const [
          {
            'mood': {
              'entries': [
                {'score': 70},
                {'score': 82},
              ],
            },
          },
          {
            'mood': {
              'entries': [
                {'score': 55},
              ],
            },
          },
        ],
      );

      expect(count, 3);
    });

    test('counts legacy mood data once and ignores empty mood maps', () {
      final count = countMoodCheckIns(
        metricDays: const [
          {
            'mood': {'avg': 75, 'label': 'Good'},
          },
          {'mood': <String, Object>{}},
          {'steps': 5000},
        ],
      );

      expect(count, 1);
    });

    test('does not double count legacy fields when entries exist', () {
      final count = countMoodCheckIns(
        metricDays: const [
          {
            'mood': {
              'avg': 75,
              'label': 'Good',
              'entries': [
                {'score': 75},
              ],
            },
          },
        ],
      );

      expect(count, 1);
    });
  });
}
