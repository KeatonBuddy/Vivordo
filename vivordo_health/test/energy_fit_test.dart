import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'package:vivordo_health/src/utils/day_effort.dart';
import 'package:vivordo_health/src/utils/energy_fit.dart';
import 'package:vivordo_health/src/utils/energy_forecast.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 8, hour, minute);

  // The textbook day: peak 9:00–11:15, dip 2:00–4:45 PM, second wind
  // 5:45–7:45 PM, wind-down 10–11 PM (energy_forecast_test).
  final forecast = forecastEnergy(
    day: DateTime(2026, 10, 8),
    nights: [
      for (var i = 0; i < 14; i++)
        (
          start: DateTime(2026, 10, 7 - i, 23),
          end: DateTime(2026, 10, 8 - i, 7),
        ),
    ],
    sleepNeedHours: 8,
  );

  EffortItem item(
    String id,
    DateTime start,
    int minutes, {
    String category = 'focused-work',
    int score = 55,
    int attendees = 0,
    bool done = false,
  }) => (
    event: CalendarCognitiveEvent(
      id: id,
      title: id,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      attendeeCount: attendees,
    ),
    score: CognitiveLoadScore(
      eventId: id,
      score: score,
      category: category,
      reason: '',
      usedAi: false,
    ),
    done: done,
    open: category == 'priority' && !done,
  );

  List<EnergyFit> fit(List<EffortItem> items, {DateTime? now}) =>
      fitDayToEnergy(forecast: forecast, items: items, now: now ?? at(8));

  test('deep work in the dip is a clash with a peak slot to move to', () {
    final fits = fit([
      item('standup', at(11), 30, category: 'collaboration', score: 40),
      item('deep work', at(14), 60),
    ]);
    final clash = fits.single;
    expect(clash.kind, EnergyFitKind.clash);
    expect(clash.phase, EnergyPhase.dip);
    expect(clash.movable, isTrue);
    // 10:00–11:00 is the free peak hour nearest 2 PM (10:15 would run into
    // the standup).
    expect(clash.suggestedStart, at(10));
  });

  test('an item never blocks its own new slot', () {
    // 7:30–9:30 is judged at 8:00, while you're groggy; the nearest peak
    // start, 9:00, overlaps the item's current time, which mustn't count as
    // busy.
    final clash = fit([item('deep work', at(7, 30), 120)], now: at(7)).single;
    expect(clash.phase, EnergyPhase.groggy);
    expect(clash.suggestedStart, at(9));
  });

  test('a meeting with other people is flagged but never moved', () {
    final clash = fit([
      item(
        'budget review',
        at(14),
        60,
        category: 'high-consequence',
        score: 75,
        attendees: 4,
      ),
    ]).single;
    expect(clash.kind, EnergyFitKind.clash);
    expect(clash.movable, isFalse);
    expect(clash.suggestedStart, isNull);
  });

  test('hard work in the peak and routine work in the dip are good fits', () {
    final fits = fit([
      item('pricing model', at(9, 30), 90),
      item('inbox', at(15), 30, category: 'routine', score: 15),
      item('team lunch', at(12, 30), 60, category: 'social', score: 20),
    ]);
    expect(
      {for (final f in fits) f.id: f.kind},
      {'pricing model': EnergyFitKind.goodFit, 'inbox': EnergyFitKind.goodFit},
    );
  });

  test('a demanding priority counts as hard work; a moderate one doesn\'t', () {
    final fits = fit([
      item('write report', at(15, 30), 60, category: 'priority', score: 75),
      item('plan offsite', at(14), 30, category: 'priority', score: 45),
    ]);
    final clash = fits.single;
    expect(clash.id, 'write report');
    expect(clash.movable, isTrue);
    expect(clash.suggestedStart, isNotNull);
  });

  test('at most two clashes, hardest first', () {
    final fits = fit([
      item('a', at(14), 30, score: 55),
      item('b', at(15), 30, category: 'high-consequence', score: 75),
      item('c', at(16), 30, score: 55),
    ]);
    expect([for (final f in fits) f.id], ['b', 'a']);
  });

  test('items already started, done or in the past are not judged', () {
    final fits = fit([
      item('earlier', at(14), 30),
      item('done', at(15, 30), 30, category: 'priority', score: 75, done: true),
      item('later', at(16), 30),
    ], now: at(15));
    expect([for (final f in fits) f.id], ['later']);
  });

  test('a full peak falls back to the second wind, then to no suggestion', () {
    final busyMorning = item('workshop', at(8, 30), 180, attendees: 6);
    final fallback = fit([busyMorning, item('deep work', at(14), 60)]);
    final slot = fallback.firstWhere((f) => f.id == 'deep work').suggestedStart;
    expect(forecast.phaseAt(slot!), EnergyPhase.secondWind);

    final busyEvening = item('dinner', at(17, 30), 150, attendees: 3);
    final none = fit([busyMorning, busyEvening, item('deep work', at(14), 60)]);
    expect(none.firstWhere((f) => f.id == 'deep work').suggestedStart, isNull);
  });

  test('declined, cancelled and free-time events are ignored', () {
    EffortItem flagged(String id, CalendarCognitiveEvent event) => (
      event: event,
      score: CognitiveLoadScore(
        eventId: id,
        score: 55,
        category: 'focused-work',
        reason: '',
        usedAi: false,
      ),
      done: false,
      open: false,
    );
    final fits = fit([
      flagged(
        'declined',
        CalendarCognitiveEvent(
          id: 'declined',
          title: '',
          start: at(14),
          end: at(15),
          isDeclined: true,
        ),
      ),
      flagged(
        'free',
        CalendarCognitiveEvent(
          id: 'free',
          title: '',
          start: at(15),
          end: at(16),
          showsAsFree: true,
        ),
      ),
    ]);
    expect(fits, isEmpty);
  });
}
