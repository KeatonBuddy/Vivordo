import 'package:flutter/material.dart';

/// The one-line insight on each metric detail screen, comparing the person
/// with their own usual rather than population cut-offs.
///
/// "Usual" is a median of the person's own recent days. Week and Month
/// compare whole days only (today is still in progress) with the same
/// number of days before them.

enum InsightTone { good, concern, neutral }

class DetailInsight {
  const DetailInsight(this.text, [this.tone = InsightTone.neutral]);

  final String text;
  final InsightTone tone;
}

/// The icon and colour a screen's insight card uses for [tone].
(IconData, Color) insightStyle(InsightTone tone) => switch (tone) {
  InsightTone.good => (Icons.trending_up_rounded, const Color(0xFF20B26B)),
  InsightTone.concern => (Icons.info_outline_rounded, const Color(0xFFE08600)),
  InsightTone.neutral => (Icons.insights_rounded, const Color(0xFF6B55F5)),
};

/// Day-keyed values (date only). Days with no data are left out, never 0.
typedef DayValues = Map<DateTime, double>;

/// Day-keyed totals per local hour (24 values), from `byHour`.
typedef DayHours = Map<DateTime, List<double>>;

/// Days of hourly history before "usual for this time of day" shows.
const usualByNowMinDays = 7;

/// The median of the 28 days before [now] of the total reached by the same
/// time of day. Null with fewer than [usualByNowMinDays] days.
double? usualByNow(DayHours hours, DateTime now) {
  final day = insightDay(now);
  final totals = [
    for (var i = 1; i < 29; i++)
      if (hours[DateTime(day.year, day.month, day.day - i)] case final h?
          when h.length == 24)
        h.take(now.hour).fold<double>(0, (a, b) => a + b) +
            h[now.hour] * now.minute / 60,
  ];
  return totals.length >= usualByNowMinDays ? median(totals) : null;
}

DateTime insightDay(DateTime d) => DateTime(d.year, d.month, d.day);

// ── Steps and active calories ────────────────────────────────────────────────

/// Steps or active calories against the daily [goal] and the person's usual.
/// [unit] is "steps" or "kcal"; [fewer] is the word for a drop.
DetailInsight countInsight({
  required DayValues values,
  required DateTime today,
  required int rangeDays,
  required double goal,
  required String unit,
  String fewer = 'fewer',
  DayHours hours = const {},
}) {
  final day = insightDay(today);
  if (rangeDays == 1) {
    final now = values[day] ?? 0;
    final byNow = usualByNow(hours, today);
    if (byNow != null && byNow > 0) {
      final difference = now - byNow;
      final pace = (difference / byNow).abs() < .1
          ? 'about your usual for this time of day'
          : '${formatCount(difference.abs())} ${difference > 0 ? 'above' : 'below'} '
                'your usual for this time of day';
      final goalPart = goal <= 0
          ? ''
          : now >= goal
          ? ' You\'ve reached your ${formatCount(goal)} goal.'
          : ' ${formatCount(goal - now)} to go for your ${formatCount(goal)} goal.';
      return DetailInsight(
        '${formatCount(now)} $unit so far, $pace.$goalPart',
        goal > 0 && now >= goal || difference / byNow >= .1
            ? InsightTone.good
            : InsightTone.neutral,
      );
    }
    final usual = median(_window(values, day, 1, 29).where((v) => v > 0));
    if (now <= 0) {
      return DetailInsight(
        'No $unit recorded yet today.'
        '${usual == null ? '' : ' Your usual day is ${formatCount(usual)}.'}',
      );
    }
    final goalPart = goal <= 0
        ? ''
        : now >= goal
        ? ' You\'ve reached your ${formatCount(goal)} goal'
        : ' ${formatCount(goal - now)} to go for your ${formatCount(goal)} goal';
    final usualPart = usual != null && now >= usual
        ? '${goalPart.isEmpty ? ' Already' : ', already'} past your usual day of ${formatCount(usual)}.'
        : goalPart.isEmpty
        ? ''
        : '.';
    return DetailInsight(
      '${formatCount(now)} $unit so far.$goalPart$usualPart',
      goal > 0 && now >= goal ? InsightTone.good : InsightTone.neutral,
    );
  }

  final recent = _window(values, day, 1, rangeDays + 1);
  if (recent.length < 3) {
    return DetailInsight(
      'Not enough days of $unit yet to compare. Your trend fills in as days sync.',
    );
  }
  // Medians, so one huge or empty day can't flip the comparison.
  final typical = median(recent)!;
  final before = _window(values, day, rangeDays + 1, 2 * rangeDays + 1);
  final met = goal > 0 ? recent.where((v) => v >= goal).length : null;
  var tone = InsightTone.neutral;
  var compare = '';
  if (before.length >= 3) {
    final previous = median(before)!;
    final difference = typical - previous;
    if (previous > 0 && (difference / previous).abs() >= .1) {
      compare =
          ', ${formatCount(difference.abs())} ${difference > 0 ? 'more' : fewer} '
          'than the $rangeDays days before';
      tone = difference > 0 ? InsightTone.good : InsightTone.concern;
    } else {
      compare = ', about the same as the $rangeDays days before';
    }
  }
  return DetailInsight(
    'A typical day over the last ${recent.length} full days had '
    '${formatCount(typical)} $unit$compare.'
    '${met == null ? '' : ' You reached your goal on $met of them.'}',
    tone,
  );
}

