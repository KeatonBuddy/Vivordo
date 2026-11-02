import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';

void main() {
  CalendarPriorityCandidate event(DateTime start) => CalendarPriorityCandidate(
    sourceEventKey: 'google:abc',
    title: 'Design review',
    start: start,
    end: start.add(const Duration(minutes: 30)),
    isAllDay: false,
    isRecurring: false,
    attendeeCount: 0,
  );
  Map<String, dynamic> stored(DateTime start, {String source = 'calendar'}) => {
    'source': source,
    'sourceStart': Timestamp.fromDate(start),
    'sourceEnd': Timestamp.fromDate(start.add(const Duration(minutes: 30))),
    'isAllDay': false,
  };
  final four = DateTime(2026, 10, 3, 16);
  final quarterPast = DateTime(2026, 10, 3, 16, 15);

  test('an imported priority follows its event when it moves', () {
    expect(
      DailyPriorityService.calendarTimeChanges(stored(four), event(four)),
      isNull,
    );
    final moved = DailyPriorityService.calendarTimeChanges(
      stored(four),
      event(quarterPast),
    )!;
    expect((moved['sourceStart'] as Timestamp).toDate(), quarterPast);
    expect(
      (moved['sourceEnd'] as Timestamp).toDate(),
      quarterPast.add(const Duration(minutes: 30)),
    );
    // A priority you made yourself is never moved by its event.
    expect(
      DailyPriorityService.calendarTimeChanges(
        stored(four, source: 'manual'),
        event(quarterPast),
      ),
      isNull,
    );
  });

  test('a priority leaves with its event and comes back with it', () {
    Map<String, Object>? change(Map<String, dynamic> data, bool there) =>
        DailyPriorityService.calendarPresenceChanges(data, there: there);
    const open = {'source': 'calendar', 'dismissed': false};
    expect(change(open, true), isNull);
    final removed = change(open, false);
    expect(removed, {'dismissed': true, 'removedWithEvent': true});
    // Gone stays gone; back when the event is (an empty read, undone).
    expect(change({...open, ...removed!}, false), isNull);
    expect(change({...open, ...removed}, true), {
      'dismissed': false,
      'removedWithEvent': false,
    });
    // Ticked off, or removed by the user: left alone either way.
    expect(change({...open, 'completed': true}, false), isNull);
    expect(change({'source': 'calendar', 'dismissed': true}, false), isNull);
    expect(change({'source': 'calendar', 'dismissed': true}, true), isNull);
    // Only priorities made from events.
    expect(change({'source': 'manual'}, false), isNull);
  });
}
