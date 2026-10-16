import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:vivordo_health/src/services/health_service.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android swaps iOS-only health types', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(
      kMetricByKey['distance']!.platformType,
      HealthDataType.DISTANCE_DELTA,
    );
    expect(
      kMetricByKey['hrv']!.platformType,
      HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
    );
    expect(kMetricByKey['exercise_time']!.platformType, isNull);
    expect(kMetricByKey['steps']!.platformType, HealthDataType.STEPS);
  });

  test('iOS keeps HealthKit types', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    for (final m in kHealthMetrics) {
      expect(m.platformType, m.type);
    }
  });
}
