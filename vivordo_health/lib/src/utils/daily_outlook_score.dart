class DailyCapacityResult {
  const DailyCapacityResult({
    required this.score,
    required this.label,
    required this.availableSignals,
  });

  final int? score;
  final String label;
  final int availableSignals;
}

/// Estimates how much personal capacity is available for the day.
///
/// Each available signal is normalized to 0–100 and the weights are
/// rebalanced when a source is missing. Heart rate is intentionally a small
/// contributor because a raw BPM value is less useful without a baseline.
DailyCapacityResult calculateDailyCapacity({
  double? sleepHours,
  double? stressScore,
  double? heartRate,
}) {
  final signals = <(double, double)>[];

  if (sleepHours != null && sleepHours.isFinite && sleepHours > 0) {
    final sleepScore = (100 - (8 - sleepHours).abs() * 15).clamp(0, 100);
    signals.add((sleepScore.toDouble(), .45));
  }
  if (stressScore != null && stressScore.isFinite) {
    signals.add(((100 - stressScore).clamp(0, 100).toDouble(), .35));
  }
  if (heartRate != null &&
      heartRate.isFinite &&
      heartRate >= 30 &&
      heartRate <= 220) {
    final heartScore = (100 - (heartRate - 60).abs() * 2).clamp(0, 100);
    signals.add((heartScore.toDouble(), .20));
  }

  if (signals.isEmpty) {
    return const DailyCapacityResult(
      score: null,
      label: 'Not enough data',
      availableSignals: 0,
    );
  }

  final totalWeight = signals.fold<double>(0, (sum, item) => sum + item.$2);
  final weightedScore = signals.fold<double>(
    0,
    (sum, item) => sum + item.$1 * item.$2,
  );
  final score = (weightedScore / totalWeight).round().clamp(0, 100);

  return DailyCapacityResult(
    score: score,
    label: score >= 70
        ? 'High'
        : score >= 40
        ? 'Moderate'
        : 'Low',
    availableSignals: signals.length,
  );
}
