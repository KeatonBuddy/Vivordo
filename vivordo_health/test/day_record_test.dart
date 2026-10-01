import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'package:vivordo_health/src/services/day_record_service.dart';

void main() {
  final day = DateTime(2026, 10, 1);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 1, hour, minute);
  DayRecordEvent event(
    String title,
    DateTime start,
    DateTime end, {
    String? key,
    bool declined = false,
  }) {
    final input = CalendarCognitiveEvent(
      id: title,
      title: title,
      start: start,
      end: end,
      isDeclined: declined,
    );
    return (
      event: input,
      score: CalendarCognitiveLoadService.scoreLocally(input),
      key: key,
    );
  }

  DayRecordPriority priority({
    DateTime? start,
    DateTime? end,
    Object? effort,
    bool done = false,
    DateTime? doneAt,
    String? eventKey,
  }) => (
    start: start,
    end: end,
    effort: effort,
    minutes: null,
    done: done,
    doneAt: doneAt,
    eventKey: eventKey,
  );

  test('records times, ratings and completion, never titles', () {
    final record = buildDayRecord(
      day: day,
      wrapUpMinutes: 17 * 60,
      calendarAvailable: true,
      events: [
        event('Client presentation', at(14), at(15)),
        event('Project Alpha', at(9), at(10)),
        event('Team meeting', at(11), at(12), declined: true),
        event(
          'Yesterday standup',
          at(9).subtract(const Duration(days: 1)),
          at(9, 30).subtract(const Duration(days: 1)),
        ),
      ],
      priorities: [
        priority(start: at(16), end: at(17), effort: 'demanding', done: true),
        priority(effort: 'light', done: true, doneAt: at(11, 5)),
        priority(effort: 'bogus'),
      ],
    );
    expect(record.toString(), isNot(contains('presentation')));
    expect(record.toString(), isNot(contains('Alpha')));
    expect(record['wrapUpAt'], Timestamp.fromDate(at(17)));
    final events = record['events']! as List;
    expect(events, hasLength(2), reason: 'declined and other days left out');
    expect((events[0] as Map)['rating'], isNull, reason: 'unknown, sorted');
    expect((events[1] as Map)['rating'], 75);
    final priorities = record['priorities']! as List;
    expect(priorities[0], {
      'start': Timestamp.fromDate(at(16)),
      'end': Timestamp.fromDate(at(17)),
      'effort': 'demanding',
      'minutes': null,
      'done': true,
    });
    expect(priorities[1], {
      'effort': 'light',
      'minutes': null,
      'done': true,
      'doneAt': Timestamp.fromDate(at(11, 5)),
    });
    expect((priorities[2] as Map)['effort'], isNull);
  });

  test('a priority linked to one of the day\'s events counts once', () {
    final record = buildDayRecord(
      day: day,
      wrapUpMinutes: 17 * 60,
      calendarAvailable: true,
      events: [event('Client presentation', at(14), at(15), key: 'google:a')],
      priorities: [
        priority(start: at(14), end: at(15), done: true, eventKey: 'google:a'),
        priority(start: at(16), end: at(17), done: true, eventKey: 'google:b'),
      ],
    );
    expect(record['priorities'], hasLength(1));
  });

  test('a timed priority from another day counts like an untimed one', () {
    final record = buildDayRecord(
      day: day,
      wrapUpMinutes: 17 * 60,
      calendarAvailable: false,
      events: const [],
      priorities: [
        priority(
          start: at(9).subtract(const Duration(days: 1)),
          end: at(10).subtract(const Duration(days: 1)),
          done: true,
        ),
      ],
    );
    expect((record['priorities']! as List).single, {
      'effort': null,
      'minutes': null,
      'done': true,
    });
    expect(record['calendarAvailable'], isFalse);
  });

  test('the nightly push hour is 11 PM local, in UTC', () {
    final hour = nightlyPushUtcHour(DateTime(2026, 10, 1, 9));
    expect(DateTime.utc(2026, 10, 1, hour).toLocal().hour, 23);
  });
}
