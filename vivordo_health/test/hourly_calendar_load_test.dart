import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'package:vivordo_health/src/services/hourly_calendar_load.dart';

void main() {
  final noon = DateTime.utc(2026, 9, 9, 12);
  CalendarCognitiveEvent event(
    String id,
    int start,
    int end, {
    String title = 'Client presentation',
    bool free = false,
    bool declined = false,
    bool cancelled = false,
    bool allDay = false,
  }) => CalendarCognitiveEvent(
    id: id,
    title: title,
    start: noon.add(Duration(minutes: start)),
    end: noon.add(Duration(minutes: end)),
    showsAsFree: free,
    isDeclined: declined,
    isCancelled: cancelled,
    isAllDay: allDay,
  );

  List<HourlyCalendarLoad> calculate(
    List<CalendarCognitiveEvent> events, {
    int hours = 1,
    DateTime? asOf,
    bool available = true,
  }) => HourlyCalendarLoadCalculator.calculate(
    events: events,
    scores: events.map(CalendarCognitiveLoadService.scoreLocally).toList(),
    from: noon,
    until: noon.add(Duration(hours: hours)),
    asOf: asOf,
    calendarAvailable: available,
  );

  test('quarter-hour demand contributes a quarter of full-hour demand', () {
    expect(calculate([event('a', 0, 15)]).single.score, 18.75);
    expect(calculate([event('a', 0, 60)]).single.score, 75);
  });
  test(
    'sequential events integrate demand and separate transition pressure',
    () {
      final hour = calculate([
        event('a', 0, 30, title: 'Team meeting'),
        event('b', 30, 60),
      ]).single;
      expect(hour.demand, 57.5);
      expect(hour.pressure, 5);
      expect(hour.score, 62.5);
    },
  );
  test(
    'overlap counts minutes once, using strongest demand and bounded pressure',
    () {
      final hour = calculate([
        event('a', 0, 60),
        event('b', 0, 60, title: 'Coding'),
      ]).single;
      expect(hour.occupiedMinutes, 60);
      expect(hour.demand, 75);
      expect(hour.score, 85);
    },
  );
  test('duplicate occurrence does not create overlap', () {
    final a = event('a', 0, 60);
    expect(calculate([a, a]).single.score, 75);
  });
  test('live calculation excludes future minutes and future transitions', () {
    final now = noon.add(const Duration(minutes: 15));
    final base = calculate([event('a', 0, 30)], asOf: now).single;
    final future = calculate([
      event('a', 0, 30),
      event('b', 30, 60),
    ], asOf: now).single;
    expect(base.score, 18.75);
    expect(future.score, base.score);
    expect(future.evaluatedUntil, now);
    expect(calculate([], asOf: noon), isEmpty);
  });
  test('multi-hour events retain demand and accumulate run pressure', () {
    final hours = calculate([event('a', 0, 180)], hours: 3);
    expect(hours.map((h) => h.demand), [75, 75, 75]);
    expect(hours.map((h) => h.pressure), [0, 2.5, 5]);
  });
  test('a fifteen-minute break removes tight transition pressure', () {
    final hour = calculate([event('a', -60, -15), event('b', 0, 60)]).single;
    expect(hour.pressure, 0);
  });
  test('cross-hour transition and continuous run are retained', () {
    final hour = calculate([event('a', -60, 0), event('b', 0, 60)]).single;
    expect(hour.pressure, 12.5);
  });
  test(
    'invalid, declined, cancelled, free and all-day events do not occupy time',
    () {
      final hour = calculate([
        event('a', 0, 60, declined: true),
        event('b', 0, 60, cancelled: true),
        event('c', 0, 60, free: true),
        event('d', 0, 60, allDay: true),
        event('e', 30, 0),
      ]).single;
      expect(hour.occupiedMinutes, 0);
      expect(hour.score, 0);
    },
  );
  test(
    'unknown, missing calendar and confirmed empty remain distinguishable',
    () {
      expect(
        calculate([event('a', 0, 60, title: 'Project Alpha')]).single.score,
        isNull,
      );
      expect(calculate([], available: false).single.score, isNull);
      expect(calculate([]).single.score, 0);
      final mixed = calculate([
        event('a', 0, 30),
        event('b', 30, 60, title: 'Project Alpha'),
      ]).single;
      expect(mixed.knownMinutes, 30);
      expect(mixed.confidence, closeTo(0.425, 0.0001));
    },
  );
  test('backend representation excludes private calendar text', () {
    final json = calculate([event('private-id', 0, 60)]).single.toJson();
    expect(json.toString(), isNot(contains('presentation')));
    expect(json.toString(), isNot(contains('private-id')));
    expect(
      json['classifier_version'],
      CalendarCognitiveLoadService.classifierVersion,
    );
  });
}
