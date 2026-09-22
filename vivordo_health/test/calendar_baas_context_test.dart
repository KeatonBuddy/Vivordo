import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:vivordo_health/src/services/calendar_baas_context.dart';

void main() {
  final start = DateTime.utc(2026, 9, 10, 12);
  final now = start.add(const Duration(minutes: 30));
  gcal.Event event({
    String title = 'Client presentation',
    String? status,
    String? transparency,
    bool declined = false,
  }) => gcal.Event()
    ..id = 'private-id'
    ..summary = title
    ..description = 'Private notes'
    ..status = status
    ..transparency = transparency
    ..attendees = [
      gcal.EventAttendee()
        ..self = true
        ..responseStatus = declined ? 'declined' : 'accepted',
    ]
    ..start = (gcal.EventDateTime()..dateTime = start)
    ..end = (gcal.EventDateTime()
      ..dateTime = start.add(const Duration(hours: 1)));

  test(
    'partial window matches accept-only backend contract and hides text',
    () {
      final result = CalendarBaasContext.build(
        events: [event()],
        from: start,
        asOf: now,
      ).single;
      expect(result['calendar_load'], 37.5);
      expect(result['occupied_minutes'], 30);
      expect(result['evaluated_until'], now.toIso8601String());
      expect(result['calendar_available'], true);
      expect(jsonEncode(result), isNot(contains('Private')));
      expect(jsonEncode(result), isNot(contains('private-id')));
      expect(jsonEncode(result), isNot(contains('presentation')));
    },
  );
  test('unavailable, empty and unknown calendars remain distinct', () {
    final missing = CalendarBaasContext.build(
      events: null,
      from: start,
      asOf: now,
    ).single;
    final empty = CalendarBaasContext.build(
      events: [],
      from: start,
      asOf: now,
    ).single;
    final unknown = CalendarBaasContext.build(
      events: [event(title: 'Alpha')],
      from: start,
      asOf: now,
    ).single;
    expect(missing['calendar_available'], false);
    expect(missing['calendar_load'], isNull);
    expect(empty['calendar_available'], true);
    expect(empty['calendar_load'], 0);
    expect(unknown['calendar_load'], isNull);
    expect(unknown['classification_confidence'], 0);
  });
  test('cancelled declined free and all-day records do not contribute', () {
    for (final item in [
      event(status: 'cancelled'),
      event(declined: true),
      event(transparency: 'transparent'),
      gcal.Event()..start = (gcal.EventDateTime()..date = start),
    ]) {
      expect(
        CalendarBaasContext.build(
          events: [item],
          from: start,
          asOf: now,
        ).single['occupied_minutes'],
        0,
      );
    }
  });
  test('future events do not contribute and offsets normalize to UTC', () {
    final future = event()
      ..start = (gcal.EventDateTime()
        ..dateTime = now.add(const Duration(minutes: 1)));
    final result = CalendarBaasContext.build(
      events: [future],
      from: DateTime.parse('2026-09-10T06:00:00-06:00'),
      asOf: now,
    ).single;
    expect(result['start'], start.toIso8601String());
    expect(result['calendar_load'], 0);
  });
}
