/// HRV comes in kinds that can't be compared or converted: Apple Health's
/// daytime SDNN and each wearable's overnight RMSSD. Anything that compares
/// HRV across days uses readings of a single kind.
/// Mirrors functions/hrv.js. The connected wearable first, then Apple Health.
const hrvKinds = ['rmssd:whoop', 'rmssd:fitbit', 'sdnn'];

/// A day's HRV readings keyed by kind, e.g. {'rmssd:whoop': 44, 'sdnn': 61}.
Map<String, double> hrvReadings(Map<String, dynamic>? data) {
  double? average(Object? metric) {
    final value = metric is Map ? metric['avg'] : null;
    return value is num && value.isFinite && value > 0
        ? value.toDouble()
        : null;
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