// ── Mood ─────────────────────────────────────────────────────────────────────

class MoodCheckIn {
  const MoodCheckIn(this.at, this.score, [this.label]);

  final DateTime at;
  final double score;
  final String? label;
}

/// The check-in word for a 0–100 mood score (MetricsService scores).
String moodWord(double score) {
  const words = [
    (10, 'Awful'),
    (30, 'Down'),
    (50, 'Okay'),
    (75, 'Good'),
    (95, 'Great'),
  ];
  return words
      .reduce((a, b) => (b.$1 - score).abs() < (a.$1 - score).abs() ? b : a)
      .$2;
}

DetailInsight moodInsight({
  required DayValues values,
  required List<MoodCheckIn> todayCheckIns,
  required DateTime today,
  required int rangeDays,
  required String Function(DateTime) time,
}) {
  final day = insightDay(today);
  final usualValues = _window(values, day, 1, 29);
  final usual = usualValues.length >= 5 ? _mean(usualValues) : null;
  if (rangeDays == 1) {
    if (todayCheckIns.isEmpty) {
      return DetailInsight(
        'No check-in yet today.'
        '${usual == null ? '' : ' Lately you\'ve usually felt ${moodWord(usual)}.'}',
      );
    }
    final last = todayCheckIns.last;
    final count = todayCheckIns.length;
    final opening =
        'You checked in ${last.label ?? moodWord(last.score)} at ${time(last.at)}'
        '${count > 1 ? ' ($count check-ins today)' : ''}';
    if (usual == null) return DetailInsight('$opening.');
    final difference = last.score - usual;
    if (difference >= 15) {
      return DetailInsight(
        '$opening, brighter than your usual ${moodWord(usual)}.',
        InsightTone.good,
      );
    }
    if (difference <= -15) {
      return DetailInsight(
        '$opening, lower than your usual ${moodWord(usual)}.',
        InsightTone.concern,
      );
    }
    return DetailInsight('$opening, about your usual.');
  }

  final recent = _window(values, day, 0, rangeDays);
  if (recent.isEmpty) {
    return const DetailInsight(
      'No check-ins in this period yet. A quick check-in builds your mood trend.',
    );
  }
  final average = _mean(recent);
  final before = _window(values, day, rangeDays, 2 * rangeDays);
  var tone = InsightTone.neutral;
  var compare = '.';
  if (before.length >= 3) {
    final difference = average - _mean(before);
    if (difference >= 10) {
      compare = ', a little brighter than the $rangeDays days before.';
      tone = InsightTone.good;
    } else if (difference <= -10) {
      compare = ', a little lower than the $rangeDays days before.';
      tone = InsightTone.concern;
    } else {
      compare = ', about the same as the $rangeDays days before.';
    }
  }
  return DetailInsight(
    'You checked in on ${recent.length} of $rangeDays days, mostly feeling '
    '${moodWord(average)}$compare',
    tone,
  );
}

// ── Sleep ────────────────────────────────────────────────────────────────────

class SleepNight {
  const SleepNight(this.hours, [this.bedtime, this.wakeTime]);

  final double hours;
  final DateTime? bedtime, wakeTime;
}

