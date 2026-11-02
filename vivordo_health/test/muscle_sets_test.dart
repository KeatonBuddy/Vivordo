import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/src/utils/muscle_sets.dart';

void main() {
  // Monday, Nov 2 2026.
  final today = DateTime(2026, 11, 2, 12);
  WorkoutExerciseRecord lift(String name, String category, int sets) =>
      WorkoutExerciseRecord(
        name: name,
        category: category,
        sets: List.filled(
          sets,
          const WorkoutSetRecord(weightLbs: 100, reps: 8),
        ),
      );
  SavedWorkout workout(int daysBack, List<WorkoutExerciseRecord> exercises) =>
      SavedWorkout(
        id: '$daysBack',
        completedAt: DateTime(2026, 11, 2 - daysBack, 18),
        durationSeconds: 3600,
        exercises: exercises,
        exerciseCount: exercises.length,
        setCount: 0,
      );
  // A week (by days back to its Wednesday) of Chest, Legs and Core.
  SavedWorkout week(int wednesday, {int chest = 10, int legs = 10}) =>
      workout(wednesday, [
        lift('Bench Press', 'Chest', chest),
        lift('Squat', 'Legs', legs),
        lift('Plank', 'Core', 3),
      ]);

  test('sets by group, in Monday-to-Sunday weeks', () {
    final weekly = weeklySets([
      workout(1, [lift('Bench Press', 'Chest', 4), lift('Run', 'Cardio', 1)]),
      workout(0, [lift('Barbell Curl', 'Arms', 3)]),
    ]);
    expect(weekly, {
      DateTime(2026, 10, 26): {'Chest': 4},
      DateTime(2026, 11, 2): {'Biceps': 3},
    });
  });

  test('Week: this week so far, flagged against the usual by today', () {
    // Thursday Nov 5; the four weeks before trained on Wednesdays.
    final thursday = DateTime(2026, 11, 5, 20);
    final view = muscleSetsWeek([
      for (final w in [5, 12, 19, 26]) week(w),
      workout(-1, [lift('Bench Press', 'Chest', 12)]),
      workout(-2, [lift('Squat', 'Legs', 4)]),
    ], thursday)!;
    expect(view.total, 16);
    expect([for (final g in view.groups) g.group], ['Chest', 'Legs', 'Core']);
    expect(view.groups[1].low, isTrue);
    expect(
      view.note,
      'Legs: 4 sets so far this week, against your usual 10 by Thursday. '
      'Core: none yet.',
    );
    // Legs usually come on Sundays, so none by Thursday isn't low.
    final sundayLegs = muscleSetsWeek([
      for (final w in [1, 8, 15, 22]) workout(w, [lift('Squat', 'Legs', 10)]),
      workout(-1, [lift('Bench Press', 'Chest', 4)]),
    ], thursday)!;
    final legs = sundayLegs.groups.firstWhere((g) => g.group == 'Legs');
    expect((legs.usual, legs.usualByNow, legs.low), (10, 0, false));
    // On Sunday the whole week is in.
    expect(
      muscleSetsWeek([
        for (final w in [5, 12, 19, 26]) week(w),
        workout(-1, [lift('Bench Press', 'Chest', 12)]),
        workout(-2, [lift('Squat', 'Legs', 4)]),
      ], DateTime(2026, 11, 8, 20))!.note,
      'Legs had 4 sets this week, against your usual 10. Core: none this week.',
    );
    // A week off doesn't lower the usual.
    expect(
      muscleSetsWeek([
        for (final w in [5, 19, 26]) week(w),
        workout(-1, [lift('Squat', 'Legs', 10)]),
      ], thursday)!.groups.firstWhere((g) => g.group == 'Legs').usual,
      10,
    );
  });

  test('Month: four full weeks a week at a time', () {
    final view = muscleSetsMonth([
      for (var i = 5; i <= 12; i++) week(7 * i - 2),
      week(26, legs: 10),
      week(19, legs: 7),
      week(12, legs: 5),
      week(5, legs: 4),
    ], today)!;
    expect(view.weeks.first, DateTime(2026, 10, 5));
    final legs = view.groups.firstWhere((g) => g.group == 'Legs');
    expect(legs.weeks, [10, 7, 5, 4]);
    expect(legs.value, 6.5);
    expect(legs.low, isFalse); // 6.5 of a usual 10 is just over 60%
    expect(view.total, 20);
    final drop = muscleSetsMonth([
      for (var i = 5; i <= 12; i++) week(7 * i - 2),
      week(26, legs: 5),
      week(19, legs: 4),
      week(12, legs: 3),
      week(5, legs: 2),
    ], today)!;
    expect(drop.note, 'Legs sets dropped three weeks running, from 5 to 2.');
  });

  test('exercises for a group, most sets first', () {
    expect(
      exerciseSets([
        workout(1, [lift('Cable Fly', 'Chest', 3), lift('Squat', 'Legs', 5)]),
        workout(3, [lift('Bench Press', 'Chest', 4)]),
      ], 'Chest'),
      'Bench Press 4 · Cable Fly 3',
    );
  });
}
