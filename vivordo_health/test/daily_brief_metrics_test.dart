import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/daily_brief_metrics.dart';
import 'package:vivordo_health/src/utils/daily_outlook_score.dart';
import 'package:vivordo_health/src/utils/home_metrics_summary.dart';

void main() {
  final now = DateTime(2026, 9, 22, 14);
  MetricDayEntry day(int number, {double sleep = 8, String version = 'v1'}) =>
      MetricDayEntry(
        dayKey: '2026-09-${number.toString().padLeft(2, '0')}',
        data: {
          'sleep': {'avg': sleep},
          'stress': {
            'current': 40,
            'algorithm_version': version,
            'computedAt': Timestamp.fromDate(DateTime(2026, 9, number, 13)),
            // Deliberately unsorted, with a future entry that must be ignored.
            'entries': [
              {
                'timestamp': Timestamp.fromDate(DateTime(2026, 9, number, 12)),
                'score': 90,
              },
              {
                'timestamp': Timestamp.fromDate(DateTime(2026, 9, number, 15)),
                'score': 99,
              },
              {
                'timestamp': Timestamp.fromDate(DateTime(2026, 9, number, 13)),
                'score': 40,
              },
            ],
          },
        },
      );

  test(
    'preserves current score, median baseline and matched historical inputs',
    () {
      final metrics = DailyBriefMetrics([
        for (var n = 15; n <= 22; n++) day(n),
      ], isFromCache: true);
      final result = metrics.summarize(now);
      expect(
        result.capacity.score,
        calculateDailyCapacity(sleepHours: 8, stressScore: 40).score,
      );
      expect(result.usualSleep, 8);
      expect(result.priorNights, 7);
      expect(result.capacityNote, 'Near your recent capacity estimate');
      expect(result.stale, false);
      expect(result.isFromCache, true);
      expect(result.stressTime, DateTime(2026, 9, 22, 13));
    },
  );

  test(
    'reuses same-minute summary; clock advances freshness without new data',
    () {
      final metrics = DailyBriefMetrics([day(22)]);
      final first = metrics.summarize(now);
      expect(
        identical(
          first,
          metrics.summarize(now.add(const Duration(seconds: 30))),
        ),
        true,
      );
      final later = metrics.summarize(now.add(const Duration(hours: 2)));
      expect(identical(first, later), false);
      expect(later.stale, true);
    },
  );

  test('new snapshot invalidates cache even in the same minute', () {
    final before = DailyBriefMetrics([day(22)]).summarize(now);
    final after = DailyBriefMetrics([day(22, sleep: 4)]).summarize(now);
    expect(after.capacity.score, lessThan(before.capacity.score!));
  });

  test('requires seven compatible historical days for capacity comparison', () {
    final metrics = DailyBriefMetrics([
      for (var n = 15; n <= 21; n++) day(n, version: n == 15 ? 'old' : 'v1'),
      day(22),
    ]);
    expect(
      metrics.summarize(now).capacityNote,
      'Building your capacity baseline',
    );
  });

  test('missing data and day rollover never reuse yesterday as current', () {
    final empty = DailyBriefMetrics([]).summarize(now);
    expect(empty.capacity.score, isNull);
    expect(empty.stale, true);
    final metrics = DailyBriefMetrics([day(22)]);
    metrics.summarize(now);
    final tomorrow = metrics.summarize(DateTime(2026, 9, 23));
    expect(tomorrow.capacity.score, isNull);
    expect(tomorrow.sleep, isNull);
  });
}
