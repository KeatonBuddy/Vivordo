import 'heart_rate_history.dart';

/// How your heart rate during a calendar event compared with your usual at
/// that time of day. Steady is the common case and isn't shown.
enum BodyReactionLevel { calm, steady, up, high }

class BodyReaction {
  const BodyReaction({
    required this.level,
    required this.median,
    required this.peak,
    required this.usualLow,
    required this.usualHigh,
    required this.usualMedian,
    required this.readings,
    required this.samples,
  });

  final BodyReactionLevel level;

  /// Heart rate during the event: median and 90th percentile.
  final double median, peak;

  /// Your usual at that time of day: the middle half, and its median.
  final double usualLow, usualHigh, usualMedian;

  /// Readings during the event.
  final int readings;

  /// The event's readings, for the chart.
  final List<HeartRateHistoryReading> samples;

  double get delta => median - usualMedian;
}

/// Words in a title that mark exercise, which isn't judged: a raised heart
/// rate there is the point.
final _exercise = RegExp(
  r'\b(workout|gym|run|running|jog|walk|hike|yoga|pilates|swim|cycle|'
  r'cycling|bike|ride|spin|training|exercise|sport|climb|tennis|soccer|'
  r'football|basketball|crossfit|lift|lifting)\b',
  caseSensitive: false,
);

bool looksLikeExercise(String title) => _exercise.hasMatch(title);

const _minEventReadings = 5;
const _minUsualReadings = 20;
const _minUsualDays = 3;

/// Your heart rate during [start]–[end] (from [today]'s readings) against
/// your usual around that time of day on earlier days ([history]). Null
/// when there isn't enough data to say: then nothing is shown.
///
/// Usual: readings within an hour either side of the event's time on earlier
/// days, with the top tenth dropped (that's mostly movement). Up: the
/// event's median clearly above your usual spread and 7+ bpm up. High: far
/// above it and 15+ bpm up (or a peak 25 over your usual and 10+ up). Calm:
/// clearly below your usual and 4+ bpm down.
BodyReaction? bodyReactionFor({
  required DateTime start,
  required DateTime end,
  required List<HeartRateHistoryReading> today,
  required List<HeartRateHistoryReading> history,
}) {
  if (!end.isAfter(start)) return null;
  final during = [
    for (final r in today)
      if (!r.timestamp.isBefore(start) && r.timestamp.isBefore(end)) r,
  ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (during.length < _minEventReadings) return null;

  int minuteOfDay(DateTime t) => t.hour * 60 + t.minute;
  final from = minuteOfDay(start) - 60;
  final to = minuteOfDay(end) + 60;
  final days = <String>{};
  final usual = <double>[];
  for (final r in history) {
    final t = r.timestamp;
    if (!t.isBefore(DateTime(start.year, start.month, start.day))) continue;
    final m = minuteOfDay(t);
    if (m < from || m > to) continue;
    usual.add(r.bpm);
    days.add('${t.year}-${t.month}-${t.day}');
  }
  if (usual.length < _minUsualReadings || days.length < _minUsualDays) {
    return null;
  }
  usual.sort();
  final trimmed = usual.sublist(0, (usual.length * .9).ceil());
  final usualLow = _quantile(trimmed, .25);
  final usualHigh = _quantile(trimmed, .75);
  final usualMedian = _quantile(trimmed, .5);
  final spread = ((usualHigh - usualLow) / 1.35).clamp(3, double.infinity);

  final bpms = [for (final r in during) r.bpm]..sort();
  final median = _quantile(bpms, .5);
  final peak = _quantile(bpms, .9);
  final delta = median - usualMedian;
  final z = delta / spread;

  // Both a clear step out of your usual spread and a real bpm change, so
  // a narrow usual range doesn't turn small wobbles into reactions.
  final level =
      (z >= 2.5 && delta >= 15) || (peak >= usualHigh + 25 && delta >= 10)
      ? BodyReactionLevel.high
      : z >= 1.25 && delta >= 7
      ? BodyReactionLevel.up
      : z <= -.75 && delta <= -4
      ? BodyReactionLevel.calm
      : BodyReactionLevel.steady;
  return BodyReaction(
    level: level,
    median: median,
    peak: peak,
    usualLow: usualLow,
    usualHigh: usualHigh,
    usualMedian: usualMedian,
    readings: during.length,
    samples: during,
  );
}

/// Linear-interpolated quantile of an ascending list.
double _quantile(List<double> sorted, double q) {
  final at = (sorted.length - 1) * q;
  final lo = at.floor(), hi = at.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (at - lo);
}

/// A short stable hash (FNV-1a, hex) so per-event history can be grouped by
/// event or series without storing its title or calendar ID.
String reactionKey(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
