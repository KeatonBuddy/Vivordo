/// One ingredient of Physical Health, as the detail screen shows it.
class PhysicalIngredient {
  const PhysicalIngredient(this.name, this.weight, this.detail, this.progress);

  final String name;

  /// Share of the score, in percent.
  final int weight;

  /// "132 of 150 min a week", or why it's missing.
  final String detail;

  /// 0–100 towards the target, or null when it isn't counted yet.
  final double? progress;
}

/// What Metrics shows for Physical Health, from `scores_daily/{day}.physical`
/// (functions/physical_health.js).
class PhysicalHealthView {
  const PhysicalHealthView({
    required this.score,
    required this.status,
    required this.note,
    required this.ingredients,
    required this.insights,
    required this.trend,
  });

  /// Null while building.
  final int? score;

  /// "Excellent", "Good", "Fair", "Needs attention" or "Building".
  final String status;

  /// "↑ 3 vs 4 weeks ago", "Based on 9 of 14 days so far"…
  final String note;
  final List<PhysicalIngredient> ingredients;
  final List<String> insights;

  /// (day, score) oldest first, for the trend chart.
  final List<(DateTime, int)> trend;

  /// From scores_daily documents keyed by day (any order). Uses the latest
  /// day with a Physical Health record. Null when there is none.
  static PhysicalHealthView? fromDays(Map<String, Map<String, dynamic>> days) {
    final keys = days.keys.toList()..sort();
    final withScore = [
      for (final k in keys)
        if (days[k]?['physical'] is Map) k,
    ];
    if (withScore.isEmpty) return null;
    final latestKey = withScore.last;
    final latest = Map<String, dynamic>.from(days[latestKey]!['physical']);
    final score = (latest['score'] as num?)?.round();
    final parts = (latest['parts'] as Map?) ?? const {};
    final details = (latest['details'] as Map?) ?? const {};
    double? part(String name) => (parts[name] as num?)?.toDouble();

    final trend = <(DateTime, int)>[
      for (final k in withScore)
        if (((days[k]!['physical'] as Map)['score'] as num?) case final s?)
          if (DateTime.tryParse(k) case final d?) (d, s.round()),
    ];
    String note;
    if (score == null) {
      final daysOfData = (latest['daysOfData'] as num? ?? 0).toInt();
      final counted = parts.values.where((v) => v != null).length;
      note = daysOfData < 14
          ? 'Based on $daysOfData of 14 days so far'
          : 'Needs $counted of 3 ingredients to start';
    } else {
      final latestDay = DateTime.parse(latestKey);
      final then = trend
          .where(
            (p) => !p.$1.isAfter(latestDay.subtract(const Duration(days: 28))),
          )
          .lastOrNull;
      note = then == null
          ? 'Change shows after 4 weeks'
          : score == then.$2
          ? 'Same as 4 weeks ago'
          : '${score > then.$2 ? '↑' : '↓'} ${(score - then.$2).abs()} vs 4 weeks ago';
    }

    final weekly = (details['weeklyActiveMinutes'] as num?)?.round();
    final steps = (details['avgSteps'] as num?)?.round();
    final strength = (details['strengthPerWeek'] as num?)?.toDouble();
    final vo2 = (details['vo2Max'] as num?)?.toDouble();
    final vo2Normal = (details['vo2Normal'] as num?)?.toDouble();
    final sleepHours = (details['sleepHours'] as num?)?.toDouble();
    final onTime = (details['sleepOnTimeShare'] as num?)?.toDouble();
    String level(double v, double n) => v >= n * 1.2
        ? 'Excellent for your age'
        : v >= n * 1.05
        ? 'Above average for your age'
        : v >= n * .95
        ? 'Average for your age'
        : 'Below average for your age';
    final ingredients = [
      PhysicalIngredient(
        'Active minutes',
        30,
        weekly == null
            ? 'Not enough exercise data yet'
            : '$weekly of 150 min a week',
        part('activeMinutes'),
      ),
      PhysicalIngredient(
        'Daily movement',
        15,
        steps == null
            ? 'Not enough step data yet'
            : '${_thousands(steps)} of 8,000 steps a day',
        part('movement'),
      ),
      PhysicalIngredient(
        'Strength',
        20,
        strength == null
            ? 'Log strength workouts in Fitness to count them'
            : '${_trim(strength)} of 2 sessions a week',
        part('strength'),
      ),
      PhysicalIngredient(
        'Cardio fitness',
        20,
        vo2 == null
            ? vo2Normal == null
                  ? 'Add your age in your profile (Fitness → Body)'
                  : 'Add your height and weight in your profile (Fitness → Body)'
            : 'VO₂ max ${vo2.round()}${details['vo2Source'] == 'estimate' ? ' (estimated)' : ''}'
                  '${vo2Normal == null ? '' : ' · ${level(vo2, vo2Normal)}'}',
        part('cardio'),
      ),
      PhysicalIngredient(
        'Sleep habits',
        15,
        details['sleepSource'] == 'checkIn'
            ? 'From your morning check-ins'
            : sleepHours == null
            ? 'Not enough sleep data yet'
            : '${_hoursMinutes(sleepHours)} avg'
                  '${onTime == null ? '' : ' · ${(onTime * 7).round()} of 7 nights on time'}',
        part('sleep'),
      ),
    ];

    // The easiest wins: counted ingredients furthest below target, weighted.
    final gaps =
        [
          for (final i in ingredients)
            if (i.progress != null && i.progress! < 95) i,
        ]..sort(
          (a, b) => ((100 - b.progress!) * b.weight).compareTo(
            (100 - a.progress!) * a.weight,
          ),
        );
    final insights = [
      for (final i in gaps.take(2))
        switch (i.name) {
          'Active minutes' =>
            'Active minutes are ${150 - (weekly ?? 0)} short a week: a brisk '
                '10-minute walk after lunch on weekdays closes most of the gap.',
          'Daily movement' =>
            'Steps are ${_thousands(8000 - (steps ?? 0))} a day under target: '
                'short walks between meetings add up fast.',
          'Strength' =>
            'Strength is an easy win: one more session a week '
                '${(strength ?? 0) < 1 ? 'starts it' : 'takes it to 100'}.',
          'Cardio fitness' =>
            'Two runs or brisk walks of 20+ minutes a week usually raise '
                'VO₂ max within a couple of months.',
          _ => 'A regular bedtime and 7–9 hours most nights lift sleep habits.',
        },
      if (gaps.isEmpty && score != null)
        'You\'re meeting your targets. Keep it up.',
      if (score == null)
        'Your Physical Health score appears after 2 weeks of activity and '
            'sleep data.',
    ];

    return PhysicalHealthView(
      score: score,
      status: score == null
          ? 'Building'
          : switch (latest['label']) {
              'excellent' => 'Excellent',
              'good' => 'Good',
              'fair' => 'Fair',
              _ => 'Needs attention',
            },
      note: note,
      ingredients: ingredients,
      insights: insights,
      trend: trend,
    );
  }
}

String _thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

String _trim(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

String _hoursMinutes(double hours) {
  final m = (hours * 60).round();
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}
