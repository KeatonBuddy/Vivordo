import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'package:vivordo_health/src/utils/energy_factors.dart';
import 'package:vivordo_health/src/utils/energy_forecast.dart';
import 'package:vivordo_health/widgets/energy_forecast_view.dart';

void main() {
  final today = DateTime(2026, 10, 10);
  String night(int daysAgo) => localDayKey(DateTime(2026, 10, 10 - daysAgo));

  /// Capacity on the morning after each of the last [count] nights: [low]
  /// after nights tagged [tag] (every [every]th), 80 otherwise.
  ({Map<String, Set<String>> tags, Map<String, Map<String, dynamic>> scores})
  history({String tag = 'alcohol', int every = 4, double low = 70}) {
    final tags = <String, Set<String>>{};
    final scores = <String, Map<String, dynamic>>{};
    for (var i = 2; i <= 28; i++) {
      final tagged = i % every == 0;
      tags[night(i)] = {if (tagged) tag};
      scores[night(i - 1)] = {
        'capacity': {'score': tagged ? low : 80},
      };
    }
    return (tags: tags, scores: scores);
  }

  test('a tag uses the research default until there are 3 such nights', () {
    final factors = energyFactors(
      today: today,
      tagsByNight: {
        night(1): {'alcohol'},
      },
      scores: const {},
    );
    expect(factors.single.id, 'alcohol');
    expect(factors.single.pressure, 0.08);
    expect(factors.single.personal, isNull);
    expect(factors.single.reason, contains('tends to make sleep lighter'));
  });

  test('your own mornings replace the default', () {
    final h = history();
    final factors = energyFactors(
      today: today,
      tagsByNight: {
        ...h.tags,
        night(1): {'alcohol'},
      },
      scores: h.scores,
    );
    expect(factors.single.personal, 10);
    expect(factors.single.pressure, closeTo(0.08, 1e-9));
    expect(factors.single.reason, contains('about 10 lower'));

    final none = history(low: 79);
    final calm = energyFactors(
      today: today,
      tagsByNight: {
        ...none.tags,
        night(1): {'alcohol'},
      },
      scores: none.scores,
    ).single;
    expect(calm.pressure, 0);
    expect(calm.reason, contains("hasn't made much difference"));
  });

  test('untagged nights and other tags add nothing', () {
    expect(
      energyFactors(
        today: today,
        tagsByNight: {night(1): <String>{}},
        scores: const {},
      ),
      isEmpty,
    );
  });

  test('a hard training day yesterday slows today', () {
    Map<String, Map<String, dynamic>> load(double value) => {
      localDayKey(today): {
        'trainingLoad': {
          'days': [
            {'day': night(2), 'value': 2.0},
            {'day': night(1), 'value': value},
          ],
        },
      },
    };
    expect(
      energyFactors(
        today: today,
        tagsByNight: const {},
        scores: load(1.6),
      ).single.id,
      hardTrainingFactor,
    );
    expect(
      energyFactors(today: today, tagsByNight: const {}, scores: load(1.2)),
      isEmpty,
    );
  });

  test('factors lower the curve and explain themselves', () {
    final nights = [
      for (var i = 0; i < 14; i++)
        (
          start: DateTime(2026, 10, 9 - i, 23),
          end: DateTime(2026, 10, 10 - i, 7),
          asleepHours: i == 0 ? 6.5 : 8.0,
        ),
    ];
    final plain = forecastEnergy(day: today, nights: nights, sleepNeedHours: 8);
    final tagged = forecastEnergy(
      day: today,
      nights: nights,
      sleepNeedHours: 8,
      factors: energyFactors(
        today: today,
        tagsByNight: {
          night(1): {'alcohol', 'late_meal'},
        },
        scores: const {},
      ),
    );
    final at10 = DateTime(2026, 10, 10, 10);
    expect(plain.at(at10)! - tagged.at(at10)!, greaterThan(0.03));
    expect(
      energyReasons(tagged).map((r) => r.$2),
      contains(contains('tagged alcohol')),
    );
    expect(energySleepLines(tagged), (
      sleep: '6 h 30 asleep · 1 h 30 under your need',
      tags: 'Alcohol and late meal last night',
    ));
    expect(energySleepLines(plain).tags, isNull);
  });
}
