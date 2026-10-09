/// Training load (docs/scores.md §4), as functions/training_load.js saves it
/// in scores_daily/{day}.trainingLoad: this week's activity against the
/// person's usual week. Words and rows for the Fitness and My Day cards.
class TrainingLoadView {
  const TrainingLoadView({
    required this.dayKey,
    required this.state,
    required this.ratio,
    required this.thisWeek,
    required this.usualWeek,
    required this.hardDays,
    required this.kind,
    required this.days,
    required this.mornings,
    required this.hrvLow,
    required this.restingHigh,
    required this.restingHrChange,
  });

  static const version = 1;
  static const hardDay = 1.5;

  /// The scores_daily day it was calculated for.
  final String dayKey;

  /// lighter, steady, building, high or strained.
  final String state;
  final double ratio;
  final double thisWeek;
  final double usualWeek;
  final int hardDays;

  /// heart, minutes, mixed or null.
  final String? kind;

  /// The 7 days before [dayKey], oldest first; 1.0 is an ordinary active day.
  final List<({String day, double value})> days;

  /// Mornings (of the last 3) with HRV or resting HR to compare.
  final int mornings;
  final int hrvLow;
  final int restingHigh;
  final double? restingHrChange;

  /// Null until there's a usual week to compare with (state "learning") or
  /// for a version this build doesn't know.
  static TrainingLoadView? fromMap(Object? raw, String dayKey) {
    if (raw is! Map || raw['version'] != version) return null;
    final state = raw['state'];
    final ratio = (raw['ratio'] as num?)?.toDouble();
    if (state is! String || state == 'learning' || ratio == null) return null;
    final body = raw['body'] is Map ? raw['body'] as Map : const {};
    return TrainingLoadView(
      dayKey: dayKey,
      state: state,
      ratio: ratio,
      thisWeek: (raw['thisWeek'] as num?)?.toDouble() ?? 0,
      usualWeek: (raw['usualWeek'] as num?)?.toDouble() ?? 0,
      hardDays: (raw['hardDays'] as num?)?.toInt() ?? 0,
      kind: raw['kind'] as String?,
      days: [
        for (final d in raw['days'] is List ? raw['days'] as List : const [])
          if (d is Map && d['day'] is String)
            (
              day: d['day'] as String,
              value: (d['value'] as num?)?.toDouble() ?? 0,
            ),
      ],
      mornings: (body['mornings'] as num?)?.toInt() ?? 0,
      hrvLow: (body['hrvLow'] as num?)?.toInt() ?? 0,
      restingHigh: (body['restingHigh'] as num?)?.toInt() ?? 0,
      restingHrChange: (body['restingHrChange'] as num?)?.toDouble(),
    );
  }

  /// High or Strained: the only states shown on My Day.
  bool get alert => state == 'high' || state == 'strained';

  String get label => switch (state) {
    'lighter' => 'Lighter',
    'building' => 'Building',
    'high' => 'High',
    'strained' => 'Strained',
    _ => 'Steady',
  };

  String get headline => switch (state) {
    'lighter' => 'Lighter than your usual week',
    'building' => 'More than your usual week',
    'high' || 'strained' => 'A lot more than usual',
    _ => 'About your usual week',
  };

  int get percent => ((ratio - 1) * 100).round();

  /// "+60% vs your usual", or "About your usual" within 5%.
  String get vsUsual => percent.abs() < 5
      ? 'About your usual'
      : '${percent > 0 ? '+' : '−'}${percent.abs()}% vs your usual';

  /// The average day of the usual week, for the chart's line.
  double get usualDay => usualWeek / 7;

  /// HRV and resting-HR rows; empty without any mornings to compare.
  List<({String label, String value, bool off})> get bodyRows {
    if (mornings == 0) return const [];
    final change = restingHrChange;
    final rows = [
      if (hrvLow > 0)
        (label: 'HRV', value: 'Low $hrvLow of the last 3 mornings', off: true),
      if (restingHigh > 0)
        (
          label: 'Resting HR',
          value: change != null && change >= 1
              ? '+${change.round()} bpm today'
              : 'Up $restingHigh of the last 3 mornings',
          off: true,
        ),
    ];
    return rows.isNotEmpty
        ? rows
        : const [
            (label: 'Body', value: 'HRV and resting HR normal', off: false),
          ];
  }

  String get measuredBy => switch (kind) {
    'heart' => 'Measured by heart rate',
    'minutes' => 'Measured by active minutes',
    'mixed' => 'Measured by heart rate, or active minutes without it',
    _ => 'No activity recorded this week',
  };

  /// My Day's sentence: "About 60% above your usual this week, on 4 hard
  /// days, and your HRV has been low 2 of the last 3 mornings."
  String get summary {
    final hard = '$hardDays hard ${hardDays == 1 ? 'day' : 'days'}';
    final body = state != 'strained'
        ? ''
        : hrvLow >= restingHigh
        ? ', and your HRV has been low $hrvLow of the last 3 mornings'
        : ', and your resting heart rate has been up $restingHigh of the '
              'last 3 mornings';
    final amount = ratio >= 2
        ? '${ratio.toStringAsFixed(1)}× your usual'
        : '$percent% above your usual';
    return 'About $amount this week, on $hard$body.';
  }

  /// What Vivordo AI is told when asked to plan an easier week.
  String get chatContext => [
    'Training load: $label. The last 7 days were ${ratio.toStringAsFixed(2)}× '
        'the usual week (the 4 weeks before), with $hardDays hard days '
        '(1.5× an ordinary active day or more). $measuredBy.',
    'Each day against an ordinary active day (1.0): '
        '${days.map((d) => '${d.day} ${d.value.toStringAsFixed(1)}').join(', ')}.',
    if (mornings > 0)
      'HRV low on $hrvLow and resting heart rate up on $restingHigh of the '
          'last 3 mornings.',
  ].join(' ');
}
