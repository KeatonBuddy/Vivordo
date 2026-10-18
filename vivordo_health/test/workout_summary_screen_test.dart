import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/workout_summary_screen.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/src/utils/personal_best.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

Future<void> _pumpSummary(WidgetTester tester, SavedWorkout workout) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: VivordoTheme.light,
      home: WorkoutSummaryScreen(workout: workout),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('cardio hero shows distance instead of sets or exercises', (
    tester,
  ) async {
    await _pumpSummary(
      tester,
      SavedWorkout(
        id: 'run',
        completedAt: DateTime(2026, 9, 29, 8),
        durationSeconds: 1800,
        exerciseCount: 1,
        setCount: 0,
        exercises: const [
          WorkoutExerciseRecord(
            name: 'Run',
            category: 'Cardio',
            sets: [],
            distanceKm: 5.2,
          ),
        ],
      ),
    );

    expect(find.text('distance'), findsOneWidget);
    expect(find.text('working sets'), findsNothing);
    expect(find.text('exercises'), findsNothing);
    // Hero and exercise card; a duplicate summary chip would make three.
    expect(find.text('5.2 km'), findsNWidgets(2));
  });

  testWidgets('strength hero shows reps and highlights the personal best', (
    tester,
  ) async {
    await _pumpSummary(
      tester,
      SavedWorkout(
        id: 'lift',
        completedAt: DateTime(2026, 9, 29, 8),
        durationSeconds: 2400,
        exerciseCount: 1,
        setCount: 2,
        exercises: const [
          WorkoutExerciseRecord(
            name: 'Bench press',
            category: 'Chest',
            sets: [
              WorkoutSetRecord(weightLbs: 135, reps: 10),
              WorkoutSetRecord(weightLbs: 155, reps: 8),
            ],
            personalBest: true,
            personalBestWeightLbs: 155,
            personalBestReps: 8,
          ),
        ],
      ),
    );

    expect(find.text('reps'), findsOneWidget);
    expect(find.text('working sets'), findsOneWidget);
    expect(find.textContaining('total reps'), findsNothing);

    Color? colorOf(String text) =>
        tester.widget<Text>(find.text(text)).style?.color;
    expect(colorOf('155 lb'), const Color(0xFFB45309)); // light theme
    expect(colorOf('135 lb'), isNot(const Color(0xFFB45309)));
  });

  testWidgets('the summary names every exercise\'s change, not "N more"', (
    tester,
  ) async {
    WorkoutExerciseRecord lift(
      String name,
      ExerciseAttemptTrend trend, {
      required double weight,
      required double previousWeight,
      required int reps,
      required int previousReps,
    }) => WorkoutExerciseRecord(
      name: name,
      category: 'Arms',
      sets: [WorkoutSetRecord(weightLbs: weight, reps: reps)],
      attemptTrend: trend,
      currentAttemptWeightLbs: weight,
      previousAttemptWeightLbs: previousWeight,
      currentAttemptReps: reps,
      previousAttemptReps: previousReps,
    );
    await _pumpSummary(
      tester,
      SavedWorkout(
        id: 'arms',
        completedAt: DateTime(2026, 10, 17, 7),
        durationSeconds: 2496,
        exerciseCount: 5,
        setCount: 5,
        exercises: [
          lift(
            'Overhead extension',
            ExerciseAttemptTrend.declined,
            weight: 30,
            previousWeight: 30,
            reps: 8,
            previousReps: 10,
          ),
          lift(
            'EZ bar extension',
            ExerciseAttemptTrend.declined,
            weight: 49,
            previousWeight: 50,
            reps: 10,
            previousReps: 10,
          ),
          lift(
            'Hammer curl',
            ExerciseAttemptTrend.declined,
            weight: 25,
            previousWeight: 30,
            reps: 10,
            previousReps: 10,
          ),
          lift(
            'Preacher curl',
            ExerciseAttemptTrend.improved,
            weight: 40,
            previousWeight: 35,
            reps: 10,
            previousReps: 10,
          ),
          lift(
            'Cable curl',
            ExerciseAttemptTrend.maintained,
            weight: 20,
            previousWeight: 20,
            reps: 12,
            previousReps: 12,
          ),
        ],
      ),
    );
    final summary = find.textContaining('Compared with your previous');
    final text = tester.widget<Text>(summary).data!;
    expect(text, isNot(contains('more exercise')));
    expect(
      text,
      contains(
        'Compared with your previous attempts, Preacher curl increased by '
        '5 lb; Overhead extension completed 2 fewer reps at the same weight; '
        'EZ bar extension used 1 lb less; Hammer curl used 5 lb less; '
        'Cable curl matched the previous attempt.',
      ),
    );
  });
}