/// Sleep hours against the person's [need] (Capacity's, null while it's
/// the 8 h placeholder), and bedtime against their usual (median of the 14
/// nights before). "Usual" is only ever about timing.
DetailInsight sleepInsight({
  required Map<DateTime, SleepNight> nights,
  required DateTime today,
  required int rangeDays,
  double? need,
}) {
  final day = insightDay(today);
  List<SleepNight> between(int from, int to) => [
    for (var i = from; i < to; i++)
      ?nights[DateTime(day.year, day.month, day.day - i)],
  ];
  final bedtimes = [
    for (final n in between(1, 15))
      if (n.bedtime case final b?) _minutesFromNoon(b),
  ];
  final usualBedtime = bedtimes.length >= 5
      ? median(bedtimes.map((m) => m.toDouble()))
      : null;
  // Wake times the same way (minutes after midnight), for lie-ins.
  final wakes = [
    for (final n in between(1, 15))
      if (n.wakeTime case final w?) _minutesOfDay(w),
  ];
  final usualWake = wakes.length >= 5
      ? median(wakes.map((m) => m.toDouble()))
      : null;

  String versusNeed(double hours) {
    if (need == null) return '';
    final difference = ((hours - need) * 60).round();
    if (difference.abs() < 15) return ', about your need';
    return ', ${_duration(difference.abs())} ${difference < 0 ? 'less' : 'more'} '
        'than your need of ${hoursMinutes(need)}';
  }

  if (rangeDays == 1) {
    final night = nights[day];
    if (night == null && nights.isEmpty) {
      return const DetailInsight(
        'No sleep tracked yet. A watch or ring that records sleep adds it.',
      );
    }
    if (night == null) {
      return DetailInsight(
        'Last night\'s sleep hasn\'t synced yet.'
        '${need == null ? '' : ' Your need is ${hoursMinutes(need)}.'}',
      );
    }
    var text =
        '${hoursMinutes(night.hours)} last night${versusNeed(night.hours)}.';
    if (need == null) {
      text =
          '${hoursMinutes(night.hours)} last night. Vivordo learns your sleep need after 2 weeks of nights.';
    }
    if (night.bedtime case final bedtime? when usualBedtime != null) {
      final offset = _minutesFromNoon(bedtime) - usualBedtime.round();
      if (offset.abs() >= 45) {
        text +=
            ' Bedtime was ${_duration(offset.abs())} ${offset > 0 ? 'later' : 'earlier'} than usual.';
      }
    }
    if (night.wakeTime case final wake? when usualWake != null) {
      final offset = _minutesOfDay(wake) - usualWake.round();
      if (offset.abs() >= 45) {
        text +=
            ' You woke ${_duration(offset.abs())} ${offset > 0 ? 'later' : 'earlier'} than usual.';
      }
    }
    final short = need != null && (need - night.hours) * 60 >= 45;
    return DetailInsight(
      text,
      short ? InsightTone.concern : InsightTone.neutral,
    );
  }

  final recent = between(0, rangeDays);
  if (recent.length < 3) {
    return const DetailInsight(
      'Not enough nights in this period to compare yet.',
    );
  }
  final average = _mean(recent.map((n) => n.hours).toList());
  var text =
      'You averaged ${hoursMinutes(average)} a night over '
      '${recent.length} nights${versusNeed(average)}.';
  final timed = [
    for (final n in recent)
      if (n.bedtime case final b?) _minutesFromNoon(b),
  ];
  if (usualBedtime != null && timed.length >= 3) {
    final onTime = timed.where((m) => (m - usualBedtime).abs() <= 60).length;
    text +=
        ' Bedtime was within an hour of usual on $onTime of ${timed.length} nights.';
  }
  final woke = [
    for (final n in recent)
      if (n.wakeTime case final w?) _minutesOfDay(w),
  ];
  if (usualWake != null && woke.length >= 3) {
    final onTime = woke.where((m) => (m - usualWake).abs() <= 60).length;
    text +=
        ' Wake time was within an hour of usual on $onTime of ${woke.length} mornings.';
  }
  final short = need != null && (need - average) * 60 >= 30;
  if (rangeDays == 7) {
    final long = longSleepAverage([
      for (var i = 0; i < 14; i++)
        nights[DateTime(day.year, day.month, day.day - i)]?.hours,
    ], need);
    if (long != null) {
      return DetailInsight(longSleepText(long, need!), InsightTone.concern);
    }
  }
  return DetailInsight(text, short ? InsightTone.concern : InsightTone.neutral);
}

