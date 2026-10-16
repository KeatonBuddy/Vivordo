import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'package:vivordo_health/src/utils/day_effort.dart';
import 'package:vivordo_health/src/utils/energy_forecast.dart';
import 'package:vivordo_health/src/utils/plan_my_day.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/plan_my_day_sheet.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 8, hour, minute);

  // The textbook day: peak 9:00–11:15, dip 2:00–4:45 PM, second wind
  // 5:45–7:45 PM, wind-down 10–11 PM (energy_forecast_test).
  final forecast = forecastEnergy(
    day: DateTime(2026, 10, 8),
    nights: [
      for (var i = 0; i < 14; i++)
        (
          start: DateTime(2026, 10, 7 - i, 23),
          end: DateTime(2026, 10, 8 - i, 7),
          asleepHours: null,
        ),
    ],
    sleepNeedHours: 8,
  );

  EffortItem event(String id, DateTime start, int minutes) => (
    event: CalendarCognitiveEvent(
      id: id,
      title: id,
      start: start,
      end: start.add(Duration(minutes: minutes)),
    ),
    score: CognitiveLoadScore(
      eventId: id,
      score: 75,
      category: 'high-consequence',
      reason: '',
      usedAi: false,
    ),
    done: false,
    open: false,
  );
  PlanTask task(String id, int minutes, String effort) =>
      (id: id, title: id, minutes: minutes, effort: effort);

  test('heavy work in the peak, light in the dip, around events', () {
    final plan = planMyDay(
      now: at(8),
      wrapUp: at(17),
      forecast: forecast,
      items: [event('quiz', at(11), 60), event('lab', at(13), 60)],
      tasks: [
        task('email', 15, 'light'),
        task('report', 90, 'demanding'),
        task('notes', 45, 'moderate'),
      ],
    );
    final byId = {for (final s in plan.placed) s.task.id: s};
    // The report fits the peak before the quiz, with a break before it.
    expect(byId['report']!.start, at(9));
    expect(byId['report']!.reason, 'In your peak');
    // Light work goes to the dip.
    expect(forecast.phaseAt(byId['email']!.start), EnergyPhase.dip);
    expect(byId['email']!.reason, 'Light work for your dip');
    // Nothing touches an event or another slot, with 10 minutes between.
    final busy = [
      (at(11), at(12)),
      (at(13), at(14)),
      for (final s in plan.placed) (s.start, s.end),
    ];
    for (final a in busy) {
      for (final b in busy) {
        if (identical(a, b)) continue;
        expect(
          a.$1.isBefore(b.$2.add(const Duration(minutes: 10))) &&
              b.$1.isBefore(a.$2.add(const Duration(minutes: 10))),
          isFalse,
          reason: '$a and $b too close',
        );
      }
    }
    expect(plan.unplaced, isEmpty);
    // Listed in time order.
    final starts = [for (final s in plan.placed) s.start];
    expect(starts, [...starts]..sort());
  });

  test("what doesn't fit before wrap-up says why", () {
    final plan = planMyDay(
      now: at(15),
      wrapUp: at(17),
      items: [event('meeting', at(15, 30), 60)],
      tasks: [task('outline', 120, 'demanding')],
    );
    expect(plan.placed, isEmpty);
    expect(plan.unplaced.single.reason, 'No 2-hour gap before your wrap-up');
  });

  test('without a forecast, the earliest free time', () {
    final plan = planMyDay(
      now: at(9, 5),
      wrapUp: at(17),
      items: const [],
      tasks: [task('read', 30, 'moderate')],
    );
    // Not before a quarter-hour lead, on the quarter hour.
    expect(plan.placed.single.start, at(9, 30));
    expect(plan.placed.single.reason, 'The next open time');
  });

  testWidgets('the sheet returns what was kept and what goes to tomorrow', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final report = task('Write lab report', 90, 'demanding');
    final email = task('Email advisor', 15, 'light');
    final outline = task('Start essay outline', 120, 'demanding');
    PlanChoice? choice;
    showPlanMyDaySheet(
      context,
      placed: [
        (task: report, start: at(9), end: at(10, 30), reason: 'In your peak'),
        (
          task: email,
          start: at(14, 15),
          end: at(14, 30),
          reason: 'Light work for your dip',
        ),
      ],
      unplaced: [(task: outline, reason: 'No 2-hour gap before your wrap-up')],
    ).then((value) => choice = value);
    await tester.pumpAndSettle();
    expect(find.text('Plan for today'), findsOneWidget);
    expect(find.textContaining('In your peak'), findsOneWidget);
    // Skip the email, send the outline to tomorrow.
    await tester.tap(find.text('Skip').last);
    await tester.tap(find.text('Tomorrow?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set this time'));
    await tester.pumpAndSettle();
    expect([for (final s in choice!.slots) s.task.id], ['Write lab report']);
    expect([for (final t in choice!.tomorrow) t.id], ['Start essay outline']);
  });

  test('after midnight, nothing before you wake', () {
    final plan = planMyDay(
      now: at(0, 20),
      wrapUp: at(17),
      forecast: forecast,
      items: const [],
      tasks: [task('read', 30, 'moderate')],
    );
    expect(plan.placed.single.start.isBefore(forecast.wake), isFalse);
  });
}
