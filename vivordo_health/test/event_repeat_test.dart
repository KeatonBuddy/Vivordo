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

  test('ending a rule keeps earlier occurrences and its other parts', () {
    final occurrence = DateTime.utc(2026, 10, 15, 14);
    expect(
      endRuleBefore(
        'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TH;COUNT=10',
        occurrence,
        allDay: false,
      ),
      'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=TH;UNTIL=20261015T135959Z',
    );
    expect(
      endRuleBefore(
        'RRULE:FREQ=MONTHLY;BYMONTHDAY=15;UNTIL=20271231',
        DateTime(2026, 10, 15),
        allDay: true,
      ),
      'RRULE:FREQ=MONTHLY;BYMONTHDAY=15;UNTIL=20261014',
    );
  });

  test('next occurrences follow the rule, from now and until its end', () {
    final first = DateTime(2026, 11, 4, 18); // a Wednesday
    final weekly = EventRepeat.parse(['RRULE:FREQ=WEEKLY;BYDAY=MO,WE']);
    expect(weekly.nextOccurrences(first, from: DateTime(2026, 11, 10)), [
      DateTime(2026, 11, 11, 18),
      DateTime(2026, 11, 16, 18),
      DateTime(2026, 11, 18, 18),
      DateTime(2026, 11, 23, 18),
    ]);
    final fortnightly = EventRepeat.parse([
      'RRULE:FREQ=WEEKLY;INTERVAL=2;UNTIL=20261202',
    ]);
    expect(fortnightly.nextOccurrences(first, from: first), [
      DateTime(2026, 11, 4, 18),
      DateTime(2026, 11, 18, 18),
      DateTime(2026, 12, 2, 18),
    ]);
    // Months without a 31st are skipped, as calendars do.
    final monthly = EventRepeat.parse(['RRULE:FREQ=MONTHLY']);
    expect(
      monthly.nextOccurrences(
        DateTime(2026, 10, 31, 9),
        from: DateTime(2026, 11),
      ),
      [
        DateTime(2026, 12, 31, 9),
        DateTime(2027, 1, 31, 9),
        DateTime(2027, 3, 31, 9),
        DateTime(2027, 5, 31, 9),
      ],
    );
    expect(
      EventRepeat.parse([
        'RRULE:FREQ=DAILY',
      ]).nextOccurrences(first, from: first, count: 2),
      [first, DateTime(2026, 11, 5, 18)],
    );
  });
}
