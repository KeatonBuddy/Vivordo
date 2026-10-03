import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/morning_check_in_card.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 2, hour, minute);

  test('the check-in is asked from 5 AM until midnight', () {
    // After midnight you haven't slept yet.
    expect(morningCheckInOpen(at(0, 30)), isFalse);
    expect(morningCheckInOpen(at(4, 59)), isFalse);
    expect(morningCheckInOpen(at(5)), isTrue);
    expect(morningCheckInOpen(at(12)), isTrue);
    expect(morningCheckInOpen(at(23, 59)), isTrue);
  });

  test('Home shows it until both questions are answered or dismissed', () {
    expect(checkInDue(const {}, at(20)), isTrue);
    expect(checkInDue(const {'feel': 75}, at(9)), isTrue);
    expect(checkInDue(const {'feel': 75, 'sleep': 50}, at(9)), isFalse);
    expect(checkInDue(const {'dismissed': true}, at(9)), isFalse);
    // Not loaded yet, or before 5 AM.
    expect(checkInDue(null, at(9)), isFalse);
    expect(checkInDue(const {}, at(3)), isFalse);
  });
}
