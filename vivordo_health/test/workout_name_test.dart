import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/workout_service.dart';

WorkoutExerciseRecord lift(String name, String category, [int sets = 3]) =>
    WorkoutExerciseRecord(
      name: name,
      category: category,
      sets: List.filled(sets, const WorkoutSetRecord(weightLbs: 100, reps: 8)),
    );

String? named(List<WorkoutExerciseRecord> exercises) =>
    strengthWorkoutName(exercises);

void main() {
  test('one group, or its push/pull/arms family, names the workout', () {
    expect(named([lift('Bench Press', 'Chest')]), 'Chest');
    expect(
      named([lift('Barbell Curl', 'Arms'), lift('Hammer Curl', 'Arms')]),
      'Biceps',
    );
    expect(
      named([lift('Rope Pushdown', 'Arms'), lift('Skull Crusher', 'Arms')]),
      'Triceps',
    );
    expect(
      named([lift('Barbell Curl', 'Arms'), lift('Rope Pushdown', 'Arms')]),
      'Arms',
    );
    expect(
      named([
        lift('Bench Press', 'Chest'),
        lift('Overhead Press', 'Shoulders'),
        lift('Triceps Pushdown', 'Arms'),
      ]),
      'Push',
    );
    expect(
      named([lift('Deadlift', 'Back'), lift('Barbell Curl', 'Arms')]),
      'Pull',
    );
    expect(
      named([lift('Bench Press', 'Chest'), lift('Barbell Row', 'Back')]),
      'Upper Body',
    );
  });

  test('legs, lower body and mixed days', () {
    expect(named([lift('Squat', 'Legs'), lift('Plank', 'Core', 1)]), 'Legs');
    expect(named([lift('Squat', 'Legs'), lift('Plank', 'Core')]), 'Lower Body');
    expect(
      named([lift('Bench Press', 'Chest'), lift('Squat', 'Legs')]),
      'Chest and Legs',
    );
    expect(
      named([
        lift('Bench Press', 'Chest'),
        lift('Overhead Press', 'Shoulders'),
        lift('Squat', 'Legs', 3),
      ]),
      'Push and Legs',
    );
    // Two leg sets in a push session don't change it.
    expect(
      named([
        lift('Bench Press', 'Chest'),
        lift('Overhead Press', 'Shoulders'),
        lift('Squat', 'Legs', 2),
      ]),
      'Push',
    );
    // Seven sets of legs to one of chest: a leg day.
    expect(
      named([lift('Squat', 'Legs', 7), lift('Bench', 'Chest', 1)]),
      'Legs',
    );
  });

  test('wrist curls are forearm work, not biceps', () {
    expect(named([lift('Wrist Curl', 'Arms')]), 'Arms');
  });

  test('cardio and sports have no strength name', () {
    expect(named([lift('Run', 'Cardio')]), isNull);
    expect(named([lift('Plank', 'Core')]), 'Core');
  });

  test('a typed name, then the activity, then the generated name', () {
    SavedWorkout workout({String? customName, String? activityName}) =>
        SavedWorkout(
          id: 'w',
          completedAt: DateTime(2026, 10, 26),
          durationSeconds: 1800,
          exercises: [lift('Bench Press', 'Chest')],
          exerciseCount: 1,
          setCount: 3,
          activityName: activityName,
          customName: customName,
        );
    expect(workout(activityName: 'Workout').displayName, 'Chest');
    expect(workout(customName: 'Heavy bench').displayName, 'Heavy bench');
    expect(workout(customName: '  ').displayName, 'Chest');
    expect(workout(activityName: 'Run').displayName, 'Run');
  });
}
