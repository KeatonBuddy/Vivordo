import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/burnout_view.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'package:vivordo_health/src/utils/training_load_view.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/contextual_insight_bar.dart';
import 'package:vivordo_health/widgets/training_load_card.dart';

void main() {
  Map<String, dynamic> record(
    String state, {
    double ratio = 1.04,
    int hardDays = 1,
    Map<String, dynamic>? body,
  }) => {
    'version': 1,
    'state': state,
    'ratio': ratio,
    'thisWeek': 7.3,
    'usualWeek': 7.0,
    'hardDays': hardDays,
    'kind': 'heart',
    'days': [
      for (var i = 0; i < 7; i++)
        {
          'day': '2026-09-${23 + i}',
          'value': i == 6 ? 2.2 : 0.8,
          'kind': 'heart',
        },
    ],
    'body':
        body ??
        {'mornings': 3, 'hrvLow': 0, 'restingHigh': 0, 'restingHrChange': 0},
  };

  test('learning, unknown versions and junk are hidden', () {
    expect(
      TrainingLoadView.fromMap({'version': 1, 'state': 'learning'}, 'd'),
      isNull,
    );
    expect(
      TrainingLoadView.fromMap({...record('steady'), 'version': 2}, 'd'),
      isNull,
    );
    expect(TrainingLoadView.fromMap('steady', 'd'), isNull);
  });

  test('a steady week reads as usual with a normal body', () {
    final view = TrainingLoadView.fromMap(record('steady'), '2026-09-30')!;
    expect(view.alert, isFalse);
    expect(view.headline, 'About your usual week');
    expect(view.vsUsual, 'About your usual');
    expect(view.days, hasLength(7));
    expect(view.bodyRows.single.value, 'HRV and resting HR normal');
    expect(view.bodyExplanation, isNull);
    expect(view.measuredBy, 'Measured by heart rate');
  });

  test('a strained week names the hard days and the body', () {
    final view = TrainingLoadView.fromMap(
      record(
        'strained',
        ratio: 1.6,
        hardDays: 4,
        body: {
          'mornings': 3,
          'hrvLow': 2,
          'restingHigh': 1,
          'restingHrChange': 4.2,
        },
      ),
      '2026-09-30',
    )!;
    expect(view.alert, isTrue);
    expect(view.vsUsual, '+60% vs your usual');
    expect(
      view.summary,
      'About 60% above your usual this week, on 4 hard days, and your HRV '
      'has been low 2 of the last 3 mornings.',
    );
    expect(view.bodyRows.map((r) => r.value), [
      'Low 2 of the last 3 mornings',
      '+4 bpm today',
    ]);
    expect(view.bodyExplanation, contains('HRV (heart rate variability)'));
    expect(view.bodyExplanation, contains('Resting heart rate is'));
    expect(
      TrainingLoadView.fromMap(
        record('high', body: {'mornings': 3, 'hrvLow': 0, 'restingHigh': 2}),
        'd',
      )!.bodyExplanation,
      allOf(
        startsWith('Resting heart rate is'),
        isNot(contains('HRV')),
        contains("It's compared with your own normal"),
      ),
    );
    expect(view.chatContext, contains('1.60× the usual week'));
    expect(
      TrainingLoadView.fromMap(record('high', ratio: 2.4), 'd')!.summary,
      startsWith('About 2.4× your usual this week'),
    );
  });

  test('lighter weeks and no mornings', () {
    final view = TrainingLoadView.fromMap(
      record('lighter', ratio: 0.62, body: {'mornings': 0}),
      'd',
    )!;
    expect(view.vsUsual, '−38% vs your usual');
    expect(view.bodyRows, isEmpty);
    expect(view.bodyExplanation, isNull);
  });

  test('burnout names training load and suggests an easier week', () {
    final view = BurnoutView.fromMap({
      'level': 'watch',
      'areas': {
        'effort': {'elevated': true, 'score': 1.4, 'worseDays': 9, 'days': 14},
      },
      'drivers': [
        {'name': 'trainingLoad', 'recent': 1.6, 'usual': 1.0},
      ],
    }, '2026-10-01')!;
    expect(view.drivers, ['Training load about 60% above your usual']);
    expect(
      view.suggestions.first,
      'Take an easier week: swap one hard session for a walk',
    );
  });

  testWidgets('My Day card plans an easier week with Vivordo AI', (
    tester,
  ) async {
    final asked = <ScreenInsight>[];
    final controller = ScreenInsightController()..onAsk = asked.add;
    addTearDown(controller.dispose);
    final view = TrainingLoadView.fromMap(
      record('high', ratio: 1.6, hardDays: 4),
      '2026-09-30',
    )!;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: ScreenInsightScope(
          controller: controller,
          child: Scaffold(body: TrainingLoadAlert(view: view)),
        ),
      ),
    );
    expect(find.text('Training load · High'), findsOneWidget);
    await tester.tap(find.text('Plan an easier week'));
    expect(asked.single.screen, 'training_load');
    expect(asked.single.context, contains('4 hard days'));

    await tester.tap(find.text('Details ›'));
    await tester.pumpAndSettle();
    expect(find.byType(TrainingLoadCard), findsOneWidget);
    expect(find.text('+60% vs your usual'), findsOneWidget);
    // A normal body needs no explanation.
    expect(find.text('What your body is saying'), findsNothing);
  });

  testWidgets('the body explanation is in the sheet, not on the card', (
    tester,
  ) async {
    final view = TrainingLoadView.fromMap(
      record(
        'strained',
        ratio: 1.6,
        hardDays: 4,
        body: {'mornings': 3, 'hrvLow': 2, 'restingHigh': 0},
      ),
      '2026-09-30',
    )!;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: SingleChildScrollView(
              child: TrainingLoadCard(
                view: view,
                onTap: () => showTrainingLoadDetails(context, view),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('HRV (heart rate variability)'), findsNothing);

    await tester.tap(find.byType(TrainingLoadCard));
    await tester.pumpAndSettle();
    expect(find.text('What your body is saying'), findsOneWidget);
    expect(find.textContaining('HRV (heart rate variability)'), findsOneWidget);
  });

  test(
    'earlier weeks: 7 days apart, a synced morning nearby, 12 weeks back',
    () {
      final latest = TrainingLoadView.fromMap(
        record('building'),
        '2026-10-30',
      )!;
      final weeks = TrainingLoadView.weeks(latest, {
        '2026-10-23': record('steady'),
        // Oct 16 didn't sync; Oct 14 is within 3 days.
        '2026-10-14': record('high', ratio: 1.6),
        '2026-10-09': {'version': 1, 'state': 'learning'},
        for (var w = 4; w < 20; w++)
          localDayKey(DateTime(2026, 10, 30 - 7 * w)): record(
            'lighter',
            ratio: .7,
          ),
      });
      expect(weeks.first, same(latest));
      expect(weeks[1].dayKey, '2026-10-23');
      expect(weeks[2].dayKey, '2026-10-14');
      // Oct 9 is still learning, so the next week is Oct 2.
      expect(weeks[3].dayKey, '2026-10-02');
      // 12 weeks back in time, less the one still learning; never older.
      expect(weeks, hasLength(TrainingLoadView.historyWeeks - 1));

      expect(TrainingLoadView.weeks(latest, const {}), [latest]);
    },
  );

  test('date range across a month', () {
    final view = TrainingLoadView.fromMap(record('steady'), '2026-09-30')!;
    expect(view.dateRange, 'Sep 23 – 29');
    final raw = record('steady');
    raw['days'] = [
      for (var i = 0; i < 7; i++)
        {'day': localDayKey(DateTime(2026, 9, 25 + i)), 'value': 1.0},
    ];
    expect(
      TrainingLoadView.fromMap(raw, '2026-10-02')!.dateRange,
      'Sep 25 – Oct 1',
    );
  });
}
