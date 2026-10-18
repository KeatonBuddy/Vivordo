import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/score_history.dart';

void main() {
  // Saturday.
  final today = DateTime(2026, 10, 17);

  test('pages are calendar weeks, months and quarters', () {
    expect(historyPeriod(ScoreHistoryRange.week, today, 0), (
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 18),
    ));
    expect(historyPeriod(ScoreHistoryRange.week, today, 2), (
      start: DateTime(2026, 9, 28),
      end: DateTime(2026, 10, 4),
    ));
    expect(historyPeriod(ScoreHistoryRange.month, today, 1), (
      start: DateTime(2026, 9),
      end: DateTime(2026, 9, 30),
    ));
    expect(historyPeriod(ScoreHistoryRange.quarter, today, 1), (
      start: DateTime(2026, 7),
      end: DateTime(2026, 9, 30),
    ));
    expect(
      historyPeriod(ScoreHistoryRange.quarter, today, 4).start,
      DateTime(2025, 10),
    );
  });

  test('page count reaches back to the first saved day', () {
    final first = DateTime(2026, 10, 1);
    expect(historyPageCount(ScoreHistoryRange.week, today, first), 3);
    expect(historyPageCount(ScoreHistoryRange.month, today, first), 1);
    expect(historyPageCount(ScoreHistoryRange.quarter, today, first), 1);
    expect(historyPageCount(ScoreHistoryRange.week, today, today), 1);
  });

  test('labels', () {
    expect(
      historyPeriodLabel(ScoreHistoryRange.week, today, 0),
      'This week · Oct 12 – 18',
    );
    expect(
      historyPeriodLabel(ScoreHistoryRange.week, today, 2),
      'Sep 28 – Oct 4',
    );
    expect(historyPeriodLabel(ScoreHistoryRange.month, today, 1), 'September');
    expect(
      historyPeriodLabel(ScoreHistoryRange.quarter, today, 4),
      'Oct – Dec 2025',
    );
  });

  Future<void> pump(
    WidgetTester tester,
    Map<String, Map<String, dynamic>> scores, {
    ScoreHistoryKind kind = ScoreHistoryKind.capacity,
    Map<String, Map<String, dynamic>> planned = const {},
  }) async {
    Future<Map<String, Map<String, dynamic>>> load(
      String collection,
      String start,
      String end,
    ) async {
      final source = collection == 'planned_demand' ? planned : scores;
      return {
        for (final e in source.entries)
          if (e.key.compareTo(start) >= 0 && e.key.compareTo(end) <= 0)
            e.key: e.value,
      };
    }

    Future<String?> earliest(String collection) async {
      final keys =
          (collection == 'planned_demand' ? planned : scores).keys.toList()
            ..sort();
      return keys.firstOrNull;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Scaffold(
          body: ScoreHistory(
            kind: kind,
            usual: 80,
            today: today,
            load: load,
            earliest: earliest,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> capacity(int score, {double? sleep}) => {
    'capacity': {
      'score': score,
      'sleepHours': ?sleep,
      'parts': {'sleep': score < 50 ? 40 : 90},
    },
  };

  testWidgets('hidden until a score has been saved', (tester) async {
    await pump(tester, const {});
    expect(find.text('7D'), findsNothing);
    await pump(tester, {
      '2026-10-16': capacity(80),
    }, kind: ScoreHistoryKind.plannedVsActual);
    expect(find.text('7D'), findsNothing, reason: 'no planned Demand yet');
  });

  testWidgets('pages back a week and explains a tapped day', (tester) async {
    await pump(tester, {
      '2026-10-08': capacity(41, sleep: 5.2),
      '2026-10-13': capacity(82),
      '2026-10-17': capacity(74),
    });
    expect(find.text('This week · Oct 12 – 18'), findsOneWidget);
    expect(find.text('Average 78 · usual 80'), findsOneWidget);

    await tester.tap(find.byTooltip('Earlier'));
    await tester.pumpAndSettle();
    expect(find.text('Oct 5 – 11'), findsOneWidget);
    expect(find.text('Average 41 · usual 80'), findsOneWidget);
    // Nothing saved before Oct 5's week: Earlier stops here.
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
          )
          .onPressed,
      isNull,
    );

    // Thursday Oct 8 is the 4th of 7 slots.
    final chart = tester.getRect(find.byType(CustomPaint).last);
    await tester.tapAt(
      Offset(chart.left + chart.width * 3.5 / 7, chart.center.dy),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thu, Oct 8 · 41 Low'), findsOneWidget);
    expect(find.text('Slept 5.2 h · sleep low'), findsOneWidget);

    await tester.tap(find.text('30D'));
    await tester.pumpAndSettle();
    expect(find.text('October'), findsOneWidget);
  });

  testWidgets('planned vs actual counts days that ran over', (tester) async {
    await pump(
      tester,
      {
        '2026-10-13': {
          'effort': {'total': 66},
        },
        '2026-10-14': {
          'effort': {'total': 30},
        },
      },
      kind: ScoreHistoryKind.plannedVsActual,
      planned: {
        '2026-10-13': {'points': 36},
        '2026-10-14': {'points': 32},
      },
    );
    expect(find.text('Ran over the plan on 1 of 2 days'), findsOneWidget);
  });

  testWidgets('days with nothing planned are not counted as over', (
    tester,
  ) async {
    await pump(
      tester,
      {
        '2026-10-16': {
          'effort': {'total': 20},
        },
        '2026-10-17': {
          'effort': {'total': 8},
        },
      },
      kind: ScoreHistoryKind.plannedVsActual,
      planned: {
        '2026-10-16': {'points': 30},
        '2026-10-17': {'points': 0},
      },
    );
    expect(find.text('Ran over the plan on 0 of 1 day'), findsOneWidget);
    expect(
      find.textContaining('days with nothing planned aren\'t counted'),
      findsOneWidget,
    );
  });
}
