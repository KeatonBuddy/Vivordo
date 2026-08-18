enum VivordoSleepStage { unspecified, awake, core, deep, rem }

class SleepInterval {
  const SleepInterval({
    required this.stage,
    required this.start,
    required this.end,
  });

  final VivordoSleepStage stage;
  final DateTime start;
  final DateTime end;
}

class SleepDaySummary {
  const SleepDaySummary({
    required this.date,
    required this.totalAsleepMinutes,
    required this.stageMinutes,
    required this.bedtime,
    required this.wakeTime,
    required this.asleepIntervals,
  });

  /// Local calendar day on which the sleep session ended.
  final DateTime date;
  final double totalAsleepMinutes;
  final Map<String, double> stageMinutes;
  final DateTime bedtime;
  final DateTime wakeTime;
  final List<SleepInterval> asleepIntervals;
}

/// Converts Apple Health sleep intervals into one summary per wake-up day.
///
/// HealthKit can return the same period from multiple sources (for example an
/// Apple Watch plus a third-party sleep app), and a staged night naturally
/// crosses midnight. Intervals are therefore clustered into sleep sessions,
/// assigned to the day the session ends, and unioned before durations are
/// calculated. This prevents overlap from inflating either total sleep or an
/// individual stage.
List<SleepDaySummary> summarizeSleepByWakeDay(
  Iterable<SleepInterval> input, {
  Duration sessionGap = const Duration(hours: 4),
}) {
  final intervals =
      input.where((interval) => interval.end.isAfter(interval.start)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  if (intervals.isEmpty) return const [];

  final sessions = <List<SleepInterval>>[];
  var current = <SleepInterval>[];
  DateTime? currentEnd;
  for (final interval in intervals) {
    if (currentEnd != null &&
        interval.start.difference(currentEnd) > sessionGap) {
      sessions.add(current);
      current = <SleepInterval>[];
      currentEnd = null;
    }
    current.add(interval);
    if (currentEnd == null || interval.end.isAfter(currentEnd)) {
      currentEnd = interval.end;
    }
  }
  if (current.isNotEmpty) sessions.add(current);

  final byWakeDay = <DateTime, List<SleepInterval>>{};
  for (final session in sessions) {
    final sessionEnd = session
        .map((interval) => interval.end)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final wakeDay = DateTime(sessionEnd.year, sessionEnd.month, sessionEnd.day);
    byWakeDay.putIfAbsent(wakeDay, () => []).addAll(session);
  }

  final summaries = <SleepDaySummary>[];
  for (final entry in byWakeDay.entries) {
    final all = entry.value;
    final stagedAsleep = all.where(
      (interval) =>
          interval.stage == VivordoSleepStage.core ||
          interval.stage == VivordoSleepStage.deep ||
          interval.stage == VivordoSleepStage.rem,
    );
    final stagedAsleepList = stagedAsleep.toList(growable: false);
    final asleep = _mergeIntervals(
      stagedAsleepList.isNotEmpty
          ? stagedAsleepList
          : all.where(
              (interval) => interval.stage == VivordoSleepStage.unspecified,
            ),
    );
    if (asleep.isEmpty) continue;

    final stages = <String, double>{};
    for (final mapping in const {
      VivordoSleepStage.awake: 'awake',
      VivordoSleepStage.rem: 'rem',
      VivordoSleepStage.core: 'core',
      VivordoSleepStage.deep: 'deep',
    }.entries) {
      final minutes = _durationMinutes(
        _mergeIntervals(all.where((interval) => interval.stage == mapping.key)),
      );
      if (minutes > 0) stages[mapping.value] = minutes;
    }

    summaries.add(
      SleepDaySummary(
        date: entry.key,
        totalAsleepMinutes: _durationMinutes(asleep),
        stageMinutes: stages,
        bedtime: asleep.first.start,
        wakeTime: asleep.last.end,
        asleepIntervals: asleep,
      ),
    );
  }

  summaries.sort((a, b) => a.date.compareTo(b.date));
  return summaries;
}

List<SleepInterval> _mergeIntervals(Iterable<SleepInterval> input) {
  final sorted = input.toList()..sort((a, b) => a.start.compareTo(b.start));
  if (sorted.isEmpty) return const [];

  final merged = <SleepInterval>[];
  var start = sorted.first.start;
  var end = sorted.first.end;
  final stage = sorted.first.stage;
  for (final interval in sorted.skip(1)) {
    if (!interval.start.isAfter(end)) {
      if (interval.end.isAfter(end)) end = interval.end;
      continue;
    }
    merged.add(SleepInterval(stage: stage, start: start, end: end));
    start = interval.start;
    end = interval.end;
  }
  merged.add(SleepInterval(stage: stage, start: start, end: end));
  return merged;
}

double _durationMinutes(Iterable<SleepInterval> intervals) => intervals.fold(
  0,
  (total, interval) =>
      total + interval.end.difference(interval.start).inMilliseconds / 60000,
);
