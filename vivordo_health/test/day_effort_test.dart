import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'package:vivordo_health/src/utils/day_effort.dart';
import 'package:vivordo_health/src/utils/home_day_load.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 1, hour, minute);
  EffortItem item(
    String id,
    DateTime start,
    DateTime end,
    int? rating, {
    bool done = false,
    bool open = false,
  }) => (
    event: CalendarCognitiveEvent(id: id, title: id, start: start, end: end),
    score: CognitiveLoadScore(
      eventId: id,
      score: rating ?? 0,
      category: rating == null ? 'unknown' : 'collaboration',
      reason: '',
      usedAi: false,
      confidence: rating == null ? 0 : 0.85,
    ),
    done: done,
    open: open,
  );
  DayEffort build(
    DateTime now,
    List<EffortItem> items, {
    List<({DateTime doneAt, Object? effort})> untimedDone = const [],
    List<({DateTime start, DateTime end, double intensity})> workouts =
        const [],
  }) => buildDayEffort(
    now: now,
    from: at(8),
    until: at(22),
    wrapUp: at(17),
    items: items,
    untimedDone: untimedDone,
    workouts: workouts,
  );

  test('an event in progress is done up to now and ahead after it', () {
    final effort = build(at(9, 30), [item('meeting', at(9), at(10), 40)]);
    final nine = effort.hours[1];
    expect(nine.done, 20, reason: '30 min × 40 / 60');
    expect(nine.ahead, 20);
    expect(effort.soFar, 2);
    expect(effort.aheadMinutes, 30);
    expect(effort.aheadLevel, DayLoadLevel.focused);
  });

  test('ticked-off priorities fill their slot; open ones are only ahead', () {
    final effort = build(at(9), [
      item('done early', at(15), at(16), 75, done: true),
      item('open', at(11), at(12), 45, open: true),
      item('missed', at(8), at(9), 45, open: true),
    ]);
    expect(effort.hours[7].done, 75, reason: '3 PM, done early');
    expect(effort.hours[7].ahead, 0);
    expect(effort.hours[3].ahead, 45, reason: '11 AM, still planned');
    expect(effort.hours[0].done, 0, reason: 'an open priority never counts');
    expect(effort.hours[0].ahead, 0, reason: 'nor is its past slot ahead');
    expect(effort.nextStart, at(11));
  });

  test('unknown events count as 30, as on the server', () {
    final effort = build(at(12), [item('Busy', at(10), at(11), null)]);
    expect(effort.hours[2].done, 30);
  });

  test('untimed priorities tick their hour; workouts get their own bar', () {
    final effort = build(
      at(19),
      const [],
      untimedDone: [(doneAt: at(10, 20), effort: 'demanding')],
      workouts: [(start: at(18), end: at(18, 45), intensity: 0.35)],
    );
    expect(effort.hours[2].ticks, 1);
    expect(effort.hours[10].workout, 100, reason: '15.75 points, capped');
    expect(effort.soFar, closeTo(6 + 45 * 0.35, 0.01));
    expect(effort.aheadLevel, DayLoadLevel.none);
  });

  test('so far is a word against the usual by this time of day', () {
    // Usual: 2 points an hour from 9 AM, so 4 by 11 AM.
    final usualDay = [for (var h = 0; h < 24; h++) h < 9 ? 0 : (h - 8) * 2];
    final past = List.filled(14, usualDay);
    String word(double soFar) =>
        effortSoFarWord(soFar: soFar, now: at(11), pastByHour: past);
    expect(word(4), 'About usual');
    expect(word(9), 'Heavier than usual');
    expect(word(0), 'Lighter than usual');
    expect(
      effortSoFarWord(soFar: 9, now: at(11), pastByHour: past.sublist(1)),
      'Still learning your usual',
    );
    expect(workoutIntensity('Morning Run'), 0.35);
    expect(workoutIntensity('Workout Legs'), 0.2);
  });

  test('Demand is what is still ahead, on the Effort scale', () {
    final effort = buildDayEffort(
      now: at(9, 30),
      from: at(8),
      until: at(22),
      wrapUp: at(17),
      items: [
        item('meeting', at(9), at(10), 40),
        item('presentation', at(14), at(15), 75),
        item('dinner', at(18), at(19), 20),
        item('Gym', at(7), at(8), 15),
        item('Evening run', at(19), at(19, 30), 15),
      ],
      untimedOpen: ['light', null],
    );
    // 30 min of the meeting (2) + presentation (7.5) + dinner after hours
    // (2 × 1.25) + run event after hours (0.75 × 1.25) and its back-to-back
    // after dinner (0.5 × 1.25) plus the chain's ramp (37.5 / 600 × 1.25)
    // + untimed 2 + 4 + the run's physical 30 × 0.35. The gym is over.
    expect(
      effort.demand,
      closeTo(2 + 7.5 + 2.5 + 0.9375 + 0.625 + 0.078125 + 6 + 10.5, 0.01),
    );
  });
}
