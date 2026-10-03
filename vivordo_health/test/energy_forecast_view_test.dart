import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/energy_forecast.dart';
import 'package:vivordo_health/src/utils/server_capacity.dart';
import 'package:vivordo_health/src/utils/sleep_nights.dart';
import 'package:vivordo_health/src/utils/sleep_schedule.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/energy_forecast_view.dart';

void main() {
  final day = DateTime(2026, 10, 8);
  List<SleepPeriod> nights({double hours = 8}) => [
    for (var i = 0; i < 14; i++)
      () {
        final end = DateTime(2026, 10, 8 - i, 7);
        return (
          start: end.subtract(Duration(minutes: (hours * 60).round())),
          end: end,
        );
      }(),
  ];

  test('nights come from days with both a bedtime and a wake time', () {
    final bed = DateTime(2026, 10, 7, 23);
    final wake = DateTime(2026, 10, 8, 7);
    expect(
      sleepNights([
        {
          'sleep': {
            'avg': 8,
            'bedtime': Timestamp.fromDate(bed),
            'wakeTime': Timestamp.fromDate(wake),
          },
        },
        {
          'sleep': {'avg': 7},
        },
        null,
      ]),
      [(start: bed, end: wake)],
    );
  });

  test("server Capacity carries the person's sleep need", () {
    final capacity = serverCapacityFor({
      '2026-10-08': {
        'capacity': {'score': 80, 'sleepNeed': 7.5},
      },
    }, '2026-10-08');
    expect(capacity?.sleepNeedHours, 7.5);
  });

  test('a clash names the exact start time', () {
    String t(String time) => time.replaceAll(' ', '\u202f');
    expect(
      energyClashText(
        title: 'Q4 review',
        start: DateTime(2026, 10, 8, 16, 26),
        phase: EnergyPhase.dip,
      ),
      'Your ${t('4:26 PM')} Q4 review lands in your afternoon dip.',
    );
    expect(
      energyClashText(
        title: 'Q4 review',
        start: DateTime(2026, 10, 8, 14),
        phase: EnergyPhase.dip,
      ),
      'Your ${t('2 PM')} Q4 review lands in your afternoon dip.',
    );
  });

  test('window times read naturally', () {
    EnergyWindow w(int h1, int m1, int h2, int m2) => EnergyWindow(
      EnergyPhase.peak,
      DateTime(2026, 10, 8, h1, m1),
      DateTime(2026, 10, 8, h2, m2),
    );
    expect(energyWindowText(w(9, 0, 11, 15)), '9–11:15 AM');
    expect(energyWindowText(w(14, 0, 16, 45)), '2–4:45 PM');
    expect(energyWindowText(w(11, 30, 13, 0)), '11:30 AM–1 PM');
  });

  test('the "why" reasons explain a short night', () {
    final short = forecastEnergy(
      day: day,
      nights: [
        (start: DateTime(2026, 10, 8, 0, 20), end: DateTime(2026, 10, 8, 7)),
        ...nights().skip(1),
      ],
      sleepNeedHours: 8,
    );
    final text = energyReasons(short).map((r) => r.$2).join('\n');
    expect(text, contains('You slept 6 h 40, 1 h 20 under your need'));
    expect(text, contains('You woke at 7:00'));
    expect(text, contains('Best for focus:'));
    expect(text, contains('about average'));

    final rested = forecastEnergy(
      day: day,
      nights: nights(),
      sleepNeedHours: 8,
    );
    expect(
      energyReasons(rested).first.$2,
      'You slept 8 h, about what you need.',
    );
    expect(
      energyReasons(forecastEnergy(day: day, nights: const [])).first.$2,
      contains("hasn't synced"),
    );
    expect(
      energyReasons(
        forecastEnergy(
          day: day,
          nights: const [],
          schedule: SleepSchedule.fallback,
        ),
      ).first.$2,
      contains('your usual sleep times'),
    );
  });

  testWidgets('the evening card shows bed-by and tomorrow\'s forecast', (
    tester,
  ) async {
    final tonight = forecastEnergy(
      day: day,
      nights: nights(hours: 7),
      sleepNeedHours: 7.5,
      tomorrowFirstEvent: DateTime(2026, 10, 9, 7),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: EnergyEveningCard(
              tonight: tonight,
              tomorrow: tomorrowEnergyForecast(
                tonight: tonight,
                today: day,
                nights: nights(hours: 7),
              ),
              firstEventTitle: 'Client call',
              firstEventStart: DateTime(2026, 10, 9, 7),
            ),
          ),
        ),
      ),
    );
    // DateFormat puts a narrow no-break space before AM/PM.
    String t(String time) => time.replaceAll(' ', '\u202f');
    // 7 AM − 1 h − 7.5 h = 10:30 PM, before the usual 11:30 PM.
    expect(find.text('Wind down from ${t('9:30 PM')}'), findsOneWidget);
    expect(find.text(t('10:30 PM')), findsOneWidget);
    expect(
      find.textContaining('Client call at ${t('7:00 AM')}'),
      findsOneWidget,
    );
    expect(find.textContaining('Peak'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('wind-down reminders follow each night\'s forecast', () {
    String t(String time) => time.replaceAll(' ', '\u202f');
    // A Thursday; 11 PM–7 AM nights and an 8 h need.
    final textbook = windDownReminders(
      today: day,
      nights: [
        for (var i = 0; i < 14; i++)
          (
            start: DateTime(2026, 10, 7 - i, 23),
            end: DateTime(2026, 10, 8 - i, 7),
          ),
      ],
      sleepNeedHours: 8,
    );
    expect(textbook, hasLength(7));
    expect(textbook.first.at, DateTime(2026, 10, 8, 22));
    expect(
      textbook.first.body,
      startsWith('Bed by ${t('11:00 PM')} for 8 h before ${t('7:00 AM')}.'),
    );
    expect(textbook.first.body, contains("Tomorrow's peak is"));
    expect(textbook.last.at, DateTime(2026, 10, 14, 22));

    // A 6:30 AM start tomorrow pulls only tonight earlier: 6:30 − 1 h prep
    // − 8 h = 9:30 PM bed, so wind down at 8:30.
    final early = windDownReminders(
      today: day,
      nights: const [],
      sleepNeedHours: 8,
      schedule: const SleepSchedule(
        bed: 23 * 60,
        wake: 7 * 60,
        weekendBed: 30,
        weekendWake: 9 * 60,
      ),
      tomorrowFirstEvent: DateTime(2026, 10, 9, 6, 30),
    );
    expect(early.first.at, DateTime(2026, 10, 8, 20, 30));
    // Friday night uses the weekend bedtime (12:30 AM), Sunday the
    // weekday one again.
    expect(early[1].at, DateTime(2026, 10, 9, 23, 30));
    expect(early[3].at, DateTime(2026, 10, 11, 22));
  });

  testWidgets('the evening card offers the reminder once', (tester) async {
    String t(String time) => time.replaceAll(' ', '\u202f');
    final tonight = forecastEnergy(
      day: day,
      nights: nights(),
      sleepNeedHours: 8,
    );
    final answers = <bool>[];
    Future<void> show(bool? reminder) => tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: EnergyEveningCard(
              tonight: tonight,
              tomorrow: tonight,
              reminder: reminder,
              onReminder: answers.add,
            ),
          ),
        ),
      ),
    );

    await show(null);
    await tester.tap(find.text('Remind me at ${t('10:00 PM')}'));
    await tester.tap(find.text('No thanks'));
    expect(answers, [true, false]);

    await show(true);
    expect(find.text('Reminder at ${t('10:00 PM')}'), findsOneWidget);
    await tester.tap(find.text('Turn off'));
    expect(answers.last, isFalse);

    await show(false);
    expect(find.textContaining('Remind'), findsNothing);
  });
}
