import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';

void main() {
  test('the saved default is used only while it can still be written to', () {
    const writable = [
      WritableCalendar(id: 'me@gmail.com', name: 'Me', isPrimary: true),
      WritableCalendar(id: 'work-id', name: 'Work', isPrimary: false),
      WritableCalendar(id: 'outlook:abc', name: 'Calendar', isPrimary: false),
    ];
    expect(CalendarService.pickDefaultCalendar('work-id', writable), 'work-id');
    expect(
      CalendarService.pickDefaultCalendar('outlook:abc', writable),
      'outlook:abc',
    );
    // Deleted, or its account disconnected.
    expect(CalendarService.pickDefaultCalendar('gone-id', writable), 'primary');
    expect(CalendarService.pickDefaultCalendar(null, writable), 'primary');
    expect(CalendarService.pickDefaultCalendar('work-id', const []), 'primary');
  });
}
