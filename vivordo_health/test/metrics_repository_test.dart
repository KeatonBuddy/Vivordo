import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/metrics_repository.dart';
import 'package:vivordo_health/src/utils/daily_brief_metrics.dart';
import 'package:vivordo_health/src/utils/home_metrics_summary.dart';
import 'package:vivordo_health/src/utils/screen_metric_projection.dart';

Future<void> settle() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeFirebaseFirestore db;
  late MetricsRepository repository;
  const day = '2026-09-24';
  Stream<MetricWindow> watch({
    String start = day,
    MetricsProjection projection = MetricsProjection.activity,
  }) => repository.watch(
    uid: 'a',
    startDay: start,
    endDay: day,
    projection: projection,
  );
  setUp(() async {
    db = FakeFirebaseFirestore();
    repository = MetricsRepository(firestore: db, uid: 'a');
    await db.doc('users/a/metrics_daily/$day').set({
      'steps': {'sum': 100},
      'heart_rate': {
        'entries': [1, 2],
      },
    });
  });
  tearDown(() => repository.dispose());

  test(
    'shares exact queries and cancels only after the last consumer',
    () async {
      final a = <MetricWindow>[];
      final b = <MetricWindow>[];
      final first = watch().listen(a.add);
      final second = watch().listen(b.add);
      await settle();
      expect(repository.activeSubscriptions, 1);
      expect(a.last.days[day]!['steps']['sum'], 100);
      expect(identical(a.last.days, b.last.days), isTrue);
      await first.cancel();
      expect(repository.activeSubscriptions, 1);
      await second.cancel();
      expect(repository.activeSubscriptions, 0);
    },
  );

  test(
    'activity ignores unrelated fields; edits and deletions are delivered',
    () async {
      final values = <MetricWindow>[];
      final sub = watch().listen(values.add);
      await settle();
      final old = values.last.days;
      final count = values.length;
      await db.doc('users/a/metrics_daily/$day').update({
        'heart_rate.entries': [3, 4],
      });
      await settle();
      expect(values.length, count);
      expect(identical(values.last.days, old), isTrue);
      await db.doc('users/a/metrics_daily/$day').update({'steps.sum': 120});
      await settle();
      expect(values.last.days[day]!['steps']['sum'], 120);
      await db.doc('users/a/metrics_daily/$day').delete();
      await settle();
      expect(values.last.days, isEmpty);
      await sub.cancel();
    },
  );

  test('replays cached data then reconciles deletions while hidden', () async {
    final stream = watch();
    var sub = stream.listen((_) {});
    await settle();
    await sub.cancel();
    await db.doc('users/a/metrics_daily/$day').delete();
    final values = <MetricWindow>[];
    sub = stream.listen(values.add);
    await settle();
    expect(values.first.days, isNotEmpty);
    expect(values.first.refreshing, isTrue);
    expect(values.last.days, isEmpty);
    expect(values.last.refreshing, isFalse);
    await sub.cancel();
  });

  test('evicted windows can reconnect through their original stream', () async {
    final original = watch();
    var sub = original.listen((_) {});
    await settle();
    await sub.cancel();
    for (var day = 1; day <= 8; day++) {
      sub = watch(
        start: '2026-09-${day.toString().padLeft(2, '0')}',
      ).listen((_) {});
      await settle();
      await sub.cancel();
    }
    final values = <MetricWindow>[];
    sub = original.listen(values.add);
    await settle();
    expect(values.last.days, isNotEmpty);
    await sub.cancel();
  });

  test(
    'account switch clears existing consumers and rejects old streams',
    () async {
      final original = watch();
      final values = <MetricWindow>[];
      final sub = original.listen(values.add);
      await settle();
      repository.switchAccount('b');
      await settle();
      expect(values.last.days, isEmpty);
      expect((await original.first).days, isEmpty);
      expect(repository.activeSubscriptions, 0);
      await sub.cancel();
    },
  );

  test('home tiles keep immutable scalars without raw sensor arrays', () async {
    final value = await watch(projection: MetricsProjection.homeToday).first;
    expect(value.days[day]!['steps']['sum'], 100);
    expect(value.days[day]!.containsKey('heart_rate'), false);
    expect(() => value.days[day]!['steps']['sum'] = 3, throwsUnsupportedError);
  });

  test(
    'projection errors retain cached totals and recovery clears error',
    () async {
      final document = db.doc('users/a/metric_summaries_daily/$day');
      await document.set({
        'schemaVersion': 1,
        'steps': {'sum': 50},
      });
      final values = <MetricWindow>[];
      final sub = repository
          .watch(
            uid: 'a',
            startDay: day,
            endDay: day,
            projection: MetricsProjection.activity,
            useSummaries: true,
          )
          .listen(values.add);
      await settle();
      await document.update({'schemaVersion': 2});
      await settle();
      expect(values.last.error, isA<StateError>());
      expect(values.last.days[day]!['steps']['sum'], 50);
      expect(values.last.isFromCache, isTrue);
      await document.update({'schemaVersion': 1});
      await settle();
      expect(values.last.error, isNull);
      expect(values.last.days[day]!['steps']['sum'], 50);
      await sub.cancel();
    },
  );

  test(
    'immutable repository data preserves Home and My Day calculations',
    () async {
      final raw = <MetricDayEntry>[];
      final now = DateTime(2026, 9, 24, 14);
      for (var n = 17; n <= 24; n++) {
        final data = <String, dynamic>{
          'sleep': {'avg': n == 24 ? 6.0 : 8.0},
          'stress': {
            'current': 40,
            'avg': 42,
            'anchor': 35,
            'algorithm_version': 'v1',
            'computedAt': Timestamp.fromDate(DateTime(2026, 9, n, 13)),
            'entries': [
              {
                'timestamp': Timestamp.fromDate(DateTime(2026, 9, n, 15)),
                'score': 90,
              },
              {
                'timestamp': Timestamp.fromDate(DateTime(2026, 9, n, 13)),
                'score': 40,
              },
            ],
          },
        };
        final key = '2026-09-$n';
        raw.add(MetricDayEntry(dayKey: key, data: data));
        await db.doc('users/a/metrics_daily/$key').set(data);
      }
      final homeWindow = await watch(
        start: '2026-09-17',
        projection: MetricsProjection.homeHistory,
      ).first;
      final briefWindow = await watch(
        start: '2026-09-17',
        projection: MetricsProjection.dailyBrief,
      ).first;
      final projected = homeWindow.days.entries
          .map((e) => MetricDayEntry(dayKey: e.key, data: e.value))
          .toList();
      final oldHome = summarizeHomeMetrics(days: raw, now: now);
      final newHome = summarizeHomeMetrics(days: projected, now: now);
      expect(newHome.stressAnchor, oldHome.stressAnchor);
      expect(newHome.sevenDayStressAverage, oldHome.sevenDayStressAverage);
      final oldBrief = DailyBriefMetrics(raw).summarize(now);
      final newBrief = DailyBriefMetrics(
        briefWindow.days.entries
            .map((e) => MetricDayEntry(dayKey: e.key, data: e.value))
            .toList(),
      ).summarize(now);
      expect(newBrief.capacity.score, oldBrief.capacity.score);
      expect(newBrief.capacityNote, oldBrief.capacityNote);
      expect(newBrief.usualSleep, oldBrief.usualSleep);
      expect(newBrief.priorNights, oldBrief.priorNights);
      expect(newBrief.stressTime, oldBrief.stressTime);
      expect(newBrief.stale, oldBrief.stale);
    },
  );

  test(
    'summary rollout falls back unless enabled and completely backfilled',
    () async {
      final value = await repository
          .watchActivity(
            uid: 'a',
            startDay: day,
            endDay: day,
            allowSummaries: true,
          )
          .first;
      expect(value.days[day]!['steps']['sum'], 100);
    },
  );

  test(
    'verified activity summary is used without a legacy subscription',
    () async {
      await db.doc('users/a/metrics_summary_migrations/v1').set({
        'enabled': true,
        'schemaVersion': 1,
        'status': 'complete',
        'startDay': day,
        'endDay': day,
      });
      await db.doc('users/a/metric_summaries_daily/$day').set({
        'schemaVersion': 1,
        'steps': {'sum': 999},
      });
      final values = <MetricWindow>[];
      final sub = repository
          .watchActivity(
            uid: 'a',
            startDay: day,
            endDay: day,
            allowSummaries: true,
          )
          .listen(values.add);
      await settle();
      expect(values.last.days[day]!['steps']['sum'], 999);
      expect(repository.activeSubscriptions, 1);
      await sub.cancel();
    },
  );

  test('incompatible summary falls back and keeps only one listener', () async {
    await db.doc('users/a/metrics_summary_migrations/v1').set({
      'enabled': true,
      'schemaVersion': 1,
      'status': 'complete',
      'startDay': day,
      'endDay': day,
    });
    await db.doc('users/a/metric_summaries_daily/$day').set({
      'schemaVersion': 2,
      'steps': {'sum': 999},
    });
    final values = <MetricWindow>[];
    final sub = repository
        .watchActivity(
          uid: 'a',
          startDay: day,
          endDay: day,
          allowSummaries: true,
        )
        .listen(values.add);
    await settle();
    expect(values.last.days[day]!['steps']['sum'], 100);
    expect(repository.activeSubscriptions, 1);
    await db.doc('users/a/metrics_daily/$day').update({'steps.sum': 200});
    await settle();
    expect(values.last.days[day]!['steps']['sum'], 200);
    await sub.cancel();
  });

  test(
    'coverage ending yesterday cannot replace current-day legacy data',
    () async {
      await db.doc('users/a/metrics_summary_migrations/v1').set({
        'enabled': true,
        'schemaVersion': 1,
        'status': 'complete',
        'startDay': '2026-09-01',
        'endDay': '2026-09-23',
      });
      final value = await repository
          .watchActivity(
            uid: 'a',
            startDay: day,
            endDay: day,
            allowSummaries: true,
          )
          .first;
      expect(value.days[day]!['steps']['sum'], 100);
    },
  );

  test(
    'tile projection ignores unrelated history but publishes corrected totals',
    () async {
      final values = <MetricWindow>[];
      final sub = watch(
        projection: MetricsProjection.homeToday,
      ).listen(values.add);
      await settle();
      final old = values.last.days;
      await db.doc('users/a/metrics_daily/$day').update({
        'heart_rate.entries': [2, 3],
      });
      await settle();
      expect(identical(old, values.last.days), isTrue);
      await db.doc('users/a/metrics_daily/$day').update({'steps.sum': 200});
      await settle();
      expect(values.last.days[day]!['steps']['sum'], 200);
      expect(old[day]!['steps']['sum'], 100);
      await sub.cancel();
    },
  );

  test(
    'Home history reconciles latest-day corrections and deletions',
    () async {
      Map<String, dynamic> heart(int bpm) => {
        'heart_rate': {
          'source': 'apple_health',
          'entries': [
            {
              'bpm': bpm,
              'timestamp': Timestamp.fromDate(DateTime(2026, 9, 24, 12)),
            },
          ],
        },
      };
      await db.doc('users/a/metrics_daily/2026-09-23').set(heart(60));
      await db.doc('users/a/metrics_daily/$day').set(heart(70));
      final values = <MetricWindow>[];
      final sub = watch(
        start: '2026-09-23',
        projection: MetricsProjection.homeHistory,
      ).listen(values.add);
      await settle();
      expect(
        (values.last.days[day]![preparedHeartKey] as PreparedHeartRate)
            .latest!
            .bpm,
        70,
      );
      expect(
        values.last.days['2026-09-23']!.containsKey(preparedHeartKey),
        false,
      );
      await db.doc('users/a/metrics_daily/$day').set(heart(80));
      await settle();
      expect(
        (values.last.days[day]![preparedHeartKey] as PreparedHeartRate)
            .latest!
            .bpm,
        80,
      );
      await db.doc('users/a/metrics_daily/$day').delete();
      await settle();
      expect(
        (values.last.days['2026-09-23']![preparedHeartKey] as PreparedHeartRate)
            .latest!
            .bpm,
        60,
      );
      await db.doc('users/a/metrics_daily/$day').set(heart(90));
      await settle();
      expect(
        values.last.days['2026-09-23']!.containsKey(preparedHeartKey),
        false,
      );
      expect(
        (values.last.days[day]![preparedHeartKey] as PreparedHeartRate)
            .latest!
            .bpm,
        90,
      );
      await sub.cancel();
    },
  );
}
