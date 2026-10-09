import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/energy_forecast.dart';
import 'package:vivordo_health/src/utils/sleep_schedule.dart';

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

  group('usual sleep schedule', () {
    // 1 AM–9 AM on weeknights, 2 AM–10:30 AM on Friday and Saturday nights.
    const late = SleepSchedule(
      bed: 60,
      wake: 9 * 60,
      weekendBed: 2 * 60,
      weekendWake: 10 * 60 + 30,
    );

    test('nights land on the right dates', () {
      expect(SleepSchedule.fallback.nightEnding(day), (
        start: at(23, 30, -1),
        end: at(7),
      ));
      expect(late.nightEnding(day), (start: at(1), end: at(9)));
      // Saturday morning uses the weekend times.
      expect(late.nightEnding(at(0, 0, 2)), (
        start: at(2, 0, 2),
        end: at(10, 30, 2),
      ));
    });

    test('stands in for tracked sleep until there is a week of it', () {
      final f = forecastEnergy(day: day, nights: const [], schedule: late);
      expect(f.estimated, isTrue);
      expect(f.usesSchedule, isTrue);
      expect(f.wake, at(9));
      expect(f.midSleepHours, 5);
      // Thursday night is a weeknight: bed at 1 AM.
      expect(f.usualBedtime, at(1, 0, 1));
      // A late sleeper peaks later than the textbook 9 AM.
      final peak = window(f, EnergyPhase.peak);
      expect(peak.start.isAfter(at(10, 30)), isTrue);

      // Friday's bedtime is the weekend's.
      final friday = forecastEnergy(
        day: at(0, 0, 1),
        nights: const [],
        schedule: late,
      );
      expect(friday.usualBedtime, at(2, 0, 2));
    });

    test('tracked sleep wins once there is enough of it', () {
      final tracked = forecastEnergy(day: day, nights: nights());
      final both = forecastEnergy(day: day, nights: nights(), schedule: late);
      expect(both.usesSchedule, isFalse);
      expect(both.wake, tracked.wake);
      expect(both.usualBedtime, tracked.usualBedtime);
      expect(
        both.windows.map((w) => w.start),
        tracked.windows.map((w) => w.start),
      );
    });

    test('prefills from tracked nights, across midnight', () {
      // Two weeks ending Thursday 8 Oct: weeknights 11:50 PM or 12:10 AM to
      // 7 AM, weekends 1 AM to 9:30 AM.
      final tracked = [
        for (var i = 0; i < 14; i++)
          () {
            final wakeDay = DateTime(2026, 10, 8 - i);
            final weekend = wakeDay.weekday >= DateTime.saturday;
            final end = wakeDay.add(
              Duration(minutes: weekend ? 9 * 60 + 30 : 7 * 60),
            );
            final start = wakeDay.add(
              Duration(minutes: weekend ? 60 : (i.isEven ? -10 : 10)),
            );
            return (start: start, end: end);
          }(),
      ];
      final s = SleepSchedule.fromNights(tracked)!;
      // 11:45 PM or 12:15 AM, never midday.
      expect(s.bed, anyOf(1425, 15));
      expect(s.wake, 7 * 60);
      expect(s.weekendBed, 60);
      expect(s.weekendWake, 9 * 60 + 30);

      // Weekends within half an hour of weeknights: one pair of times.
      final steady = SleepSchedule.fromNights(nights())!;
      expect(steady.toMap(), {'bed': 23 * 60, 'wake': 7 * 60});
      expect(SleepSchedule.fromNights(nights(count: 2)), isNull);
    });

    test('saves and reads back, dropping weekend times when they match', () {
      expect(late.toMap(), {
        'bed': 60,
        'wake': 540,
        'weekendBed': 120,
        'weekendWake': 630,
      });
      final read = SleepSchedule.fromPreferences({
        'sleepSchedule': {'bed': 60, 'wake': 540},
      })!;
      expect(read.weekendsDiffer, isFalse);
      expect(read.toMap(), {'bed': 60, 'wake': 540});
      expect(
        SleepSchedule.fromPreferences({
          'sleepSchedule': {'bed': 60},
        }),
        isNull,
      );
      expect(SleepSchedule.fromPreferences(null), isNull);
    });
  });
}
