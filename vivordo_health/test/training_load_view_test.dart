import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/burnout_view.dart';
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
    expect(find.text('TRAINING LOAD · HIGH'), findsOneWidget);
    await tester.tap(find.text('Plan an easier week'));
    expect(asked.single.screen, 'training_load');
    expect(asked.single.context, contains('4 hard days'));

    await tester.tap(find.text('Details ›'));
    await tester.pumpAndSettle();
    expect(find.byType(TrainingLoadCard), findsOneWidget);
    expect(find.text('HOW THIS WORKS'), findsOneWidget);
    expect(find.text('+60% vs your usual'), findsOneWidget);
  });
}
