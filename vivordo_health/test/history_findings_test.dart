import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/history_findings.dart';

void main() {
  final today = DateTime(2026, 10, 11);

  HistoryDay day(
    int daysAgo, {
    double? capacity = 75,
    double? sleep,
    double sleepNeed = 7.5,
    double? hrv,
    double? restingHr,
    String? restingHrKind = 'resting',
    double? effort,
    double? afterHours,
  }) => (
    day: today.subtract(Duration(days: daysAgo)),
    capacity: capacity,
    sleepHours: sleep,
    sleepNeed: sleepNeed,
    hrv: hrv,
    restingHr: restingHr,
    restingHrKind: restingHrKind,
    effort: effort,
    afterHoursMinutes: afterHours,
  );

  test('sleep against the next morning\'s HRV comes first', () {
    final found = historyFindings([
      for (var i = 1; i <= 4; i++) day(i, sleep: 8, hrv: 66),
      for (var i = 5; i <= 8; i++) day(i, sleep: 6, hrv: 55),
    ], today: today);
    expect(
      found.insight,
      'After 7½ hours or more of sleep, your HRV the next morning was 20% '
      'higher.',
    );
    expect(found.basis, 'Based on 8 nights.');
  });

  test(
    'resting heart rate when HRV shows nothing, never the sleeping kind',
    () {
      List<HistoryDay> week(String kind) => [
        for (var i = 1; i <= 4; i++)
          day(i, sleep: 8, hrv: 60, restingHr: 50, restingHrKind: kind),
        for (var i = 5; i <= 8; i++)
          day(i, sleep: 6, hrv: 60, restingHr: 54, restingHrKind: kind),
      ];
      expect(
        historyFindings(week('resting'), today: today).insight,
        'After 7½ hours or more of sleep, your resting heart rate the next '
        'morning was 4 bpm lower.',
      );
      expect(historyFindings(week('sleeping'), today: today).insight, isNull);
    },
  );

  test('the heaviest weekday needs 3 of every weekday', () {
    // Oct 11, 2026 is a Sunday; 21 days back covers each weekday 3 times.
    final days = [
      for (var i = 1; i <= 21; i++)
        day(
          i,
          effort: today.subtract(Duration(days: i)).weekday == DateTime.thursday
              ? 70
              : 30,
        ),
    ];
    final found = historyFindings(days, today: today);
    expect(found.insight, 'Thursdays are your heaviest day.');
    expect(found.usuals.last, (value: 'Thu', label: 'heaviest day'));
    expect(
      historyFindings(days.take(13).toList(), today: today).insight,
      isNull,
    );
  });

  test('nights after hours in the last 28 days', () {
    final found = historyFindings([
      for (var i = 1; i <= 20; i++) day(i, afterHours: i % 3 == 0 ? 60 : 0),
    ], today: today);
    expect(found.insight, 'You worked after hours on 6 of the last 20 days.');
    expect(found.usuals.last, (value: '6 of 20', label: 'days after hours'));
  });

  test('a change in resting heart rate since the start of the history', () {
    final found = historyFindings([
      for (var i = 60; i < 66; i++) day(i, restingHr: 55),
      for (var i = 1; i <= 6; i++) day(i, restingHr: 52),
    ], today: today);
    expect(
      found.insight,
      'Your resting heart rate is 3 bpm lower than in July.',
    );
  });

  test('without a strong pattern: no insight, just the usuals', () {
    final found = historyFindings([
      for (var i = 1; i <= 6; i++)
        day(i, capacity: 80, sleep: 7.25, hrv: 60, restingHr: 51),
    ], today: today);
    expect(found.insight, isNull);
    expect(found.usuals, [
      (value: '7h 15m', label: 'sleep a night'),
      (value: '80', label: 'Capacity'),
      (value: '51 bpm', label: 'resting heart rate'),
    ]);
    expect(
      historyFindings(
        [day(1, capacity: 80, sleep: 7)],
        today: today,
        numbers: false,
      ).usuals.map((u) => u.label),
      ['sleep a night'],
    );
  });
}