/// A run of long sleep not explained by recovery: [nights] are the last 14
/// nights' hours, last night first (null for a missing night). At least 4
/// of the last 7 at [need] + 1.5 h, and the 7 before averaging no more than
/// 30 minutes under the need (otherwise it's paying back debt). Returns the
/// last 7 nights' average, or null. Only with a settled need.
double? longSleepAverage(List<double?> nights, double? need) {
  if (need == null || nights.length < 14) return null;
  final recent = nights.take(7).whereType<double>().toList();
  final before = nights.skip(7).take(7).whereType<double>().toList();
  if (before.length < 3) return null;
  final long = recent.where((h) => h >= need + 1.5).length;
  if (long < 4 || _mean(before) < need - 0.5) return null;
  return _mean(recent);
}

/// The sentence for [longSleepAverage].
String longSleepText(double average, double need) =>
    'You\'ve slept a lot longer than usual this week: '
    '${hoursMinutes(average)} on average against your need of '
    '${hoursMinutes(need)}. That can be a sign you\'re run down or coming '
    'down with something.';

/// How Sleep detail's summary card sets its bar.
enum SleepNeedTone { met, short, learning }

/// Sleep detail's bar: [hours] (last night, or the period's average)
/// against the person's [need] (Capacity's; null while it's the 8 h
/// placeholder). Without a need, progress towards the 14 [nights] the need
/// takes. Null when there's nothing to show.
({String label, String value, double progress, SleepNeedTone tone})?
sleepNeedBar({required double hours, double? need, required int nights}) {
  String spaced(int minutes) => minutes < 60
      ? '$minutes m'
      : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} m';
  if (need == null) {
    if (nights >= 14) return null;
    return (
      label: 'Learning your sleep need',
      value: '$nights of 14 nights',
      progress: nights / 14,
      tone: SleepNeedTone.learning,
    );
  }
  if (hours <= 0) return null;
  final difference = ((hours - need) * 60).round();
  return (
    label: 'Your need ${spaced((need * 60).round())}',
    value: difference.abs() < 15
        ? 'About your need'
        : '${spaced(difference.abs())} ${difference < 0 ? 'short' : 'over'}',
    progress: (hours / need).clamp(0.0, 1.0),
    tone: difference <= -15 ? SleepNeedTone.short : SleepNeedTone.met,
  );
}

// ── Heart rate ───────────────────────────────────────────────────────────────

/// Resting heart rate against the person's normal (Day) or the period before
/// (Week and Month). Workout readings never drive it.
DetailInsight heartInsight({
  required bool isDay,
  required int rangeDays,
  double? todayResting,
  double? restingNormal,
  List<double> todayReadings = const [],
  double? rangeResting,
  double? priorResting,
}) {
  if (isDay) {
    final resting = todayResting;
    if (resting != null) {
      final r = resting.round();
      if (restingNormal == null) {
        return DetailInsight(
          'Resting heart rate $r bpm today. Vivordo learns your normal after a week.',
        );
      }
      final normal = restingNormal.round();
      final difference = r - normal;
      if (difference.abs() <= 1) {
        return DetailInsight(
          'Resting heart rate $r bpm, in line with your normal $normal.',
        );
      }
      return DetailInsight(
        'Resting heart rate $r bpm, ${difference.abs()} ${difference > 0 ? 'above' : 'below'} your normal $normal.',
        difference >= 5 ? InsightTone.concern : InsightTone.neutral,
      );
    }
    if (todayReadings.isNotEmpty) {
      final low = todayReadings.reduce((a, b) => a < b ? a : b).round();
      final high = todayReadings.reduce((a, b) => a > b ? a : b).round();
      return DetailInsight(
        'No resting heart rate yet today. Readings so far ranged $low–$high bpm'
        '${restingNormal == null ? '.' : ', and your resting normal is ${restingNormal.round()} bpm.'}',
      );
    }
    return const DetailInsight(
      'No readings yet today. Wear your watch or take a heart scan.',
    );
  }

  final average = rangeResting;
  if (average == null) {
    return const DetailInsight(
      'No resting heart rate in this period. It comes from your watch overnight or a heart scan.',
    );
  }
  final a = average.round();
  final prior = priorResting;
  if (prior == null) {
    return DetailInsight('Resting heart rate was typically $a bpm.');
  }
  final difference = average - prior;
  if (difference.abs() < 1.5) {
    return DetailInsight(
      'Resting heart rate was typically $a bpm, about the same as the $rangeDays days before.',
    );
  }
  return DetailInsight(
    'Resting heart rate was typically $a bpm, ${difference.abs().round()} '
    '${difference < 0 ? 'lower' : 'higher'} than the $rangeDays days before.',
    difference >= 3
        ? InsightTone.concern
        : difference < 0
        ? InsightTone.good
        : InsightTone.neutral,
  );
}

