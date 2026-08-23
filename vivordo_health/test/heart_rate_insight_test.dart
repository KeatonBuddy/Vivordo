import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/heart_rate_insight.dart';

void main() {
  final start = DateTime(2026, 8, 23, 8);

  List<HeartRateInsightReading> series(List<double> values) => [
    for (var index = 0; index < values.length; index += 1)
      HeartRateInsightReading(
        bpm: values[index],
        timestamp: start.add(Duration(minutes: index * 5)),
      ),
  ];

  String dayInsight(List<double> values, {double? heartHealthScore = 80}) {
    return buildHeartRateInsight(
      isDay: true,
      readings: series(values),
      heartHealthScore: heartHealthScore,
      restingAverage: null,
      restingChange: null,
    );
  }

  test('missing data gives a short collection prompt', () {
    expect(dayInsight(const []), contains('No readings yet'));
  });

  test('limited data asks for more readings', () {
    expect(dayInsight([70, 72, 74]), contains('More readings are needed'));
  });

  test('low Heart Health score prioritizes rest', () {
    final insight = dayInsight([65, 67, 69, 68, 66, 67], heartHealthScore: 32);
    expect(insight, contains('Keep activity light and prioritize rest'));
  });

  test('below-target Heart Health score recommends recovery breaks', () {
    final insight = dayInsight([65, 67, 69, 68, 66, 67], heartHealthScore: 62);
    expect(insight, contains('Take recovery breaks'));
  });

  test('upward daily trend recommends a recovery break', () {
    final insight = dayInsight([62, 64, 66, 70, 76, 82, 90, 94, 98]);
    expect(insight, contains('trending up'));
  });

  test('downward daily trend recognizes settling readings', () {
    final insight = dayInsight([98, 94, 90, 84, 78, 72, 68, 64, 62]);
    expect(insight, contains('settling'));
  });

  test('high readings recommend reduced intensity', () {
    final insight = dayInsight([102, 104, 105, 106, 103, 101]);
    expect(insight, contains('Reduce intensity'));
  });

  test('mostly raised readings recommend rest', () {
    final insight = dayInsight([82, 84, 86, 88, 85, 83]);
    expect(insight, contains('short rest period'));
  });

  test('mostly low readings recommend gentle activity', () {
    final insight = dayInsight([54, 56, 58, 57, 55, 59]);
    expect(insight, contains('gentle activity'));
  });

  test('relaxed readings with a strong score reinforce normal activity', () {
    final insight = dayInsight([64, 66, 68, 70, 72, 74]);
    expect(insight, contains('looks balanced'));
    expect(insight, contains('normal activity'));
  });

  test('week and month retain resting heart-rate comparisons', () {
    final insight = buildHeartRateInsight(
      isDay: false,
      readings: series([70, 80]),
      heartHealthScore: 75,
      restingAverage: 61,
      restingChange: -3,
    );

    expect(insight, 'Your resting heart rate improved by 3 bpm.');
  });
}
