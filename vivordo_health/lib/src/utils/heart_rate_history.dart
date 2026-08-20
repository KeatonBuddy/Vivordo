import 'package:cloud_firestore/cloud_firestore.dart';

class HeartRateHistoryReading {
  const HeartRateHistoryReading({required this.bpm, required this.timestamp});

  final double bpm;
  final DateTime timestamp;
}

class _Candidate {
  const _Candidate(this.reading, this.priority);

  final HeartRateHistoryReading reading;
  final int priority;
}

/// Combines stored heart-rate histories without losing inactive sources.
///
/// Samples are reduced to one value per minute. WHOOP Bluetooth has the
/// highest precedence when it overlaps another source, while non-overlapping
/// Apple Health and camera readings remain in the returned history.
List<HeartRateHistoryReading> mergedHeartRateHistory(
  Map<String, dynamic> data, {
  required DateTime fallbackDate,
  bool includeDailyFallback = true,
}) {
  const applePriority = 10;
  const legacyPriority = 15;
  const scanPriority = 20;
  const whoopPriority = 30;
  final byMinute = <int, _Candidate>{};

  DateTime entryTime(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? fallbackDate;
    return fallbackDate;
  }

  int minuteKey(DateTime time) =>
      time.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute;

  void addMetric(Map? metric, int priority) {
    final rawEntries = metric?['entries'];
    if (rawEntries is! List) return;

    // A source can contain multiple raw samples in one minute. Average those
    // first, then apply source precedence to the minute as a whole.
    final totals = <int, ({double sum, int count, DateTime timestamp})>{};
    for (final raw in rawEntries) {
      if (raw is! Map || raw['bpm'] is! num) continue;
      final timestamp = entryTime(raw['timestamp']);
      final key = minuteKey(timestamp);
      final existing = totals[key];
      totals[key] = (
        sum: (existing?.sum ?? 0) + (raw['bpm'] as num).toDouble(),
        count: (existing?.count ?? 0) + 1,
        timestamp: existing?.timestamp ?? timestamp,
      );
    }

    for (final entry in totals.entries) {
      final existing = byMinute[entry.key];
      if (existing != null && existing.priority > priority) continue;
      byMinute[entry.key] = _Candidate(
        HeartRateHistoryReading(
          bpm: entry.value.sum / entry.value.count,
          timestamp: entry.value.timestamp,
        ),
        priority,
      );
    }
  }

  final sources = data['heart_rate_sources'] as Map?;
  final apple = sources?['apple_health'] as Map?;
  final whoop = sources?['whoop_ble'] as Map?;
  final active = data['heart_rate'] as Map?;
  final scan = data['heart_rate_scan'] as Map?;

  addMetric(apple, applePriority);

  // The canonical field supports older records. Avoid reading it twice when
  // the same source-specific history is also present.
  final activeSource = active?['source'];
  final activeHasDedicatedSource =
      (activeSource == 'apple_health' && apple != null) ||
      (activeSource == 'whoop_ble' && whoop != null);
  if (!activeHasDedicatedSource) {
    addMetric(
      active,
      activeSource == 'whoop_ble'
          ? whoopPriority
          : activeSource == 'apple_health'
          ? applePriority
          : legacyPriority,
    );
  }

  addMetric(scan, scanPriority);
  addMetric(whoop, whoopPriority);

  if (byMinute.isEmpty && includeDailyFallback) {
    void addDailyFallback(Map? metric, int priority) {
      if (metric?['avg'] is! num) return;
      final timestamp = entryTime(
        metric?['lastReadingAt'] ?? metric?['syncedAt'],
      );
      final key = minuteKey(timestamp);
      final existing = byMinute[key];
      if (existing != null && existing.priority > priority) return;
      byMinute[key] = _Candidate(
        HeartRateHistoryReading(
          bpm: (metric!['avg'] as num).toDouble(),
          timestamp: timestamp,
        ),
        priority,
      );
    }

    addDailyFallback(apple, applePriority);
    if (!activeHasDedicatedSource) {
      addDailyFallback(
        active,
        activeSource == 'whoop_ble'
            ? whoopPriority
            : activeSource == 'apple_health'
            ? applePriority
            : legacyPriority,
      );
    }
    addDailyFallback(scan, scanPriority);
    addDailyFallback(whoop, whoopPriority);
  }

  final result = byMinute.values.map((value) => value.reading).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return result;
}
