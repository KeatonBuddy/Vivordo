import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'package:vivordo_health/src/utils/meeting_patterns.dart';
import 'package:vivordo_health/src/utils/weekly_review.dart';

void main() {
  final sunday = DateTime(2026, 10, 4);
  DateTime at(int i) => DateTime(2026, 10, 4 + i);

  /// 28 usual days (Capacity 75, parts at 70/70/80) then the week's days.
  Map<String, Map<String, dynamic>> scores(
    List<Map<String, dynamic>?> week, {
    double usualAfterHours = 10,
  }) => {
    for (var i = 1; i <= 28; i++)
      localDayKey(sunday.subtract(Duration(days: i))): {
        'capacity': {
          'score': 75,
          'version': 2,
          'parts': {'sleep': 70, 'body': 70, 'recovery': 80},
        },
        'effort': {'total': 50, 'afterHoursMinutes': usualAfterHours},
      },
    for (var i = 0; i < week.length; i++)
      if (week[i] != null) localDayKey(at(i)): week[i]!,
  };

  Map<String, dynamic> day({
    double capacity = 75,
    double effort = 50,
    Map<String, double> parts = const {'sleep': 70, 'body': 70, 'recovery': 80},
    double? sleep,
    double sleepNeed = 7.5,
    double? restingHr,
    double? feel,
    int done = 0,
    int left = 0,
    int backToBack = 0,
  }) => {
    'capacity': {
      'score': capacity,
      'version': 2,
      'parts': parts,
      'sleepHours': ?sleep,
      'sleepNeed': sleepNeed,
      'restingHr': ?restingHr,
      'restingHrNormal': restingHr == null ? null : 55,
      'checkInFeel': ?feel,
    },
    'effort': {
      'total': effort,
      'prioritiesDone': done,
      'unfinishedPriorities': left,
      'backToBack': backToBack,
    },
  };

  test('needs Capacity on 4 of the 7 days', () {
    expect(
      buildWeeklyReview(
        WeeklyReviewInput(
          weekStart: sunday,
          scores: scores([day(), day(), day(), null, null, null, null]),
        ),
      ),
      isNull,
    );
  });

  test('more or less energy than usual, rather than "mixed"', () {
    String headline(double capacity) => buildWeeklyReview(
      WeeklyReviewInput(
        weekStart: sunday,
        scores: scores([for (var i = 0; i < 7; i++) day(capacity: capacity)]),
      ),
    )!.headline;
    expect(headline(82), 'A week with more energy than usual');
    expect(headline(69), 'A lower-energy week');
    expect(headline(77), 'A lighter, steadier week');
  });

  test(
    'training load stands without logged workouts; learning is left out',
    () {
      String? row(String state, {int workouts = 0}) {
        final week = [for (var i = 0; i < 7; i++) day()];
        week[6]['trainingLoad'] = {'state': state};
        final review = buildWeeklyReview(
          WeeklyReviewInput(
            weekStart: sunday,
            scores: scores(week),
            workouts: workouts,
          ),
        )!;
        final found = review.rows.where(
          (r) => r.label == 'Workouts' || r.label == 'Training load',
        );
        return found.isEmpty
            ? null
            : '${found.single.label}: ${found.single.value}';
      }

      expect(row('building'), 'Training load: Building');
      expect(row('learning'), isNull);
      expect(row('learning', workouts: 2), 'Workouts: 2');
      expect(row('steady', workouts: 3), 'Workouts: 3 · training load steady');
    },
  );

  test('a heavy week you handled well, and one that wore on you', () {
    final handled = buildWeeklyReview(
      WeeklyReviewInput(
        weekStart: sunday,
        scores: scores([
          day(),
          day(effort: 95, backToBack: 5, done: 3, left: 2),
          day(effort: 92),
          day(effort: 94),
          day(),
          day(),
          day(feel: 75),
        ]),
      ),
    )!;
    expect(handled.headline, 'A heavy week you handled well');
    expect(handled.chips.first, '3 heavy days');
    expect(handled.drained.first.title, 'Monday: 5 back-to-backs');
    expect(handled.rows.map((r) => r.label), contains('Mood'));

    final wore = buildWeeklyReview(
      WeeklyReviewInput(
        weekStart: sunday,
        scores: scores([
          day(capacity: 78),
          day(capacity: 76, effort: 95),
          day(capacity: 74, effort: 92),
          day(capacity: 70, effort: 94),
          day(capacity: 66),
          day(capacity: 64),
          day(capacity: 62),
        ]),
      ),
    )!;
    expect(wore.headline, 'A heavy week that wore on you');
  });

  test('a sick week names the body as the reason, and spares meetings', () {
    final low = {'sleep': 70.0, 'body': 40.0, 'recovery': 80.0};
    final review = buildWeeklyReview(
      WeeklyReviewInput(
        weekStart: sunday,
        scores: scores([
          day(),
          day(),
          day(capacity: 62, parts: low, restingHr: 61),
          day(capacity: 63, parts: low, restingHr: 61),
          day(capacity: 64, parts: low, restingHr: 60),
          day(),
          day(),
        ]),
        nightTags: {
          localDayKey(at(1)): ['sick'],
        },
        reactions: [
          // On an off day (Tuesday): not counted.
          MeetingReaction(
            day: at(2),
            key: 'a',
            series: 's1',
            category: 'collaboration',
            guests: 5,
            minutes: 60,
            startHour: 14,
            median: 80,
            usual: 68,
          ),
        ],
      ),
    )!;
    expect(review.headline, 'A tough week while you were unwell');
    expect(review.drained.first.kind, 'sick');
    expect(
      review.drained.first.detail,
      contains('resting heart rate was up about 6 bpm'),
    );
    expect(review.drained.any((l) => l.kind == 'meeting'), isFalse);
    expect(review.offDayNote, contains('meetings then'));
    expect(review.days[2].sick, isTrue);
  });

  test('a meeting that ran high on a normal day is named by series', () {
    final review = buildWeeklyReview(
      WeeklyReviewInput(
        weekStart: sunday,
        scores: scores([day(), day(), day(), day(), day(), day(), day()]),
        reactions: [
          for (final i in [1, 3])
            MeetingReaction(
              day: at(i),
              key: 'k$i',
              series: 's1',
              category: 'collaboration',
              guests: 6,
              minutes: 60,
              startHour: 14,
              median: 80,
              usual: 68,
            ),
        ],
      ),
    )!;
    final line = review.drained.single;
    expect(line.seriesKey, 's1');
    expect(line.title, isEmpty);
    expect(line.detail, contains('2 times'));
    expect(review.headline, 'A lighter, steadier week');
  });

  test('sleeping your need helps when the mornings show it', () {
    final review = buildWeeklyReview(
      WeeklyReviewInput(
        weekStart: sunday,
        scores: scores([
          day(sleep: 7.6, capacity: 82),
          day(sleep: 7.5, capacity: 80),
          day(sleep: 6.0, capacity: 70),
          day(sleep: 6.2, capacity: 72),
          day(sleep: 7.8, capacity: 81),
          day(sleep: 6.1, capacity: 71),
          day(sleep: 7.6, capacity: 80),
        ]),
      ),
    )!;
    expect(review.helped.first.title, 'Sleeping your need');
    expect(review.helped.first.detail, contains('about 10 points higher'));
    expect(review.rows.first.value, contains('4 of 7 on target'));
  });

  test('next week: labels, headline and a slot for a slipping priority', () {
    final review = buildWeeklyReview(
      WeeklyReviewInput(
        weekStart: sunday,
        scores: scores([day(), day(), day(), day(), day(), day(), day()]),
        openPriorities: [
          (title: 'Finalize pitch deck', since: DateTime(2026, 10, 5)),
        ],
        nextWeek: [
          (day: DateTime(2026, 10, 12), demand: 95),
          (day: DateTime(2026, 10, 13), demand: 75),
          (day: DateTime(2026, 10, 14), demand: 40),
          (day: DateTime(2026, 10, 15), demand: 96),
          (day: DateTime(2026, 10, 16), demand: 55),
        ],
      ),
    )!;
    expect(review.nextWeek.map((d) => d.label), [
      'More than your usual',
      'About usual',
      'Light',
      'More than your usual',
      'Light',
    ]);
    expect(review.nextHeadline, 'Busier than this one');
    expect(
      review.suggestion,
      'Give "Finalize pitch deck" a slot on Wednesday, your lightest day.',
    );
    expect(
      review.drained.single.title,
      '"Finalize pitch deck" has been open since Monday',
    );
  });

  test('saves and reads back, with the week\'s context', () {
    final review = buildWeeklyReview(
      WeeklyReviewInput(
        weekStart: sunday,
        scores: scores([day(), day(), day(), day(), day(), day(), day()]),
      ),
    )!.withContext(['Travel'], 'Moving apartments');
    final back = WeeklyReview.fromMap(review.toMap())!;
    expect(back.headline, review.headline);
    expect(back.days.length, 7);
    expect(back.context, ['Travel']);
    expect(back.note, 'Moving apartments');
    expect(back.range, 'Oct 4 – 10');
    expect(back.readOn, DateTime(2026, 10, 11));
    expect(back.matches('moving', (l) => l.title), isTrue);
    expect(back.matches('marathon', (l) => l.title), isFalse);
    expect(review.chatContext((l) => l.title), contains('Moving apartments'));
  });

  test('the review on any day covers the Sunday-to-Saturday before', () {
    expect(reviewWeekStart(DateTime(2026, 10, 11)), DateTime(2026, 10, 4));
    expect(reviewWeekStart(DateTime(2026, 10, 14)), DateTime(2026, 10, 4));
    expect(reviewWeekStart(DateTime(2026, 10, 17)), DateTime(2026, 10, 4));
  });

  test('day lists only make ranges of consecutive days', () {
    DateTime d(int day) => DateTime(2026, 10, day); // Oct 4 is a Sunday
    expect(weekdayList([d(6)]), 'Tuesday');
    expect(weekdayList([d(4), d(10)]), 'Sunday and Saturday');
    // Oct 4–10: Sun, Mon, Tue and Sat flagged, Wed–Fri normal.
    expect(weekdayList([d(4), d(5), d(6), d(10)]), 'Sun–Tue and Sat');
    expect(weekdayList([d(4), d(6), d(8)]), 'Sun, Tue and Thu');
    expect(weekdayList([for (var i = 4; i <= 10; i++) d(i)]), 'Sun–Sat');
  });

  test('after-hours is only compared with weeks that had Effort', () {
    String? afterHoursLine(Map<String, Map<String, dynamic>> history) {
      final week = [
        for (var i = 0; i < 7; i++)
          day()..['effort'] = {'total': 50, 'afterHoursMinutes': 30.0},
      ];
      final review = buildWeeklyReview(
        WeeklyReviewInput(
          weekStart: sunday,
          scores: {
            ...history,
            for (var i = 0; i < 7; i++) localDayKey(at(i)): week[i],
          },
        ),
      );
      return review!.drained
          .where((l) => l.title == 'After-hours work')
          .map((l) => l.detail)
          .firstOrNull;
    }

    Map<String, Map<String, dynamic>> weeks(int count, double minutes) => {
      for (var i = 1; i <= 7 * count; i++)
        localDayKey(sunday.subtract(Duration(days: i))): {
          'capacity': {'score': 75, 'version': 2},
          'effort': {'total': 50, 'afterHoursMinutes': minutes},
        },
    };
    // 3h 30m this week; only one earlier week of Effort, so no usual.
    expect(afterHoursLine(weeks(1, 0)), isNull);
    // Four earlier weeks at 0 a day: all of it is more than usual.
    expect(
      afterHoursLine(weeks(4, 0)),
      '3h 30m after hours, 3h 30m more than usual.',
    );
    // 10 minutes a day before (1h 10m a week): 2h 20m more than usual.
    expect(
      afterHoursLine(weeks(4, 10)),
      '3h 30m after hours, 2h 20m more than usual.',
    );
  });
}
