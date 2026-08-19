import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/activity_score.dart';

void main() {
  const goals = (steps: 10000.0, exerciseMinutes: 40.0, activeCalories: 700.0);

  ActivityScoreResult? score({
    double? steps,
    double? exerciseMinutes,
    double? activeCalories,
  }) => calculateActivityScore(
    steps: steps,
    exerciseMinutes: exerciseMinutes,
    activeCalories: activeCalories,
    stepsGoal: goals.steps,
    exerciseMinutesGoal: goals.exerciseMinutes,
    activeCaloriesGoal: goals.activeCalories,
  );

  test('returns null when every activity signal is unavailable', () {
    expect(score(), isNull);
  });

  test('full goals produce a score of 100', () {
    final result = score(
      steps: 10000,
      exerciseMinutes: 40,
      activeCalories: 700,
    );
    expect(result?.score, 100);
    expect(result?.availableSignals, 3);
  });

  test('missing signals redistribute their weight', () {
    final result = score(exerciseMinutes: 32, activeCalories: 420);
    // (80 * .60 + 60 * .20) / .80
    expect(result?.score, 75);
    expect(result?.availableSignals, 2);
  });

  test('recorded zero is scored instead of treated as unavailable', () {
    final result = score(steps: 0, exerciseMinutes: 40, activeCalories: 700);
    // 100 primary exercise, 0 secondary movement, 100 exertion.
    expect(result?.score, 80);
    expect(result?.availableSignals, 3);
  });

  test('the stronger movement mode receives the primary weight', () {
    final result = score(steps: 5000, exerciseMinutes: 40, activeCalories: 350);
    // 100 exercise primary, 50 steps secondary, 50 exertion.
    expect(result?.score, 80);
  });

  test('a single available signal can still produce a score', () {
    final result = score(steps: 7500);
    expect(result?.score, 75);
    expect(result?.availableSignals, 1);
  });
}
