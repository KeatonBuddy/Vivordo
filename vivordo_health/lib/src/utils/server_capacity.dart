/// Capacity calculated on the server (functions/capacity.js,
/// docs/scores.md §4) and stored in `users/{uid}/scores_daily/{day}`.
class ServerCapacity {
  const ServerCapacity({
    required this.score,
    required this.label,
    required this.provisional,
    required this.note,
  });

  final int score;

  /// "high" (≥ 80), "moderate" (50–79) or "low" (< 50).
  final String label;

  /// Last night's sleep hasn't synced yet; the score will update when it
  /// does.
  final bool provisional;

  /// How today compares with the person's usual Capacity.
  final String note;
}

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
            when past['version'] == today['version'] && past['score'] is num)
          (past['score'] as num).toDouble(),
  ]..sort();
  final usual = earlier.length < 7
      ? null
      : earlier.length.isOdd
      ? earlier[earlier.length ~/ 2]
      : (earlier[earlier.length ~/ 2 - 1] + earlier[earlier.length ~/ 2]) / 2;
  final note = provisional
      ? 'Estimated · waiting for sleep'
      : usual == null
      ? 'Still learning your usual'
      : (score - usual).abs() < 10
      ? 'Near your usual'
      : score < usual
      ? 'Below your usual'
      : 'Above your usual';
  return ServerCapacity(
    score: score,
    label: today['label'] is String ? today['label'] as String : 'moderate',
    provisional: provisional,
    note: note,
  );
}
