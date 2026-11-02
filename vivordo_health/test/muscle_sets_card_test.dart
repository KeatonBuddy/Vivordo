import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/muscle_sets_card.dart';

/// Push and legs days for the last [weeks] weeks, relative to now, with
/// legs fading over the last three.
List<SavedWorkout> trainingWeeks({int weeks = 12, bool today = true}) {
  final now = DateTime.now();
  WorkoutExerciseRecord lift(String name, String category, int sets) =>
      WorkoutExerciseRecord(
        name: name,
        category: category,
        sets: List.filled(
          sets,
          const WorkoutSetRecord(weightLbs: 100, reps: 8),
        ),
      );
  SavedWorkout at(int daysBack, List<WorkoutExerciseRecord> exercises) =>
      SavedWorkout(
        id: '$daysBack',
        completedAt: DateTime(now.year, now.month, now.day - daysBack, 7, 10),
        durationSeconds: 3600,
        exercises: exercises,
        exerciseCount: exercises.length,
        setCount: 0,
      );
  return [
    if (today)
      at(0, [
        lift('Bench Press', 'Chest', 4),
        lift('Overhead Press', 'Shoulders', 3),
        lift('Triceps Pushdown', 'Arms', 3),
      ]),
    for (var w = 0; w < weeks; w++) ...[
      at(7 * w + 2, [
        lift('Bench Press', 'Chest', 4),
        lift('Cable Fly', 'Chest', 4),
        lift('Barbell Row', 'Back', 6),
        lift('Barbell Curl', 'Arms', 4),
      ]),
      at(7 * w + 4, [
        lift('Squat', 'Legs', w < 3 ? 2 + w : 10),
        lift('Plank', 'Core', w < 2 ? 0 : 3),
        lift('Lat Pulldown', 'Back', 6),
      ]),
    ],
  ];
}

Future<void> phone(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: VivordoTheme.dark, home: child));
  await tester.pumpAndSettle();
}

void main() {
  for (final (range, name, headline) in [
    (0, 'Day', 'sets today'),
    (1, 'Week', 'sets'),
    (2, 'Month', 'sets a week'),
  ]) {
    testWidgets('$name card lays out on a phone', (tester) async {
      await phone(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: MuscleSetsSection(
              workouts: trainingWeeks(),
              rangeIndex: range,
            ),
          ),
        ),
      );
      expect(find.text('Sets by muscle group'), findsOneWidget);
      expect(
        find.textContaining(' $headline', findRichText: true),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a rest day says when the last workout was', (tester) async {
    await phone(
      tester,
      Scaffold(
        body: MuscleSetsSection(
          workouts: trainingWeeks(today: false),
          rangeIndex: 0,
        ),
      ),
    );
    expect(find.text('No sets today'), findsOneWidget);
    expect(find.textContaining('Last workout was'), findsOneWidget);
  });

  testWidgets('nothing without strength workouts', (tester) async {
    await phone(
      tester,
      const Scaffold(body: MuscleSetsSection(workouts: [], rangeIndex: 1)),
    );
    expect(find.text('Sets by muscle group'), findsNothing);
  });
}