/// The median of the 28 days of resting heart rate before [today], with at
/// least 7 days.
double? restingNormal(DayValues resting, DateTime today) {
  final values = _window(resting, insightDay(today), 1, 29);
  return values.length >= 7 ? median(values) : null;
}

// ── Exercise ─────────────────────────────────────────────────────────────────

/// Exercise minutes against the daily [goal]. Missing days count as no
/// exercise in both periods, so the comparison is like for like.
DetailInsight exerciseInsight({
  required DayValues minutes,
  required DateTime today,
  required int rangeDays,
  required double goal,
}) {
  final day = insightDay(today);
  double total(int from, int to) {
    var sum = 0.0;
    for (var i = from; i < to; i++) {
      sum += minutes[DateTime(day.year, day.month, day.day - i)] ?? 0;
    }
    return sum;
  }

  if (rangeDays == 1) {
    final now = (minutes[day] ?? 0).round();
    final week = total(0, 7).round();
    final goalPart = goal <= 0
        ? '.'
        : now >= goal
        ? ', meeting your ${goal.round()}-minute goal.'
        : ', ${(goal - now).round()} to go for your ${goal.round()}-minute goal.';
    return DetailInsight(
      '$now min of exercise today$goalPart $week min over the last 7 days.',
      goal > 0 && now >= goal ? InsightTone.good : InsightTone.neutral,
    );
  }

  // Only days with data count: a day missing from Health isn't 0 minutes.
  final days = _window(minutes, day, 1, rangeDays + 1);
  if (days.isEmpty) {
    return DetailInsight('No exercise data in the last $rangeDays days yet.');
  }
  final sum = days.fold<double>(0, (a, b) => a + b).round();
  final active = days.where((m) => m > 0).length;
  final met = goal > 0 ? days.where((m) => m >= goal).length : null;
  final before = _window(minutes, day, rangeDays + 1, 2 * rangeDays + 1);
  var tone = InsightTone.neutral;
  var compare = '';
  if (days.length >= 3 && before.length >= 3 && _mean(before) > 0) {
    // A day's minutes against a day's, so uneven coverage compares fairly.
    final difference = (_mean(days) - _mean(before)).round();
    if ((difference / _mean(before)).abs() >= .1 && difference != 0) {
      compare =
          ', ${difference.abs()} min a day ${difference > 0 ? 'more' : 'less'} '
          'than the $rangeDays days before';
      tone = difference > 0 ? InsightTone.good : InsightTone.concern;
    } else {
      compare = ', about the same as the $rangeDays days before';
    }
  }
  final span = days.length == rangeDays
      ? 'the last $rangeDays full days'
      : '${days.length} ${days.length == 1 ? 'day' : 'days'} with data in '
            'the last $rangeDays';
  return DetailInsight(
    '${formatCount(sum.toDouble())} min over $span, active on $active of '
    'them$compare.'
    '${met == null ? '' : ' You met your ${goal.round()}-minute goal on $met.'}',
    tone,
  );
}

// ── Shared ───────────────────────────────────────────────────────────────────

String formatCount(double value) => value.round().toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

String hoursMinutes(double hours) {
  final minutes = (hours * 60).round();
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// "25 min" or "1h 10m".
String _duration(int minutes) => minutes < 60
    ? '$minutes min'
    : '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';

/// Minutes after noon, so bedtimes either side of midnight compare simply.
int _minutesFromNoon(DateTime t) => (t.hour * 60 + t.minute - 720) % 1440;

/// Minutes after midnight, for wake times (mornings).
int _minutesOfDay(DateTime t) => t.hour * 60 + t.minute;

/// Values from [from] (inclusive) to [to] (exclusive) days before [day].
List<double> _window(DayValues values, DateTime day, int from, int to) => [
  for (var i = from; i < to; i++)
    ?values[DateTime(day.year, day.month, day.day - i)],
];

double _mean(List<double> values) =>
    values.reduce((a, b) => a + b) / values.length;

/// The middle value, or null for none.
double? median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return null;
  final m = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[m] : (sorted[m - 1] + sorted[m]) / 2;
}
