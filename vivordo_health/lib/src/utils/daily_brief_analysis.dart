import 'dart:math' as math;

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

bool sameBriefDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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
