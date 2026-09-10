import 'dart:math' as math;

import 'calendar_cognitive_load_service.dart';

/// Versioned, experimental calendar context, not a physiological measurement.
/// Demand is integrated over a full hour (unoccupied minutes contribute zero).
/// Pressure adds at most 25 points, scaled by occupied minutes / 60.
class HourlyCalendarLoad {
  const HourlyCalendarLoad({
    required this.start,
    required this.end,
    required this.evaluatedUntil,
    required this.calendarAvailable,
    required this.demand,
    required this.pressure,
    required this.occupiedMinutes,
    required this.knownMinutes,
    required this.confidence,
    required this.score,
    this.overlapMinutes = 0,
    this.backToBackMinutes = 0,
    this.backToBackTransitions = 0,
    this.continuousPressurePoints = 0,
  });

  final DateTime start, end, evaluatedUntil;
  final bool calendarAvailable;
  final double demand, pressure, occupiedMinutes, knownMinutes, confidence;

  /// Null means unavailable calendar or only unclassified occupied events.
  final double? score;
  final double overlapMinutes, backToBackMinutes, continuousPressurePoints;
  final int backToBackTransitions;

  Map<String, Object?> toJson() => {
    'version': 1,
    'classifier_version': CalendarCognitiveLoadService.classifierVersion,
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
    'evaluated_until': evaluatedUntil.toUtc().toIso8601String(),
    'calendar_available': calendarAvailable,
    'demand': demand,
    'schedule_pressure': pressure,
    'occupied_minutes': occupiedMinutes,
    'known_minutes': knownMinutes,
    'classification_confidence': confidence,
    'calendar_load': score,
    'overlap_minutes': overlapMinutes,
    'back_to_back_minutes': backToBackMinutes,
    'back_to_back_transitions': backToBackTransitions,
    'continuous_pressure_points': continuousPressurePoints,
  };
}

class HourlyCalendarLoadCalculator {
  /// [asOf] limits live/historical calculations to elapsed time. Omit it only
  /// for a forecast. Include earlier events to detect runs across hour boundaries.
  static List<HourlyCalendarLoad> calculate({
    required List<CalendarCognitiveEvent> events,
    required List<CognitiveLoadScore> scores,
    required DateTime from,
    required DateTime until,
    DateTime? asOf,
    bool calendarAvailable = true,
  }) {
    final cutoff = asOf != null && asOf.isBefore(until) ? asOf : until;
    final byId = {for (final score in scores) score.eventId: score};
    // Same provider occurrence ID is counted once. Separate occurrences must
    // have separate IDs at the provider boundary.
    final eligible = {
      for (final event in events)
        if (event.contributesToSchedule && event.start.isBefore(cutoff))
          event.id: event,
    }.values.toList()..sort((a, b) => a.start.compareTo(b.start));
    final result = <HourlyCalendarLoad>[];
    for (
      var start = from;
      start.isBefore(cutoff);
      start = start.add(const Duration(hours: 1))
    ) {
      final end = start.add(const Duration(hours: 1));
      final stop = end.isBefore(cutoff) ? end : cutoff;
      final relevant = eligible
          .where((e) => e.end.isAfter(start) && e.start.isBefore(stop))
          .toList();
      final boundaries = <DateTime>{start, stop};
      for (final e in relevant) {
        if (e.start.isAfter(start)) boundaries.add(e.start);
        if (e.end.isBefore(stop)) boundaries.add(e.end);
      }
      final points = boundaries.toList()..sort();
      double overlapMinutes = 0, tightMinutes = 0, continuousPoints = 0;
      final transitions = <String>{};
      double occupied = 0,
          known = 0,
          demand = 0,
          certainty = 0,
          pressureIntegral = 0;
      for (var i = 0; i < points.length - 1; i++) {
        final a = points[i], b = points[i + 1];
        final minutes =
            b.difference(a).inMicroseconds / Duration.microsecondsPerMinute;
        final active = relevant
            .where((e) => !e.start.isAfter(a) && e.end.isAfter(a))
            .toList();
        if (active.isEmpty) continue;
        occupied += minutes;
        final classified =
            active
                .map((e) => byId[e.id])
                .whereType<CognitiveLoadScore>()
                .where((s) => s.isKnown)
                .toList()
              ..sort((a, b) => b.score.compareTo(a.score));
        if (classified.isNotEmpty) {
          final strongest = classified.first;
          demand += minutes * strongest.score / 60;
          known += minutes;
          certainty += minutes * strongest.confidence;
        }
        // Only transitions already reached contribute; future meetings cannot
        // raise the current hour. Use previous end times, not a UI hint flag.
        var tight = false;
        for (final e in active) {
          final hasTightTransition = eligible.any(
            (previous) =>
                previous.id != e.id &&
                !previous.end.isAfter(e.start) &&
                e.start.difference(previous.end) < const Duration(minutes: 15),
          );
          tight = tight || hasTightTransition;
          if (hasTightTransition && !e.start.isBefore(start)) {
            transitions.add(e.id);
          }
        }
        // Find the continuous occupied run leading into this segment.
        var runStart = active
            .map((e) => e.start)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        for (final e in eligible.reversed) {
          if (e.start.isBefore(runStart) && !e.end.isBefore(runStart)) {
            runStart = e.start;
          }
        }
        final runMinutes =
            a.difference(runStart).inMicroseconds /
            Duration.microsecondsPerMinute;
        // Integrate the ramp exactly, so splitting an event cannot change load.
        double rampArea(double t) {
          final x = (t - 60).clamp(0.0, 60.0);
          return x * x / 120 + math.max(0, t - 120);
        }

        final runPressure =
            5 * (rampArea(runMinutes + minutes) - rampArea(runMinutes));
        if (active.length > 1) overlapMinutes += minutes;
        if (tight) tightMinutes += minutes;
        continuousPoints += runPressure / 60;
        pressureIntegral +=
            minutes * ((active.length > 1 ? 10 : 0) + (tight ? 10 : 0)) +
            runPressure;
      }
      final pressure = occupied == 0 ? 0.0 : pressureIntegral / occupied;
      final value = !calendarAvailable || (occupied > 0 && known == 0)
          ? null
          : (demand + pressureIntegral / 60).clamp(0.0, 100.0).toDouble();
      result.add(
        HourlyCalendarLoad(
          start: start,
          end: end,
          evaluatedUntil: stop,
          calendarAvailable: calendarAvailable,
          demand: demand,
          pressure: pressure,
          occupiedMinutes: occupied,
          knownMinutes: known,
          confidence: occupied == 0 ? 0 : certainty / occupied,
          score: value,
          overlapMinutes: overlapMinutes,
          backToBackMinutes: tightMinutes,
          backToBackTransitions: transitions.length,
          continuousPressurePoints: continuousPoints,
        ),
      );
    }
    return result;
  }
}
