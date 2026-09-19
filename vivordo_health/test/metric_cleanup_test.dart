import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/metric_cleanup.dart';

void main() {
  test('an empty sleep read never clears the night already saved', () {
    expect(emptyReadMayClearSavedMetric('sleep'), isFalse);
  });

  test('other metrics still clear days the read did not cover', () {
    for (final metric in [
      'steps',
      'heart_rate',
      'hrv',
      'active_calories',
      'exercise_time',
      'mood',
    ]) {
      expect(
        emptyReadMayClearSavedMetric(metric),
        isTrue,
        reason: '$metric should keep the existing cleanup behaviour',
      );
    }
  });
}
