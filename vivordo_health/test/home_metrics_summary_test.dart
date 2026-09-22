import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/home_metrics_summary.dart';

MetricDayEntry day(String dayKey, Map<String, dynamic> data) =>
    MetricDayEntry(dayKey: dayKey, data: data);

Map<String, dynamic> stressDay(Map<String, dynamic> stress) => {
  'stress': stress,
};

void main() {
  group('homeMetricsWindowStartKey', () {
    test('counts today as the first of the ninety days', () {
      expect(
        homeMetricsWindowStartKey(DateTime(2026, 9, 18)),
        '2026-06-21',
      );
      expect(
        DateTime(2026, 9, 18).difference(DateTime(2026, 6, 21)).inDays,
        89,
      );
    });

    test('zero-pads so ids sort lexicographically', () {
      expect(homeMetricsWindowStartKey(DateTime(2026, 4, 9)), '2026-01-10');
    });

    test('holds the boundary across a daylight saving change', () {
      // 2026-04-09 minus 89 calendar days spans a spring-forward in most
      // northern-hemisphere zones; Duration-based maths lands a day early.
      final start = homeMetricsWindowStartKey(DateTime(2026, 4, 9));
      expect(start, '2026-01-10');
      expect(homeMetricsWindowStartKey(DateTime(2026, 11, 20)), '2026-08-23');
    });

    test('crosses a year boundary', () {
      expect(homeMetricsWindowStartKey(DateTime(2026, 2, 1)), '2025-11-04');
    });
  });

  group('durationUntilNextLocalDay', () {
    test('measures the gap to the next midnight', () {
      expect(
        durationUntilNextLocalDay(
          DateTime(2026, 9, 18, 23, 30),
          slack: Duration.zero,
        ),
        const Duration(minutes: 30),
      );
    });

    test('adds slack so a timer never fires before the date changes', () {
      expect(
        durationUntilNextLocalDay(DateTime(2026, 9, 18, 23, 59, 59)),
        const Duration(seconds: 2),
      );
    });

    test('a moment past midnight waits out the whole new day', () {
      expect(
        durationUntilNextLocalDay(
          DateTime(2026, 9, 18, 0, 0, 1),
          slack: Duration.zero,
        ),
        const Duration(hours: 23, minutes: 59, seconds: 59),
      );
    });

    test('carries across a month and a year boundary', () {
      expect(
        durationUntilNextLocalDay(
          DateTime(2026, 9, 30, 22),
          slack: Duration.zero,
        ),
        const Duration(hours: 2),
      );
      expect(
        durationUntilNextLocalDay(
          DateTime(2026, 12, 31, 21, 15),
          slack: Duration.zero,
        ),
        const Duration(hours: 2, minutes: 45),
      );
    });

    test('never returns a non-positive wait', () {
      for (final hour in [0, 6, 12, 18, 23]) {
        expect(
          durationUntilNextLocalDay(DateTime(2026, 3, 8, hour, 30)),
          greaterThan(Duration.zero),
        );
      }
    });
  });

  group('seven day stress average', () {
    test('spans today-7 inclusive through yesterday, excluding today', () {
      final summary = summarizeHomeMetrics(
        now: DateTime(2026, 9, 18, 14),
        days: [
          day('2026-09-18', stressDay({'avg': 100})), // today, excluded
          day('2026-09-17', stressDay({'avg': 10})),
          day('2026-09-11', stressDay({'avg': 20})), // today-7, included
          day('2026-09-10', stressDay({'avg': 900})), // older, excluded
        ],
      );
      expect(summary.sevenDayStressAverage, 15);
    });

    test('prefers avg over current, matching the previous definition', () {
      final summary = summarizeHomeMetrics(
        now: DateTime(2026, 9, 18),
        days: [
          day('2026-09-17', stressDay({'avg': 40, 'current': 90})),
          day('2026-09-16', stressDay({'current': 60})),
        ],
      );
      expect(summary.sevenDayStressAverage, 50);
    });

    test('is null rather than zero when no day in range has stress', () {
      final summary = summarizeHomeMetrics(
        now: DateTime(2026, 9, 18),
        days: [day('2026-09-17', {'steps': {'sum': 900}})],
      );
      expect(summary.sevenDayStressAverage, isNull);
    });

    test('skips documents whose id is not a date', () {
      final summary = summarizeHomeMetrics(
        now: DateTime(2026, 9, 18),
        days: [
          day('not-a-date', stressDay({'avg': 999})),
          day('2026-09-17', stressDay({'avg': 30})),
        ],
      );
      expect(summary.sevenDayStressAverage, 30);
    });
  });

  group('stress anchor', () {
    test('takes anchor, then current, then avg from the newest day', () {
      expect(
        summarizeHomeMetrics(
          now: DateTime(2026, 9, 18),
          days: [
            day('2026-09-18', stressDay({'anchor': 41, 'current': 70})),
          ],
        ).stressAnchor,
        41,
      );
      expect(
        summarizeHomeMetrics(
          now: DateTime(2026, 9, 18),
          days: [day('2026-09-18', stressDay({'current': 70}))],
        ).stressAnchor,
        70,
      );
      expect(
        summarizeHomeMetrics(
          now: DateTime(2026, 9, 18),
          days: [day('2026-09-18', stressDay({'avg': 55}))],
        ).stressAnchor,
        55,
      );
    });

    test('falls through days that carry no usable stress value', () {
      final summary = summarizeHomeMetrics(
        now: DateTime(2026, 9, 18),
        days: [
          day('2026-09-18', {'steps': {'sum': 10}}),
          day('2026-09-17', stressDay({'note': 'nothing numeric'})),
          day('2026-09-16', stressDay({'anchor': 33})),
        ],
      );
      expect(summary.stressAnchor, 33);
    });

    test('is null rather than zero when the window holds no stress', () {
      final summary = summarizeHomeMetrics(
        now: DateTime(2026, 9, 18),
        days: [day('2026-09-18', {'steps': {'sum': 10}})],
      );
      expect(summary.stressAnchor, isNull);
    });
  });

  group('latest heart rate', () {
    test('takes the newest timestamped reading in the window', () {
      final summary = summarizeHomeMetrics(
        now: DateTime(2026, 9, 18),
        days: [
          day('2026-09-18', {
            'heart_rate': {
              'source': 'apple_health',
              'entries': [
                {'bpm': 61, 'timestamp': '2026-09-18T08:00:00Z'},
                {'bpm': 74, 'timestamp': '2026-09-18T11:00:00Z'},
              ],
            },
          }),
          day('2026-09-17', {
            'heart_rate': {
              'source': 'apple_health',
              'entries': [
                {'bpm': 99, 'timestamp': '2026-09-17T09:00:00Z'},
              ],
            },
          }),
        ],
      );
      expect(summary.latestHeartRate?.bpm, 74);
    });

    test('is null rather than zero when the window holds no reading', () {
      final summary = summarizeHomeMetrics(
        now: DateTime(2026, 9, 18),
        days: [day('2026-09-18', {'steps': {'sum': 10}})],
      );
      expect(summary.latestHeartRate, isNull);
    });

    test('finds a camera scan saved today', () {
      // The shape scan_screen writes: heart_rate without entries, plus
      // heart_rate_scan carrying one entry per scan.
      final summary = summarizeHomeMetrics(
        now: DateTime(2026, 9, 19, 14),
        days: [
          day('2026-09-19', {
            'heart_rate': {'avg': 72, 'source': 'camera_ppg'},
            'heart_rate_scan': {
              'avg': 72,
              'source': 'camera_ppg',
              'entries': [
                {'bpm': 70, 'timestamp': '2026-09-19T09:00:00Z'},
                {'bpm': 74, 'timestamp': '2026-09-19T13:00:00Z'},
              ],
            },
          }),
        ],
      );
      expect(summary.latestHeartRate?.bpm, 74);
    });
  });

  group('ordering is not borrowed from the query', () {
    // A previous version relied on the Firestore query returning documents
    // newest first. A collection query without an orderBy returns them
    // oldest first, which silently inverted every "latest" lookup.
    final unordered = [
      day('2026-09-16', stressDay({'anchor': 16})),
      day('2026-09-19', stressDay({'anchor': 19})),
      day('2026-09-17', stressDay({'anchor': 17})),
    ];

    test('the newest anchor wins whatever order the days arrive in', () {
      expect(
        summarizeHomeMetrics(
          now: DateTime(2026, 9, 20),
          days: unordered,
        ).stressAnchor,
        19,
      );
      expect(
        summarizeHomeMetrics(
          now: DateTime(2026, 9, 20),
          days: unordered.reversed.toList(),
        ).stressAnchor,
        19,
      );
    });

    test('oldest-first input still yields the newest heart rate', () {
      final oldestFirst = [
        day('2026-09-17', {
          'heart_rate': {
            'source': 'apple_health',
            'entries': [
              {'bpm': 55, 'timestamp': '2026-09-17T09:00:00Z'},
            ],
          },
        }),
        day('2026-09-19', {
          'heart_rate': {
            'source': 'apple_health',
            'entries': [
              {'bpm': 88, 'timestamp': '2026-09-19T09:00:00Z'},
            ],
          },
        }),
      ];
      expect(
        summarizeHomeMetrics(
          now: DateTime(2026, 9, 20),
          days: oldestFirst,
        ).latestHeartRate?.bpm,
        88,
      );
    });

    test('does not mutate the caller\'s list', () {
      final original = [...unordered];
      summarizeHomeMetrics(now: DateTime(2026, 9, 20), days: original);
      expect(original.map((e) => e.dayKey), unordered.map((e) => e.dayKey));
    });
  });

  group('HomeMetricsSummaryCache', () {
    final rows = [day('2026-09-17', stressDay({'anchor': 20}))];
    List<MetricDayEntry> build() => rows;

    test('reuses the summary for an unchanged snapshot, day and account', () {
      final cache = HomeMetricsSummaryCache();
      final snapshot = Object();

      final first = cache.summarize(
        snapshotKey: snapshot,
        dayKey: '2026-09-18',
        uid: 'user-a',
        now: DateTime(2026, 9, 18),
        days: build,
      );
      final second = cache.summarize(
        snapshotKey: snapshot,
        dayKey: '2026-09-18',
        uid: 'user-a',
        now: DateTime(2026, 9, 18),
        days: build,
      );

      expect(cache.computeCount, 1);
      expect(identical(first, second), isTrue);
    });

    test('recomputes when a new snapshot arrives', () {
      final cache = HomeMetricsSummaryCache();
      for (final snapshot in [Object(), Object()]) {
        cache.summarize(
          snapshotKey: snapshot,
          dayKey: '2026-09-18',
          uid: 'user-a',
          now: DateTime(2026, 9, 18),
          days: build,
        );
      }
      expect(cache.computeCount, 2);
    });

    test('recomputes after the local day rolls over', () {
      final cache = HomeMetricsSummaryCache();
      final snapshot = Object();
      cache.summarize(
        snapshotKey: snapshot,
        dayKey: '2026-09-18',
        uid: 'user-a',
        now: DateTime(2026, 9, 18, 23, 59),
        days: build,
      );
      cache.summarize(
        snapshotKey: snapshot,
        dayKey: '2026-09-19',
        uid: 'user-a',
        now: DateTime(2026, 9, 19, 0, 1),
        days: build,
      );
      expect(cache.computeCount, 2);
    });

    test('recomputes when the signed-in account changes', () {
      final cache = HomeMetricsSummaryCache();
      final snapshot = Object();
      cache.summarize(
        snapshotKey: snapshot,
        dayKey: '2026-09-18',
        uid: 'user-a',
        now: DateTime(2026, 9, 18),
        days: build,
      );
      cache.summarize(
        snapshotKey: snapshot,
        dayKey: '2026-09-18',
        uid: 'user-b',
        now: DateTime(2026, 9, 18),
        days: build,
      );
      expect(cache.computeCount, 2);
    });

    test('treats a null snapshot as its own cacheable state', () {
      final cache = HomeMetricsSummaryCache();
      cache.summarize(
        snapshotKey: null,
        dayKey: '2026-09-18',
        uid: 'user-a',
        now: DateTime(2026, 9, 18),
        days: () => const [],
      );
      final second = cache.summarize(
        snapshotKey: null,
        dayKey: '2026-09-18',
        uid: 'user-a',
        now: DateTime(2026, 9, 18),
        days: () => const [],
      );
      expect(cache.computeCount, 1);
      expect(second.latestHeartRate, isNull);
      expect(second.stressAnchor, isNull);
      expect(second.sevenDayStressAverage, isNull);
    });
  });
}
