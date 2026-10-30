import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/screens/workout_summary_screen.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/src/utils/personal_best.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

Future<void> _pumpSummary(WidgetTester tester, SavedWorkout workout) async {
  // Canada: lb for lifts, km for distance, whatever the machine running the tests.
  tester.platformDispatcher.localeTestValue = const Locale('en', 'CA');
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  await tester.pumpWidget(
    MaterialApp(
      builder: (_, child) => ChangeNotifierProvider(
        create: (_) => ThemeController(),
        child: child,
      ),
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
    expect(colorOf('155 lbs'), const Color(0xFFB45309)); // light theme
    expect(colorOf('135 lbs'), isNot(const Color(0xFFB45309)));
  });

  testWidgets('trends show as grouped rows; the text keeps the advice', (
    tester,
  ) async {
    WorkoutExerciseRecord lift(
      String name,
      ExerciseAttemptTrend? trend, {
      required double weight,
      double? previousWeight,
      required int reps,
      int? previousReps,
      bool personalBest = false,
    }) => WorkoutExerciseRecord(
      name: name,
      category: 'Arms',
      sets: [WorkoutSetRecord(weightLbs: weight, reps: reps)],
      attemptTrend: trend,
      personalBest: personalBest,
      currentAttemptWeightLbs: weight,
      previousAttemptWeightLbs: previousWeight,
      currentAttemptReps: reps,
      previousAttemptReps: previousReps,
    );
    tester.view.physicalSize = const Size(1200, 6000);
    addTearDown(tester.view.reset);
    await _pumpSummary(
      tester,
      SavedWorkout(
        id: 'arms',
        completedAt: DateTime(2026, 10, 17, 7),
        durationSeconds: 2496,
        exerciseCount: 6,
        setCount: 6,
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
            'Preacher curl',
            ExerciseAttemptTrend.improved,
            weight: 40,
            previousWeight: 35,
            reps: 10,
            previousReps: 10,
            personalBest: true,
          ),
          lift(
            'Cable curl',
            ExerciseAttemptTrend.improved,
            weight: 20,
            previousWeight: 20,
            reps: 12,
            previousReps: 10,
          ),
          lift(
            'Hammer curl',
            ExerciseAttemptTrend.maintained,
            weight: 25,
            previousWeight: 25,
            reps: 10,
            previousReps: 10,
          ),
          lift('Wrist curl', null, weight: 15, reps: 15),
        ],
      ),
    );
    for (final label in ['2 up', '1 same', '2 lower', 'Up', 'Same', 'Lower']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('New'), findsOneWidget);
    for (final chip in ['+5 lbs', '+2 reps', 'Matched', '−1 lbs', '−2 reps']) {
      expect(find.text(chip), findsOneWidget, reason: chip);
    }
    expect(find.text('First time'), findsOneWidget);
    expect(
      find.text('35 × 10  →  40 × 10', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Preacher curl  ★ PB', findRichText: true),
      findsOneWidget,
    );

    final text = tester
        .widget<Text>(find.textContaining('You completed'))
        .data!;
    expect(text, isNot(contains('Compared with')), reason: 'rows show it');
    expect(
      text,
      contains('Cable curl is ready for a small weight increase next session.'),
    );
    expect(text, contains('Give the trained areas time to recover'));
  });
}
