import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/energy_forecast.dart';

void main() {
  // Sunday, October 11, 2026.
  final sunday = DateTime(2026, 10, 11, 21);

  /// Two weeks of 23:00-06:30 nights, then the weekend's wake times.
  List<SleepPeriod> nights({
    required int saturdayWake,
    required int sundayWake,
  }) => [
    for (var i = 2; i <= 14; i++)
      (
        start: DateTime(2026, 10, 11 - i - 1, 23),
        end: DateTime(2026, 10, 11 - i, 6, 30),
        asleepHours: null,
      ),
    (
      start: DateTime(2026, 10, 9, 23),
      end: DateTime(2026, 10, 10, saturdayWake ~/ 60, saturdayWake % 60),
      asleepHours: null,
    ),
    (
      start: DateTime(2026, 10, 10, 23),
      end: DateTime(2026, 10, 11, sundayWake ~/ 60, sundayWake % 60),
      asleepHours: null,
    ),
  ];

  test('Sunday evening: the weekend lie-in against weekday wakes', () {
    // Up at 08:45 on Sunday: 2h 15m past the usual 06:30.
    expect(
      weekendLieIn(
        nights(saturdayWake: 7 * 60, sundayWake: 8 * 60 + 45),
        sunday,
      ),
      const Duration(minutes: 135),
    );
    // An hour later isn't enough to mention.
    expect(
      weekendLieIn(
        nights(saturdayWake: 7 * 60 + 30, sundayWake: 7 * 60),
        sunday,
      ),
      isNull,
    );
    // Only on Sunday, before the work week.
    expect(
      weekendLieIn(
        nights(saturdayWake: 9 * 60, sundayWake: 9 * 60),
        DateTime(2026, 10, 10, 21),
      ),
      isNull,
    );
  });
}
