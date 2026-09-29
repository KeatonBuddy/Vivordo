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
  const BriefPlan(this.score, this.missingEstimates, this.flexibleMinutes);
  final int score, missingEstimates, flexibleMinutes;
}

bool sameBriefDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Remaining load: flexible work changes occupancy only, never gap pressure.
/// Effort multipliers are product heuristics, not physiological stress estimates.
BriefPlan analyzeBriefPlan(
  DateTime now,
  List<BriefCommitment> events,
  List<BriefPriority> priorities,
) {
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
  return BriefPlan(score, missing, flexible);
}

double? sleepBaseline(Iterable<double> nights) {
  final values = nights.where((n) => n.isFinite && n > 0 && n <= 24).toList()
    ..sort();
  if (values.length < 7) return null;
  final m = values.length ~/ 2;
  return values.length.isOdd ? values[m] : (values[m - 1] + values[m]) / 2;
}

String sleepComparison(double? today, double? baseline) {
  if (today == null || !today.isFinite || today <= 0) {
    return 'Sleep data unavailable.';
  }
  if (baseline == null) return 'Still learning your usual sleep.';
  final difference = ((today - baseline) * 60).round();
  if (difference.abs() < 45) return 'Slept about your usual.';
  final minutes = math.min(difference.abs(), 1440);
  final h = minutes ~/ 60, m = minutes % 60;
  final amount = h == 0
      ? '$m min'
      : m == 0
      ? '${h}h'
      : '${h}h ${m}m';
  return 'Slept $amount ${difference < 0 ? "less" : "more"} than usual.';
}

/// What is left today, e.g. "3 events and 2 priorities left."
String remainingToday(int events, int priorities) {
  if (events == 0 && priorities == 0) return 'Nothing else planned today.';
  String count(int n, String one, String many) =>
      '${n == 0 ? 'No' : n} ${n == 1 ? one : many}';
  return '${count(events, 'event', 'events')} and '
      '${count(priorities, 'priority', 'priorities')} left.';
}
