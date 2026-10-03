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
}
