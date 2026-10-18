import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:vivordo_health/src/services/panda_prompts.dart';

gcal.Event _event(String title, DateTime start) => gcal.Event(
  summary: title,
  start: gcal.EventDateTime(dateTime: start),
  end: gcal.EventDateTime(dateTime: start.add(const Duration(hours: 1))),
);

void main() {
  final dayStart = DateTime(2026, 10, 13);

  test('events weeks ahead are listed after the day-by-day schedule', () {
    final context = PandaPrompts.scheduleContext([
      _event('Standup', DateTime(2026, 10, 16, 9)),
      _event('Genesis service', DateTime(2026, 11, 12, 8, 30)),
      _event('Too far', DateTime(2027, 2, 1, 9)),
    ], dayStart);
    expect(context, contains('Fri 2026-10-16: 09:00–10:00 Standup'));
    expect(
      context,
      endsWith(
        'Later, through 2027-01-14:\nThu 2026-11-12 08:30 Genesis service',
      ),
    );
    expect(context, isNot(contains('Too far')));
  });

  test('a busy calendar is cut to fit, saying how many were left out', () {
    final events = [
      for (var i = 0; i < 400; i++)
        _event(
          'Meeting $i',
          DateTime(2026, 10, 25, 8).add(Duration(hours: i * 3)),
        ),
    ];
    final context = PandaPrompts.scheduleContext(events, dayStart);
    expect(context.length, lessThanOrEqualTo(7800));
    expect(context, matches(RegExp(r'\(\d+ later events not shown\)$')));
  });
}
