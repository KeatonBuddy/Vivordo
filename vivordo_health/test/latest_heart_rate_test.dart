import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/home_metrics_summary.dart';

/// Home's heart-rate tile, which resolves through [summarizeHomeMetrics].
int? tileBpm(List<MetricDayEntry> days, {DateTime? now}) =>
    summarizeHomeMetrics(days: days, now: now ?? DateTime.now())
        .latestHeartRate
        ?.bpm;

MetricDayEntry day(String dayKey, Map<String, dynamic> data) =>
    MetricDayEntry(dayKey: dayKey, data: data);

void main() {
  test('returns the timestamp and source of the latest reading', () {
    final timestamp = DateTime(2026, 8, 17, 14, 25);
    final reading = summarizeHomeMetrics(
      now: DateTime(2026, 8, 17, 15),
      days: [
        day('2026-08-17', {
          'heart_rate': {
            'source': 'apple_health',
            'entries': [
              {'bpm': 82, 'timestamp': Timestamp.fromDate(timestamp)},
            ],
          },
        }),
      ],
    ).latestHeartRate;

    expect(reading?.bpm, 82);
    expect(reading?.timestamp, timestamp);
    expect(reading?.source, 'apple_health');
  });

  test('newer wearable reading wins over an older Vivordo scan', () {
    expect(
      tileBpm(now: DateTime(2026, 8, 17, 16), [
        day('2026-08-17', {
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
        }),
      ]),
      82,
    );
  });

  test('newer Vivordo scan wins over an older wearable reading', () {
    expect(
      tileBpm(now: DateTime(2026, 8, 17, 16), [
        day('2026-08-17', {
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
        }),
      ]),
      68,
    );
  });

  test('fresh WHOOP Bluetooth wins over a newer Apple Health reading', () {
    final now = DateTime(2026, 8, 17, 15);
    expect(
      tileBpm(now: now, [
        day('2026-08-17', {
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
        }),
      ]),
      91,
    );
  });

  test('stale WHOOP Bluetooth falls back to Apple Health', () {
    final now = DateTime(2026, 8, 17, 15);
    expect(
      tileBpm(now: now, [
        day('2026-08-17', {
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
        }),
      ]),
      74,
    );
  });

  test('fresh Fitbit Bluetooth wins over synced health data', () {
    final now = DateTime(2026, 8, 17, 15);
    expect(
      tileBpm(now: now, [
        day('2026-08-17', {
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
        }),
      ]),
      86,
    );
  });

  group('regressions', () {
    test('a wearable reading hours old is still shown', () {
      // The previous resolver discarded a Bluetooth metric outright once it
      // was more than five minutes old, so a strap worn earlier in the day
      // left the tile reading "No data".
      final now = DateTime(2026, 8, 17, 18);
      expect(
        tileBpm(now: now, [
          day('2026-08-17', {
            'heart_rate_sources': {
              'whoop_ble': {
                'source': 'whoop_ble',
                'lastReadingAt': Timestamp.fromDate(
                  now.subtract(const Duration(hours: 3)),
                ),
                'entries': [
                  {
                    'bpm': 64,
                    'timestamp': Timestamp.fromDate(
                      now.subtract(const Duration(hours: 3)),
                    ),
                  },
                ],
              },
            },
          }),
        ]),
        64,
      );
    });

    test('a camera scan is shown when it is the only reading', () {
      final now = DateTime(2026, 9, 19, 14);
      expect(
        tileBpm(now: now, [
          day('2026-09-19', {
            'heart_rate': {'avg': 72, 'source': 'camera_ppg'},
            'heart_rate_scan': {
              'avg': 72,
              'source': 'camera_ppg',
              'entries': [
                {
                  'bpm': 70,
                  'timestamp': Timestamp.fromDate(DateTime(2026, 9, 19, 9)),
                },
                {
                  'bpm': 74,
                  'timestamp': Timestamp.fromDate(DateTime(2026, 9, 19, 13)),
                },
              ],
            },
          }),
        ]),
        74,
      );
    });

    test('today wins over a day with older readings', () {
      final now = DateTime(2026, 9, 19, 14);
      expect(
        tileBpm(now: now, [
          day('2026-09-18', {
            'heart_rate': {
              'source': 'apple_health',
              'entries': [
                {
                  'bpm': 120,
                  'timestamp': Timestamp.fromDate(DateTime(2026, 9, 18, 13)),
                },
              ],
            },
          }),
          day('2026-09-19', {
            'heart_rate_scan': {
              'source': 'camera_ppg',
              'entries': [
                {
                  'bpm': 66,
                  'timestamp': Timestamp.fromDate(DateTime(2026, 9, 19, 9)),
                },
              ],
            },
          }),
        ]),
        66,
      );
    });
  });
}
