import 'package:intl/intl.dart';

/// One day of the imported history, from its `scores_daily` Capacity and
/// Effort (docs/scores.md §4): last night's sleep, the overnight body and
/// the day's load.
typedef HistoryDay = ({
  DateTime day,
  double? capacity,
  double? sleepHours,
  double? sleepNeed,
  double? hrv,
  double? restingHr,
  String? restingHrKind,
  double? effort,
  double? afterHoursMinutes,
});

/// What onboarding's "Here's what we found" shows: one pattern from the
/// history, when there's one strong enough, and the person's usuals.
typedef HistoryFindings = ({
  String? insight,
  String? basis,
  List<({String value, String label})> usuals,
});

/// [days] as the strongest finding and the usuals, in this order: sleep
/// against the next morning's HRV, then resting heart rate (never against
/// Capacity, which is mostly sleep already), the heaviest weekday, nights
/// after hours, then a change in resting heart rate. Each needs enough days
/// to mean something; with none, [HistoryFindings.insight] is null.
/// [numbers] off leaves Capacity out, as words mode does.
HistoryFindings historyFindings(
  List<HistoryDay> days, {
  required DateTime today,
  bool numbers = true,
}) {
  final sorted = [...days]..sort((a, b) => a.day.compareTo(b.day));
  final slept = [
    for (final d in sorted)
      if (d.sleepHours case final h? when h > 0) (day: d, hours: h),
  ];
  final need = _median([for (final s in slept) s.day.sleepNeed ?? 7.5]);
  final needLabel = need == null ? null : _hours(need);

  String? insight;
  String? basis;
  // Sleep against the overnight body: nights at or over the need against
  // nights under it, 3 of each at least.
  ({double enough, double short})? split(double? Function(HistoryDay) read) {
    final enough = <double>[], short = <double>[];
    for (final s in slept) {
      final value = read(s.day);
      if (value == null) continue;
      (s.hours >= (s.day.sleepNeed ?? 7.5) ? enough : short).add(value);
    }
    if (enough.length < 3 || short.length < 3) return null;
    return (enough: _median(enough)!, short: _median(short)!);
  }

  if (split((d) => d.hrv) case final hrv?
      when hrv.short > 0 && hrv.enough / hrv.short - 1 >= .05) {
    insight =
        'After $needLabel or more of sleep, your HRV the next morning was '
        '${((hrv.enough / hrv.short - 1) * 100).round()}% higher.';
    basis = 'Based on ${slept.length} nights.';
  } else if (split((d) => d.restingHrKind == 'sleeping' ? null : d.restingHr)
      case final rhr? when rhr.short - rhr.enough >= 2) {
    insight =
        'After $needLabel or more of sleep, your resting heart rate the next '
        'morning was ${(rhr.short - rhr.enough).round()} bpm lower.';
    basis = 'Based on ${slept.length} nights.';
  }

  // The heaviest weekday: its median Effort well over the usual day's, with
  // 3 of every weekday at least.
  final byWeekday = <int, List<double>>{};
  for (final d in sorted) {
    if (d.effort case final e?) (byWeekday[d.day.weekday] ??= []).add(e);
  }
  String? heaviest;
  final allEffort = [for (final d in sorted) ?d.effort];
  if (byWeekday.length == 7 && byWeekday.values.every((v) => v.length >= 3)) {
    final usual = _median(allEffort)!;
    final top = byWeekday.entries
        .map((e) => (weekday: e.key, median: _median(e.value)!))
        .reduce((a, b) => a.median >= b.median ? a : b);
    if (top.median >= usual * 1.25 && top.median - usual >= 8) {
      heaviest = DateFormat('EEEE').format(
        DateTime(2026, 10, 4 + top.weekday % 7), // Oct 4, 2026 is a Sunday
      );
    }
  }
  if (insight == null && heaviest != null) {
    insight = '${heaviest}s are your heaviest day.';
    basis = 'From your calendar over the last ${allEffort.length} days.';
  }

  // Nights after hours in the last 28 days with a day record.
  final recent = [
    for (final d in sorted)
      if (d.afterHoursMinutes != null && today.difference(d.day).inDays < 28)
        d.afterHoursMinutes!,
  ];
  final lateDays = recent.where((m) => m > 0).length;
  if (insight == null && lateDays >= 5) {
    insight =
        'You worked after hours on $lateDays of the last ${recent.length} '
        'days.';
    basis = 'From your calendar.';
  }

  // Resting heart rate now against the start of the history.
  final resting = [
    for (final d in sorted)
      if (d.restingHrKind != 'sleeping' && d.restingHr != null) d,
  ];
  if (insight == null && resting.length >= 10) {
    final early = [
      for (final d in resting)
        if (today.difference(d.day).inDays >= 60) d.restingHr!,
    ];
    final late = [
      for (final d in resting)
        if (today.difference(d.day).inDays < 14) d.restingHr!,
    ];
    if (early.length >= 5 && late.length >= 5) {
      final change = (_median(late)! - _median(early)!).round();
      if (change.abs() >= 2) {
        final month = DateFormat(
          'MMMM',
        ).format(today.subtract(const Duration(days: 75)));
        insight =
            'Your resting heart rate is ${change.abs()} bpm '
            '${change < 0 ? 'lower' : 'higher'} than in $month.';
        basis = 'From ${resting.length} days of readings.';
      }
    }
  }

  final usualSleep = _median([for (final s in slept) s.hours]);
  final usualCapacity = _median([for (final d in sorted) ?d.capacity]);
  final usualResting = _median([for (final d in resting) d.restingHr!]);
  return (
    insight: insight,
    basis: basis,
    usuals: [
      if (usualSleep != null)
        (value: _duration(usualSleep), label: 'sleep a night'),
      if (numbers && usualCapacity != null)
        (value: '${usualCapacity.round()}', label: 'Capacity'),
      if (usualResting != null)
        (value: '${usualResting.round()} bpm', label: 'resting heart rate'),
      if (heaviest != null)
        (value: heaviest.substring(0, 3), label: 'heaviest day')
      else if (recent.length >= 14 && lateDays > 0)
        (value: '$lateDays of ${recent.length}', label: 'days after hours'),
    ],
  );
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final s = [...values]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/// 7.5 → "7½ hours", to the nearest half hour.
String _hours(double hours) {
  final halves = (hours * 2).round();
  return '${halves ~/ 2}${halves.isOdd ? '½' : ''} hours';
}

/// 7.07 → "7h 04m".
String _duration(double hours) {
  final minutes = (hours * 60).round();
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}
