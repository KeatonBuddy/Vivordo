import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/detail_insights.dart';

void main() {
  final today = DateTime(2026, 10, 8, 15);
  DateTime back(int days) => DateTime(2026, 10, 8 - days);
  DayValues days(
    double Function(int back) value, {
    int from = 0,
    int to = 60,
  }) => {for (var i = from; i < to; i++) back(i): value(i)};
  String time(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  group('steps and calories', () {
    test('Day: progress to the goal and past the usual day', () {
      final values = days((i) => i == 0 ? 9200 : 8000);
      final insight = countInsight(
        values: values,
        today: today,
        rangeDays: 1,
        goal: 10000,
        unit: 'steps',
      );
      expect(
        insight.text,
        '9,200 steps so far. 800 to go for your 10,000 goal, already past '
        'your usual day of 8,000.',
      );
      expect(
        countInsight(
          values: {back(0): 10500},
          today: today,
          rangeDays: 1,
          goal: 10000,
          unit: 'steps',
        ).tone,
        InsightTone.good,
      );
    });

    test('Week: average against the week before and goal days', () {
      final values = days((i) => i <= 7 ? 9000 : 7000);
      final insight = countInsight(
        values: values,
        today: today,
        rangeDays: 7,
        goal: 8000,
        unit: 'steps',
      );
      expect(
        insight.text,
        'You averaged 9,000 steps a day over the last 7 full days, 2,000 more '
        'than the 7 days before. You reached your goal on 7 of them.',
      );
      expect(insight.tone, InsightTone.good);
    });

    test('Week: small changes read as about the same', () {
      final insight = countInsight(
        values: days((i) => i <= 7 ? 520 : 500),
        today: today,
        rangeDays: 7,
        goal: 600,
        unit: 'kcal',
        fewer: 'less',
      );
      expect(insight.text, contains('about the same as the 7 days before'));
      expect(insight.text, contains('goal on 0 of them'));
    });

    test('too few days says so instead of guessing', () {
      expect(
        countInsight(
          values: {back(1): 5000},
          today: today,
          rangeDays: 7,
          goal: 8000,
          unit: 'steps',
        ).text,
        startsWith('Not enough days'),
      );
    });
  });

  group('usual for this time of day', () {
    // 500 steps every hour from 8 AM to 8 PM on each earlier day.
    final day = [for (var h = 0; h < 24; h++) h >= 8 && h < 20 ? 500.0 : 0.0];
    DayHours history(int days) => {
      for (var i = 1; i <= days; i++) back(i): day,
    };

    test('the usual is the median total by the same minute', () {
      // By 3:30 PM: 7 full hours (3,500) plus half of the 3 PM hour.
      expect(usualByNow(history(7), DateTime(2026, 10, 8, 15, 30)), 3750);
      expect(usualByNow(history(6), DateTime(2026, 10, 8, 15, 30)), isNull);
    });

    test('Day: above, below or about the usual, plus the goal', () {
      String text(double now) => countInsight(
        values: {back(0): now},
        today: today,
        rangeDays: 1,
        goal: 10000,
        unit: 'steps',
        hours: history(10),
      ).text;
      // At 3 PM the usual is 3,500.
      expect(
        text(4600),
        '4,600 steps so far, 1,100 above your usual for this time of day. '
        '5,400 to go for your 10,000 goal.',
      );
      expect(
        text(2500),
        contains('1,000 below your usual for this time of day'),
      );
      expect(text(3600), contains('about your usual for this time of day'));
    });

    test('without a week of hours it falls back to the day total', () {
      expect(
        countInsight(
          values: {back(0): 4600},
          today: today,
          rangeDays: 1,
          goal: 10000,
          unit: 'steps',
          hours: history(3),
        ).text,
        '4,600 steps so far. 5,400 to go for your 10,000 goal.',
      );
    });
  });

  group('mood', () {
    test('Day: today\'s check-in against the usual', () {
      final insight = moodInsight(
        values: days((i) => 50, from: 1),
        todayCheckIns: [MoodCheckIn(DateTime(2026, 10, 8, 9, 12), 75, 'Good')],
        today: today,
        rangeDays: 1,
        time: time,
      );
      expect(
        insight.text,
        'You checked in Good at 9:12, brighter than your usual Okay.',
      );
      expect(insight.tone, InsightTone.good);
    });

    test('Day: no check-in yet', () {
      expect(
        moodInsight(
          values: days((i) => 75, from: 1),
          todayCheckIns: const [],
          today: today,
          rangeDays: 1,
          time: time,
        ).text,
        'No check-in yet today. Lately you\'ve usually felt Good.',
      );
    });

    test('Week: check-in days and typical mood', () {
      final values = {back(0): 75.0, back(2): 75.0, back(3): 50.0};
      final insight = moodInsight(
        values: values,
        todayCheckIns: const [],
        today: today,
        rangeDays: 7,
        time: time,
      );
      expect(
        insight.text,
        'You checked in on 3 of 7 days, mostly feeling Good.',
      );
    });

    test('scores map to the check-in words', () {
      expect(moodWord(10), 'Awful');
      expect(moodWord(33), 'Down');
      expect(moodWord(66), 'Good');
    });
  });

  group('sleep', () {
    final nights = {
      for (var i = 1; i < 20; i++)
        back(i): SleepNight(7.5, DateTime(2026, 10, 8 - i - 1, 23)),
    };

    test('Day: last night against the usual, with a late bedtime', () {
      final insight = sleepInsight(
        nights: {
          ...nights,
          back(0): SleepNight(6.5, DateTime(2026, 10, 8, 0, 30)),
        },
        today: today,
        rangeDays: 1,
      );
      expect(
        insight.text,
        '6h 30m last night, 1h 00m less than your usual 7h 30m. Bedtime was '
        '1h 30m later than usual.',
      );
      expect(insight.tone, InsightTone.concern);
    });

    test('Day: about usual, and nothing synced yet', () {
      expect(
        sleepInsight(
          nights: {
            ...nights,
            back(0): SleepNight(7.4, DateTime(2026, 10, 7, 23)),
          },
          today: today,
          rangeDays: 1,
        ).text,
        '7h 24m last night, about your usual.',
      );
      expect(
        sleepInsight(nights: nights, today: today, rangeDays: 1).text,
        'Last night\'s sleep hasn\'t synced yet. Your usual is 7h 30m.',
      );
    });

    test('Week: average and bedtime regularity', () {
      final insight = sleepInsight(
        nights: {
          ...nights,
          back(0): SleepNight(7.5, DateTime(2026, 10, 8, 1, 30)),
        },
        today: today,
        rangeDays: 7,
      );
      expect(
        insight.text,
        'You averaged 7h 30m a night over 7 nights, about your usual. Bedtime '
        'was within an hour of usual on 6 of 7 nights.',
      );
    });
  });

  group('heart rate', () {
    test('Day: resting against the normal', () {
      expect(
        heartInsight(
          isDay: true,
          rangeDays: 1,
          todayResting: 61,
          restingNormal: 55,
        ).text,
        'Resting heart rate 61 bpm, 6 above your normal 55.',
      );
      expect(
        heartInsight(
          isDay: true,
          rangeDays: 1,
          todayResting: 55.4,
          restingNormal: 55,
        ).text,
        'Resting heart rate 55 bpm, in line with your normal 55.',
      );
    });

    test('Day: no resting value yet uses the readings without advice', () {
      expect(
        heartInsight(
          isDay: true,
          rangeDays: 1,
          todayReadings: const [62, 140, 70],
          restingNormal: 54,
        ).text,
        'No resting heart rate yet today. Readings so far ranged 62–140 bpm, '
        'and your resting normal is 54 bpm.',
      );
    });

    test('Week: no "improved by 0" for no change', () {
      final same = heartInsight(
        isDay: false,
        rangeDays: 7,
        rangeResting: 56.2,
        priorResting: 56.0,
      );
      expect(
        same.text,
        'Resting heart rate averaged 56 bpm, about the same as the 7 days before.',
      );
      final lower = heartInsight(
        isDay: false,
        rangeDays: 7,
        rangeResting: 53,
        priorResting: 56,
      );
      expect(lower.text, contains('3 lower than the 7 days before'));
      expect(lower.tone, InsightTone.good);
    });

    test('the normal needs a week of resting values', () {
      expect(restingNormal(days((i) => 55, from: 1, to: 6), today), isNull);
      expect(restingNormal(days((i) => 55, from: 1, to: 20), today), 55);
    });
  });

  group('exercise', () {
    test('Day: today against the goal and the last 7 days', () {
      expect(
        exerciseInsight(
          minutes: days((i) => i == 0 ? 12 : 20, to: 10),
          today: today,
          rangeDays: 1,
          goal: 30,
        ).text,
        '12 min of exercise today, 18 to go for your 30-minute goal. 132 min '
        'over the last 7 days.',
      );
    });

    test('Week: like-for-like totals and no "increased by 0"', () {
      final same = exerciseInsight(
        minutes: {back(2): 30, back(4): 30, back(9): 30, back(11): 30},
        today: today,
        rangeDays: 7,
        goal: 30,
      );
      expect(
        same.text,
        '60 min over the last 7 full days, active on 2 of them, about the same '
        'as the 7 days before. You met your 30-minute goal on 2.',
      );
      final more = exerciseInsight(
        minutes: {back(2): 60, back(4): 30, back(9): 30},
        today: today,
        rangeDays: 7,
        goal: 30,
      );
      expect(more.text, contains('60 min more than the 7 days before'));
      expect(more.tone, InsightTone.good);
    });
  });
}
