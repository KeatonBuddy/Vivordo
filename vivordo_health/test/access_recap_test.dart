import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/access_recap.dart';
import 'package:vivordo_health/src/utils/meeting_patterns.dart';

Map<String, Map<String, dynamic>> scoresFor(
  DateTime from,
  int days,
  double Function(int) score,
) => {
  for (var i = 0; i < days; i++)
    _key(from.add(Duration(days: i))): {
      'capacity': {'score': score(i)},
    },
};

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

MeetingPattern pattern({required bool series, double percent = 21}) =>
    MeetingPattern(
      id: series ? 'abc' : 'size:large',
      label: series ? 'A repeating meeting' : 'Meetings with 6+ people',
      isSeries: series,
      direction: PatternDirection.high,
      count: 8,
      agreeing: 7,
      liftBpm: 9,
      liftPercent: percent,
      events: const [],
    );

void main() {
  final from = DateTime(2026, 11, 6), to = DateTime(2026, 12, 6);

  test('a month: every line, worded from the numbers', () {
    final recap = accessRecap(
      from: from,
      to: to,
      scores: scoresFor(from, 30, (i) => 55 + (i % 13).toDouble()),
      fixDays: {
        '2026-11-10': {
          'kinds': {
            'addBreak': {'used': true},
          },
        },
        '2026-11-11': {
          'kinds': {
            'moveLater': {'used': true, 'undone': true},
          },
        },
        '2026-11-12': {
          'helped': {'vivordoAi': true},
        },
        '2026-11-13': {
          'helped': {'planMyDay': true, 'vivordoAi': true},
        },
        '2026-10-01': {
          'helped': {'planMyDay': true},
        },
      },
      focus: '9:45–11:45 AM',
      freeFocusDays: 3,
      meeting: pattern(series: true),
      meetingName: 'Team sync',
    );
    expect(recap.heading, 'What Vivordo learned this month');
    expect(recap.dates, 'Nov 6 – Dec 6');
    expect(
      [for (final l in recap.lines) l.title],
      [
        'Your usual Capacity is 61',
        'Best focus: 9:45–11:45 AM',
        'Team sync raises your heart rate most',
        // The undone fix and the day outside the month don't count.
        'Vivordo helped plan 3 of your days',
      ],
    );
    expect(
      [for (final l in recap.lines) l.detail],
      [
        'learned from 4 weeks of your days',
        "and it's free on 3 days a week",
        '21% over your usual',
        'with day fixes, Plan my day and Vivordo AI',
      ],
    );
  });

  test('only lines with real numbers', () {
    final recap = accessRecap(
      from: from,
      to: to,
      scores: scoresFor(from, 5, (_) => 60),
      fixDays: const {},
      focus: '10–12 PM',
    );
    // Five scored days isn't a usual yet; no calendar, no meetings.
    expect([for (final l in recap.lines) l.title], ['Best focus: 10–12 PM']);
    expect(recap.lines.single.detail, 'when your energy usually peaks');
    expect(
      accessRecap(
        from: from,
        to: to,
        scores: const {},
        fixDays: const {},
      ).lines,
      isEmpty,
    );
  });

  test('a long subscription compares Capacity with the first month', () {
    final start = DateTime(2026, 12, 6), end = DateTime(2027, 6, 6);
    final recap = accessRecap(
      from: start,
      to: end,
      scores: scoresFor(start, 182, (i) => i < 30 ? 58 : 63),
      fixDays: {
        '2027-01-04': {
          'helped': {'vivordoAi': true},
        },
      },
      meeting: pattern(series: false),
    );
    expect(recap.heading, 'What Vivordo learned in 6 months');
    expect(recap.dates, 'Dec 2026 – Jun 2027');
    expect(recap.lines.first.detail, 'up from 58 in your first month');
    expect(
      recap.lines[1].title,
      'Meetings with 6+ people raise your heart rate most',
    );
    expect(recap.lines.last.title, 'Vivordo helped plan 1 of your days');
    expect(recap.lines.last.detail, 'with Vivordo AI');
  });
}
