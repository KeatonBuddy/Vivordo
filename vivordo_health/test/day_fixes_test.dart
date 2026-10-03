import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'package:vivordo_health/src/utils/day_effort.dart';
import 'package:vivordo_health/src/utils/day_fixes.dart';
import 'package:vivordo_health/src/utils/energy_fit.dart';
import 'package:vivordo_health/src/utils/energy_forecast.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 8, hour, minute);
  final now = at(8);

  EffortItem item(
    String id,
    DateTime start,
    int minutes, {
    String category = 'collaboration',
    int score = 40,
    int attendees = 0,
    bool organizer = false,
  }) => (
    event: CalendarCognitiveEvent(
      id: id,
      title: id,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      attendeeCount: attendees,
      isOrganizer: organizer,
    ),
    score: CognitiveLoadScore(
      eventId: id,
      score: score,
      category: category,
      reason: '',
      usedAi: false,
    ),
    done: false,
    open: category == 'priority',
  );

  double demandOf(List<EffortItem> items, List<Object?> untimed) =>
      buildDayEffort(
        now: now,
        from: at(0),
        until: DateTime(2026, 10, 9),
        wrapUp: at(17),
        items: items,
        untimedOpen: untimed,
      ).demand;

  List<DayFix> fixes(
    List<EffortItem> items, {
    List<DayFixPriority> untimed = const [],
    bool Function(EffortItem)? canMove,
    List<EnergyFit> fits = const [],
    bool breaks = false,
  }) => [
    for (final fix in findDayFixes(
      now: now,
      items: items,
      untimed: untimed,
      demandOf: demandOf,
      canMove: canMove ?? (_) => true,
      fits: fits,
    ))
      // Most days here have a long run; breaks have their own tests.
      if (breaks || fix.kind != DayFixKind.addBreak) fix,
  ];

  test('a buffer opens a gap in a back-to-back run, priced for real', () {
    final day = [
      item('standup', at(12), 30),
      item('design review', at(12, 30), 60, score: 55),
      item('client call', at(13, 30), 60),
    ];
    final buffer = fixes(day).single;
    expect(buffer.kind, DayFixKind.buffer);
    // Pushing the review leaves the call back-to-back with it, so the call
    // (which has an hour free after it) is the better move.
    expect(buffer.id, 'client call');
    expect(buffer.after, 'design review');
    expect(buffer.newStart, at(13, 45));
    expect(buffer.newEnd, at(14, 45));
    final after = demandOf([
      day[0],
      day[1],
      item('client call', at(13, 45), 60),
    ], const []);
    expect(buffer.demandSaved, closeTo(demandOf(day, const []) - after, 1e-9));
  });

  test('a buffer never lands on something else', () {
    final fits = fixes([
      item('standup', at(12), 30),
      item('review', at(12, 30), 30),
      item('call', at(13), 30),
    ]);
    // Pushing review to 12:45 would overlap the call; pushing the call to
    // 1:15 is fine.
    expect(fits.single.id, 'call');
  });

  test('meetings with other guests move only if you organised them', () {
    final day = [
      item('standup', at(12), 30),
      item('board meeting', at(12, 30), 60, attendees: 6),
    ];
    expect(fixes(day), isEmpty);
    final mine = fixes([
      day[0],
      item('board meeting', at(12, 30), 60, attendees: 6, organizer: true),
    ]).single;
    expect(mine.guests, 5);
  });

  test('the priority that saves most is the one to move', () {
    final fixesFound = fixes(
      [
        item('pitch deck', at(15), 120, category: 'priority', score: 75),
        item('inbox', at(10), 30, category: 'priority', score: 20),
      ],
      untimed: [(id: 'shoes', title: 'Buy running shoes', effort: 'light')],
    );
    final move = fixesFound.single;
    expect(move.kind, DayFixKind.movePriority);
    expect(move.title, 'pitch deck');
    final deck = item(
      'pitch deck',
      at(15),
      120,
      category: 'priority',
      score: 75,
    );
    final inbox = item('inbox', at(10), 30, category: 'priority', score: 20);
    expect(
      move.demandSaved,
      closeTo(
        demandOf([deck, inbox], ['light']) - demandOf([inbox], ['light']),
        1e-9,
      ),
    );
  });

  test('an untimed priority can be the one to move', () {
    final move = fixes(
      const [],
      untimed: [(id: 'deck', title: 'Finalize deck', effort: 'demanding')],
    ).single;
    expect(move.id, 'deck');
    expect(move.demandSaved, 6);
    expect(move.start, isNull);
  });

  test('items the app may not change are never offered', () {
    final day = [
      item('standup', at(12), 30),
      item('call', at(12, 30), 60),
      item('deck', at(15), 120, category: 'priority', score: 75),
    ];
    expect(fixes(day, canMove: (_) => false), isEmpty);
    // Past items aren't either.
    expect(
      findDayFixes(
        now: at(16),
        items: day,
        untimed: const [],
        demandOf: demandOf,
        canMove: (_) => true,
      ).where((f) => f.kind != DayFixKind.addBreak),
      isEmpty,
    );
  });

  test('a better energy slot comes after the Demand savings', () {
    final forecast = forecastEnergy(
      day: at(0),
      nights: [
        for (var i = 0; i < 14; i++)
          (
            start: DateTime(2026, 10, 7 - i, 23),
            end: DateTime(2026, 10, 8 - i, 7),
          ),
      ],
      sleepNeedHours: 8,
    );
    final day = [
      item('standup', at(12), 30),
      item('call', at(12, 30), 60),
      item('deep work', at(14), 60, category: 'focused-work', score: 55),
    ];
    final found = fixes(
      day,
      fits: fitDayToEnergy(forecast: forecast, items: day, now: now),
    );
    expect(found.map((f) => f.kind), [
      DayFixKind.buffer,
      DayFixKind.energySlot,
    ]);
    expect(found.last.id, 'deep work');
    // The free peak start nearest 2 PM that ends before the noon standup.
    expect(found.last.newStart, at(11));
  });

  group('a break', () {
    final run = [
      item('standup', at(12), 30),
      item('review', at(12, 30), 60),
      item('planning', at(13, 30), 30),
    ];

    test('goes right after a long back-to-back run, saving nothing', () {
      final fix = fixes(run, canMove: (_) => false, breaks: true).single;
      expect(fix.kind, DayFixKind.addBreak);
      expect(fix.newStart, at(14));
      expect(fix.newEnd, at(14, 15));
      expect(fix.after, 'planning');
      expect(fix.runMinutes, 120);
      expect(fix.beforeRun, isFalse);
      expect(fix.demandSaved, 0);
    });

    test('goes before the run when there is no room after', () {
      // Anything right after a run joins it, so "no room" is the day's end.
      final fix = fixes(
        [item('late shift', at(22), 115), item('wrap-up', at(23, 55), 5)],
        canMove: (_) => false,
        breaks: true,
      ).single;
      expect(fix.newStart, at(21, 45));
      expect(fix.beforeRun, isTrue);
      expect(fix.after, 'late shift');
    });

    test('is not offered for a short run or when a break is there', () {
      final hour = [item('standup', at(12), 30), item('sync', at(12, 30), 30)];
      expect(
        fixes(hour, canMove: (_) => false, breaks: true),
        isEmpty,
        reason: '90 minutes is the minimum',
      );
      final rested = item('Break', at(14), 15, category: 'rest', score: 0);
      expect(
        fixes([...run, rested], canMove: (_) => false, breaks: true),
        isEmpty,
      );
    });
  });
}
