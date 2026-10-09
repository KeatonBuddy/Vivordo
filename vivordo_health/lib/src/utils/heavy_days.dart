/// Heavy meeting days (4+ hours in events) against your other weekdays:
/// that night's sleep and the next morning's Capacity, from scores_daily
/// (effort.busyMinutes; the next day's capacity.sleepHours and score). A
/// wellness estimate from a few weeks of your own days.
class HeavyDays {
  const HeavyDays({
    required this.heavy,
    required this.other,
    required this.sleepMinutes,
    required this.capacity,
  });

  /// Weekdays counted each way.
  final int heavy;
  final int other;

  /// Heavy minus other (medians); null without enough nights or mornings.
  final double? sleepMinutes;
  final double? capacity;

  bool get ready => sleepMinutes != null || capacity != null;
}

const heavyBusyMinutes = 240;
const _minHeavy = 6;
const _minOther = 10;

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// [scores] is scores_daily by day key. Capacity is compared only within
/// one formula version (the latest seen), since versions score differently.
HeavyDays heavyDaysFrom(Map<String, Map<String, dynamic>> scores) {
  String next(String key) {
    final d = DateTime.parse(key);
    final n = DateTime(d.year, d.month, d.day + 1);
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  num? at(Map<String, dynamic>? doc, String map, String field) =>
      (doc?[map] as Map?)?[field] as num?;
  final version = scores.values
      .map((d) => at(d, 'capacity', 'version'))
      .whereType<num>()
      .fold<num?>(null, (a, b) => a == null || b > a ? b : a);

  final sleep = (heavy: <double>[], other: <double>[]);
  final capacity = (heavy: <double>[], other: <double>[]);
  var heavyDays = 0, otherDays = 0;
  for (final e in scores.entries) {
    final day = DateTime.tryParse(e.key);
    final busy = at(e.value, 'effort', 'busyMinutes');
    if (day == null || busy == null || day.weekday > 5) continue;
    final isHeavy = busy >= heavyBusyMinutes;
    isHeavy ? heavyDays++ : otherDays++;
    final after = scores[next(e.key)];
    if (at(after, 'capacity', 'sleepHours') case final h?) {
      (isHeavy ? sleep.heavy : sleep.other).add(h * 60);
    }
    if (at(after, 'capacity', 'score') case final s?
        when at(after, 'capacity', 'version') == version) {
      (isHeavy ? capacity.heavy : capacity.other).add(s.toDouble());
    }
  }
  double? diff(({List<double> heavy, List<double> other}) v) =>
      v.heavy.length >= _minHeavy && v.other.length >= _minOther
      ? _median(v.heavy) - _median(v.other)
      : null;
  return HeavyDays(
    heavy: heavyDays,
    other: otherDays,
    sleepMinutes: diff(sleep),
    capacity: diff(capacity),
  );
}
