/// Capacity calculated on the server (functions/capacity.js,
/// docs/scores.md §4) and stored in `users/{uid}/scores_daily/{day}`.
class ServerCapacity {
  const ServerCapacity({
    required this.score,
    required this.label,
    required this.provisional,
    required this.note,
    this.sleepNeedHours,
    this.usual,
    this.bigDay,
    this.activityBase,
    this.activityThreshold,
    this.todayLoad,
  });

  final int score;

  /// "high" (≥ 80), "moderate" (50–79) or "low" (< 50).
  final String label;

  /// Last night's sleep hasn't synced yet; the score will update when it
  /// does.
  final bool provisional;

  /// How today compares with the person's usual Capacity.
  final String note;

  /// The person's sleep need in hours (90-day median, 7–9 h).
  final double? sleepNeedHours;

  /// Median Capacity of earlier days (comparable formula versions); null
  /// until there are 7.
  final double? usual;

  /// A big day in the last 3 that's lowering Recovery (`capacity.bigDay`).
  final BigDay? bigDay;

  /// From `capacity.activityUsual`: the usual load a big day is measured
  /// against, and the load that makes one, in today's kind: heart-rate
  /// TRIMP once today's heart rate is measured, else Effort points
  /// (docs/scores.md §4).
  final double? activityBase, activityThreshold;

  /// Today's load so far, in the same kind: `activityLoad.trimp` or
  /// `effort.physicalLoad`.
  final double? todayLoad;

  /// Today's load against the usual when it's a big day, e.g. 3.1; null
  /// otherwise.
  double? get todayBigDayRatio =>
      bigDayRatio(todayLoad, activityBase, activityThreshold);
}

/// A recent day of much more activity than usual (functions/capacity.js
/// bigDayEffect).
class BigDay {
  const BigDay({required this.day, required this.ratio, required this.halved});

  final DateTime day;

  /// Its load against the usual, e.g. 3.0.
  final double ratio;

  /// The body was already back at its normal, so it cost half.
  final bool halved;
}

/// [load] against [base] once it reaches [threshold] (the server's
/// bigDayScale); null below it.
double? bigDayRatio(double? load, double? base, double? threshold) {
  if (load == null || base == null || threshold == null || base <= 0) {
    return null;
  }
  return load >= threshold ? load / base : null;
}

/// Capacity versions whose scores compare: 2 only changed days after a big
/// day.
bool _comparable(Object? a, Object? b) =>
    a == b || ((a == 1 || a == 2) && (b == 1 || b == 2));

/// Today's server Capacity from a window of `scores_daily` documents (day
/// key -> data), compared with the median of earlier days calculated with
/// the same formula version. Null when the server has no Capacity for
/// [dayKey] yet.
ServerCapacity? serverCapacityFor(
  Map<String, Map<String, dynamic>> days,
  String dayKey,
) {
  final today = days[dayKey]?['capacity'];
  if (today is! Map || today['score'] is! num) return null;
  final score = (today['score'] as num).round();
  final provisional = today['provisional'] == true;
  final earlier = <double>[
    for (final entry in days.entries)
      if (entry.key.compareTo(dayKey) < 0)
        if (entry.value['capacity'] case final Map past
            when _comparable(past['version'], today['version']) &&
                past['score'] is num)
          (past['score'] as num).toDouble(),
  ]..sort();
  final usual = earlier.length < 7
      ? null
      : earlier.length.isOdd
      ? earlier[earlier.length ~/ 2]
      : (earlier[earlier.length ~/ 2 - 1] + earlier[earlier.length ~/ 2]) / 2;
  final parts = today['parts'];
  final note = provisional
      ? parts is Map && parts['sleep'] == null && parts['body'] == null
            ? 'Based on your check-in'
            : 'Estimated · waiting for sleep'
      : usual == null
      ? 'Still learning your usual'
      : (score - usual).abs() < 10
      ? 'Near your usual'
      : score < usual
      ? 'Below your usual'
      : 'Above your usual';
  final bigDay = today['bigDay'];
  // `activityUsual`: {heart, minutes}, each {usual, base, threshold} or null
  // (docs/scores.md §4); records from before the per-day fallback have one
  // scale with a `kind`.
  final activity = today['activityUsual'];
  Map? scaleOf(String kind) => activity is! Map
      ? null
      : activity[kind] is Map
      ? activity[kind] as Map
      : activity['kind'] == kind
      ? activity
      : null;
  // Today by heart rate once it's measured, minutes otherwise (a watch left
  // off), each against its own usual.
  final todayDoc = days[dayKey];
  final todayHeart = (todayDoc?['activityLoad'] as Map?)?['trimp'];
  final useHeart = scaleOf('heart') != null && todayHeart is num;
  final scale = scaleOf(useHeart ? 'heart' : 'minutes');
  final todayMinutes = (todayDoc?['effort'] as Map?)?['physicalLoad'];
  final todayLoad = useHeart ? todayHeart : todayMinutes;
  return ServerCapacity(
    bigDay: bigDay is Map && DateTime.tryParse('${bigDay['day']}') != null
        ? BigDay(
            day: DateTime.parse(bigDay['day'] as String),
            ratio: (bigDay['ratio'] as num? ?? 2).toDouble(),
            halved: bigDay['halved'] == true,
          )
        : null,
    activityBase: (scale?['base'] as num?)?.toDouble(),
    activityThreshold: (scale?['threshold'] as num?)?.toDouble(),
    todayLoad: todayLoad is num ? todayLoad.toDouble() : null,
    score: score,
    label: today['label'] is String ? today['label'] as String : 'moderate',
    provisional: provisional,
    note: note,
    sleepNeedHours: (today['sleepNeed'] as num?)?.toDouble(),
    usual: usual,
  );
}

/// My Day's morning headline while a big day is lowering Capacity:
/// "Big day yesterday. Go easy today." or, two or three days on, "Still
/// recovering from Monday's big day".
String bigDayHeadline(BigDay bigDay, DateTime today) {
  final days = DateTime(today.year, today.month, today.day)
      .difference(DateTime(bigDay.day.year, bigDay.day.month, bigDay.day.day))
      .inDays;
  if (days <= 1) return 'Big day yesterday. Go easy today.';
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return 'Still recovering from ${weekdays[bigDay.day.weekday - 1]}’s big day';
}
