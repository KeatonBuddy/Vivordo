enum FitnessGoalNotificationType {
  steps,
  activeCalories,
  exerciseMinutes,
  allRings,
}

extension FitnessGoalNotificationTypeDetails on FitnessGoalNotificationType {
  String get storageKey => switch (this) {
    FitnessGoalNotificationType.steps => 'steps',
    FitnessGoalNotificationType.activeCalories => 'activeCalories',
    FitnessGoalNotificationType.exerciseMinutes => 'exerciseMinutes',
    FitnessGoalNotificationType.allRings => 'allRings',
  };
}

/// Returns every fitness milestone reached by the supplied daily totals.
///
/// Missing metrics do not count as completed. The combined ring milestone is
/// reached only when all three individual goals have been met.
List<FitnessGoalNotificationType> reachedFitnessGoalNotifications({
  required Map<String, dynamic> dailyMetrics,
  required int stepsGoal,
  required int activeCaloriesGoal,
  required int exerciseMinutesGoal,
}) {
  double? sumFor(String metric) {
    final value = (dailyMetrics[metric] as Map?)?['sum'];
    return value is num ? value.toDouble() : null;
  }

  final steps = sumFor('steps');
  final activeCalories = sumFor('active_calories');
  final exerciseMinutes = sumFor('exercise_time');
  final reachedSteps = steps != null && steps >= stepsGoal;
  final reachedCalories =
      activeCalories != null && activeCalories >= activeCaloriesGoal;
  final reachedExercise =
      exerciseMinutes != null && exerciseMinutes >= exerciseMinutesGoal;

  return [
    if (reachedSteps) FitnessGoalNotificationType.steps,
    if (reachedCalories) FitnessGoalNotificationType.activeCalories,
    if (reachedExercise) FitnessGoalNotificationType.exerciseMinutes,
    if (reachedSteps && reachedCalories && reachedExercise)
      FitnessGoalNotificationType.allRings,
  ];
}
