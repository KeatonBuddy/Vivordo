import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'package:vivordo_health/src/services/hourly_calendar_load.dart';
import 'package:vivordo_health/src/utils/day_agenda.dart';
import 'package:vivordo_health/src/utils/home_day_load.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 29, hour, minute);

  test('levels use the calendar load cut points', () {
    expect(dayLoadLevel(null), DayLoadLevel.none);
    expect(dayLoadLevel(0), DayLoadLevel.none);
    expect(dayLoadLevel(29), DayLoadLevel.light);
    expect(dayLoadLevel(30), DayLoadLevel.focused);
    expect(dayLoadLevel(60), DayLoadLevel.heavy);
    expect(dayLoadLevel(priorityLoad(null)), DayLoadLevel.focused);
    expect(dayLoadLevel(priorityLoad('light')), DayLoadLevel.light);
    expect(dayLoadLevel(priorityLoad('moderate')), DayLoadLevel.focused);
    expect(dayLoadLevel(priorityLoad('demanding')), DayLoadLevel.heavy);
  });

  /// One hour's load from 9 AM, as the Home bars compute it.
  double? loadAt9({
    List<({CalendarCognitiveEvent event, CognitiveLoadScore score})> items =
        const [],
  }) {
    final hour = HourlyCalendarLoadCalculator.calculate(
      events: [for (final i in items) i.event],
      scores: [for (final i in items) i.score],
      from: at(9),
      until: at(10),
    ).single;
    return hour.score;
  }

  ({CalendarCognitiveEvent event, CognitiveLoadScore score}) meeting(
    String id,
    DateTime start,
    DateTime end, {
    required int score,
    double confidence = 1,
  }) => (
    event: CalendarCognitiveEvent(id: id, title: id, start: start, end: end),
    score: CognitiveLoadScore(
      eventId: id,
      score: score,
      category: confidence > 0 ? 'meeting' : 'unknown',
      reason: '',
      usedAi: false,
      confidence: confidence,
    ),
  );

  test('a priority counts for the minutes it covers', () {
    // Demanding for the whole hour is heavy; for half of it, focused.
    final full = priorityLoadInput(
      id: 'p',
      title: 'Deck',
      start: at(9),
      end: at(10),
      effort: 'demanding',
    );
    final half = priorityLoadInput(
      id: 'p',
      title: 'Deck',
      start: at(9),
      end: at(9, 30),
      effort: 'demanding',
    );
    expect(dayLoadLevel(loadAt9(items: [full])), DayLoadLevel.heavy);
    expect(loadAt9(items: [half]), 37.5);
    expect(dayLoadLevel(loadAt9(items: [half])), DayLoadLevel.focused);
  });

  test('a priority on top of a meeting adds overlap pressure', () {
    final call = meeting('call', at(9), at(10), score: 50);
    final priority = priorityLoadInput(
      id: 'p',
      title: 'Notes',
      start: at(9),
      end: at(10),
    );
    expect(dayLoadLevel(loadAt9(items: [call])), DayLoadLevel.focused);
    expect(loadAt9(items: [call, priority]), 60);
    expect(dayLoadLevel(loadAt9(items: [call, priority])), DayLoadLevel.heavy);
  });

  test('bars cover 7 AM to 10 PM, stretched to fit the day', () {
    ({DateTime start, DateTime end}) item(DateTime start, DateTime end) =>
        (start: start, end: end);
    final day = at(12);

    final normal = dayLoadRange(day, [item(at(9), at(10))]);
    expect((normal.from, normal.until), (at(7), at(22)));

    // A 6:30 AM run and a call ending 10:15 PM pull both edges out to whole
    // hours.
    final stretched = dayLoadRange(day, [
      item(at(6, 30), at(7, 15)),
      item(at(21, 30), at(22, 15)),
    ]);
    expect((stretched.from, stretched.until), (at(6), at(23)));

    // Items running over midnight stop at the edges of today; other days
    // are ignored.
    final overnight = dayLoadRange(day, [
      item(DateTime(2026, 9, 28, 23), at(1)),
      item(at(23), DateTime(2026, 9, 30, 2)),
      item(DateTime(2026, 9, 30, 5), DateTime(2026, 9, 30, 6)),
    ]);
    expect((overnight.from, overnight.until), (at(0), DateTime(2026, 9, 30)));
  });

  test('next opening names what follows it', () {
    final opening = nextDayOpening(at(15, 50), [
      AgendaItem('Standup', at(9), at(9, 30)),
      AgendaItem('Review', at(15), at(16)),
      AgendaItem('Investor update', at(17, 30), at(18)),
    ]);
    expect(opening?.start, at(16));
    expect(opening?.end, at(17, 30));
    expect(opening?.next, 'Investor update');
  });

  test('the rest of the day is an opening with nothing after it', () {
    final opening = nextDayOpening(at(21), const []);
    expect(opening?.start, at(21));
    expect(opening?.end, isNull);
    expect(opening?.next, isNull);
  });

  test('no opening when the day is booked to midnight', () {
    expect(
      nextDayOpening(at(22), [
        AgendaItem('Late shift', at(21), DateTime(2026, 9, 30)),
      ]),
      isNull,
    );
  });
}
