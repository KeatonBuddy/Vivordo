import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/fitness_screen.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/assistant_blocks.dart';

void main() {
  test('saved workouts keep optional sets and reps targets', () async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('workout_templates').doc('push');
    await ref.set({
      'name': 'Push day',
      'source': 'vivordo_ai',
      'exercises': [
        const WorkoutTemplateExercise(
          name: 'Barbell Bench Press',
          category: 'Chest',
          sets: 4,
          reps: '6-8',
        ).toMap(),
        // A workout saved before targets existed.
        {'name': 'Cable Chest Fly', 'category': 'Chest'},
        // Out-of-range data is ignored rather than trusted.
        {'name': 'Triceps Pushdown', 'category': 'Arms', 'sets': 40},
      ],
    });
    final template = WorkoutTemplate.fromDocument(await ref.get());
    expect(template.fromVivordoAi, isTrue);
    expect(template.exercises.first.sets, 4);
    expect(template.exercises.first.reps, '6-8');
    expect(template.exercises[1].sets, isNull);
    expect(template.exercises[2].sets, isNull);
    expect(template.targetSets, 4);
    expect(
      const WorkoutTemplateExercise(name: 'Run', category: 'Cardio').toMap(),
      {'name': 'Run', 'category': 'Cardio'},
    );
  });

  test('a target starts that many set rows and survives a resume', () {
    final started = roundTripWorkoutExerciseForTesting({
      'name': 'Barbell Bench Press',
      'category': 'Chest',
      'targetSets': 4,
      'targetReps': '6-8',
    });
    expect(started['sets'], hasLength(4));
    expect(started['targetSets'], 4);
    expect(started['targetReps'], '6-8');

    final untargeted = roundTripWorkoutExerciseForTesting({
      'name': 'Cable Chest Fly',
      'category': 'Chest',
    });
    expect(untargeted['sets'], hasLength(2), reason: 'the old default');
    expect(untargeted.containsKey('targetSets'), isFalse);
  });

  testWidgets('a routine card lists targets and saves or dismisses', (
    tester,
  ) async {
    var saved = 0;
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Scaffold(
          body: ActionCard(
            action: const {
              'type': 'workout',
              'name': 'Push day',
              'minutes': 45,
              'exercises': [
                {
                  'name': 'Barbell Bench Press',
                  'category': 'Chest',
                  'sets': 4,
                  'reps': '6-8',
                },
                {
                  'name': 'Cable Chest Fly',
                  'category': 'Chest',
                  'sets': 3,
                  'reps': '12',
                },
              ],
            },
            status: ActionStatus.open,
            onConfirm: () => saved++,
            onCancel: () => dismissed++,
          ),
        ),
      ),
    );
    expect(find.text('Saved workout'), findsOneWidget);
    expect(find.text('Push day'), findsOneWidget);
    expect(find.text('2 exercises · about 45 min'), findsOneWidget);
    expect(find.text('4 × 6-8'), findsOneWidget);
    expect(find.text('3 × 12'), findsOneWidget);
    await tester.tap(find.text('Save workout'));
    await tester.tap(find.text('Not now'));
    expect((saved, dismissed), (1, 1));
    expect(
      ActionCard.describe(const {
        'type': 'workout',
        'name': 'Push day',
        'exercises': [{}],
      }),
      'Save “Push day” · 1 exercise',
    );
  });
}
