class ActivityScoreResult {
  const ActivityScoreResult({
    required this.score,
    required this.availableSignals,
  });

  final double score;
  final int availableSignals;
}

/// Scores daily activity from movement, intentional exercise, and exertion.
///
/// Steps and exercise are interchangeable ways to demonstrate activity: the
/// stronger of those two signals receives the primary weight and the other
/// receives a smaller complementary weight. Active calories capture exertion.
/// Missing signals are excluded and the remaining weights are normalized;
/// recorded zeroes remain part of the calculation.
ActivityScoreResult? calculateActivityScore({
  required double? steps,
  required double? exerciseMinutes,
  required double? activeCalories,
  required double stepsGoal,
  required double exerciseMinutesGoal,
  required double activeCaloriesGoal,
}) {
  double? normalized(double? value, double goal) {
    if (value == null || !value.isFinite || goal <= 0 || !goal.isFinite) {
      return null;
    }
    return (value / goal * 100).clamp(0.0, 100.0).toDouble();
  }

  final movement = normalized(steps, stepsGoal);
  final exercise = normalized(exerciseMinutes, exerciseMinutesGoal);
  final exertion = normalized(activeCalories, activeCaloriesGoal);
  final movementSignals = [?movement, ?exercise]
    ..sort((a, b) => b.compareTo(a));

  var weightedScore = 0.0;
  var availableWeight = 0.0;
  if (movementSignals.isNotEmpty) {
    weightedScore += movementSignals.first * 0.60;
    availableWeight += 0.60;
  }
  if (movementSignals.length > 1) {
    weightedScore += movementSignals[1] * 0.20;
    availableWeight += 0.20;
  }
  if (exertion != null) {
    weightedScore += exertion * 0.20;
    availableWeight += 0.20;
  }

  if (availableWeight == 0) return null;
  return ActivityScoreResult(
    score: (weightedScore / availableWeight).clamp(0.0, 100.0),
    availableSignals:
        (movement == null ? 0 : 1) +
        (exercise == null ? 0 : 1) +
        (exertion == null ? 0 : 1),
  );
}
