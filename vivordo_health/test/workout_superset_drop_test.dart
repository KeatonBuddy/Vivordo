import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/screens/fitness_screen.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

void main() {
  Future<Map<String, dynamic> Function()> pumpCard(
    WidgetTester tester,
    Map<String, dynamic> exercise,
  ) async {
    // Canada: lb for lifts, whatever the machine running the tests.
    tester.platformDispatcher.localeTestValue = const Locale('en', 'CA');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    var saved = exercise;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => ChangeNotifierProvider(
          create: (_) => ThemeController(),
          child: child,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: workoutExerciseCardForTesting(
              initialExercise: exercise,
              distance: ValueNotifier((km: null, loading: false)),
              onChanged: (data) => saved = data,
            ),
          ),
        ),
      ),
    );
    return () => saved;
  }

  testWidgets('Drop set adds a lighter row under the last set done', (
    tester,
  ) async {
    final saved = await pumpCard(tester, {
      'name': 'Bench Press',
      'category': 'Chest',
      'sets': [
        {'lbs': '135', 'reps': '8'},
        {'lbs': '', 'reps': ''},
      ],
    });
    await tester.tap(find.text('Drop set'));
    await tester.pump();
    // About 25% lighter, to the nearest 5 lb, under set 1 (set 2 is empty).
    expect(saved()['sets'][0]['drops'][0]['lbs'], '100');
    await tester.tap(find.text('Drop set'));
    await tester.pump();
    expect(saved()['sets'][0]['drops'][1]['lbs'], '75');
    expect(saved()['sets'][1]['drops'], isNull);
    expect(find.text('D'), findsNWidgets(2));
  });

  testWidgets('a superset row under every set, removed with its button', (
    tester,
  ) async {
    final saved = await pumpCard(tester, {
      'name': 'Bench Press',
      'category': 'Chest',
      'superset': {'name': 'Bent-Over Row', 'category': 'Back'},
      'sets': [
        {
          'lbs': '135',
          'reps': '8',
          'partner': {'lbs': '', 'reps': ''},
        },
      ],
    });
    expect(find.text('Bent-Over Row'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    await tester.tap(find.text('Add Set'));
    await tester.pump();
    expect(saved()['sets'][1]['partner'], isNotNull);
    expect(find.text('B'), findsNWidgets(2));

    // Nothing typed in the superset rows, so no confirmation.
    await tester.tap(find.byTooltip('Remove superset'));
    await tester.pump();
    expect(saved()['superset'], isNull);
    expect(saved()['sets'][0]['partner'], isNull);
    expect(find.text('Superset'), findsOneWidget);
    expect(find.text('B'), findsNothing);
  });

  test('drops and superset rows survive the draft', () {
    final draft = {
      'name': 'Bench Press',
      'category': 'Chest',
      'distanceKm': '',
      'historyLoaded': true,
      'previousSets': <Map<String, dynamic>>[],
      'sets': [
        {
          'lbs': '135',
          'reps': '8',
          'previous': null,
          'drops': [
            {'lbs': '100', 'reps': '6', 'previous': null},
          ],
          'partner': {
            'lbs': '95',
            'reps': '10',
            'previous': {'weightLbs': 90.0, 'reps': 10},
          },
        },
      ],
      'superset': {'name': 'Bent-Over Row', 'category': 'Back'},
      'supersetPrevious': [
        {'weightLbs': 90.0, 'reps': 10},
      ],
    };
    expect(roundTripWorkoutExerciseForTesting(draft), draft);
  });

  test('a saved set keeps its drops', () {
    final set = WorkoutSetRecord(
      weightLbs: 60,
      reps: 10,
      loggedAt: DateTime.utc(2026, 11, 15, 18),
      drops: const [
        WorkoutSetRecord(weightLbs: 45, reps: 8),
        WorkoutSetRecord(weightLbs: 30, reps: 8),
      ],
    );
    final back = WorkoutSetRecord.fromMap(set.toMap())!;
    expect(
      [for (final d in back.drops) (d.weightLbs, d.reps)],
      [(45.0, 8), (30.0, 8)],
    );
    expect(back.loggedAt, set.loggedAt!.toLocal());
    expect(const WorkoutSetRecord(weightLbs: 1, reps: 1).toMap(), {
      'weightLbs': 1.0,
      'reps': 1,
    });
  });

  test('a superset is compared only with earlier supersets', () {
    final names = ['Bench Press', 'Bent-Over Row', 'Curl'];
    final supersetWith = [null, 'Bench Press', null];
    expect(
      exerciseComparisonKey(names, supersetWith, 0),
      'bench press (superset)',
    );
    expect(
      exerciseComparisonKey(names, supersetWith, 1),
      'bent-over row (superset)',
    );
    expect(exerciseComparisonKey(names, supersetWith, 2), 'curl');
    expect(exerciseComparisonKey(['Bench Press'], [null], 0), 'bench press');
    expect(
      isSupersetComparisonKey(exerciseComparisonKey(names, supersetWith, 1)),
      isTrue,
    );
    expect(
      isSupersetComparisonKey(exerciseComparisonKey(names, supersetWith, 2)),
      isFalse,
    );
  });
}
