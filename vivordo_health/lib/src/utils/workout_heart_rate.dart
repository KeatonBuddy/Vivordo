import 'dart:math' as math;

import 'package:vivordo_health/src/services/workout_service.dart';

import 'heart_rate_history.dart';

/// Heart-rate zones as a share of maximum heart rate, as WHOOP and most
/// training apps use them. Below zone 1 (under 50%) is resting or easy
/// movement and isn't a zone.
enum WorkoutZone {
  z1('Zone 1', 'Warm-up', .5),
  z2('Zone 2', 'Easy', .6),
  z3('Zone 3', 'Aerobic', .7),
  z4('Zone 4', 'Threshold', .8),
  z5('Zone 5', 'Max effort', .9);

  const WorkoutZone(this.label, this.feel, this.fromShare);

  final String label;
  final String feel;

  /// The zone starts at this share of maximum heart rate.
  final double fromShare;
}

/// A workout's heart rate: the readings during it, average and peak, and
/// time in each zone.
class WorkoutHeartRate {
  const WorkoutHeartRate({
    required this.readings,
    required this.average,
    required this.peak,
    required this.maxHr,
    required this.zoneTime,
  });

  /// One reading per minute (or as often as the source records), oldest
  /// first, all inside the workout.
  final List<HeartRateHistoryReading> readings;
  final int average;
  final int peak;

  /// The maximum heart rate the zones are measured against.
  final int maxHr;

  /// Time in each zone, in [WorkoutZone] order.
  final Map<WorkoutZone, Duration> zoneTime;

  Duration get totalInZones =>
      zoneTime.values.fold(Duration.zero, (sum, time) => sum + time);

  /// The zone [bpm] falls in, or null under zone 1.
  WorkoutZone? zoneOf(double bpm) => workoutZoneFor(bpm, maxHr);
}

/// [bpm]'s zone against [maxHr], or null under 50%.
WorkoutZone? workoutZoneFor(double bpm, int maxHr) {
  final share = bpm / maxHr;
  WorkoutZone? zone;
  for (final candidate in WorkoutZone.values) {
    if (share >= candidate.fromShare) zone = candidate;
  }
  return zone;
}

/// Maximum heart rate as the server's training load measures it
/// (functions/activity_load.js maxHeartRate): Tanaka (208 − 0.7 × age), or
/// 190 without an age, raised to the highest reading seen (capped at 220).
int workoutMaxHeartRate(int? age, double? peak) {
  final estimate = age == null ? 190.0 : 208 - 0.7 * age;
  return (peak == null ? estimate : math.max(estimate, math.min(peak, 220)))
      .round();
}

/// A reading stands for the time until the next one, up to this: an Apple
/// Watch records every few seconds in a workout, every few minutes outside.
const _maxGap = Duration(minutes: 2);

/// The workout's heart rate from the day's merged readings, or null when
/// there aren't enough of them to draw honestly: at least 5 readings and
/// one every 3 minutes on average (a watch worn and recording).
WorkoutHeartRate? workoutHeartRate(
  List<HeartRateHistoryReading> dayReadings, {
  required DateTime start,
  required DateTime end,
  int? age,
}) {
  final readings = [
    for (final reading in dayReadings)
      if (!reading.timestamp.isBefore(start) &&
          !reading.timestamp.isAfter(end) &&
          reading.bpm >= 30 &&
          reading.bpm <= 240)
        reading,
  ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final minutes = end.difference(start).inSeconds / 60;
  if (readings.length < 5 || readings.length < minutes / 3) return null;

  final peak = readings.map((r) => r.bpm).reduce(math.max);
  final maxHr = workoutMaxHeartRate(age, peak);
  final zoneTime = {for (final zone in WorkoutZone.values) zone: Duration.zero};
  for (var i = 0; i < readings.length; i++) {
    final zone = workoutZoneFor(readings[i].bpm, maxHr);
    if (zone == null) continue;
    final next = i + 1 < readings.length ? readings[i + 1].timestamp : end;
    var span = next.difference(readings[i].timestamp);
    if (span > _maxGap) span = _maxGap;
    if (span <= Duration.zero) span = const Duration(seconds: 1);
    zoneTime[zone] = zoneTime[zone]! + span;
  }
  final average =
      readings.fold<double>(0, (sum, r) => sum + r.bpm) / readings.length;
  return WorkoutHeartRate(
    readings: readings,
    average: average.round(),
    peak: peak.round(),
    maxHr: maxHr,
    zoneTime: zoneTime,
  );
}

/// One exercise's stretch of the workout on the heart rate graph.
class WorkoutExerciseSpan {
  const WorkoutExerciseSpan({
    required this.index,
    required this.start,
    required this.end,
  });

  /// Its place in the workout's exercise list.
  final int index;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime time) => !time.isBefore(start) && !time.isAfter(end);
}

/// Where each exercise falls in the workout, from when its sets were
/// logged. An exercise runs from the end of the one before it (or the start
/// of the workout) to its last set, so rest before its first set counts
/// towards it. Null when the times can't place them: a workout saved
/// before set times were recorded, exercises done alternately (supersets),
/// or sets all entered at the end, which leaves an exercise under a minute.
/// Exercises without sets (cardio, sports) aren't placed.
List<WorkoutExerciseSpan>? workoutExerciseSpans(
  List<WorkoutExerciseRecord> exercises, {
  required DateTime start,
  required DateTime end,
}) {
  final timed = <(int, DateTime, DateTime)>[];
  for (final (index, exercise) in exercises.indexed) {
    if (exercise.sets.isEmpty) continue;
    final times = exercise.sets.map((set) => set.loggedAt).toList();
    if (times.contains(null)) return null;
    final sorted = times.cast<DateTime>()..sort();
    timed.add((index, sorted.first, sorted.last));
  }
  if (timed.isEmpty) return null;
  timed.sort((a, b) => a.$2.compareTo(b.$2));
  final spans = <WorkoutExerciseSpan>[];
  var from = start;
  for (final (index, first, last) in timed) {
    if (spans.isNotEmpty && first.isBefore(from)) return null;
    final to = last.isAfter(end) ? end : last;
    if (to.difference(from) < const Duration(minutes: 1)) return null;
    spans.add(WorkoutExerciseSpan(index: index, start: from, end: to));
    from = to;
  }
  return spans;
}
