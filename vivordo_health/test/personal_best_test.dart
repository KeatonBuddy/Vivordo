import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/personal_best.dart';

void main() {
  group('personal best calculation', () {
    test('normalizes casing and repeated whitespace', () {
      expect(
        normalizeExerciseName('  Cable   Hammer Curl '),
        'cable hammer curl',
      );
    });

    test('uses Epley estimated one-rep max', () {
      expect(
        estimatedOneRepMax(weightLbs: 100, reps: 10),
        closeTo(133.33, 0.01),
      );
    });

    test('selects the strongest set rather than the heaviest set', () {
      final best = bestPersonalBestPerformance([
        (weightLbs: 150.0, reps: 1),
        (weightLbs: 135.0, reps: 8),
      ]);

      expect(best, isNotNull);
      expect(best!.weightLbs, 135);
      expect(best.reps, 8);
    });

    test('requires a meaningful improvement over the previous record', () {
      expect(
        isNewPersonalBest(
          candidateEstimatedOneRepMax: 150.01,
          previousEstimatedOneRepMax: 150,
        ),
        isFalse,
      );
      expect(
        isNewPersonalBest(
          candidateEstimatedOneRepMax: 151,
          previousEstimatedOneRepMax: 150,
        ),
        isTrue,
      );
    });

    test('ignores unweighted or incomplete sets', () {
      expect(
        bestPersonalBestPerformance([
          (weightLbs: 0.0, reps: 12),
          (weightLbs: 100.0, reps: 0),
        ]),
        isNull,
      );
    });

    test('compares performance with the previous exercise attempt', () {
      final improvement = exercisePerformanceChangePercent(
        currentEstimatedOneRepMax: 110,
        previousEstimatedOneRepMax: 100,
      );
      final decline = exercisePerformanceChangePercent(
        currentEstimatedOneRepMax: 90,
        previousEstimatedOneRepMax: 100,
      );

      expect(improvement, closeTo(10, 0.001));
      expect(exerciseAttemptTrend(improvement), ExerciseAttemptTrend.improved);
      expect(exerciseAttemptTrend(decline), ExerciseAttemptTrend.declined);
      expect(exerciseAttemptTrend(0.5), ExerciseAttemptTrend.maintained);
    });

    test('recommends more weight after meaningful rep progression', () {
      expect(
        shouldRecommendWeightIncrease(
          currentWeightLbs: 50,
          previousWeightLbs: 50,
          currentReps: 9,
          previousReps: 7,
        ),
        isTrue,
      );
    });

    test('recommends more weight when reps increase from nine to ten', () {
      expect(
        shouldRecommendWeightIncrease(
          currentWeightLbs: 50,
          previousWeightLbs: 50,
          currentReps: 10,
          previousReps: 9,
        ),
        isTrue,
      );
    });

    test('does not recommend more weight before the rep threshold', () {
      expect(
        shouldRecommendWeightIncrease(
          currentWeightLbs: 50,
          previousWeightLbs: 50,
          currentReps: 8,
          previousReps: 6,
        ),
        isFalse,
      );
      expect(
        shouldRecommendWeightIncrease(
          currentWeightLbs: 50,
          previousWeightLbs: 50,
          currentReps: 9,
          previousReps: 8,
        ),
        isFalse,
      );
    });

    test('does not recommend more weight when the load changed', () {
      expect(
        shouldRecommendWeightIncrease(
          currentWeightLbs: 55,
          previousWeightLbs: 50,
          currentReps: 10,
          previousReps: 8,
        ),
        isFalse,
      );
    });

    test('does not recommend more weight without rep progress', () {
      expect(
        shouldRecommendWeightIncrease(
          currentWeightLbs: 50,
          previousWeightLbs: 50,
          currentReps: 10,
          previousReps: 10,
        ),
        isFalse,
      );
      expect(
        shouldRecommendWeightIncrease(
          currentWeightLbs: 50,
          previousWeightLbs: 50,
          currentReps: 10,
          previousReps: 12,
        ),
        isFalse,
      );
    });
  });
}
