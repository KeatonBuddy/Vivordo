import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/fitness_screen.dart';
import 'package:vivordo_health/src/services/workout_service.dart';

void main() {
  final legacy = <String, dynamic>{
    'name': 'Bench press',
    'category': 'Strength',
    'sets': [
      {'lbs': '105', 'reps': '8'},
      {'lbs': '', 'reps': ''},
    ],
  };
  test(
    'recovered history survives disk JSON round trip without changing inputs',
    () {
      final saved = roundTripWorkoutExerciseForTesting(
        legacy,
        recoveredHistory: [
          const WorkoutSetRecord(weightLbs: 100, reps: 10),
          const WorkoutSetRecord(weightLbs: 95, reps: 12),
          const WorkoutSetRecord(weightLbs: 90, reps: 15),
        ],
      );
      final restored = roundTripWorkoutExerciseForTesting(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(saved))),
      );
      expect(restored, saved);
      expect(restored['historyLoaded'], true);
      expect((restored['previousSets'] as List).length, 3);
      final sets = restored['sets'] as List;
      expect(sets.first['lbs'], '105');
      expect(sets.first['reps'], '8');
      expect(sets.first['previous'], {'weightLbs': 100.0, 'reps': 10});
      expect(sets.last['lbs'], '');
    },
  );
  test(
    'legacy drafts request history; empty recovered history is remembered',
    () {
      expect(
        roundTripWorkoutExerciseForTesting(legacy)['historyLoaded'],
        false,
      );
      final saved = roundTripWorkoutExerciseForTesting(
        legacy,
        recoveredHistory: [],
      );
      expect(saved['historyLoaded'], true);
      expect((saved['sets'] as List).first['previous'], isNull);
    },
  );
  test('recovery preserves already captured previous set references', () {
    final saved = roundTripWorkoutExerciseForTesting(
      legacy,
      recoveredHistory: [const WorkoutSetRecord(weightLbs: 100, reps: 10)],
    );
    final recovered = roundTripWorkoutExerciseForTesting(
      saved,
      recoveredHistory: [const WorkoutSetRecord(weightLbs: 120, reps: 5)],
    );
    expect((recovered['sets'] as List).first['previous'], {
      'weightLbs': 100.0,
      'reps': 10,
    });
  });
}
