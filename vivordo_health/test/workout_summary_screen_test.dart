import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/workout_summary_screen.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
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
}
