import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/metric_cleanup.dart';

const _metrics = [
  'steps',
  'heart_rate',
  'hrv',
  'active_calories',
  'exercise_time',
  'distance',
  'mood',
];

void main() {
  group('a read that returned nothing at all', () {
    test('never clears any metric', () {
      for (final metric in [..._metrics, 'sleep']) {
        expect(
          readMayClearMissingDays(
            metricKey: metric,
            readCoveredAnyDay: false,
          ),
          isFalse,
          reason:
              '$metric: an empty read cannot be told apart from read access '
              'never having been granted',
        );
      }
    });

    test('is what opening Metrics on Week used to erase', () {
      // dashboard_screen syncs its whole filter window, so active_calories
      // coming back empty cleared seven days of saved values.
      expect(
        readMayClearMissingDays(
          metricKey: 'active_calories',
          readCoveredAnyDay: false,
        ),
        isFalse,
      );
    });
  });

  group('a read that covered at least one day', () {
    test('may clear the days it skipped', () {
      for (final metric in _metrics) {
        expect(
          readMayClearMissingDays(metricKey: metric, readCoveredAnyDay: true),
          isTrue,
          reason: '$metric is readable, so a skipped day is genuinely empty',
        );
      }
    });

    test('still never clears sleep', () {
      // A night reaches the phone late, so a read can return yesterday's
      // sleep and not last night's while the watch is catching up.
      expect(
        readMayClearMissingDays(metricKey: 'sleep', readCoveredAnyDay: true),
        isFalse,
      );
    });
  });

  test('sleep is the only metric exempt from an otherwise-trusted read', () {
    expect(emptyReadMayClearSavedMetric('sleep'), isFalse);
    for (final metric in _metrics) {
      expect(emptyReadMayClearSavedMetric(metric), isTrue);
    }
  });
}
