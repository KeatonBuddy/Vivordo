import 'dart:math' as math;

class DailyCapacityResult {
  const DailyCapacityResult({
    required this.score,
    required this.label,
    required this.availableSignals,
  });

  final int? score;
  final String label;
  final int availableSignals;
}

class ScheduleDemandResult {
  const ScheduleDemandResult({
    required this.score,
    required this.label,
    required this.occupancyPoints,
    required this.continuousLoadPoints,
    required this.breakQualityPoints,
    required this.fragmentationPoints,
    required this.occupiedMinutes,
    required this.unscheduledMinutes,
  });

  final int score;
  final String label;
  final double occupancyPoints;
  final double continuousLoadPoints;
  final double breakQualityPoints;
  final double fragmentationPoints;
  final int occupiedMinutes;
  final int unscheduledMinutes;
}

class DailyScheduleEvent {
  const DailyScheduleEvent({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final DateTime start;
  final DateTime end;
}

/// Estimates how much personal capacity is available for the day.
///
/// Each available signal is normalized to 0–100 and the weights are
/// rebalanced when a source is missing. Heart rate is intentionally a small
/// contributor because a raw BPM value is less useful without a baseline.
DailyCapacityResult calculateDailyCapacity({
  double? sleepHours,
  double? stressScore,
  double? heartRate,
}) {
  final signals = <(double, double)>[];

  if (sleepHours != null && sleepHours.isFinite && sleepHours > 0) {
    final sleepScore = (100 - (8 - sleepHours).abs() * 15).clamp(0, 100);
    signals.add((sleepScore.toDouble(), .45));
  }
  if (stressScore != null && stressScore.isFinite) {
    signals.add(((100 - stressScore).clamp(0, 100).toDouble(), .35));
  }
  if (heartRate != null &&
      heartRate.isFinite &&
      heartRate >= 30 &&
      heartRate <= 220) {
    final heartScore = (100 - (heartRate - 60).abs() * 2).clamp(0, 100);
    signals.add((heartScore.toDouble(), .20));
  }

  if (signals.isEmpty) {
    return const DailyCapacityResult(
      score: null,
      label: 'Not enough data',
      availableSignals: 0,
    );
  }

  final totalWeight = signals.fold<double>(0, (sum, item) => sum + item.$2);
  final weightedScore = signals.fold<double>(
    0,
    (sum, item) => sum + item.$1 * item.$2,
  );
  final score = (weightedScore / totalWeight).round().clamp(0, 100);

  return DailyCapacityResult(
    score: score,
    label: score >= 70
        ? 'High'
        : score >= 40
        ? 'Moderate'
        : 'Low',
    availableSignals: signals.length,
  );
}

/// Measures schedule demand across the whole calendar day.
///
/// Overlapping events are merged for occupancy, gaps under ten minutes do not
/// reset continuous load, and event-count pressure has diminishing returns.
/// Eight occupied hours represents maximum occupancy pressure even though all
/// events from midnight to midnight are eligible.
ScheduleDemandResult calculateScheduleDemand({
  required Iterable<DailyScheduleEvent> events,
  required DateTime dayStart,
  required DateTime dayEnd,
}) {
  if (!dayEnd.isAfter(dayStart)) {
    throw ArgumentError.value(dayEnd, 'dayEnd', 'Must be after dayStart');
  }

  final seen = <String>{};
  final eligible =
      events
          .where((event) {
            if (!event.end.isAfter(event.start) ||
                !event.end.isAfter(dayStart) ||
                !event.start.isBefore(dayEnd)) {
              return false;
            }
            final key =
                '${event.title.trim().toLowerCase()}|'
                '${event.start.millisecondsSinceEpoch}|${event.end.millisecondsSinceEpoch}';
            return seen.add(key);
          })
          .map((event) {
            final start = event.start.isBefore(dayStart)
                ? dayStart
                : event.start;
            final end = event.end.isAfter(dayEnd) ? dayEnd : event.end;
            return _ScheduleBlock(start, end);
          })
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  if (eligible.isEmpty) {
    return const ScheduleDemandResult(
      score: 0,
      label: 'Low',
      occupancyPoints: 0,
      continuousLoadPoints: 0,
      breakQualityPoints: 0,
      fragmentationPoints: 0,
      occupiedMinutes: 0,
      unscheduledMinutes: 480,
    );
  }

  final occupiedBlocks = _mergeBlocks(eligible, maximumGapMinutes: 0);
  final occupiedMinutes = occupiedBlocks.fold<int>(
    0,
    (sum, block) => sum + block.end.difference(block.start).inMinutes,
  );
  final occupancyPoints = (occupiedMinutes / 480).clamp(0, 1).toDouble() * 35;
  final unscheduledMinutes = math.max(0, 480 - occupiedMinutes);

  final continuousBlocks = _mergeBlocks(eligible, maximumGapMinutes: 9);
  final longestContinuousMinutes = continuousBlocks.fold<int>(
    0,
    (longest, block) =>
        math.max(longest, block.end.difference(block.start).inMinutes),
  );
  final continuousLoadPoints =
      (longestContinuousMinutes / 120).clamp(0, 1).toDouble() * 25;

  final gapPressures = <double>[];
  var chainEnd = eligible.first.end;
  for (final event in eligible.skip(1)) {
    final gapMinutes = event.start.difference(chainEnd).inMinutes;
    gapPressures.add(_breakPressure(gapMinutes));
    if (event.end.isAfter(chainEnd)) chainEnd = event.end;
  }
  final breakQualityPoints = gapPressures.isEmpty
      ? 0.0
      : gapPressures.reduce((a, b) => a + b) / gapPressures.length * 25;

  final contextSwitches = math.max(0, eligible.length - 1);
  final fragmentationPoints = (1 - math.exp(-contextSwitches / 3)) * 15;
  final score =
      (occupancyPoints +
              continuousLoadPoints +
              breakQualityPoints +
              fragmentationPoints)
          .round()
          .clamp(0, 100);

  return ScheduleDemandResult(
    score: score,
    label: score >= 65
        ? 'High'
        : score >= 35
        ? 'Moderate'
        : 'Low',
    occupancyPoints: occupancyPoints,
    continuousLoadPoints: continuousLoadPoints,
    breakQualityPoints: breakQualityPoints,
    fragmentationPoints: fragmentationPoints,
    occupiedMinutes: occupiedMinutes,
    unscheduledMinutes: unscheduledMinutes,
  );
}

double _breakPressure(int gapMinutes) {
  if (gapMinutes < 10) return 1;
  if (gapMinutes >= 30) return 0;
  return (30 - gapMinutes) / 20;
}

List<_ScheduleBlock> _mergeBlocks(
  List<_ScheduleBlock> events, {
  required int maximumGapMinutes,
}) {
  final blocks = <_ScheduleBlock>[];
  var start = events.first.start;
  var end = events.first.end;
  for (final event in events.skip(1)) {
    final gap = event.start.difference(end).inMinutes;
    if (gap <= maximumGapMinutes) {
      if (event.end.isAfter(end)) end = event.end;
      continue;
    }
    blocks.add(_ScheduleBlock(start, end));
    start = event.start;
    end = event.end;
  }
  blocks.add(_ScheduleBlock(start, end));
  return blocks;
}

class _ScheduleBlock {
  const _ScheduleBlock(this.start, this.end);

  final DateTime start;
  final DateTime end;
}
