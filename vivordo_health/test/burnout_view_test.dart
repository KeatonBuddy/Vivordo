import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/burnout_view.dart';

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
      'learningDays': 21,
      'areas': {},
    }, '2026-10-01')!;
    expect(view.title, 'Learning your normal');
    expect(view.learningProgress, 0.5);
    expect(view.body, contains('21 of 42 days'));
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
}
