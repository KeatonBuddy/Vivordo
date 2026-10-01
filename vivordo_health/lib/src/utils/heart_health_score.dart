import 'dart:math' as math;

const int heartHealthBaselineWindowDays = 28;
const int heartHealthMinimumBaselineDays = 7;

class HeartHealthSignals {
  const HeartHealthSignals({
    this.restingHeartRate,
    this.hrv,
    this.quietHeartRate,
  });

  final double? restingHeartRate;
  final double? hrv;
  final double? quietHeartRate;
}

/// HRV comes in kinds that can't be compared or converted: Apple Health's
/// daytime SDNN and each wearable's overnight RMSSD. Scores compare HRV with
/// the person's own normal, so each uses readings of a single kind.
/// Mirrors functions/hrv.js. The connected wearable first, then Apple Health.
const hrvKinds = ['rmssd:whoop', 'rmssd:fitbit', 'sdnn'];

/// A day's HRV readings keyed by kind, e.g. {'rmssd:whoop': 44, 'sdnn': 61}.
Map<String, double> hrvReadings(Map<String, dynamic>? data) {
  double? average(Object? metric) {
    final value = metric is Map ? metric['avg'] : null;
    return value is num && _valid(value.toDouble()) ? value.toDouble() : null;
  }

  final rmssd = data?['hrv_rmssd'];
  final kind = 'rmssd:${rmssd is Map ? rmssd['source'] : null}';
  final rmssdValue = average(rmssd);
  final sdnnValue = average(data?['hrv']);
  return {
    if (hrvKinds.contains(kind) && rmssdValue != null) kind: rmssdValue,
    'sdnn': ?sdnnValue,
  };
}

/// Today's HRV with the same-kind values of earlier days. Prefers the
/// wearable, but keeps using a kind that already has a normal while a newly
/// connected wearable builds its own. `history` lines up with the input days.
({String? kind, double? value, List<double?> history}) pickHrv(
  Map<String, double> today,
  List<Map<String, double>> history,
  int minimumBaseline,
) {
  final options = [
    for (final kind in hrvKinds)
      if (today[kind] != null)
        (
          kind: kind,
          value: today[kind],
          history: [for (final day in history) day[kind]],
        ),
  ];
  for (final option in options) {
    if (option.history.whereType<double>().length >= minimumBaseline) {
      return option;
    }
  }
  return options.isNotEmpty
      ? options.first
      : (kind: null, value: null, history: List.filled(history.length, null));
}

enum HeartHealthConfidence { low, medium, high }

class HeartHealthScoreResult {
  const HeartHealthScoreResult({
    required this.score,
    required this.restingHeartRateScore,
    required this.hrvScore,
    required this.quietHeartRateScore,
    required this.availableSignals,
    required this.scoredSignals,
    required this.baselineDays,
    required this.confidence,
  });

  final double? score;
  final double? restingHeartRateScore;
  final double? hrvScore;
  final double? quietHeartRateScore;
  final int availableSignals;
  final int scoredSignals;
  final int baselineDays;
  final HeartHealthConfidence confidence;

  bool get isBuildingBaseline => availableSignals > 0 && score == null;
}

/// Produces a personalized Heart Health score from cardiovascular trends.
///
/// A user's own recent median is the neutral reference point (80/100). Resting
/// and quiet heart rates score better when modestly below their usual level;
/// HRV scores better when above its usual level. Median absolute deviation
/// makes the comparison robust to isolated spikes. Signals with fewer than
/// seven prior days are excluded and the remaining weights are normalized.
HeartHealthScoreResult calculateHeartHealthScore({
  required HeartHealthSignals current,
  required List<HeartHealthSignals> history,
}) {
  final restingHistory = _values(history.map((day) => day.restingHeartRate));
  final hrvHistory = _values(history.map((day) => day.hrv));
  final quietHistory = _values(history.map((day) => day.quietHeartRate));

  final restingScore = _personalizedScore(
    current: current.restingHeartRate,
    history: restingHistory,
    lowerIsBetter: true,
    minimumScale: 3,
    pointsPerDeviation: 12,
  );
  final hrvScore = _personalizedScore(
    current: current.hrv,
    history: hrvHistory,
    lowerIsBetter: false,
    minimumScale: 5,
    pointsPerDeviation: 10,
  );
  final quietScore = _personalizedScore(
    current: current.quietHeartRate,
    history: quietHistory,
    lowerIsBetter: true,
    minimumScale: 3,
    pointsPerDeviation: 10,
  );

  const weights = [0.50, 0.30, 0.20];
  final scores = [restingScore, hrvScore, quietScore];
  var weightedScore = 0.0;
  var availableWeight = 0.0;
  for (var index = 0; index < scores.length; index++) {
    final score = scores[index];
    if (score == null) continue;
    weightedScore += score * weights[index];
    availableWeight += weights[index];
  }

  final availableSignals = [
    current.restingHeartRate,
    current.hrv,
    current.quietHeartRate,
  ].where(_valid).length;
  final scoredSignals = scores.whereType<double>().length;
  final baselineCounts = <int>[
    if (restingScore != null) restingHistory.length,
    if (hrvScore != null) hrvHistory.length,
    if (quietScore != null) quietHistory.length,
  ];
  final baselineDays = baselineCounts.isEmpty
      ? math.max(
          restingHistory.length,
          math.max(hrvHistory.length, quietHistory.length),
        )
      : baselineCounts.reduce(math.min);
  final confidence = scoredSignals == 3 && baselineDays >= 14
      ? HeartHealthConfidence.high
      : scoredSignals >= 2 || (scoredSignals == 1 && baselineDays >= 14)
      ? HeartHealthConfidence.medium
      : HeartHealthConfidence.low;

  return HeartHealthScoreResult(
    score: availableWeight == 0
        ? null
        : (weightedScore / availableWeight).clamp(0.0, 100.0),
    restingHeartRateScore: restingScore,
    hrvScore: hrvScore,
    quietHeartRateScore: quietScore,
    availableSignals: availableSignals,
    scoredSignals: scoredSignals,
    baselineDays: baselineDays,
    confidence: confidence,
  );
}

List<double> _values(Iterable<double?> values) => values
    .where(_valid)
    .map((value) => value!.toDouble())
    .toList(growable: false);

bool _valid(double? value) => value != null && value.isFinite && value > 0;

double? _personalizedScore({
  required double? current,
  required List<double> history,
  required bool lowerIsBetter,
  required double minimumScale,
  required double pointsPerDeviation,
}) {
  if (!_valid(current) || history.length < heartHealthMinimumBaselineDays) {
    return null;
  }
  final baseline = _median(history);
  final deviations = history
      .map((value) => (value - baseline).abs())
      .toList(growable: false);
  final scale = math.max(_median(deviations) * 1.4826, minimumScale);
  final standardizedDifference = (current! - baseline) / scale;
  final direction = lowerIsBetter ? -1.0 : 1.0;
  return (80 + standardizedDifference * direction * pointsPerDeviation).clamp(
    0.0,
    100.0,
  );
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
