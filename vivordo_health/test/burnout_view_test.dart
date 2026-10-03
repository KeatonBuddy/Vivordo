import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/burnout_view.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/burnout_card.dart';

void main() {
  Map<String, dynamic> area({bool elevated = false, num score = 0}) => {
    'elevated': elevated,
    'score': score,
    'worseDays': 11,
    'days': 14,
  };

  test('learning counts days towards the first check', () {
    final view = BurnoutView.fromMap({
      'level': 'learning',
      'learningDays': 7,
      'areas': {},
    }, '2026-10-01')!;
    expect(view.title, 'Learning your normal');
    expect(view.learningProgress, closeTo(1 / 3, 1e-9));
    expect(view.body, contains('7 of 21 days'));
  });

  test('watch names the drifting area and what held steady', () {
    final view = BurnoutView.fromMap({
      'level': 'watch',
      'areas': {
        'capacity': area(),
        'effort': area(elevated: true, score: 1.4),
        'mood': area(),
      },
      'drivers': [
        {'name': 'afterHoursMinutes', 'recent': 70, 'usual': 20},
      ],
    }, '2026-10-01')!;
    expect(view.title, 'Your days have been heavier than usual');
    expect(
      view.body,
      'Effort has been heavier than usual on 11 of the last 14 days, '
      'while Capacity and Mood held steady.',
    );
    expect(view.areas[1].word, 'Heavier · 11 of 14 days');
    expect(view.drivers, ['1h 10m after hours a day (usual 20m)']);
    expect(
      view.suggestions.first,
      'Protect one evening this week from after-hours work',
    );
  });

  test('warning counts days since it started', () {
    final view = BurnoutView.fromMap({
      'level': 'warning',
      'since': '2026-09-21',
      'state': {'strainedDays': 13},
      'areas': {
        'capacity': area(elevated: true, score: 2.1),
        'effort': area(elevated: true, score: 1.2),
        'mood': area(score: 0.4),
      },
      'drivers': [
        {'name': 'sleepHours', 'recent': 6.2, 'usual': 7.05},
        {'name': 'backToBack', 'recent': 5, 'usual': 2},
      ],
    }, '2026-09-30')!;
    expect(view.title, 'Signs of a slide for 13 days');
    expect(
      view.body,
      "Capacity and Effort have been off your normal, and it's held for "
      'over a week.',
    );
    expect(view.areas[2].word, 'Slightly lower');
    expect(view.drivers.first, 'Sleep 6h 12m a night (usual 7h 03m)');
    expect(view.suggestions, hasLength(3));
  });

  test('no result yet shows nothing', () {
    expect(BurnoutView.fromMap(null, '2026-10-01'), isNull);
  });

  testWidgets('learning and steady are one line; watch is the full card', (
    tester,
  ) async {
    Future<void> show(Map<String, dynamic> data) => tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: BurnoutCard(view: BurnoutView.fromMap(data, '2026-10-01')!),
        ),
      ),
    );

    await show({'level': 'learning', 'learningDays': 13, 'areas': {}});
    expect(find.text('Burnout check'), findsOneWidget);
    expect(find.text('Learning your normal'), findsOneWidget);
    expect(find.textContaining('42'), findsNothing);

    await show({'level': 'steady', 'areas': {}});
    expect(find.text('Steady'), findsOneWidget);

    await show({'level': 'steady', 'early': true, 'areas': {}});
    expect(find.text('Steady · early check'), findsOneWidget);
    expect(find.textContaining('normal range'), findsNothing);

    await show({
      'level': 'watch',
      'areas': {'capacity': area(elevated: true, score: 1.4)},
    });
    expect(find.text('BURNOUT CHECK · WORTH WATCHING'), findsOneWidget);
    expect(find.text('Burnout check'), findsNothing);
  });
}
