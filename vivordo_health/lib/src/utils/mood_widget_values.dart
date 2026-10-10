import 'package:cloud_firestore/cloud_firestore.dart';

/// A check-in tapped on the Mood widget, waiting for the app to save it.
typedef PendingMoodCheckIn = ({
  String id,
  double score,
  String label,
  DateTime at,
});

/// The signed-in account's queued widget taps, oldest first, so the latest
/// tap is the one left as the day's current mood. Malformed entries and taps
/// made while another account was signed in are skipped.
List<PendingMoodCheckIn> pendingMoodCheckIns(String uid, List<Object?> raw) {
  final checkIns = <PendingMoodCheckIn>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final id = item['id'];
    final score = item['score'];
    final label = item['label'];
    final at = item['at'];
    if (item['account'] != uid ||
        id is! String ||
        score is! num ||
        label is! String ||
        at is! num) {
      continue;
    }
    checkIns.add((
      id: id,
      score: score.toDouble().clamp(0, 100).toDouble(),
      label: label,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
    ));
  }
  return checkIns..sort((a, b) => a.at.compareTo(b.at));
}

/// Today's check-in count and latest check-in for the Mood widget, from a
/// `metrics_daily` day's `mood` map.
Map<String, Object> moodWidgetValues(Object? mood) {
  var count = 0;
  num? lastScore;
  DateTime? lastAt;
  if (mood is Map) {
    final entries = mood['entries'];
    if (entries is List && entries.isNotEmpty) {
      for (final entry in entries) {
        if (entry is! Map) continue;
        count++;
        final at = (entry['timestamp'] as Timestamp?)?.toDate();
        final score = entry['score'];
        if (at != null &&
            score is num &&
            (lastAt == null || at.isAfter(lastAt))) {
          lastAt = at;
          lastScore = score;
        }
      }
    } else if (mood['avg'] is num) {
      // Days saved before check-ins were kept as entries.
      count = 1;
      lastScore = mood['avg'] as num;
      lastAt = (mood['checkInAt'] as Timestamp?)?.toDate();
    }
  }
  return {
    'moodTodayCount': count,
    'moodLastScore': lastScore?.round() ?? -1,
    'moodLastAt': lastAt?.millisecondsSinceEpoch ?? 0,
  };
}
