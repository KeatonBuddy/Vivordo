import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/desk_glance.dart';

void main() {
  DeskEvent event(int startHour, int startMinute, int minutes) {
    final start = DateTime(2026, 11, 17, startHour, startMinute);
    return (
      title: 'e',
      start: start,
      end: start.add(Duration(minutes: minutes)),
    );
  }

  test('the strip starts shortly before a far-off first event', () {
    final now = DateTime(2026, 11, 17, 4, 27);
    final window = deskWindow([event(9, 0, 30), event(11, 30, 60)], now);
    expect(window.start, DateTime(2026, 11, 17, 8, 15));
    expect(window.end, DateTime(2026, 11, 17, 13, 0));
  });

  test('the strip starts now once an event is near or under way', () {
    final now = DateTime(2026, 11, 17, 8, 40);
    expect(deskWindow([event(9, 0, 30)], now).start, now);
    final during = DateTime(2026, 11, 17, 9, 10);
    expect(deskWindow([event(9, 0, 30)], during).start, during);
  });

  test('the strip is at least three hours and stops at midnight', () {
    final now = DateTime(2026, 11, 17, 8, 40);
    expect(
      deskWindow([event(9, 0, 30)], now).end,
      DateTime(2026, 11, 17, 11, 40),
    );
    final late = DateTime(2026, 11, 17, 22, 30);
    expect(deskWindow([event(23, 0, 45)], late).end, DateTime(2026, 11, 18));
    expect(deskWindow(const [], late).end, DateTime(2026, 11, 18));
  });

  test('only events still to finish today are ahead', () {
    final now = DateTime(2026, 11, 17, 10, 0);
    expect(deskAhead([event(8, 0, 60), event(9, 30, 60)], now).length, 1);
  });
}
