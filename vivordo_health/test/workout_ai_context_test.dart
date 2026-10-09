import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/widgets/workout_ai_insight.dart';

void main() {
  SavedWorkout workout(int reps) => SavedWorkout(
    id: 'selected-workout',
    completedAt: DateTime(2026, 9, 24),
    durationSeconds: 1800,
    exerciseCount: 1,
    setCount: 1,
    exercises: [
      WorkoutExerciseRecord(
        name: 'Bench press',
        category: 'Chest',
        sets: [WorkoutSetRecord(weightLbs: 100, reps: reps)],
        previousAttemptWeightLbs: 100,
        previousAttemptReps: 8,
      ),
    ],
  );
  test('selected workout context retains units and previous performance', () {
    final data = jsonDecode(workoutAdviceContext(workout(10))) as Map;
    expect(data['workoutId'], 'selected-workout');
    expect(data['durationSeconds'], 1800);
    expect(data['exercises'][0]['sets'][0]['weightLbs'], 100);
    expect(data['exercises'][0]['previousAttemptReps'], 8);
  });
  test(
    'unchanged content is stable; edited sets invalidate cached context',
    () {
      expect(
        workoutAdviceContext(workout(10)),
        workoutAdviceContext(workout(10)),
      );
      expect(
        workoutAdviceContext(workout(10)),
        isNot(workoutAdviceContext(workout(11))),
      );
    },
  );
}
