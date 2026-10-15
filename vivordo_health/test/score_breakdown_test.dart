import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'package:vivordo_health/src/utils/day_effort.dart';
import 'package:vivordo_health/src/utils/score_breakdown.dart';
import 'package:vivordo_health/widgets/score_breakdown_sheet.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 15, hour, minute);
  EffortItem item(
    String title,
    DateTime start,
    DateTime end,
    int rating,
    String category, {
    bool done = false,
  }) => (
    event: CalendarCognitiveEvent(
      id: title,
      title: title,
      start: start,
      end: end,
    ),
    score: CognitiveLoadScore(
      eventId: title,
      score: rating,
      category: category,
      reason: '',
      usedAi: false,
      confidence: .85,
    ),
    done: done,
    open: false,
  );

  test('Capacity part by part against the usual parts', () {
    Map record(double sleep, double body, double recovery) => {
      'parts': {'sleep': sleep, 'body': body, 'recovery': recovery},
    };
    final earlier = [for (var i = 0; i < 5; i++) record(90, 70, 100)];
    final today = {
      ...record(70, 76, 80),
      'sleepHours': 5.83,
      'sleepNeed': 7.05,
      'sleepNeedSettled': true,
      'bodyMeasured': true,
      'hrv': 52.0,
      'hrvNormal': 48.0,
      'restingHr': 58,
      'restingHrNormal': 58,
      'bigDay': {'ratio': 2.4, 'halved': false},
    };
    final rows = capacityBreakdown(today, earlier);
    expect(
      [for (final r in rows) r.title],
      ['Sleep', 'Overnight body', 'Recent load'],
    );
    // Weights 45, 35, 20 out of 100 counted today.
    expect(rows[0].points, closeTo(-9, 1e-9)); // (70 − 90) × 45%
    expect(rows[1].points, closeTo(2.1, 1e-9)); // (76 − 70) × 35%
    expect(rows[2].points, closeTo(-4, 1e-9)); // (80 − 100) × 20%
    expect(rows[0].detail, '5 h 50 · 1 h 13 under your need');
    expect(
      rows[1].detail,
      'HRV above your normal · resting heart rate at your normal',
    );
    expect(rows[2].detail, 'A big day: 2.4× your usual activity');

    // Sleep not in yet: a line for the rest of the gap to the usual.
    final partial = capacityBreakdown(
      {
        'score': 78,
        'parts': {'recovery': 89.8, 'checkIn': 62.5},
      },
      [
        for (var i = 0; i < 5; i++)
          {
            'parts': {'sleep': 85, 'recovery': 60, 'checkIn': 75},
          },
      ],
      usualScore: 82,
    );
    expect(partial.last.title, 'Not in today');
    expect(partial.last.detail, 'Sleep: part of your usual day');
    // Recent load: with no big day, recovery 89.8 against a usual of
    // 60 helps, and the detail says why.
    expect(partial[0].title, 'Recent load');
    expect(partial[0].points! > 0, isTrue);
    expect(
      partial[0].detail,
      'Heavier than usual, but lighter than your recent days',
    );
    // A big day that still helps reads as such, not as bad news.
    final bigButLighter = capacityBreakdown(
      {
        'score': 78,
        'parts': {'recovery': 89.8, 'checkIn': 62.5},
        'bigDay': {'ratio': 2.0, 'halved': false},
      },
      [
        for (var i = 0; i < 5; i++)
          {
            'parts': {'recovery': 60, 'checkIn': 75},
          },
      ],
      day: DateTime(2026, 10, 15),
    );
    expect(
      bigButLighter[0].detail,
      'A big day: 2.0× your usual activity, but lighter than your recent days',
    );
    // Named when it wasn't yesterday.
    final monday = capacityBreakdown(
      {
        'score': 78,
        'parts': {'recovery': 89.8},
        'bigDay': {'day': '2026-10-12', 'ratio': 2.0},
      },
      [
        for (var i = 0; i < 5; i++)
          {
            'parts': {'recovery': 60},
          },
      ],
      day: DateTime(2026, 10, 15),
    );
    expect(
      monday[0].detail,
      'A big day on Monday: 2.0× your usual activity, but lighter than your '
      'recent days',
    );
    // The check-in names both answers and how they compare: felt good
    // (75) but slept okay (50) is 62.5, under the usual 75.
    final checkIn = capacityBreakdown(
      {
        'score': 78,
        'parts': {'checkIn': 62.5},
        'checkInFeel': 75,
      },
      [
        for (var i = 0; i < 5; i++)
          {
            'parts': {'checkIn': 75},
          },
      ],
    ).single;
    expect(checkIn.points! < 0, isTrue);
    expect(
      checkIn.detail,
      'Felt good, slept okay · lower than your usual check-in',
    );
    // The whole numbers shown add up to the gap.
    final total = partial.fold<int>(0, (s, r) => s + r.points!.round());
    expect(total, 78 - 82);

    // Too little history: the parts show, without a number.
    expect(
      capacityBreakdown(today, earlier.take(2).toList())[0].points,
      isNull,
    );
  });

  test("Demand's rows add up to Demand, back-to-backs on their own line", () {
    final items = [
      item('Quiz', at(11), at(12), 75, 'high-consequence'),
      item('Lab', at(13), at(14), 40, 'collaboration'),
      item('App development', at(14), at(16, 30), 55, 'focused-work'),
      item('Done earlier', at(9), at(10), 40, 'collaboration'),
    ];
    final result = demandBreakdown(
      now: at(10, 30),
      from: at(0),
      until: at(24),
      wrapUp: at(17),
      items: items,
      untimedOpen: const ['light', 'light'],
    );
    final titles = [for (final r in result.rows) r.title];
    expect(titles, containsAllInOrder(['Quiz', 'Lab', 'App development']));
    expect(titles, isNot(contains('Done earlier')));
    expect(titles, contains('2 priorities'));
    expect(titles, contains('Back-to-backs and long runs'));
    expect(result.rows.first.chip, 'High stakes');
    final sum = result.rows.fold<double>(0, (s, r) => s + r.points!);
    expect(sum, closeTo(result.total, 1e-9));
  });

  test("Effort's rows add up to Effort", () {
    final result = effortBreakdown(
      now: at(15),
      from: at(0),
      until: at(24),
      wrapUp: at(17),
      items: [
        item('Quiz', at(11), at(12), 75, 'high-consequence'),
        item('Later', at(16), at(17), 40, 'collaboration'),
      ],
      untimedDone: [(doneAt: at(13), effort: 'light')],
      physical: 4,
    );
    expect(
      [for (final r in result.mental) r.title],
      ['Quiz', '1 priority ticked off'],
    );
    final mental = result.mental.fold<double>(0, (s, r) => s + r.points!);
    expect(mental + result.physical, closeTo(result.total, 1e-9));
  });

  test('whole-number points add up to the score', () {
    List<int?> whole(List<double?> points, int score, {bool leftOut = false}) {
      final rows = [
        for (final p in points) BreakdownRow('', '', points: p),
        if (leftOut) BreakdownRow('', '', leftOut: true),
      ];
      final map = wholePoints(rows, score);
      return [for (final row in rows) map[row]];
    }

    // Schedule 18 and Activity 10.5 make 29: the half rounds up.
    expect(whole([18, 10.5], 29), [18, 11]);
    // Three 3.4s show as 10, not 9.
    final threes = whole([3.4, 3.4, 3.4], 10);
    expect(threes.fold<int>(0, (a, b) => a + b!), 10);
    // Left-out rows and rows without points get no number.
    expect(whole([5.6, null], 6, leftOut: true), [6, null, null]);
    // A score the rows can't reach: plain rounding.
    expect(whole([2.4, 2.4], 20), [2, 2]);
  });
}
