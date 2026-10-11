import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/weekly_review_screen.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'package:vivordo_health/src/utils/weekly_review.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/contextual_insight_bar.dart';

void main() {
  final sunday = DateTime(2026, 10, 4);
  Map<String, dynamic> day(double effort, {double capacity = 75}) => {
    'capacity': {
      'score': capacity,
      'version': 2,
      'parts': {'sleep': 70, 'body': 70, 'recovery': 80},
    },
    'effort': {'total': effort, 'prioritiesDone': 2, 'unfinishedPriorities': 1},
  };
  final review = buildWeeklyReview(
    WeeklyReviewInput(
      weekStart: sunday,
      scores: {
        for (var i = 1; i <= 28; i++)
          localDayKey(sunday.subtract(Duration(days: i))): day(50),
        for (final (i, e) in <double>[50, 95, 92, 94, 50, 50, 50].indexed)
          localDayKey(sunday.add(Duration(days: i))): day(e),
      },
      openPriorities: [(title: 'Pitch deck', since: DateTime(2026, 10, 5))],
      nextWeek: [
        for (final (i, d) in <double>[95, 75, 40, 96, 55].indexed)
          (day: DateTime(2026, 10, 12 + i), demand: d),
      ],
      lastWeekNote: 'Travel',
    ),
  )!;

  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: VivordoTheme.light, home: child),
    );
  }

  testWidgets('the review: the week, next week, and planning it', (
    tester,
  ) async {
    final asked = <ScreenInsight>[];
    await show(tester, WeeklyReviewScreen(review: review, ask: asked.add));
    expect(find.text('Week of Oct 4 – 10'), findsOneWidget);
    expect(find.text('A heavy week you handled well'), findsOneWidget);
    expect(find.text('Last week you mentioned: Travel.'), findsOneWidget);
    expect(find.text('THE WEEK AT A GLANCE'), findsOneWidget);
    expect(find.text('WHAT DRAINED YOU'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('NEXT WEEK'), 300);
    expect(find.text('Lighter than this one'), findsOneWidget);
    expect(find.text('Busy'), findsNWidgets(2));

    final plan = find.text('Plan next week with Vivordo AI');
    await tester.scrollUntilVisible(plan, 300);
    await tester.ensureVisible(plan);
    await tester.pumpAndSettle();
    await tester.tap(plan);
    expect(asked.single.screen, 'weekly_review');
    expect(asked.single.context, contains('Pitch deck'));
  });

  testWidgets('"Something else" opens a short note', (tester) async {
    await show(tester, WeeklyReviewScreen(review: review));
    expect(find.text('Plan next week with Vivordo AI'), findsNothing);
    final other = find.text('Something else…');
    await tester.scrollUntilVisible(other, 300);
    await tester.ensureVisible(other);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(other);
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'x' * 100);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      hasLength(80),
    );
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('the first card explains itself and offers the reminder', (
    tester,
  ) async {
    await show(
      tester,
      Scaffold(
        body: WeeklyReviewCard(
          state: (review: review, intro: true, reminder: false),
        ),
      ),
    );
    expect(find.text('YOUR WEEK · OCT 4 – 10'), findsOneWidget);
    expect(find.text('Remind me on Sundays'), findsOneWidget);
    expect(find.text('3 heavy days'), findsOneWidget);

    await show(
      tester,
      Scaffold(
        body: WeeklyReviewCard(
          state: (review: review, intro: false, reminder: false),
        ),
      ),
    );
    expect(find.text('Remind me on Sundays'), findsNothing);
  });
}
