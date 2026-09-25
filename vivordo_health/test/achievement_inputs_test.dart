import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/achievement_inputs.dart';
import 'package:vivordo_health/src/services/achievement_service.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';

Object? field(Map<String, dynamic> data, String path) {
  Object? value = data;
  for (final part in path.split('.')) {
    value = value is Map ? value[part] : null;
  }
  return value;
}

Future<void> settle() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('legacy and entry counts match existing mood/ring rules', () {
    final days = <Map<String, dynamic>>[
      {},
      {'mood': {}, 'heart_rate_scan': {}},
      {
        'mood': {'avg': 0},
        'heart_rate_scan': {'source': 'camera_ppg'},
      },
      {
        'mood': {'label': 'Good', 'entries': []},
        'heart_rate_scan': {'avg': 0},
      },
      {
        'mood': {
          'avg': 2,
          'entries': [1, 2],
        },
        'heart_rate_scan': {
          'avg': 60,
          'entries': [1, 2, 3],
        },
      },
      {
        'steps': {'sum': 12000},
        'active_calories': {'sum': 600},
        'exercise_time': {'sum': 60},
      },
      {
        'steps': {'sum': 12000},
        'active_calories': {'sum': 800},
        'exercise_time': {'sum': 60},
      },
    ];
    final inputs = AchievementInputs({
      for (var i = 0; i < days.length; i++)
        '$i': projectAchievementDay((path) => field(days[i], path)),
    }, {});
    expect(inputs.moods, countMoodCheckIns(metricDays: days));
    expect(inputs.scans, 5);
    for (final calories in [500, 700, 900]) {
      final goals = ActivityGoals(activeCalories: calories);
      expect(
        inputs.ringDays(goals),
        countCompletedActivityRingDays(metricDays: days, goals: goals),
      );
    }
    expect(() => inputs.days.clear(), throwsUnsupportedError);
  });

  test('projects only required fields, never raw unrelated histories', () {
    final reads = <String>[];
    projectAchievementDay((path) {
      reads.add(path);
      return null;
    });
    expect(reads, isNot(contains('heart_rate.entries')));
    expect(reads, isNot(contains('stress.entries')));
    expect(reads.every((path) => path.contains('.')), isTrue);
  });

  test('workout categories preserve mixed and legacy classification', () {
    final cases = <(Map<String, dynamic>, bool)>[
      ({}, false),
      ({'activityCategory': 'Cardio'}, true),
      ({'activityCategory': 'Sports'}, true),
      (
        {
          'exercises': [
            {'category': 'Cardio'},
            {'category': 'Sports'},
          ],
        },
        true,
      ),
      (
        {
          'exercises': [
            {'category': 'Cardio'},
            {'category': 'Strength'},
          ],
        },
        false,
      ),
      (
        {
          'exercises': [null, 1],
        },
        false,
      ),
      (
        {
          'exercises': [
            null,
            {'category': 'Sports'},
          ],
        },
        true,
      ),
    ];
    for (final (data, expected) in cases) {
      expect(projectAchievementWorkout((path) => field(data, path)), expected);
    }
  });

  group('shared inputs', () {
    late FakeFirebaseFirestore db;
    late AchievementInputsRepository repository;
    setUp(() {
      db = FakeFirebaseFirestore();
    });
    tearDown(() async {
      await repository.dispose();
    });

    test(
      'empty history is ready and shared loads return the same snapshot',
      () async {
        repository = AchievementInputsRepository(db, 'a');
        final results = await Future.wait([
          repository.load(),
          repository.load(),
        ]);
        expect(identical(results[0], results[1]), isTrue);
        expect(results.first.days, isEmpty);
        expect(results.first.workoutCount, 0);
      },
    );

    test(
      'lifetime history, edits, deletion and recreation are retained correctly',
      () async {
        final doc = db.doc('users/a/metrics_daily/2020-01-01');
        await doc.set({
          'mood': {
            'entries': [1, 2],
          },
          'steps': {'sum': 10},
        });
        repository = AchievementInputsRepository(db, 'a');
        final initial = await repository.load();
        expect(initial.moods, 2);
        await doc.update({
          'mood.entries': [1],
        });
        await settle();
        expect((await repository.load()).moods, 1);
        expect(initial.moods, 2); // Prior snapshots never mutate.
        await doc.delete();
        await settle();
        expect((await repository.load()).days, isEmpty);
        await doc.set({
          'heart_rate_scan': {'source': 'camera_ppg'},
        });
        await settle();
        expect((await repository.load()).scans, 1);
      },
    );

    test(
      'unrelated sensor and workout edits do not invalidate inputs',
      () async {
        final day = db.doc('users/a/metrics_daily/2026-09-25');
        final workout = db.doc('users/a/workouts/w');
        await day.set({
          'steps': {'sum': 42},
        });
        await workout.set({'activityCategory': 'Cardio', 'name': 'Run'});
        repository = AchievementInputsRepository(db, 'a');
        final initial = await repository.load();
        final changes = <bool>[];
        final sub = repository.changes.listen(changes.add);
        await day.update({
          'heart_rate.entries': List.filled(1000, 80),
          'stress.current': 60,
        });
        await workout.update({'name': 'Morning run'});
        await settle();
        expect(identical(initial, await repository.load()), isTrue);
        expect(changes.where((changed) => changed), isEmpty);
        await sub.cancel();
      },
    );

    test('workout edits and deletion update classification', () async {
      final workout = db.doc('users/a/workouts/w');
      await workout.set({
        'exercises': [
          {'category': 'Strength'},
        ],
      });
      repository = AchievementInputsRepository(db, 'a');
      expect((await repository.load()).cardioCount, 0);
      await workout.update({'activityCategory': 'Sports'});
      await settle();
      expect((await repository.load()).cardioCount, 1);
      await workout.delete();
      await settle();
      expect((await repository.load()).workoutCount, 0);
    });

    test(
      'goal changes recalculate ring days without changing stored inputs',
      () async {
        await db.doc('users/a/metrics_daily/2020-01-01').set({
          'steps': {'sum': 11000},
          'active_calories': {'sum': 600},
          'exercise_time': {'sum': 60},
        });
        repository = AchievementInputsRepository(db, 'a');
        final inputs = await repository.load();
        expect(inputs.ringDays(const ActivityGoals()), 0);
        expect(inputs.ringDays(const ActivityGoals(activeCalories: 500)), 1);
        expect(identical(inputs, await repository.load()), isTrue);
      },
    );

    test(
      'disposal rejects further reads and another account is isolated',
      () async {
        await db.doc('users/a/metrics_daily/2020-01-01').set({
          'mood': {'avg': 50},
        });
        repository = AchievementInputsRepository(db, 'a');
        expect((await repository.load()).moods, 1);
        await repository.dispose();
        await expectLater(repository.load(), throwsStateError);
        repository = AchievementInputsRepository(db, 'b');
        expect((await repository.load()).moods, 0);
      },
    );

    test(
      'malformed input surfaces an error and a corrected snapshot recovers',
      () async {
        final doc = db.doc('users/a/metrics_daily/2026-09-25');
        await doc.set({
          'steps': {'sum': 'invalid'},
        });
        repository = AchievementInputsRepository(db, 'a');
        await expectLater(repository.load(), throwsA(isA<TypeError>()));
        await doc.update({'steps.sum': 100});
        await settle();
        expect((await repository.load()).days.values.single.steps, 100);
      },
    );
  });

  test(
    'overlapping requests coalesce and rerun using the newest inputs',
    () async {
      var calls = 0, value = 1;
      final release = Completer<void>();
      final queue = AchievementReconciliationQueue<int>(() async {
        calls++;
        final captured = value;
        if (calls == 1) await release.future;
        return captured;
      });
      final first = queue.request();
      await settle();
      value = 2;
      final second = queue.request();
      final third = queue.request();
      expect(identical(first, second), isTrue);
      expect(identical(second, third), isTrue);
      release.complete();
      expect(await first, 2);
      expect(calls, 2);
    },
  );

  test(
    'source updates during a run queue a follow-up without a new caller',
    () async {
      var calls = 0;
      final release = Completer<void>();
      final queue = AchievementReconciliationQueue<int>(() async {
        if (++calls == 1) await release.future;
        return calls;
      });
      final result = queue.request();
      await settle();
      queue.markDirty();
      release.complete();
      expect(await result, 2);
    },
  );

  test(
    'invalidation prevents queued follow-up and rejects new requests',
    () async {
      var calls = 0;
      final release = Completer<void>();
      final queue = AchievementReconciliationQueue<int>(() async {
        calls++;
        await release.future;
        return calls;
      });
      final result = queue.request();
      await settle();
      queue.markDirty();
      queue.valid = false;
      release.complete();
      await result;
      expect(calls, 1);
      await expectLater(queue.request(), throwsStateError);
    },
  );

  test('failed runs release the queue and a later request can retry', () async {
    var calls = 0;
    final queue = AchievementReconciliationQueue<int>(() async {
      if (++calls == 1) throw StateError('offline');
      return calls;
    });
    await expectLater(queue.request(), throwsStateError);
    expect(await queue.request(), 2);
  });

  test(
    'a request during a failed run still receives a trailing attempt',
    () async {
      var calls = 0;
      final release = Completer<void>();
      final queue = AchievementReconciliationQueue<int>(() async {
        if (++calls == 1) {
          await release.future;
          throw StateError('temporary failure');
        }
        return calls;
      });
      final result = queue.request();
      await settle();
      final next = queue.request();
      release.complete();
      expect(await result, 2);
      expect(await next, 2);
      expect(calls, 2);
    },
  );

  test(
    'unchanged progress ignores timestamps and preserved unlock metadata',
    () {
      final fields = <String, dynamic>{
        'progress': 12,
        'tier': 'bronze',
        'completed': false,
      };
      final saved = {
        ...fields,
        'earnedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'earnedTiers': ['bronze'],
      };
      expect(achievementFieldsChanged(saved, fields), isFalse);
      expect(
        achievementFieldsChanged(saved, {...fields, 'progress': 13}),
        isTrue,
      );
      expect(
        achievementFieldsChanged(saved, {...fields, 'tier': 'silver'}),
        isTrue,
      );
      expect(achievementFieldsChanged(null, fields), isTrue);
    },
  );
}
