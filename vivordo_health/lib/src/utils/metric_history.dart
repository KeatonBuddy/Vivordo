import 'package:collection/collection.dart';

/// A week or month of one metric.
typedef MetricPeriod = ({
  DateTime start,
  double average,
  double total,
  int days,
  int goalDays,
});

/// One metric's whole history (steps, active calories, exercise minutes) by
/// day, week and month, for the 6M and Y views. Days without data, or with 0,
/// are left out, never averaged in as 0.
class MetricHistory {
  MetricHistory(Map<String, num?> byDay, {required this.goal})
    : days = {
        for (final MapEntry(:key, :value) in byDay.entries)
          if (value != null && value > 0)
            if (DateTime.tryParse(key) case final date?)
              DateTime(date.year, date.month, date.day): value.toDouble(),
      };

  final Map<DateTime, double> days;
  final num goal;

  /// The first day with data.
  DateTime? get first => days.keys.minOrNull;

  /// Every month from [from]'s through [now]'s, oldest first, empty ones
  /// included.
  List<MetricPeriod> months(DateTime from, DateTime now) => [
    for (
      var m = DateTime(from.year, from.month);
      !m.isAfter(now);
      m = DateTime(m.year, m.month + 1)
    )
      _period(m, DateTime(m.year, m.month + 1)),
  ];

  /// Every Monday-to-Sunday week from [from]'s through [now]'s, oldest first.
  List<MetricPeriod> weeks(DateTime from, DateTime now) => [
    for (
      var w = DateTime(from.year, from.month, from.day - from.weekday + 1);
      !w.isAfter(now);
      w = DateTime(w.year, w.month, w.day + 7)
    )
      _period(w, DateTime(w.year, w.month, w.day + 7)),
  ];

  /// The days from [from] up to (not including) [to].
  List<double> between(DateTime from, DateTime to) => [
    for (final MapEntry(:key, :value) in days.entries)
      if (!key.isBefore(from) && key.isBefore(to)) value,
  ];

  MetricPeriod _period(DateTime start, DateTime end) {
    final values = between(start, end);
    final total = values.sum;
    return (
      start: start,
      average: values.isEmpty ? 0 : total / values.length,
      total: total,
      days: values.length,
      goalDays: values.where((v) => v >= goal).length,
    );
  }

  /// Days in [month], by day of the month.
  Map<int, double> daysIn(DateTime month) => {
    for (final MapEntry(:key, :value) in days.entries)
      if (key.year == month.year && key.month == month.month) key.day: value,
  };

  /// The highest day from [from] on.
  MapEntry<DateTime, double>? bestSince(DateTime from) => days.entries
      .where((e) => !e.key.isBefore(from))
      .fold<MapEntry<DateTime, double>?>(
        null,
        (best, day) => best == null || day.value > best.value ? day : best,
      );
}
