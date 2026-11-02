import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/detail_insights.dart';

void main() {
  // A Sunday afternoon; back(0) is this morning (last night).
  final today = DateTime(2026, 11, 1, 15);
  DateTime back(int i) => DateTime(2026, 11, 1 - i);
  // A night of [hours] ending at [wake] minutes after midnight.
  SleepNight night(DateTime morning, double hours, {int wake = 7 * 60}) {
    final end = morning.add(Duration(minutes: wake));
    return SleepNight(
      hours,
      end.subtract(Duration(minutes: (hours * 60).round())),
      end,
    );
  }

  Map<DateTime, SleepNight> nights(
    int count,
    SleepNight Function(DateTime morning, int back) make,
  ) => {for (var i = 0; i < count; i++) back(i): make(back(i), i)};
  List<String> ids(List<SleepPattern> patterns) => [
    for (final p in patterns) p.id,
  ];
  // The evening a night starts on.
  int evening(DateTime morning) =>
      morning.subtract(const Duration(days: 1)).weekday;

  test('needs 10 of the last 14 nights first', () {
    final patterns = sleepPatterns(
      nights: nights(6, (m, _) => night(m, 7.5)),
      today: today,
      need: 7.5,
    );
    expect(ids(patterns), ['building']);
    expect(patterns.single.body, endsWith('6 so far.'));
    expect(patterns.single.progress, closeTo(.6, .01));
  });

  test('enough sleep at steady times is good news only', () {
    final patterns = sleepPatterns(
      nights: nights(60, (m, _) => night(m, 7.5)),
      today: today,
      need: 7.5,
    );
    expect(ids(patterns), ['well_rested']);
    expect(patterns.single.tone, InsightTone.good);
  });

  test('a run of short nights, counted in nights, never hours owed', () {
    final streak = sleepPatterns(
      nights: nights(60, (m, i) => night(m, i < 4 ? 6 : 7.5)),
      today: today,
      need: 7.5,
    );
    final short = streak.first;
    expect(short.id, 'running_short');
    expect(short.tone, InsightTone.concern);
    expect(short.body, 'The last 4 nights were under your sleep need.');
    expect(short.chart!.highlight, {10, 11, 12, 13});
    expect(short.chart!.reference, 7.5);

    final often = sleepPatterns(
      nights: nights(
        60,
        (m, i) => night(m, i < 4 || (i < 14 && i.isOdd) ? 6 : 7.5),
      ),
      today: today,
      need: 7.5,
    );
    expect(
      often.first.body,
      'Under your sleep need on 9 of the last 14 nights, the last 4 in a row.',
    );
    // Not without a real need.
    expect(
      ids(
        sleepPatterns(nights: nights(60, (m, i) => night(m, 6)), today: today),
      ),
      isNot(contains('running_short')),
    );
  });

  test(
    'weekend shift on Friday and Saturday nights, not counted as irregular',
    () {
      final patterns = sleepPatterns(
        nights: nights(
          60,
          (m, _) => night(
            m,
            7.5,
            wake: evening(m) >= 5 && evening(m) <= 6 ? 570 : 420,
          ),
        ),
        today: today,
        need: 7.5,
      );
      final shift = patterns.firstWhere((p) => p.id == 'weekend_shift');
      expect(shift.tone, InsightTone.concern);
      expect(shift.body, startsWith('Your sleep runs about 2h 30m later'));
      expect(ids(patterns), isNot(contains('irregular')));
    },
  );

  test('irregular sleep times', () {
    final patterns = sleepPatterns(
      nights: nights(60, (m, i) => night(m, 7.5, wake: i % 3 == 0 ? 330 : 480)),
      today: today,
      need: 7.5,
    );
    final irregular = patterns.firstWhere((p) => p.id == 'irregular');
    expect(irregular.body, contains('from night to night'));
    expect(ids(patterns), isNot(contains('steady_wake')));
  });

  test('suddenly longer, unless long nights are the usual', () {
    final sudden = sleepPatterns(
      nights: nights(60, (m, i) => night(m, i < 5 ? 9.5 : 7.5, wake: 480)),
      today: today,
      need: 7.5,
    );
    expect(sudden.first.id, 'long_sudden');
    expect(sudden.first.action, SleepPatternAction.tagSick);

    final usual = sleepPatterns(
      nights: nights(60, (m, _) => night(m, 10.5, wake: 540)),
      today: today,
      need: 7.5,
    );
    expect(ids(usual), contains('long_usual'));
    expect(ids(usual), isNot(contains('long_sudden')));
  });

  test('a short weekday, with the likely reason', () {
    // Wednesday nights: up an hour early for Thursday.
    final wednesdays = nights(60, (m, _) {
      final wed = evening(m) == DateTime.wednesday;
      return night(m, wed ? 6.25 : 7.5, wake: wed ? 360 : 420);
    });
    final byWake = sleepPatterns(
      nights: wednesdays,
      today: today,
      need: 7.5,
    ).firstWhere((p) => p.id == 'weekday_short');
    expect(byWake.title, 'Wednesday nights run short');
    expect(
      byWake.body,
      'About 1h 15m less than your other nights. You wake about 1h 00m '
      'earlier on Thursdays, but go to bed at your usual time.',
    );
    expect(byWake.chart!.highlight, {2});
    expect(byWake.tryThis, contains('aim for bed around 10:15 PM'));

    final byCalendar = sleepPatterns(
      nights: wednesdays,
      today: today,
      need: 7.5,
      firstEvents: {
        for (var i = 0; i < 42; i++)
          back(i): back(i).weekday == DateTime.thursday ? 450 : 540,
      },
    ).firstWhere((p) => p.id == 'weekday_short');
    expect(
      byCalendar.body,
      endsWith('Thursdays usually start with something before 8:00 AM.'),
    );

    // One bad Wednesday isn't a pattern.
    final once = sleepPatterns(
      nights: nights(60, (m, i) => night(m, i == 4 ? 4 : 7.5)),
      today: today,
      need: 7.5,
    );
    expect(ids(once), isNot(contains('weekday_short')));
  });

  test('a night tag that costs sleep', () {
    final hours = <int, double>{3: 6.5, 10: 6.5, 17: 6.5, 24: 7.4};
    final patterns = sleepPatterns(
      nights: nights(60, (m, i) => night(m, hours[i] ?? 7.5)),
      today: today,
      tags: {
        for (var i = 0; i < 30; i++)
          back(i + 1): hours.containsKey(i) ? {'late_caffeine'} : <String>{},
      },
    );
    final lever = patterns.firstWhere((p) => p.id == 'tag_late_caffeine');
    expect(
      lever.body,
      'On 3 of the 4 nights you tagged late caffeine, you slept about '
      '1h 00m less than usual.',
    );
  });

  test('what the rated mornings say', () {
    final patterns = sleepPatterns(
      nights: nights(20, (m, i) => night(m, i.isEven ? 8 : 6.8)),
      today: today,
      ratings: {for (var i = 0; i < 20; i++) back(i): i.isEven ? 75 : 25},
    );
    expect(
      patterns.firstWhere((p) => p.id == 'mornings').body,
      'You rated your sleep Good or Great on 10 of 10 mornings after 7h 00m '
      'or more, and 0 of 10 after less.',
    );
  });

  test('bedtime creeping later than a month ago', () {
    final patterns = sleepPatterns(
      nights: {
        for (var i = 0; i < 14; i++) back(i): night(back(i), 6.5),
        for (var i = 28; i < 56; i++) back(i): night(back(i), 8),
      },
      today: today,
    );
    expect(
      patterns.firstWhere((p) => p.id == 'bedtime_drift').body,
      'Around 12:30 AM now, about 1h 30m later than a month ago, with the '
      'same wake time.',
    );
  });
}
