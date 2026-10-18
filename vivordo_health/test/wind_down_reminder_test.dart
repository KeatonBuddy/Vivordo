import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/wind_down_reminder.dart';

void main() {
  test('sleep inputs are reused for 3 hours on the same day only', () {
    final at = DateTime(2026, 10, 17, 8);
    bool fresh(DateTime now) => WindDownReminders.inputsFresh(at, now);
    expect(fresh(DateTime(2026, 10, 17, 8)), isTrue);
    expect(fresh(DateTime(2026, 10, 17, 10, 59)), isTrue);
    expect(fresh(DateTime(2026, 10, 17, 11)), isFalse);
    final late = DateTime(2026, 10, 17, 23);
    expect(
      WindDownReminders.inputsFresh(late, DateTime(2026, 10, 18, 0, 30)),
      isFalse,
    );
  });
}
