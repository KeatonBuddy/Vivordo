import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/energy_forecast.dart';

void main() {
  // A Thursday.
  final day = DateTime(2026, 10, 8);
  DateTime at(int hour, [int minute = 0, int dayOffset = 0]) =>
      DateTime(2026, 10, 8 + dayOffset, hour, minute);

  /// [count] nights ending at [wakeHour]:[wakeMinute] on today and earlier
  /// days, each [hours] long.
  List<SleepPeriod> nights({
    int count = 14,
    int wakeHour = 7,
    int wakeMinute = 0,
    double hours = 8,
  }) => [
    for (var i = 0; i < count; i++)
      () {
        final end = DateTime(2026, 10, 8 - i, wakeHour, wakeMinute);
        return (
          start: end.subtract(Duration(minutes: (hours * 60).round())),
          end: end,
        );
      }(),
  ];

  EnergyWindow window(EnergyForecast f, EnergyPhase phase) =>
      f.window(phase) ?? (throw TestFailure('no $phase window'));

  test('a typical 11 PM–7 AM sleeper gets the textbook day', () {
    final f = forecastEnergy(day: day, nights: nights(), sleepNeedHours: 8);
    expect(f.estimated, isFalse);
    expect(f.wake, at(7));
    expect(f.usualBedtime, at(23));
    expect(f.midSleepHours, 3);
    expect(f.sleepDebtHours, 0);

    final groggy = window(f, EnergyPhase.groggy);
    expect(groggy.end.isAfter(at(8)) && groggy.end.isBefore(at(8, 30)), isTrue);
    expect(window(f, EnergyPhase.peak).contains(at(10)), isTrue);
    expect(window(f, EnergyPhase.dip).contains(at(15)), isTrue);
    expect(window(f, EnergyPhase.secondWind).contains(at(18, 30)), isTrue);
    final windDown = window(f, EnergyPhase.windDown);
    expect((windDown.start, windDown.end), (at(22), at(23)));

    // Peak beats the dip clearly; the curve falls before bed.
    expect(f.at(at(10))! - f.at(at(15))!, greaterThan(0.15));
    expect(f.at(at(22, 30))!, lessThan(f.at(at(19))!));
    expect(f.phaseAt(at(10)), EnergyPhase.peak);
  });

  test('a short night lowers the peak and deepens the dip', () {
    final rested = forecastEnergy(
      day: day,
      nights: nights(),
      sleepNeedHours: 8,
    );
    final short = forecastEnergy(
      day: day,
      nights: [(start: at(0, 30), end: at(6)), ...nights(hours: 7).skip(1)],
      sleepNeedHours: 8,
    );
    expect(short.sleptHours, 5.5);
    expect(short.sleepDebtHours, closeTo(2.5 + 6, 0.01));
    expect(rested.at(at(10))! - short.at(at(10))!, greaterThan(0.08));
    expect(rested.at(at(15))! - short.at(at(15))!, greaterThan(0.08));
  });

  test('a late body clock shifts every window later', () {
    final early = forecastEnergy(day: day, nights: nights(), sleepNeedHours: 8);
    final late = forecastEnergy(
      day: day,
      nights: nights(wakeHour: 9, wakeMinute: 30),
      sleepNeedHours: 8,
    );
    expect(late.midSleepHours, 5.5);
    for (final phase in [EnergyPhase.peak, EnergyPhase.dip]) {
      final shift = window(
        late,
        phase,
      ).start.difference(window(early, phase).start);
      expect(shift.inMinutes, inInclusiveRange(120, 180), reason: '$phase');
    }
  });

  test('a night-shift sleeper is anchored to their own sleep', () {
    final f = forecastEnergy(
      day: day,
      nights: nights(wakeHour: 15, wakeMinute: 30, hours: 7.5),
      sleepNeedHours: 7.5,
    );
    expect(f.wake, at(15, 30));
    expect(f.usualBedtime, at(8, 0, 1));
    final peak = window(f, EnergyPhase.peak);
    final dip = window(f, EnergyPhase.dip);
    expect(peak.start.isAfter(f.wake), isTrue);
    expect(dip.start.isAfter(peak.start), isTrue);
    expect(dip.end.isBefore(f.usualBedtime), isTrue);
  });

  test('without sleep data the forecast is estimated, not missing', () {
    final f = forecastEnergy(day: day, nights: const []);
    expect(f.estimated, isTrue);
    expect(f.midSleepHours, 3.5);
    expect(f.wake, at(7, 30));
    expect(f.window(EnergyPhase.peak), isNotNull);
    expect(f.window(EnergyPhase.dip), isNotNull);
  });

  test('bed-by works back from tomorrow\'s first event', () {
    final usual = forecastEnergy(
      day: day,
      nights: nights(),
      sleepNeedHours: 7.5,
      tomorrowFirstEvent: at(8, 0, 1),
    );
    // 8 AM − 1 h − 7.5 h = 11:30 PM, later than the usual 11 PM.
    expect(usual.bedBy, at(23));

    final early = forecastEnergy(
      day: day,
      nights: nights(),
      sleepNeedHours: 7.5,
      tomorrowFirstEvent: at(6, 30, 1),
    );
    expect(early.bedBy, at(22));
    final windDown = window(early, EnergyPhase.windDown);
    expect((windDown.start, windDown.end), (at(21), at(22)));
  });

  test('sleep debt counts the last 7 nights and is capped', () {
    final f = forecastEnergy(
      day: day,
      nights: nights(hours: 6),
      sleepNeedHours: 8,
    );
    // 7 nights × 2 h short = 14 h, capped at 10; older nights don't count.
    expect(f.sleepDebtHours, 10);
    final mild = forecastEnergy(
      day: day,
      nights: nights(hours: 7.5),
      sleepNeedHours: 8,
    );
    expect(mild.sleepDebtHours, 3.5);
  });

  test('a night after today is ignored', () {
    final f = forecastEnergy(
      day: day,
      nights: [...nights(), (start: at(23), end: at(7, 0, 2))],
      sleepNeedHours: 8,
    );
    expect(f.wake, at(7));
  });
}
