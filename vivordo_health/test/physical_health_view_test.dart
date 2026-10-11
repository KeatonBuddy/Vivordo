import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/physical_health_view.dart';

void main() {
  Map<String, dynamic> record(int? score, {String label = 'good'}) => {
    'physical': {
      'score': score,
      'label': score == null ? 'building' : label,
      'daysOfData': 28,
      'parts': {
        'activeMinutes': 88.0,
        'movement': 90.5,
        'strength': 75.0,
        'cardio': 55.0,
        'sleep': 80.0,
      },
      'details': <String, Object?>{
        'weeklyActiveMinutes': 132,
        'avgSteps': 7240,
        'strengthPerWeek': 1.5,
        'vo2Max': 41.2,
        'vo2Source': 'apple_health',
        'vo2Normal': 41,
        'sleepHours': 7.08,
        'sleepOnTimeShare': .71,
        'sleepSource': 'tracked',
      },
    },
  };

  test('the latest score, its change over 4 weeks and ingredient details', () {
    final view = PhysicalHealthView.fromDays({
      '2026-09-03': record(71),
      '2026-09-20': record(73),
      '2026-10-01': record(74),
    })!;
    expect(view.score, 74);
    expect(view.status, 'Good');
    expect(view.note, '↑ 3 vs 4 weeks ago');
    expect(view.trend.map((p) => p.$2), [71, 73, 74]);
    expect(view.ingredients[0].detail, '132 of 150 min a week');
    expect(view.ingredients[1].detail, '7,240 of 8,000 steps a day');
    expect(view.ingredients[2].detail, '1.5 of 2 sessions a week');
    expect(view.ingredients[3].detail, 'VO₂ max 41 · Average for your age');
    expect(view.ingredients[4].detail, '7h 05m avg · 5 of 7 nights on time');
    // Biggest weighted gaps first: cardio (45 × 20), then strength.
    expect(view.insights.first, startsWith('Brisk walks or runs of 20+'));
    expect(view.insights[1], startsWith('Strength is an easy win'));
  });

  test('building shows progress and what is missing', () {
    final building = record(null);
    (building['physical'] as Map)['daysOfData'] = 9;
    final view = PhysicalHealthView.fromDays({'2026-10-01': building})!;
    expect(view.score, isNull);
    expect(view.status, 'Building');
    expect(view.note, 'Based on 9 of 14 days so far');
    expect(view.insights, [
      'Your Physical Health score appears after 2 weeks of activity and '
          'sleep data (9 of 14 days so far).',
    ]);
  });

  test('building after 2 weeks names what is missing, not fake gaps', () {
    // The server writes parts but no details while building.
    final view = PhysicalHealthView.fromDays({
      '2026-10-01': {
        'physical': {
          'score': null,
          'label': 'building',
          'daysOfData': 20,
          'parts': {
            'activeMinutes': 40.0,
            'movement': 60.0,
            'strength': null,
            'cardio': null,
            'sleep': null,
          },
        },
      },
    })!;
    expect(view.note, '2 of the 3 ingredients it needs so far');
    expect(view.insights, [
      'Your score starts once 3 of the 5 ingredients have data. Still '
          'missing: strength, cardio fitness and sleep habits.',
    ]);
  });

  test('the active-minutes tip scales with the gap', () {
    final short = record(60);
    final p = short['physical'] as Map;
    p['parts'] = {'activeMinutes': 20.0, 'movement': 100.0, 'sleep': 100.0};
    (p['details'] as Map)['weeklyActiveMinutes'] = 30;
    expect(
      PhysicalHealthView.fromDays({'2026-10-01': short})!.insights.first,
      'Active minutes are 120 short a week: about 25 more minutes on '
      'weekdays closes the gap.',
    );
  });

  test('missing cardio fitness explains what to add', () {
    final noAge = record(70);
    final details = (noAge['physical'] as Map)['details'] as Map;
    details['vo2Max'] = null;
    details['vo2Normal'] = null;
    final view = PhysicalHealthView.fromDays({'2026-10-01': noAge})!;
    expect(
      view.ingredients[3].detail,
      'Add your age in your profile (Fitness → Body)',
    );
    expect(PhysicalHealthView.fromDays({'2026-10-01': {}}), isNull);
  });
}
