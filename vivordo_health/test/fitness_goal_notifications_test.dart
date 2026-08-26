import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/fitness_goal_notifications.dart';

void main() {
  List<FitnessGoalNotificationType> evaluate(Map<String, dynamic> metrics) =>
      reachedFitnessGoalNotifications(
        dailyMetrics: metrics,
        stepsGoal: 10000,
        activeCaloriesGoal: 700,
        exerciseMinutesGoal: 40,
      );

  test('returns each independently reached fitness goal', () {
    expect(
      evaluate({
        'steps': {'sum': 10000},
        'active_calories': {'sum': 699},
        'exercise_time': {'sum': 41},
      }),
      [
        FitnessGoalNotificationType.steps,
        FitnessGoalNotificationType.exerciseMinutes,
      ],
    );
  });

  test('adds the completed ring after all three goals are reached', () {
    expect(
      evaluate({
        'steps': {'sum': 12000},
        'active_calories': {'sum': 800},
        'exercise_time': {'sum': 45},
      }),
      FitnessGoalNotificationType.values,
    );
  });

  test('missing metrics do not count as a completed goal', () {
    expect(
      evaluate({
        'steps': {'sum': 12000},
      }),
      [FitnessGoalNotificationType.steps],
    );
  });
}
