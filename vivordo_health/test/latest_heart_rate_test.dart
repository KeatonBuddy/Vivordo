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

  test('fresh WHOOP Bluetooth wins over a newer Apple Health reading', () {
    final now = DateTime.now();
    final result = latestHeartRateBpmFromMetricDays([
      {
        'heart_rate_sources': {
          'whoop_ble': {
            'source': 'whoop_ble',
            'lastReadingAt': Timestamp.fromDate(
              now.subtract(const Duration(minutes: 1)),
            ),
            'entries': [
              {
                'bpm': 91,
                'timestamp': Timestamp.fromDate(
                  now.subtract(const Duration(minutes: 1)),
                ),
              },
            ],
          },
          'apple_health': {
            'source': 'apple_health',
            'entries': [
              {'bpm': 74, 'timestamp': Timestamp.fromDate(now)},
            ],
          },
        },
      },
    ]);

    expect(result, 91);
  });

  test('stale WHOOP Bluetooth falls back to Apple Health', () {
    final now = DateTime.now();
    final result = latestHeartRateBpmFromMetricDays([
      {
        'heart_rate': {
          'source': 'whoop_ble',
          'lastReadingAt': Timestamp.fromDate(
            now.subtract(const Duration(minutes: 10)),
          ),
          'entries': [
            {
              'bpm': 91,
              'timestamp': Timestamp.fromDate(
                now.subtract(const Duration(minutes: 10)),
              ),
            },
          ],
        },
        'heart_rate_sources': {
          'apple_health': {
            'source': 'apple_health',
            'entries': [
              {
                'bpm': 74,
                'timestamp': Timestamp.fromDate(
                  now.subtract(const Duration(minutes: 2)),
                ),
              },
            ],
          },
        },
      },
    ]);

    expect(result, 74);
  });

  test('fresh Fitbit Air Bluetooth wins over synced health data', () {
    final now = DateTime.now();
    final result = latestHeartRateBpmFromMetricDays([
      {
        'heart_rate_sources': {
          'fitbit_ble': {
            'source': 'fitbit_ble',
            'lastReadingAt': Timestamp.fromDate(now),
            'entries': [
              {'bpm': 86, 'timestamp': Timestamp.fromDate(now)},
            ],
          },
          'apple_health': {
            'source': 'apple_health',
            'entries': [
              {'bpm': 72, 'timestamp': Timestamp.fromDate(now)},
            ],
          },
        },
      },
    ]);

    expect(result, 86);
  });
}
