import 'dart:math' as math;

import '../services/calendar_cognitive_load_service.dart';
import '../services/hourly_calendar_load.dart';
import 'home_day_load.dart';

/// Unknown events count as 30, as in the server's Effort (docs/scores.md §1).
const unknownEventRating = 30;

/// A rated calendar event or timed priority for the day's Effort card.
typedef EffortItem = ({
  CalendarCognitiveEvent event,
  CognitiveLoadScore score,

  /// A priority ticked off: counts as done in its whole slot, even if it's
  /// still ahead. Calendar events count as done only once they happen.
  bool done,

  /// An open priority: never counts as done, only as ahead.
  bool open,
});

/// One hour of Home's "Your Day's Effort" bars (0–100 each).
class EffortHour {
  const EffortHour({
    required this.start,
    required this.done,
    required this.ahead,
    required this.workout,
    required this.ticks,
  });

  final DateTime start;

  /// What happened (Effort), what's still planned (Demand), and workouts.
  final double done, ahead, workout;

  /// Untimed priorities ticked off in this hour.
  final int ticks;
}

/// The day's Effort card: bars from [from] to [until], Effort so far and
/// what's still ahead.
class DayEffort {
  const DayEffort({
    required this.hours,
    required this.soFar,
    required this.aheadMinutes,
    required this.aheadLevel,
    required this.nextStart,
    required this.demand,
  });

  final List<EffortHour> hours;

  /// Effort points so far today (mental + workouts), the same scale as the
  /// server's daily Effort.
  final double soFar;

  /// Planned minutes still ahead today and how heavy they are on average.
  final int aheadMinutes;
  final DayLoadLevel aheadLevel;

  /// When the next planned item starts, if one hasn't started yet.
  final DateTime? nextStart;

  /// Demand: Effort points still ahead today (docs/scores.md §2), on the
  /// same scale as Effort and Capacity's comparison.
  final double demand;
}

/// Calendar titles that are workouts: Demand forecasts their physical
/// Effort as well as the event itself.
final _workoutTitle = RegExp(
  r'\b(workout|gym|run|running|jog|hiit|spin|cycling|cycle|swim|yoga|pilates|'
  r'lift|lifting|training|crossfit|boxing|rowing|climb|climbing)\b',
  caseSensitive: false,
);

const _untimedPoints = {'light': 2, 'demanding': 6};

/// In-app workout intensity in points per minute, as the server
/// (functions/effort.js `workoutIntensity`).
double workoutIntensity(String text) {
  final value = text.toLowerCase();
  if (RegExp(
    r'\b(run|running|sprint|hiit|interval|spin|cycling|rowing|swim|boxing|crossfit)',
  ).hasMatch(value)) {
    return 0.35;
  }
  if (RegExp(
    r'\b(walk|walking|yoga|stretch|mobility|pilates|cooldown)',
  ).hasMatch(value)) {
    return 0.1;
  }
  return 0.2;
}

CognitiveLoadScore _rated(CognitiveLoadScore score) => score.isKnown
    ? score
    : CognitiveLoadScore(
        eventId: score.eventId,
        score: unknownEventRating,
        category: 'estimate',
        reason: score.reason,
        usedAi: score.usedAi,
        confidence: 0.3,
      );

CalendarCognitiveEvent _clip(
  CalendarCognitiveEvent e, {
  DateTime? start,
  DateTime? end,
}) => CalendarCognitiveEvent(
  id: e.id,
  title: e.title,
  start: start ?? e.start,
  end: end ?? e.end,
);

