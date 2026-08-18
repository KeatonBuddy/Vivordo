import 'package:cloud_firestore/cloud_firestore.dart';

/// Returns the newest timestamped heart-rate reading across HealthKit and
/// Vivordo camera metrics. [metricDays] should be ordered newest day first so
/// legacy records without timestamps retain a sensible fallback order.
int? latestHeartRateBpmFromMetricDays(
  Iterable<Map<String, dynamic>> metricDays,
) {
  int? latestBpm;
  DateTime? latestTime;
  int? fallbackBpm;

  DateTime? timestampDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  void considerMetric(Map? metric) {
    if (metric == null) return;
    var foundTimestampedEntry = false;
    final rawEntries = metric['entries'];
    if (rawEntries is List) {
      for (final entry in rawEntries) {
        if (entry is! Map || entry['bpm'] is! num) continue;
        final bpm = (entry['bpm'] as num).round();
        final entryTime = timestampDate(entry['timestamp']);
        if (entryTime == null) {
          fallbackBpm ??= bpm;
          continue;
        }

        foundTimestampedEntry = true;
        if (latestTime == null || entryTime.isAfter(latestTime!)) {
          latestBpm = bpm;
          latestTime = entryTime;
        }
      }
    }

    // Older records may only contain a daily value and sync timestamp.
    if (!foundTimestampedEntry && metric['avg'] is num) {
      final bpm = (metric['avg'] as num).round();
      final syncedAt = timestampDate(metric['syncedAt']);
      if (syncedAt != null &&
          (latestTime == null || syncedAt.isAfter(latestTime!))) {
        latestBpm = bpm;
        latestTime = syncedAt;
      } else {
        fallbackBpm ??= bpm;
      }
    }
  }

  for (final data in metricDays) {
    considerMetric(data['heart_rate'] as Map?);
    considerMetric(data['heart_rate_scan'] as Map?);
  }

  return latestBpm ?? fallbackBpm;
}
