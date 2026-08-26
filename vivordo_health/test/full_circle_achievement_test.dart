import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/achievement_service.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';

void main() {
  group('countCompletedActivityRingDays', () {
    const goals = ActivityGoals(
      steps: 10000,
      activeCalories: 700,
      exerciseMinutes: 40,
    );

    Map<String, dynamic> metricDay({
      required num steps,
      required num activeCalories,
      required num exerciseMinutes,
    }) => {
      'steps': {'sum': steps},
      'active_calories': {'sum': activeCalories},
      'exercise_time': {'sum': exerciseMinutes},
    };

    test('counts qualifying days cumulatively rather than as a streak', () {
      final completedDays = countCompletedActivityRingDays(
        goals: goals,
        metricDays: [
          metricDay(steps: 10000, activeCalories: 700, exerciseMinutes: 40),
          metricDay(steps: 12000, activeCalories: 400, exerciseMinutes: 55),
          metricDay(steps: 11000, activeCalories: 800, exerciseMinutes: 50),
        ],
      );

      expect(completedDays, 2);
    });

    test('requires all three activity rings to reach their goals', () {
      final completedDays = countCompletedActivityRingDays(
        goals: goals,
        metricDays: [
          metricDay(steps: 9999, activeCalories: 700, exerciseMinutes: 40),
          metricDay(steps: 10000, activeCalories: 699, exerciseMinutes: 40),
          metricDay(steps: 10000, activeCalories: 700, exerciseMinutes: 39),
          {
            'steps': {'sum': 15000},
            'active_calories': {'sum': 900},
          },
        ],
      );

      expect(completedDays, 0);
    });
  });
}