/// Builds the day's Effort and Demand. Events count as done up to [now] and
/// as ahead after it; ticked-off priorities count as done in their slot;
/// open priorities only ahead. Effort so far adds untimed priorities ticked
/// off today ([untimedDone], at light 2 / moderate 4 / demanding 6) and the
/// elapsed part of [workouts]; Demand adds open untimed priorities
/// ([untimedOpen], their efforts) and workouts planned in the calendar. For
/// a whole day ahead (tomorrow), pass the day's start as [now].
DayEffort buildDayEffort({
  required DateTime now,
  required DateTime from,
  required DateTime until,
  required DateTime wrapUp,
  required List<EffortItem> items,
  List<({DateTime doneAt, Object? effort})> untimedDone = const [],
  List<Object?> untimedOpen = const [],
  List<({DateTime start, DateTime end, double intensity})> workouts = const [],
}) {
  List<HourlyCalendarLoad> loads(
    Iterable<(CalendarCognitiveEvent, CognitiveLoadScore)> rated,
  ) {
    final list = rated.toList();
    return HourlyCalendarLoadCalculator.calculate(
      events: [for (final (e, _) in list) e],
      scores: [for (final (_, s) in list) s],
      from: from,
      until: until,
    );
  }

  final done = loads([
    for (final item in items)
      if (item.done)
        (item.event, _rated(item.score))
      else if (!item.open && item.event.start.isBefore(now))
        (
          item.event.end.isAfter(now)
              ? _clip(item.event, end: now)
              : item.event,
          _rated(item.score),
        ),
  ]);
  final ahead = loads([
    for (final item in items)
      if (!item.done && item.event.end.isAfter(now))
        (
          item.event.start.isBefore(now)
              ? _clip(item.event, start: now)
              : item.event,
          _rated(item.score),
        ),
  ]);

  final hours = <EffortHour>[];
  var soFar = 0.0;
  var demand = 0.0;
  for (var i = 0; i < done.length; i++) {
    final start = from.add(Duration(hours: i));
    final end = start.add(const Duration(hours: 1));
    // After-hours share of the hour by time, × 1.25 (display estimate; the
    // server's Effort is exact).
    final afterMinutes = end.isAfter(wrapUp)
        ? end
              .difference(wrapUp.isAfter(start) ? wrapUp : start)
              .inMinutes
              .clamp(0, 60)
        : 0;
    final doneLoad = done[i].score ?? 0;
    soFar += doneLoad * (1 + 0.25 * afterMinutes / 60) / 10;
    demand += (ahead[i].score ?? 0) * (1 + 0.25 * afterMinutes / 60) / 10;
    var workoutPoints = 0.0;
    for (final w in workouts) {
      final overlapStart = w.start.isAfter(start) ? w.start : start;
      final cutoff = [w.end, end, now].reduce((a, b) => a.isBefore(b) ? a : b);
      if (cutoff.isAfter(overlapStart)) {
        workoutPoints +=
            cutoff.difference(overlapStart).inSeconds / 60 * w.intensity;
      }
    }
    soFar += workoutPoints;
    hours.add(
      EffortHour(
        start: start,
        done: doneLoad,
        ahead: ahead[i].score ?? 0,
        workout: math.min(100, workoutPoints * 10),
        ticks: untimedDone
            .where((p) => !p.doneAt.isBefore(start) && p.doneAt.isBefore(end))
            .length,
      ),
    );
  }
  for (final p in untimedDone) {
    soFar += _untimedPoints[p.effort] ?? 4;
  }
  for (final effort in untimedOpen) {
    demand += _untimedPoints[effort] ?? 4;
  }
  // Workouts planned in the calendar: their remaining minutes' physical
  // Effort, as the server will count them once they're logged.
  for (final item in items) {
    if (item.done ||
        !item.event.end.isAfter(now) ||
        !_workoutTitle.hasMatch(item.event.title)) {
      continue;
    }
    final start = item.event.start.isBefore(now) ? now : item.event.start;
    demand +=
        item.event.end.difference(start).inMinutes *
        workoutIntensity(item.event.title);
  }

  final aheadMinutes = ahead.fold<double>(0, (s, h) => s + h.occupiedMinutes);
  final aheadDemand = ahead.fold<double>(0, (s, h) => s + h.demand * 60);
  final upcoming = [
    for (final item in items)
      if (!item.done && item.event.start.isAfter(now)) item.event.start,
  ]..sort();
  return DayEffort(
    hours: hours,
    soFar: soFar,
    aheadMinutes: aheadMinutes.round(),
    aheadLevel: aheadMinutes == 0
        ? DayLoadLevel.none
        : dayLoadLevel(aheadDemand / aheadMinutes),
    nextStart: upcoming.firstOrNull,
    demand: demand,
  );
}

/// "So far" on Home: today's Effort compared with the usual by this time of
/// day, the median of earlier days' running totals (`effort.byHour` from
/// the server). A word only, never a number (docs/scores.md §3).
String effortSoFarWord({
  required double soFar,
  required DateTime now,
  required List<List<num>> pastByHour,
}) {
  if (pastByHour.length < 14) return 'Still learning your usual';
  final hour = now.hour;
  final fraction = now.minute / 60;
  final usualByNow = [
    for (final day in pastByHour)
      if (day.length > hour)
        (hour == 0 ? 0 : day[hour - 1].toDouble()) +
            (day[hour] - (hour == 0 ? 0 : day[hour - 1])) * fraction,
  ]..sort();
  if (usualByNow.length < 14) return 'Still learning your usual';
  final mid = usualByNow.length ~/ 2;
  final usual = usualByNow.length.isOdd
      ? usualByNow[mid]
      : (usualByNow[mid - 1] + usualByNow[mid]) / 2;
  // A margin of 20% and at least 2 points, so a quiet morning isn't
  // "heavier" over a point or two.
  if (soFar > usual * 1.2 + 2) return 'Heavier than usual';
  if (soFar < usual * 0.8 - 2) return 'Lighter than usual';
  return 'About usual';
}
