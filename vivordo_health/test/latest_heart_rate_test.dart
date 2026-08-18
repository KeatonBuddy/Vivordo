import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/latest_heart_rate.dart';

void main() {
  test('newer wearable reading wins over an older Vivordo scan', () {
    final result = latestHeartRateBpmFromMetricDays([
      {
        'heart_rate': {
          'source': 'apple_health',
          'entries': [
            {
              'bpm': 82,
              'timestamp': Timestamp.fromDate(DateTime(2026, 8, 17, 14)),
            },
          ],
        },
        'heart_rate_scan': {
          'source': 'camera_ppg',
          'entries': [
            {
              'bpm': 71,
              'timestamp': Timestamp.fromDate(DateTime(2026, 8, 17, 12)),
            },
          ],
        },
      },
    ]);

    expect(result, 82);
  });

  test('newer Vivordo scan wins over an older wearable reading', () {
    final result = latestHeartRateBpmFromMetricDays([
      {
        'heart_rate': {
          'source': 'apple_health',
          'entries': [
            {
              'bpm': 76,
              'timestamp': Timestamp.fromDate(DateTime(2026, 8, 17, 12)),
            },
          ],
        },
        'heart_rate_scan': {
          'source': 'camera_ppg',
          'entries': [
            {
              'bpm': 68,
              'timestamp': Timestamp.fromDate(DateTime(2026, 8, 17, 15)),
            },
          ],
        },
      },
    ]);

    expect(result, 68);
  });
}
