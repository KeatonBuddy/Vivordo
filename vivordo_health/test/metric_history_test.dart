import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/metric_history_screen.dart';
import 'package:vivordo_health/src/utils/metric_history.dart';

void main() {
  test('weeks and months cover the range, gaps included', () {
    final history = MetricHistory({
      '2026-08-30': 12000,
      '2026-08-31': 6000,
      '2026-09-15': null,
      '2026-10-01': 0,
      '2026-10-02': 10000,
      'not-a-day': 5000,
    }, goal: 10000);
    final now = DateTime(2026, 11, 10);

    expect(history.first, DateTime(2026, 8, 30));
    final months = history.months(DateTime(2026, 8), now);
    expect(months.map((m) => m.start), [
      DateTime(2026, 8),
      DateTime(2026, 9),
      DateTime(2026, 10),
      DateTime(2026, 11),
    ]);
    // Missing and 0 days are left out of the average, not counted as 0.
    expect(months[0].average, 9000);
    expect(months[0].days, 2);
    expect(months[0].goalDays, 1);
    expect(months[1].days, 0);
    expect(months[1].average, 0);
    expect(months[2].average, 10000);
    expect(months[2].goalDays, 1);

    // Monday weeks: Aug 30 (a Sunday) is in the week of Aug 24.
    final weeks = history.weeks(DateTime(2026, 8, 30), now);
    expect(weeks.first.start, DateTime(2026, 8, 24));
    expect(weeks.first.total, 12000);
    expect(weeks[1].start, DateTime(2026, 8, 31));
    expect(weeks[1].total, 6000);
    expect(weeks.last.start, DateTime(2026, 11, 9));

    expect(history.daysIn(DateTime(2026, 8)), {30: 12000, 31: 6000});
    expect(history.between(DateTime(2026, 9), DateTime(2026, 11)), [10000]);
    expect(
      history.bestSince(DateTime(2026, 8, 31))?.key,
      DateTime(2026, 10, 2),
    );
  });

  test('no data has no first day or best', () {
    final history = MetricHistory({'2026-10-01': null}, goal: 1);
    expect(history.first, isNull);
    expect(history.bestSince(DateTime(2026)), isNull);
  });

  testWidgets('a month shows its days, the best one picked, and moves back', (
    tester,
  ) async {
    final history = MetricHistory({
      '2026-08-03': 4000,
      '2026-09-01': 6000,
      '2026-09-14': 15200,
      '2026-09-20': 10000,
    }, goal: 10000);
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MetricMonthScreen(
          metric: HistoryMetric.steps,
          history: history,
          month: DateTime(2026, 9),
          firstMonth: DateTime(2026, 8),
        ),
      ),
    );
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('10,400 steps a day · 2 goal days'), findsOneWidget);
    // Opens on the month's best day.
    expect(find.text('Monday, September 14'), findsOneWidget);
    expect(find.text('Best day this month'), findsOneWidget);
    expect(find.text('+46%'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('September 1, 6,000 steps'));
    await tester.pump();
    expect(find.text('6,000 steps'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    expect(find.text('August 2026'), findsOneWidget);
    // August is the first month: no further back.
    final back = find.ancestor(
      of: find.byTooltip('Previous month'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(back).onPressed, isNull);
  });
}
