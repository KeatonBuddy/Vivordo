import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/heart_rate_history.dart';

void main() {
  test('preserves Apple and WHOOP history and prefers WHOOP per minute', () {
    final day = DateTime(2026, 8, 19);
    final atNine = DateTime(2026, 8, 19, 9);
    final atTen = DateTime(2026, 8, 19, 10);
    final atEleven = DateTime(2026, 8, 19, 11);
    final result = mergedHeartRateHistory({
      // Apple has become canonical after the live WHOOP reading went stale.
      'heart_rate': {
        'source': 'apple_health',
        'entries': [
          {'bpm': 70, 'timestamp': Timestamp.fromDate(atNine)},
          {'bpm': 72, 'timestamp': Timestamp.fromDate(atTen)},
        ],
      },
      'heart_rate_sources': {
        'apple_health': {
          'source': 'apple_health',
          'entries': [
            {'bpm': 70, 'timestamp': Timestamp.fromDate(atNine)},
            {'bpm': 72, 'timestamp': Timestamp.fromDate(atTen)},
          ],
        },
        'whoop_ble': {
          'source': 'whoop_ble',
          'entries': [
            // This collision must replace Apple's 10:00 value.
            {'bpm': 88, 'timestamp': Timestamp.fromDate(atTen)},
            {'bpm': 90, 'timestamp': Timestamp.fromDate(atEleven)},
          ],
        },
      },
    }, fallbackDate: day);

    expect(result.map((reading) => reading.timestamp), [
      atNine,
      atTen,
      atEleven,
    ]);
    expect(result.map((reading) => reading.bpm), [70, 88, 90]);
  });

  test('averages multiple samples from one source within a minute', () {
    final minute = DateTime(2026, 8, 19, 10, 4);
    final result = mergedHeartRateHistory({
      'heart_rate_sources': {
        'apple_health': {
          'entries': [
            {'bpm': 70, 'timestamp': Timestamp.fromDate(minute)},
            {
              'bpm': 80,
              'timestamp': Timestamp.fromDate(
                minute.add(const Duration(seconds: 30)),
              ),
            },
          ],
        },
      },
    }, fallbackDate: DateTime(2026, 8, 19));

    expect(result, hasLength(1));
    expect(result.single.bpm, 75);
  });

  test('can exclude daily summaries when timestamped history is required', () {
    final day = DateTime(2026, 8, 19);
    final result = mergedHeartRateHistory(
      {
        'heart_rate': {
          'avg': 64,
          'syncedAt': Timestamp.fromDate(day.add(const Duration(hours: 8))),
        },
      },
      fallbackDate: day,
      includeDailyFallback: false,
    );

    expect(result, isEmpty);
  });
}
