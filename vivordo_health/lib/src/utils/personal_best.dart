import 'dart:math' as math;

const double personalBestComparisonTolerance = 0.05;
const double exerciseComparisonThresholdPercent = 1;
const double progressiveOverloadWeightToleranceLbs = 0.05;
const int progressiveOverloadMinimumRepIncrease = 2;
const int progressiveOverloadMinimumCurrentReps = 9;
const int progressiveOverloadAutomaticRepThreshold = 10;

enum ExerciseAttemptTrend { improved, maintained, declined }

class PersonalBestPerformance {
  const PersonalBestPerformance({
    required this.weightLbs,
    required this.reps,
    required this.estimatedOneRepMax,
  });

  final double weightLbs;
  final int reps;
  final double estimatedOneRepMax;
}

String normalizeExerciseName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

double? estimatedOneRepMax({required double weightLbs, required int reps}) {
  if (weightLbs <= 0 || reps <= 0) return null;
  final cappedReps = math.min(reps, 30);
  return weightLbs * (1 + cappedReps / 30);
}

PersonalBestPerformance? bestPersonalBestPerformance(
  Iterable<({double weightLbs, int reps})> sets,
) {
  PersonalBestPerformance? best;
  for (final set in sets) {
    final estimate = estimatedOneRepMax(
      weightLbs: set.weightLbs,
      reps: set.reps,
    );
    if (estimate == null) continue;
    if (best == null || estimate > best.estimatedOneRepMax) {
      best = PersonalBestPerformance(
        weightLbs: set.weightLbs,
        reps: set.reps,
        estimatedOneRepMax: estimate,
      );
    }
  }
  return best;
}

bool isNewPersonalBest({
  required double candidateEstimatedOneRepMax,
  double? previousEstimatedOneRepMax,
}) =>
    previousEstimatedOneRepMax == null ||
    candidateEstimatedOneRepMax >
        previousEstimatedOneRepMax + personalBestComparisonTolerance;

double exercisePerformanceChangePercent({
  required double currentEstimatedOneRepMax,
  required double previousEstimatedOneRepMax,
}) {
  if (previousEstimatedOneRepMax <= 0) return 0;
  return (currentEstimatedOneRepMax - previousEstimatedOneRepMax) /
      previousEstimatedOneRepMax *
      100;
}

ExerciseAttemptTrend exerciseAttemptTrend(double changePercent) {
  if (changePercent >= exerciseComparisonThresholdPercent) {
    return ExerciseAttemptTrend.improved;
  }
  if (changePercent <= -exerciseComparisonThresholdPercent) {
    return ExerciseAttemptTrend.declined;
  }
  return ExerciseAttemptTrend.maintained;
}

bool shouldRecommendWeightIncrease({
  required double currentWeightLbs,
  required double previousWeightLbs,
  required int currentReps,
  required int previousReps,
}) {
  final repIncrease = currentReps - previousReps;
  final sameWeight =
      (currentWeightLbs - previousWeightLbs).abs() <=
      progressiveOverloadWeightToleranceLbs;
  final reachedAutomaticThreshold =
      currentReps >= progressiveOverloadAutomaticRepThreshold &&
      repIncrease > 0;
  final madeMeaningfulRepProgress =
      currentReps >= progressiveOverloadMinimumCurrentReps &&
      repIncrease >= progressiveOverloadMinimumRepIncrease;
  return currentWeightLbs > 0 &&
      previousWeightLbs > 0 &&
      sameWeight &&
      (reachedAutomaticThreshold || madeMeaningfulRepProgress);
}
