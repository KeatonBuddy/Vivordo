import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/heart_health_score.dart';

void main() {
  List<HeartHealthSignals> baseline({
    int days = 14,
    double restingHeartRate = 64,
    double hrvSdnn = 48,
    double quietHeartRate = 66,
  }) => List.generate(
    days,
    (_) => HeartHealthSignals(
      restingHeartRate: restingHeartRate,
      hrvSdnn: hrvSdnn,
      quietHeartRate: quietHeartRate,
    ),
  );

  test('scores a day at the personal baseline as 80', () {
    final result = calculateHeartHealthScore(
      current: const HeartHealthSignals(
        restingHeartRate: 64,
        hrvSdnn: 48,
        quietHeartRate: 66,
      ),
      history: baseline(),
    );

    expect(result.score, 80);
    expect(result.availableSignals, 3);
    expect(result.scoredSignals, 3);
    expect(result.confidence, HeartHealthConfidence.high);
  });

  test('rewards a favorable personalized trend', () {
    final result = calculateHeartHealthScore(
      current: const HeartHealthSignals(
        restingHeartRate: 61,
        hrvSdnn: 53,
        quietHeartRate: 63,
      ),
      history: baseline(),
    );

    expect(result.score, greaterThan(90));
  });

  test('reduces the score when signals move below the usual trend', () {
    final result = calculateHeartHealthScore(
      current: const HeartHealthSignals(
        restingHeartRate: 70,
        hrvSdnn: 38,
        quietHeartRate: 72,
      ),
      history: baseline(),
    );

    expect(result.score, lessThan(60));
  });

  test('redistributes weight when a baseline signal is unavailable', () {
    final result = calculateHeartHealthScore(
      current: const HeartHealthSignals(restingHeartRate: 64, hrvSdnn: 48),
      history: baseline()
          .map(
            (day) => HeartHealthSignals(
              restingHeartRate: day.restingHeartRate,
              hrvSdnn: day.hrvSdnn,
            ),
          )
          .toList(),
    );

    expect(result.score, 80);
    expect(result.scoredSignals, 2);
    expect(result.confidence, HeartHealthConfidence.medium);
  });

  test('builds a baseline before returning a score', () {
    final result = calculateHeartHealthScore(
      current: const HeartHealthSignals(restingHeartRate: 64),
      history: baseline(days: 6),
    );

    expect(result.score, isNull);
    expect(result.isBuildingBaseline, isTrue);
    expect(result.baselineDays, 6);
  });

  test(
    'uses the median so a historical outlier does not shift the baseline',
    () {
      final history = baseline(days: 13)
        ..add(
          const HeartHealthSignals(
            restingHeartRate: 140,
            hrvSdnn: 2,
            quietHeartRate: 150,
          ),
        );
      final result = calculateHeartHealthScore(
        current: const HeartHealthSignals(
          restingHeartRate: 64,
          hrvSdnn: 48,
          quietHeartRate: 66,
        ),
        history: history,
      );

      expect(result.score, 80);
    },
  );
}
