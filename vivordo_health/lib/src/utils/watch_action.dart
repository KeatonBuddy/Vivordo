import 'package:vivordo_health/src/services/workout_service.dart';

/// A workout recorded on the watch (VivordoWatch/WorkoutSession.swift).
typedef WatchWorkout = ({
  String name,
  DateTime startedAt,
  DateTime endedAt,
  int seconds,
  List<WorkoutExerciseRecord> exercises,
});

/// One thing done on the Apple Watch, as queued by the phone
/// (`pendingWatchActions` on the home-widgets channel): a finished reset, an
/// energy check-in, a priority ticked off or a workout.
typedef PendingWatchAction = ({
  String id,
  String kind,
  DateTime at,
  int? seconds,
  int? hrStart,
  int? hrEnd,
  double? score,
  String? priorityId,
  String? day,
  WatchWorkout? workout,
});

/// This account's queued actions, oldest first. Anything malformed, of an
/// unknown kind or from another account is left in the queue untouched.
List<PendingWatchAction> pendingWatchActions(String uid, List<Object?> raw) {
  final actions = <PendingWatchAction>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final id = item['id'];
    final kind = item['kind'];
    final at = item['at'];
    if (item['account'] != uid ||
        id is! String ||
        kind is! String ||
        at is! num) {
      continue;
    }
    final seconds = item['seconds'];
    final score = item['score'];
    final priorityId = item['priorityId'];
    final day = item['day'];
    final complete = switch (kind) {
      'reset' => seconds is num,
      'checkIn' => score is num,
      'taskDone' => priorityId is String && day is String,
      'workout' => true,
      _ => false,
    };
    final workout = kind == 'workout' ? _workout(item) : null;
    if (!complete || (kind == 'workout' && workout == null)) continue;
    final hrStart = item['hrStart'];
    final hrEnd = item['hrEnd'];
    actions.add((
      id: id,
      kind: kind,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      seconds: seconds is num ? seconds.toInt() : null,
      hrStart: hrStart is num ? hrStart.toInt() : null,
      hrEnd: hrEnd is num ? hrEnd.toInt() : null,
      score: score is num ? score.toDouble().clamp(0, 100).toDouble() : null,
      priorityId: priorityId is String ? priorityId : null,
      day: day is String ? day : null,
      workout: workout,
    ));
  }
  return actions..sort((a, b) => a.at.compareTo(b.at));
}

/// Weights in pounds, as the phone logs them; sets with no reps are dropped.
WatchWorkout? _workout(Map item) {
  final name = item['name'];
  final start = item['startAt'];
  final end = item['endAt'];
  final seconds = item['seconds'];
  final rawExercises = item['exercises'];
  if (name is! String ||
      start is! num ||
      end is! num ||
      seconds is! num ||
      seconds <= 0 ||
      end < start ||
      rawExercises is! List) {
    return null;
  }
  final exercises = <WorkoutExerciseRecord>[];
  for (final raw in rawExercises.whereType<Map>()) {
    final exerciseName = raw['name'];
    if (exerciseName is! String || exerciseName.trim().isEmpty) continue;
    final category = raw['category'];
    final km = raw['km'];
    exercises.add(
      WorkoutExerciseRecord(
        name: exerciseName.trim(),
        category: category is String ? category : 'Other',
        distanceKm: km is num && km > 0 ? km.toDouble() : null,
        sets: [
          for (final set in (raw['sets'] as List? ?? const []).whereType<Map>())
            if (set['w'] case final num w when w >= 0)
              if (set['r'] case final num r when r > 0)
                WorkoutSetRecord(
                  weightLbs: w.toDouble(),
                  reps: r.toInt(),
                  loggedAt: set['at'] is num
                      ? DateTime.fromMillisecondsSinceEpoch(
                          (set['at'] as num).toInt(),
                        )
                      : null,
                ),
        ],
      ),
    );
  }
  return (
    name: name.trim(),
    startedAt: DateTime.fromMillisecondsSinceEpoch(start.toInt()),
    endedAt: DateTime.fromMillisecondsSinceEpoch(end.toInt()),
    seconds: seconds.toInt(),
    exercises: exercises,
  );
}

/// The watch's copy of the saved workouts (`watchWorkouts`): each exercise
/// with its targets and the sets from the last time it was done, keyed in
/// [last] by lower-cased name as `WorkoutService.loadLatestExerciseSets`
/// returns them.
List<Map<String, Object>> watchWorkoutValues(
  List<WorkoutTemplate> templates,
  Map<String, List<WorkoutSetRecord>> last,
) => [
  for (final template in templates)
    if (template.exercises.isNotEmpty)
      {
        'id': template.id,
        'name': template.name,
        'exercises': [
          for (final exercise in template.exercises)
            {
              'name': exercise.name,
              'category': exercise.category,
              'sets': ?exercise.sets,
              'reps': ?exercise.reps,
              'last': [
                for (final set
                    in last[exercise.name.trim().toLowerCase()] ?? const [])
                  {'w': set.weightLbs, 'r': set.reps},
              ],
            },
        ],
      },
];
