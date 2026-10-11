import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/check_in_reminder.dart';

void main() {
  test('reminders run 10 AM daily, skipping today once answered', () {
    final today = DateTime(2026, 10, 3);
    final open = checkInReminderTimes(today, todayOpen: true);
    expect(open, hasLength(7));
    expect(open.first, DateTime(2026, 10, 3, 10));
    expect(open.last, DateTime(2026, 10, 9, 10));

    final answered = checkInReminderTimes(today, todayOpen: false);
    expect(answered.first, DateTime(2026, 10, 4, 10));
    expect(answered, hasLength(6));
  });
}
