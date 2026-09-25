import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/fitness_screen.dart';

void main() {
  testWidgets(
    'edits stay local; sets and distance update without losing input',
    (tester) async {
      final distance = ValueNotifier<({double? km, bool loading})>((
        km: null,
        loading: false,
      ));
      Map<String, dynamic>? saved;
      var parentBuilds = 0;
      final strength = workoutExerciseCardForTesting(
        initialExercise: {
          'name': 'Bench Press',
          'category': 'Chest',
          'sets': [
            {
              'lbs': '50',
              'reps': '8',
              'previous': {'weightLbs': 45, 'reps': 8},
            },
          ],
        },
        distance: distance,
        onChanged: (data) => saved = data,
      );
      final cardio = workoutExerciseCardForTesting(
        initialExercise: {'name': 'Run', 'category': 'Cardio'},
        distance: distance,
        onChanged: (_) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (_) {
                  parentBuilds++;
                  return Column(children: [strength, cardio]);
                },
              ),
            ),
          ),
        ),
      );
      final initialBuilds = parentBuilds;
      await tester.enterText(find.byType(TextFormField).first, '75');
      await tester.pump();
      expect(saved!['sets'][0]['lbs'], '75');
      expect(parentBuilds, initialBuilds);
      await tester.tap(find.text('Add Set'));
      await tester.pump();
      expect(saved!['sets'].length, 2);
      expect(find.byType(TextFormField), findsNWidgets(4));
      await tester.tap(find.byTooltip('Remove set').last);
      await tester.pump();
      expect(saved!['sets'].length, 1);
      expect(find.text('75'), findsOneWidget);
      distance.value = (km: 1.25, loading: true);
      await tester.pump();
      expect(find.text('1.25 km'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      distance.value = (km: 1.25, loading: false);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('75'), findsOneWidget);
      expect(parentBuilds, initialBuilds);
      await tester.pumpWidget(const SizedBox.shrink());
      distance.dispose();
    },
  );
}
