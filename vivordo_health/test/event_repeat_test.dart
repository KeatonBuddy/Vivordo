import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/src/utils/event_repeat.dart';

void main() {
  test('presets become plain rules', () {
    expect(const EventRepeat().recurrence(), 'none');
    expect(
      const EventRepeat(unit: RepeatUnit.day).recurrence(),
      'RRULE:FREQ=DAILY',
    );
    expect(
      const EventRepeat(unit: RepeatUnit.year).recurrence(),
      'RRULE:FREQ=YEARLY',
    );
    expect(
      const EventRepeat(
        unit: RepeatUnit.week,
        weekdays: {DateTime.wednesday, DateTime.monday},
      ).recurrence(),
      'RRULE:FREQ=WEEKLY;BYDAY=MO,WE',
    );
  });

  test('custom rules carry interval and end date', () {
    final repeat = EventRepeat(
      unit: RepeatUnit.week,
      interval: 2,
      weekdays: const {DateTime.friday},
      until: DateTime(2026, 12, 31),
    );
    expect(
      repeat.recurrence(allDay: true),
      'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=FR;UNTIL=20261231',
    );
    final timed = repeat.recurrence();
    expect(timed, startsWith('RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=FR;UNTIL='));
    expect(timed, endsWith('Z'));
    expect(repeat.describe(), 'Every 2 weeks on Fri, until Dec 31, 2026');
  });

  test('rules survive a round trip through Google', () {
    final repeat = EventRepeat(
      unit: RepeatUnit.month,
      interval: 3,
      until: DateTime(2027, 3, 1),
    );
    for (final allDay in [false, true]) {
      final parsed = EventRepeat.parse([repeat.recurrence(allDay: allDay)]);
      expect(parsed.unit, RepeatUnit.month);
      expect(parsed.interval, 3);
      expect(parsed.until, DateTime(2027, 3, 1));
    }
  });

  test('parsing tolerates missing or foreign rules', () {
    expect(EventRepeat.parse(null).repeats, isFalse);
    expect(EventRepeat.parse(['EXDATE:20261001T090000Z']).repeats, isFalse);
    final monthly = EventRepeat.parse(['RRULE:FREQ=MONTHLY;BYDAY=1MO']);
    expect(monthly.unit, RepeatUnit.month);
    expect(monthly.weekdays, isEmpty);
    expect(monthly.describe(), 'Every month');
  });

  test('the service passes new rules through and keeps the old names', () {
    expect(CalendarService.recurrenceRules('RRULE:FREQ=YEARLY'), [
      'RRULE:FREQ=YEARLY',
    ]);
    expect(CalendarService.recurrenceRules('weekly:MO,WE;until=20261231'), [
      'RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261231T235959Z',
    ]);
    expect(CalendarService.recurrenceRules('none'), isEmpty);
  });
}
