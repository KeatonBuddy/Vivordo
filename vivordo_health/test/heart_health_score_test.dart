import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/heart_health_score.dart';

void main() {
  List<HeartHealthSignals> baseline({
    int days = 14,
    double restingHeartRate = 64,
    double hrv = 48,
    double quietHeartRate = 66,
  }) => List.generate(
    days,
    (_) => HeartHealthSignals(
      restingHeartRate: restingHeartRate,
      hrv: hrv,
      quietHeartRate: quietHeartRate,
    ),
  );

  test('scores a day at the personal baseline as 80', () {
    final result = calculateHeartHealthScore(
      current: const HeartHealthSignals(
        restingHeartRate: 64,
        hrv: 48,
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
        hrv: 53,
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
        hrv: 38,
        quietHeartRate: 72,
      ),
      history: baseline(),
    );

    expect(result.score, lessThan(60));
  });

  test('redistributes weight when a baseline signal is unavailable', () {
    final result = calculateHeartHealthScore(
      current: const HeartHealthSignals(restingHeartRate: 64, hrv: 48),
      history: baseline()
          .map(
            (day) => HeartHealthSignals(
              restingHeartRate: day.restingHeartRate,
              hrv: day.hrv,
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
            hrv: 2,
            quietHeartRate: 150,
          ),
        );
      final result = calculateHeartHealthScore(
        current: const HeartHealthSignals(
          restingHeartRate: 64,
          hrv: 48,
          quietHeartRate: 66,
        ),
        history: history,
      );

      expect(result.score, 80);
    },
  );

  // Same cases as functions/test/hrv.test.js, so app and server agree.
  group('HRV kinds', () {
    Map<String, dynamic> apple(double avg) => {
      'hrv': {'avg': avg, 'source': 'apple_health'},
    };
    Map<String, dynamic> whoop(double avg) => {
      'hrv_rmssd': {'avg': avg, 'source': 'whoop', 'method': 'rmssd'},
    };

    test('readings are keyed by kind and ignore unknown or invalid values', () {
      expect(hrvReadings({...apple(61), ...whoop(44)}), {
        'rmssd:whoop': 44,
        'sdnn': 61,
      });
      expect(
        hrvReadings({
          'hrv_rmssd': {'avg': 40, 'source': 'garmin'},
          'hrv': {'avg': 0},
        }),
        isEmpty,
      );
      expect(hrvReadings(null), isEmpty);
    });

    test('uses the wearable once it has a normal, never mixing kinds', () {
      final history = List.generate(
        7,
        (_) => hrvReadings({...apple(60), ...whoop(45)}),
      );
      final pick = pickHrv(
        hrvReadings({...apple(58), ...whoop(40)}),
        history,
        7,
      );
      expect(pick.kind, 'rmssd:whoop');
      expect(pick.value, 40);
      expect(pick.history, List.filled(7, 45));
    });

    test('keeps Apple SDNN while a new wearable builds its normal', () {
      final history = [
        ...List.generate(10, (_) => hrvReadings(apple(60))),
        ...List.generate(3, (_) => hrvReadings({...apple(60), ...whoop(45)})),
      ];
      final pick = pickHrv(
        hrvReadings({...apple(57), ...whoop(42)}),
        history,
        7,
      );
      expect(pick.kind, 'sdnn');
      expect(pick.value, 57);
    });

    test('a wearable-only user without a normal yet reports its kind', () {
      final pick = pickHrv(hrvReadings(whoop(42)), [hrvReadings(whoop(45))], 7);
      expect(pick.kind, 'rmssd:whoop');
      expect(pick.value, 42);
      expect(pick.history, [45]);
      final none = pickHrv({}, [{}], 7);
      expect(none.kind, isNull);
      expect(none.history, [null]);
    });
  });
}
