import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/daily_brief_metrics.dart';
import 'package:vivordo_health/src/utils/home_metrics_summary.dart';
import 'package:vivordo_health/src/utils/home_stress_card_logic.dart';
import 'package:vivordo_health/src/utils/screen_metric_projection.dart';

Object? field(Map<String, dynamic> data, String path) {
  Object? value = data;
  for (final part in path.split('.')) {
    if (value is! Map) return null;
    value = value[part];
  }
  return value;
}

void expectBrief(
  DailyBriefMetricsSummary actual,
  DailyBriefMetricsSummary expected,
) {
  expect(actual.sleep, expected.sleep);
  expect(actual.usualSleep, expected.usualSleep);
  expect(actual.capacity.score, expected.capacity.score);
  expect(actual.capacity.label, expected.capacity.label);
  expect(actual.capacity.availableSignals, expected.capacity.availableSignals);
  expect(actual.capacityNote, expected.capacityNote);
  expect(actual.stale, expected.stale);
  expect(actual.stressTime, expected.stressTime);
  expect(actual.healthTime, expected.healthTime);
  expect(actual.priorNights, expected.priorNights);
  expect(actual.isFromCache, expected.isFromCache);
}

void main() {
  Map<String, dynamic> sample(int bpm, int minute, {int second = 0}) => {
    'bpm': bpm,
    'timestamp': DateTime(2026, 9, 24, 14, minute, second),
  };
  Map<String, dynamic> metric(String source, List<dynamic> entries) => {
    'source': source,
    'entries': entries,
  };

  test(
    'Home tiles read only display fields and preserve drivers and missing/zero',
    () {
      final data = <String, dynamic>{
        'stress': {
          'current': 40,
          'avg': 30,
          'computedAt': Timestamp(1, 0),
          'entries': List.filled(10000, {'score': 100}),
          'top_drivers': [
            {'signal': 'calendar', 'reason_code': 'busy_day'},
            {'name': 'sleep', 'direction': 'below', 'weight': 0.4},
          ],
        },
        'steps': {
          'sum': 0,
          'entries': List.filled(10000, {'value': 100}),
        },
        'mood': {'label': 'Good', 'avg': 75},
      };
      final reads = <String>[];
      final projected = projectScreenFields(
        (path) {
          reads.add(path);
          return field(data, path);
        },
        MetricsProjection.homeToday,
        isToday: true,
      );
      expect(reads.any((path) => path.endsWith('.entries')), false);
      expect(projected['steps']['sum'], 0);
      expect(projected['sleep'], isNull);
      expect(projected['mood'], data['mood']);
      expect(projected['stress']['computedAt'], Timestamp(1, 0));
      expect(
        homeStressDrivers(
          projected['stress']['top_drivers'],
        ).map((d) => d.label),
        homeStressDrivers(data['stress']['top_drivers']).map((d) => d.label),
      );
      expect(() => projected['stress']['current'] = 99, throwsUnsupportedError);
    },
  );

  final fixtures = <Map<String, dynamic>>[
    {},
    {
      'heart_rate': metric('apple_health', [
        sample(60, 1),
        sample(80, 1, second: 10),
      ]),
    },
    {
      'heart_rate': metric('apple_health', [sample(1, 59)]),
      'heart_rate_sources': {
        'apple_health': metric('apple_health', [sample(72, 1), sample(74, 3)]),
        'whoop_ble': metric('whoop_ble', [
          sample(80, 1),
          sample(100, 1, second: 15),
        ]),
        'fitbit_ble': metric('fitbit_ble', [sample(88, 2)]),
      },
      'heart_rate_scan': metric('camera_ppg', [sample(78, 3)]),
    },
    {
      'heart_rate': metric('apple_health', [sample(99, 5)]),
      'heart_rate_sources': {'apple_health': <String, dynamic>{}},
    },
    {
      'heart_rate': {
        'source': 'whoop_ble',
        'avg': 90,
        'lastReadingAt': DateTime(2026, 9, 24, 14),
      },
      'heart_rate_sources': {
        'apple_health': {
          'source': 'apple_health',
          'avg': 70,
          'syncedAt': DateTime(2026, 9, 24, 14, 1),
        },
      },
    },
    {
      'heart_rate': metric('camera_ppg', [
        {'bpm': 70, 'timestamp': 'invalid'},
        {'bpm': 80},
        null,
        {'value': 99},
      ]),
    },
  ];
  for (var i = 0; i < fixtures.length; i++) {
    test('prepared heart candidates match legacy resolution: fixture $i', () {
      final data = fixtures[i];
      final prepared = projectHeartRate(
        (path) => field(data, path),
        '2026-09-24',
      );
      for (final minute in [0, 2, 5, 6, 7, 8, 30]) {
        final now = DateTime(2026, 9, 24, 14, minute);
        final expected = summarizeHomeMetrics(
          days: [MetricDayEntry(dayKey: '2026-09-24', data: data)],
          now: now,
        ).latestHeartRate;
        final actual = prepared.at(now);
        expect(actual?.bpm, expected?.bpm);
        expect(actual?.timestamp, expected?.timestamp);
        expect(actual?.source, expected?.source);
      }
    });
  }

  test(
    'stress preparation matches filter/sort across times, ties and nanoseconds',
    () {
      final base = DateTime(2026, 9, 23, 10);
      final raw = <dynamic>[
        for (var n = 0; n < 160; n++)
          {
            'timestamp': Timestamp.fromDate(base.add(Duration(minutes: n * 3))),
            'score': n % 2 == 0 ? n.toDouble() : null,
          },
        {'timestamp': Timestamp.fromDate(base), 'score': 99},
        {
          'timestamp': Timestamp(Timestamp.fromDate(base).seconds, 1),
          'score': 98,
        },
        {'timestamp': 'not a timestamp', 'score': 50},
        null,
      ].reversed.toList();
      final prepared = PreparedStressHistory(raw);
      for (var minute = -1; minute < 800; minute += 7) {
        final cutoff = base.add(Duration(minutes: minute));
        final legacy =
            raw
                .whereType<Map>()
                .where(
                  (e) =>
                      e['timestamp'] is Timestamp &&
                      !(e['timestamp'] as Timestamp).toDate().isAfter(cutoff) &&
                      cutoff.difference(
                            (e['timestamp'] as Timestamp).toDate(),
                          ) <=
                          const Duration(hours: 2),
                )
                .toList()
              ..sort(
                (a, b) => (b['timestamp'] as Timestamp).compareTo(
                  a['timestamp'] as Timestamp,
                ),
              );
        expect(
          prepared.at(cutoff),
          legacy.isEmpty ? null : legacy.first['score'],
        );
      }
      expect(() => prepared.entries.clear(), throwsUnsupportedError);
    },
  );

  test(
    'prepared My Day inputs preserve baselines, freshness and clock rollover',
    () {
      final raw = <MetricDayEntry>[];
      final compact = <MetricDayEntry>[];
      for (var n = 1; n <= 24; n++) {
        final key = '2026-09-${n.toString().padLeft(2, '0')}';
        final data = <String, dynamic>{
          if (n % 5 != 0) 'sleep': {'avg': n == 24 ? 6.0 : 8.0},
          'stress': {
            'current': 40,
            'avg': 42,
            'anchor': 35,
            'algorithm_version': n < 4 ? 'old' : 'v1',
            'computedAt': Timestamp.fromDate(DateTime(2026, 9, n, 14)),
            'entries': [
              for (var hour = 8; hour <= 18; hour++)
                {
                  'timestamp': Timestamp.fromDate(DateTime(2026, 9, n, hour)),
                  'score': hour * 3,
                },
            ],
          },
          if (n == 24) ...fixtures[2],
        };
        raw.add(MetricDayEntry(dayKey: key, data: data));
        final reads = <String>[];
        final projected = projectScreenFields(
          (path) {
            reads.add(path);
            return field(data, path);
          },
          MetricsProjection.dailyBrief,
          isToday: n == 24,
        );
        expect(reads.any((p) => p.startsWith('heart_rate')), false);
        if (n == 24) expect(reads.contains('stress.entries'), false);
        compact.add(
          MetricDayEntry(
            dayKey: key,
            data: {
              ...projected,
              if (n == 24)
                preparedHeartKey: projectHeartRate((p) => field(data, p), key),
            },
          ),
        );
      }
      final old = DailyBriefMetrics(raw, isFromCache: true);
      final next = DailyBriefMetrics(compact, isFromCache: true);
      for (final hour in [8, 12, 14, 15, 18, 23]) {
        final now = DateTime(2026, 9, 24, hour, 12);
        expectBrief(next.summarize(now), old.summarize(now));
      }
      final tomorrow = DateTime(2026, 9, 25);
      expectBrief(next.summarize(tomorrow), old.summarize(tomorrow));
    },
  );

  test('large irrelevant histories are never traversed by screen projections', () {
    final data = <String, dynamic>{
      for (final name in [
        'steps',
        'active_calories',
        'exercise_time',
        'hrv',
        'sleep',
      ])
        name: {
          'sum': 123,
          'avg': 8,
          'entries': List.generate(
            3000,
            (i) => {
              'timestamp': Timestamp(i, 0),
              'value': i,
              'source': 'apple_health',
            },
          ),
        },
      'stress': {
        'current': 40,
        'avg': 35,
        'entries': List.generate(
          100,
          (i) => {'timestamp': Timestamp(i, 0), 'score': i},
        ),
      },
    };
    var visited = 0;
    dynamic decode(Object? value, {bool freeze = false}) {
      visited++;
      if (value is Map) {
        final result = value.map(
          (k, v) => MapEntry(k as String, decode(v, freeze: freeze)),
        );
        return freeze ? Map<String, dynamic>.unmodifiable(result) : result;
      }
      if (value is List) {
        final result = value.map((v) => decode(v, freeze: freeze)).toList();
        return freeze ? List.unmodifiable(result) : result;
      }
      return value;
    }

    final oldTimer = Stopwatch()..start();
    for (var day = 0; day < 29; day++) {
      // Model the removed doc.data() conversion followed by recursive freeze.
      decode(decode(data), freeze: true);
    }
    oldTimer.stop();
    final legacyVisits = visited;
    visited = 0;
    final newTimer = Stopwatch()..start();
    for (var day = 0; day < 29; day++) {
      projectScreenFields(
        (p) => decode(field(data, p)),
        MetricsProjection.dailyBrief,
        isToday: day == 28,
      );
    }
    newTimer.stop();
    expect(visited, lessThan(legacyVisits ~/ 50));
    // Diagnostic only: CI timing is not a phone performance guarantee.
    // ignore: avoid_print
    print(
      'Synthetic 29-day projection: legacy ${oldTimer.elapsedMilliseconds} ms / '
      '$legacyVisits visited values; compact ${newTimer.elapsedMilliseconds} ms / $visited values',
    );
  });
}
