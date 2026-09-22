import 'dart:math' as math;
import 'daily_outlook_score.dart';

class BriefCommitment {
  const BriefCommitment(this.key, this.title, this.start, this.end);
  final String key, title;
  final DateTime start, end;
}

class BriefPriority {
  const BriefPriority({
    required this.id,
    this.plannedDay,
    this.start,
    this.minutes,
    this.effort,
    this.eventKey,
    this.completed = false,
  });
  final String id;
  final DateTime? plannedDay, start;
  final int? minutes;
  final String? effort, eventKey;
  final bool completed;
}

class BriefPlan {
  const BriefPlan(
    this.score,
    this.observation,
    this.missingEstimates,
    this.flexibleMinutes,
  );
  final int score, missingEstimates, flexibleMinutes;
  final String observation;
}

bool sameBriefDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Remaining load: flexible work changes occupancy only, never gap pressure.
/// Effort multipliers are product heuristics, not physiological stress estimates.
BriefPlan analyzeBriefPlan(
  DateTime now,
  List<BriefCommitment> events,
  List<BriefPriority> priorities, {
  int startHour = 9,
  int endHour = 17,
}) {
  final end = DateTime(now.year, now.month, now.day + 1);
  final blocks = events
      .where((e) => e.end.isAfter(now) && e.start.isBefore(end))
      .map(
        (e) => BriefCommitment(
          e.key,
          e.title,
          e.start.isBefore(now) ? now : e.start,
          e.end.isAfter(end) ? end : e.end,
        ),
      )
      .toList();
  final keys = events.map((e) => e.key).toSet();
  var missing = 0;
  var flexible = 0;
  var effortMinutes = 0;
  for (final p in priorities) {
    if (p.completed || (p.eventKey != null && keys.contains(p.eventKey))) {
      continue;
    }
    if (p.start != null
        ? !sameBriefDay(p.start!, now)
        : !(p.plannedDay != null && sameBriefDay(p.plannedDay!, now))) {
      continue;
    }
    // A linked event missing from this snapshot must not be guessed into a slot.
    if (p.eventKey != null) {
      missing++;
      continue;
    }
    final minutes = p.minutes;
    if (minutes == null || minutes <= 0 || minutes > 1440) {
      missing++;
      continue;
    }
    final factor = p.effort == 'demanding'
        ? 1.2
        : p.effort == 'light'
        ? .8
        : 1.0;
    if (p.start == null) {
      flexible += minutes;
      effortMinutes += (minutes * (factor - 1)).round();
    } else {
      final finish = p.start!.add(Duration(minutes: minutes));
      if (finish.isAfter(now)) {
        final remaining = finish
            .difference(p.start!.isBefore(now) ? now : p.start!)
            .inMinutes;
        effortMinutes += (remaining * (factor - 1)).round();
        blocks.add(
          BriefCommitment(
            p.id,
            'Priority ${p.id}',
            p.start!.isBefore(now) ? now : p.start!,
            finish,
          ),
        );
      } else {
        // Overdue unfinished work still remains, but does not invent a future slot.
        flexible += minutes;
        effortMinutes += (minutes * (factor - 1)).round();
      }
    }
  }
  blocks.sort((a, b) => a.start.compareTo(b.start));
  final demand = calculateScheduleDemand(
    events: blocks.map(
      (e) => DailyScheduleEvent(title: e.title, start: e.start, end: e.end),
    ),
    dayStart: now,
    dayEnd: end,
  );
  final score =
      (demand.score -
              demand.occupancyPoints +
              ((demand.occupiedMinutes + flexible + effortMinutes) / 480).clamp(
                    0,
                    1,
                  ) *
                  35)
          .round()
          .clamp(0, 100);
  final windowStart = DateTime(now.year, now.month, now.day, startHour);
  final windowEnd = DateTime(now.year, now.month, now.day, endHour);
  var cursor = now.isAfter(windowStart) ? now : windowStart;
  DateTime? opening;
  for (final block in blocks) {
    if (!block.start.isBefore(windowEnd)) break;
    if (block.start.difference(cursor).inMinutes >= 30) {
      opening = cursor;
      break;
    }
    if (block.end.isAfter(cursor)) cursor = block.end;
  }
  if (opening == null && windowEnd.difference(cursor).inMinutes >= 30) {
    opening = cursor;
  }
  var occupiedAfternoon = 0;
  var afternoonEnd = DateTime(now.year, now.month, now.day, 12);
  if (now.isAfter(afternoonEnd)) afternoonEnd = now;
  for (final block in blocks) {
    final s = block.start.isAfter(afternoonEnd) ? block.start : afternoonEnd;
    final e = block.end.isBefore(windowEnd) ? block.end : windowEnd;
    if (e.isAfter(s)) occupiedAfternoon += e.difference(s).inMinutes;
    if (e.isAfter(afternoonEnd)) afternoonEnd = e;
  }
  var chain = 0;
  var longestChain = 0;
  DateTime? chainEnd;
  for (final block in blocks) {
    chain = chainEnd != null && block.start.difference(chainEnd).inMinutes < 10
        ? chain + 1
        : 1;
    longestChain = math.max(longestChain, chain);
    if (chainEnd == null || block.end.isAfter(chainEnd)) chainEnd = block.end;
  }
  final observation = longestChain >= 3
      ? '$longestChain consecutive or overlapping commitments ahead.'
      : occupiedAfternoon >= 180
      ? 'Busy afternoon ahead.'
      : blocks.isEmpty
      ? 'No timed commitments remain today.'
      : '${blocks.length} timed commitments remain today.';
  final gap = opening == null
      ? 'No 30-minute opening found in your 9–5 planning window.'
      : opening.isAtSameMomentAs(now)
      ? 'Your plan has a 30-minute opening now.'
      : 'Your next 30-minute opening starts at ${_time(opening)}.';
  final workload = flexible > 0
      ? ' You also have $flexible minutes of flexible priority work.'
      : '';
  return BriefPlan(score, '$observation $gap$workload', missing, flexible);
}

String _time(DateTime value) =>
    '${value.hour % 12 == 0 ? 12 : value.hour % 12}:${value.minute.toString().padLeft(2, "0")} ${value.hour < 12 ? "AM" : "PM"}';

double? sleepBaseline(Iterable<double> nights) {
  final values = nights.where((n) => n.isFinite && n > 0 && n <= 24).toList()
    ..sort();
  if (values.length < 7) return null;
  final m = values.length ~/ 2;
  return values.length.isOdd ? values[m] : (values[m - 1] + values[m]) / 2;
}

String sleepComparison(double? today, double? baseline) {
  if (today == null || !today.isFinite || today <= 0) {
    return 'Sleep data is unavailable.';
  }
  if (baseline == null) return 'Building your usual sleep range.';
  final difference = ((today - baseline) * 60).round();
  if (difference.abs() < 45) {
    return 'Your sleep was close to your recent usual.';
  }
  final minutes = math.min(difference.abs(), 1440);
  return 'You slept ${minutes ~/ 60}h ${minutes % 60}m ${difference < 0 ? "less" : "more"} than your recent usual.';
}
