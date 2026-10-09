import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/utils/fitness_goal_insight.dart';

void main() {
  final now = DateTime(2026, 9, 24, 12);
  Map<String, dynamic> day(num steps, num calories, num minutes) => {
    'steps': {'sum': steps},
    'active_calories': {'sum': calories},
    'exercise_time': {'sum': minutes},
  };
  final history = {
    for (var d = 10; d < 24; d++) '2026-09-$d': day(5000, 500, 30),
  };
  String insight(
    Map<String, dynamic>? data,
    Map<String, Map<String, dynamic>> past,
  ) => fitnessGoalInsight(data, const ActivityGoals(), history: past, now: now);
  test('compares each metric and labels full-day baseline', () {
    final text = insight(day(6000, 100, 30), history);
    expect(text, contains('steps are above'));
    expect(text, contains('active calories are below'));
    expect(text, contains('exercise minutes are close to'));
    expect(text, isNot(contains('These compare today')));
    expect(text, isNot(contains('not your usual pace by this time')));
  });
  test('groups all three matching comparisons', () {
    expect(
      insight(day(100, 100, 1), history),
      contains(
        'Your steps, active calories, and exercise minutes are below your recent daily average.',
      ),
    );
  });
  test('groups only metrics with the same comparison', () {
    final text = insight(day(100, 100, 40), history);
    expect(
      text,
      contains(
        'Your steps and active calories are below your recent daily average.',
      ),
    );
    expect(
      text,
      contains('Your exercise minutes are above your recent daily average.'),
    );
    expect(text, isNot(contains('and exercise minutes are below')));
  });
  test('excludes today, old dates and future dates', () {
    expect(
      insight(day(5000, 500, 30), {
        ...history,
        '2026-09-24': day(99999, 99999, 99999),
        '2026-09-09': day(99999, 99999, 99999),
        '2026-09-25': day(99999, 99999, 99999),
      }),
      insight(day(5000, 500, 30), history),
    );
  });
  test('requires seven valid days per metric and preserves zeros', () {
    final partial = <String, Map<String, dynamic>>{
      for (var d = 10; d < 17; d++)
        '2026-09-$d': {
          'steps': {'sum': 0},
        },
    };
    final text = insight(day(0, 0, 0), partial);
    expect(text, contains('steps match'));
    expect(
      text,
      contains('Building your average for active calories, exercise minutes'),
    );
    expect(insight(day(0, 0, 0), {}), isNot(contains('are below')));
  });
  test('invalid current data never becomes zero', () {
    expect(
      insight(day(double.nan, -1, double.infinity), history),
      contains('No data today for steps, active calories, exercise minutes'),
    );
    expect(insight(null, history), contains('Sync a connected source'));
  });
}
