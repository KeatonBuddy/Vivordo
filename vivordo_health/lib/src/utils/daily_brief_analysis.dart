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

/// Last night against the sleep need: Capacity's, the same one Home and
/// the energy forecast use (docs/scores.md §4). [need] is null while it's
/// still the 8 h placeholder, so a plain duration is shown instead.
/// Without [tracksSleep] (no sleep in the last weeks) nothing is said, rather
/// than "unavailable" every day. With [inBed] the hours are time in bed (no
/// wearable that night), so they're never called sleep.
String sleepComparison(
  double? today, {
  double? need,
  bool tracksSleep = true,
  bool inBed = false,
}) {
  String duration(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    return h == 0
        ? '$m min'
        : m == 0
        ? '${h}h'
        : '${h}h ${m}m';
  }

  if (today == null || !today.isFinite || today <= 0) {
    return tracksSleep ? "Last night's sleep hasn't synced yet." : '';
  }
  final hours = duration((today * 60).round());
  if (need == null) return inBed ? '$hours in bed.' : 'Slept $hours.';
  final difference = ((today - need) * 60).round();
  if (difference.abs() <= 15) {
    return inBed ? '$hours in bed, about your need.' : 'Slept about your need.';
  }
  final amount = duration(math.min(difference.abs(), 1440));
  final side = difference < 0 ? 'under' : 'over';
  return inBed
      ? '$hours in bed, $amount $side your need.'
      : 'Slept $amount $side your need.';
}

/// What is left today, e.g. "3 events and 2 priorities left."
String remainingToday(int events, int priorities) {
  if (events == 0 && priorities == 0) return 'Nothing else planned today.';
  String count(int n, String one, String many, {bool first = false}) =>
      '${n == 0 ? (first ? 'No' : 'no') : n} ${n == 1 ? one : many}';
  return '${count(events, 'event', 'events', first: true)} and '
      '${count(priorities, 'priority', 'priorities')} left.';
}
