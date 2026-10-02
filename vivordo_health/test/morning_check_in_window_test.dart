import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/morning_check_in_card.dart';

void main() {
  test('the morning check-in is asked from 5 AM to noon', () {
    bool open(int hour, [int minute = 0]) =>
        morningCheckInOpen(DateTime(2026, 10, 2, hour, minute));
    // After midnight you haven't slept yet.
    expect(open(0, 30), isFalse);
    expect(open(4, 59), isFalse);
    expect(open(5), isTrue);
    expect(open(11, 59), isTrue);
    expect(open(12), isFalse);
    expect(open(23), isFalse);
  });
}
