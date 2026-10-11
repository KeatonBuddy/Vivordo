import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/fitness_activity_history.dart';
import 'package:vivordo_health/src/utils/fitness_goal_insight.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';

void main() {
  const today = '2026-09-24';
  const yesterday = '2026-09-23';
  const totals = (steps: 100, calories: 200, minutes: 30);

  test('unchanged totals retain identity and skip downstream emission', () {
    final cache = FitnessActivityHistory();
    final first = cache.update([today], {today: totals});
    // A heart-rate-only update still appears as a changed Firestore document.
    expect(identical(cache.update([today], {today: totals}), first), isTrue);
    expect(identical(cache.update([today], {}), first), isTrue);
    final next = cache.update(
      [today],
      {today: (steps: 101, calories: 200, minutes: 30)},
    );
    expect(identical(next, first), isFalse);
    expect(next[today]!['steps']['sum'], 101);
    expect(first[today]!['steps']['sum'], 100);
  });

  test('incremental additions and removals preserve other days', () {
    final cache = FitnessActivityHistory();
    cache.update([yesterday], {yesterday: totals});
    final added = cache.update(
      [yesterday, today],
      {today: (steps: 500, calories: 300, minutes: 40)},
    );
    expect(added[yesterday]!['steps']['sum'], 100);
    final removed = cache.update([today], {});
    expect(removed.keys, [today]);
    expect(removed[today]!['steps']['sum'], 500);
    expect(cache.update([], {}), isEmpty);
  });

  test(
    'reconnect prunes days deleted while hidden, even without removed changes',
    () {
      final cache = FitnessActivityHistory();
      cache.update([yesterday, today], {yesterday: totals, today: totals});
      final resumed = cache.update([today], {today: totals});
      expect(resumed.keys, [today]);
    },
  );

  test('missing stays distinct from zero and caches are isolated', () {
    final cache = FitnessActivityHistory();
    final missing = cache.update(
      [today],
      {today: (steps: null, calories: null, minutes: null)},
    );
    final zero = cache.update(
      [today],
      {today: (steps: 0, calories: 0, minutes: 0)},
    );
    expect(identical(missing, zero), isFalse);
    expect(missing[today]!['steps']['sum'], isNull);
    expect(zero[today]!['steps']['sum'], 0);
    expect(FitnessActivityHistory().update([], {}), isEmpty);
    expect(() => zero[today]!['steps']['sum'] = 20, throwsUnsupportedError);
  });

  test(
    'projected history preserves comparisons and responds to goal changes',
    () {
      final cache = FitnessActivityHistory();
      final days = {
        for (var day = 10; day <= 24; day++) '2026-09-$day': totals,
      };
      final history = cache.update(days.keys, days);
      String insight(ActivityGoals goals) => fitnessGoalInsight(
        history[today],
        goals,
        history: history,
        now: DateTime(2026, 9, 24),
      );
      expect(insight(const ActivityGoals()), contains('are close to'));
      expect(
        insight(const ActivityGoals()),
        isNot(contains('reached all three')),
      );
      expect(
        insight(
          const ActivityGoals(
            steps: 100,
            activeCalories: 200,
            exerciseMinutes: 30,
          ),
        ),
        contains('reached all three'),
      );
    },
  );
}
