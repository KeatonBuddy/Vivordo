import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'package:vivordo_health/src/utils/metrics_insights.dart';

void main() {
  final today = DateTime(2026, 10, 7);
  String day(int back) =>
      localDayKey(DateTime(today.year, today.month, today.day - back));

  /// 35 days of scores; [recent] overrides the last 7 (0 = today).
  Map<String, Map<String, dynamic>> history({
    // 12 min under the 7.5 h need: neither short nor met.
    double usualSleep = 7.3,
    double recentSleep = 7.3,
    double usualCapacity = 78,
    double recentCapacity = 78,
    double usualEffort = 30,
    double recentEffort = 30,
    double recentAfterHours = 0,
  }) => {
    for (var back = 0; back < 35; back++)
      day(back): {
        'capacity': {
          'score': back < 7 ? recentCapacity : usualCapacity,
          'sleepHours': back < 7 ? recentSleep : usualSleep,
          'sleepNeed': 7.5,
        },
        'effort': {
          'total': back < 8 ? recentEffort : usualEffort,
          'afterHoursMinutes': back < 8 ? recentAfterHours : 0,
        },
      },
  };

  List<MetricsInsightKind> kinds(List<MetricsInsight> insights) =>
      insights.map((i) => i.kind).toList();

  test('a usual week has nothing to say', () {
    expect(metricsInsights(history(), today), isEmpty);
  });

  test('a hard week lists concerns first, at most three', () {
    final insights = metricsInsights(
      history(
        recentSleep: 6.5,
        recentCapacity: 66,
        recentEffort: 45,
        recentAfterHours: 40,
      ),
      today,
    );
    expect(kinds(insights), [
      MetricsInsightKind.sleep,
      MetricsInsightKind.energy,
      MetricsInsightKind.effort,
    ]);
    expect(insights.every((i) => i.tone == MetricsInsightTone.concern), true);
    expect(
      insights.first.text,
      'Sleep averaged 6h 30m this week, 60 min under your need of 7h 30m.',
    );
    expect(insights[1].text, contains('Capacity averaged 66'));
    expect(insights[1].text, contains('your usual 78'));
  });

  test('after-hours plans count only past two hours a week', () {
    expect(
      kinds(metricsInsights(history(recentAfterHours: 17), today)),
      isEmpty,
    );
    final insights = metricsInsights(history(recentAfterHours: 20), today);
    expect(kinds(insights), [MetricsInsightKind.afterHours]);
    expect(insights.single.text, contains('2h 20m'));
  });

  test('good news when sleep meets the need and energy is up', () {
    final insights = metricsInsights(
      history(usualSleep: 7, recentSleep: 7.6, recentCapacity: 86),
      today,
    );
    expect(kinds(insights), [
      MetricsInsightKind.sleep,
      MetricsInsightKind.energy,
    ]);
    expect(insights.every((i) => i.tone == MetricsInsightTone.good), true);
  });

  test('today\'s growing Effort is left out', () {
    final days = history(recentEffort: 30);
    (days[day(0)]!['effort'] as Map)['total'] = 500;
    expect(metricsInsights(days, today), isEmpty);
  });

  test('too little data stays quiet instead of guessing', () {
    final days = {
      for (var back = 0; back < 3; back++)
        day(back): {
          'capacity': {'score': 40, 'sleepHours': 4.0, 'sleepNeed': 8.0},
        },
    };
    expect(metricsInsights(days, today), isEmpty);
  });

  test('Physical Health adds its easiest win', () {
    final days = history();
    days[day(0)]!['physical'] = {
      'score': 62,
      'label': 'fair',
      'parts': {'activeMinutes': 40, 'sleep': 100},
      'details': {'weeklyActiveMinutes': 60, 'sleepHours': 7.5},
    };
    final insights = metricsInsights(days, today);
    expect(kinds(insights), [MetricsInsightKind.physical]);
    expect(insights.single.text, contains('90 short a week'));
  });
}
