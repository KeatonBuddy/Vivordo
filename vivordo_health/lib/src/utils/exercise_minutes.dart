import 'dart:math' as math;

typedef ExerciseSample = ({
  String source,
  DateTime from,
  DateTime to,
  double minutes,
});

typedef WorkoutWindow = ({DateTime start, DateTime end});

/// One day's Apple Health exercise minutes, counted once.
///
/// Health returns every source's samples, so an Apple Watch and an iPhone can
/// both report the same minutes; as with steps, the largest single source wins
/// instead of adding sources together. Minutes that fall inside an in-app
/// workout are left out because that workout's duration is already counted in
/// `exercise_time.workoutMinutes`.
///
/// ponytail: the largest source undercounts if two devices cover different
/// parts of the day (e.g. swapping watches at noon); merge sample intervals
/// across sources if that turns up.
double healthExerciseMinutes(
  Iterable<ExerciseSample> samples,
  Iterable<WorkoutWindow> workouts,
) {
  final bySource = <String, double>{};
  // Health can return the same sample twice; count each one once.
  for (final sample in samples.toSet()) {
    final span = sample.to.difference(sample.from).inMilliseconds;
    var covered = 0;
    for (final workout in workouts) {
      final start = sample.from.isAfter(workout.start)
          ? sample.from
          : workout.start;
      final end = sample.to.isBefore(workout.end) ? sample.to : workout.end;
      if (end.isAfter(start)) covered += end.difference(start).inMilliseconds;
    }
    final insideWorkout = span <= 0
        ? workouts.any(
            (workout) =>
                !sample.from.isBefore(workout.start) &&
                sample.from.isBefore(workout.end),
          )
        : false;
    final kept = span <= 0
        ? (insideWorkout ? 0.0 : sample.minutes)
        : sample.minutes * (1 - (covered / span).clamp(0.0, 1.0));
    bySource[sample.source] = (bySource[sample.source] ?? 0) + kept;
  }
  return bySource.isEmpty ? 0 : bySource.values.reduce(math.max);
}
