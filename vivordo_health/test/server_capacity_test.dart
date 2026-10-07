import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/server_capacity.dart';

Map<String, dynamic> day(
  int score, {
  bool provisional = false,
  int version = 1,
}) => {
  'capacity': {
    'score': score,
    'label': score >= 80
        ? 'high'
        : score >= 50
        ? 'moderate'
        : 'low',
    'provisional': provisional,
    'version': version,
  },
};

void main() {
  const today = '2026-10-01';
  Map<String, Map<String, dynamic>> week(int usual) => {
    for (var i = 1; i <= 7; i++)
      '2026-09-${(23 + i - 1).toString()}': day(usual),
  };

  test('no server Capacity yet is null, so the old calculation is used', () {
    expect(serverCapacityFor({}, today), isNull);
    expect(
      serverCapacityFor({
        today: {'capacity': null},
      }, today),
      isNull,
    );
  });

  test('compares with the median of earlier days on the same version', () {
    expect(
      serverCapacityFor({...week(80), today: day(82)}, today)!.note,
      'Near your usual',
    );
    expect(
      serverCapacityFor({...week(80), today: day(65)}, today)!.note,
      'Below your usual',
    );
    expect(
      serverCapacityFor({...week(70), today: day(88)}, today)!.note,
      'Above your usual',
    );
    // Older formula versions don't count toward "usual".
    final oldVersion = {
      for (final e in week(80).entries) e.key: day(80, version: 0),
    };
    expect(
      serverCapacityFor({...oldVersion, today: day(60)}, today)!.note,
      'Still learning your usual',
    );
  });

  test('waiting for sleep says so, and keeps the label', () {
    final result = serverCapacityFor({
      ...week(80),
      today: day(45, provisional: true),
    }, today)!;
    expect(result.note, 'Estimated · waiting for sleep');
    expect(result.label, 'low');
    expect(result.score, 45);
  });

  test('a check-in-only Capacity says so', () {
    final checkInOnly = day(50, provisional: true);
    (checkInOnly['capacity'] as Map)['parts'] = {
      'sleep': null,
      'body': null,
      'checkIn': 50,
    };
    expect(
      serverCapacityFor({today: checkInOnly}, today)!.note,
      'Based on your check-in',
    );
    expect(
      serverCapacityFor({today: day(70, provisional: true)}, today)!.note,
      'Estimated · waiting for sleep',
    );
  });

  test('exposes usual Capacity for the evening card, null until 7 days', () {
    expect(serverCapacityFor({...week(68), today: day(90)}, today)!.usual, 68);
    expect(
      serverCapacityFor({'2026-09-30': day(70), today: day(90)}, today)!.usual,
      isNull,
    );
  });

  test('version 2 compares with version 1 days', () {
    final c = serverCapacityFor({
      ...week(80),
      today: day(60, version: 2),
    }, today)!;
    expect(c.usual, 80);
    expect(c.note, 'Below your usual');
  });

  test('a big day and today\'s load are read for My Day', () {
    final c = serverCapacityFor({
      today: {
        'capacity': {
          ...day(64, version: 2)['capacity'] as Map<String, dynamic>,
          'bigDay': {
            'day': '2026-09-30',
            'ratio': 3,
            'penalty': 70,
            'halved': false,
          },
          'activityUsual': {
            'kind': 'minutes',
            'usual': 8,
            'base': 8,
            'threshold': 16,
          },
        },
        'effort': {'physicalLoad': 26},
        'activityLoad': {'trimp': 300},
      },
    }, today)!;
    expect(c.bigDay!.day, DateTime(2026, 9, 30));
    expect(c.bigDay!.ratio, 3);
    expect(c.bigDay!.halved, isFalse);
    expect(c.todayBigDayRatio, closeTo(3.25, 1e-9));
    expect(
      bigDayHeadline(c.bigDay!, DateTime(2026, 10, 1)),
      'Big day yesterday. Go easy today.',
    );
    // 2026-09-30 is a Wednesday.
    expect(
      bigDayHeadline(c.bigDay!, DateTime(2026, 10, 2)),
      'Still recovering from Wednesday’s big day',
    );
  });

  test('today is a big day from the server\'s threshold', () {
    expect(bigDayRatio(16, 8, 16), 2);
    expect(bigDayRatio(15, 8, 16), isNull);
    expect(bigDayRatio(30, null, null), isNull);
  });

  test('heart-rate Capacity compares today\'s heart-rate load', () {
    final c = serverCapacityFor({
      today: {
        'capacity': {
          ...day(70, version: 2)['capacity'] as Map<String, dynamic>,
          'activityUsual': {
            'kind': 'heart',
            'usual': 50,
            'base': 50,
            'threshold': 100,
          },
        },
        'effort': {'physicalLoad': 26},
        'activityLoad': {'trimp': 160},
      },
    }, today)!;
    expect(c.todayLoad, 160);
    expect(c.todayBigDayRatio, closeTo(3.2, 1e-9));
  });
}
