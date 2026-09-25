import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';

import 'heart_rate_history.dart';
import 'latest_heart_rate.dart';
import 'performance_trace.dart';

enum MetricsProjection { activity, homeToday, homeHistory, dailyBrief }

typedef MetricFieldReader = Object? Function(String path);

// Private-to-the-client keys; these are never written to Firestore.
const preparedHeartKey = '_preparedHeart';
const preparedStressKey = '_preparedStress';

/// Small, immutable candidates. Selection stays clock-dependent so a cached
/// Bluetooth value stops overriding newer readings when it is no longer live.
class PreparedHeartRate {
  const PreparedHeartRate(this.latest, this.latestBle);
  final HeartRateHistoryReading? latest;
  final HeartRateHistoryReading? latestBle;

  LatestHeartRateReading? at(DateTime now) {
    final ble = latestBle;
    final chosen =
        ble != null &&
            now.difference(ble.timestamp) <= const Duration(minutes: 5)
        ? ble
        : latest;
    return chosen == null
        ? null
        : LatestHeartRateReading(
            bpm: chosen.bpm.round(),
            timestamp: chosen.timestamp,
            source: chosen.source,
          );
  }

  static Object? _key(HeartRateHistoryReading? r) =>
      r == null ? null : (r.bpm, r.timestamp, r.source);

  @override
  bool operator ==(Object other) =>
      other is PreparedHeartRate &&
      _key(latest) == _key(other.latest) &&
      _key(latestBle) == _key(other.latestBle);
  @override
  int get hashCode => Object.hash(_key(latest), _key(latestBle));
}

/// Historical entries sorted once, not on every clock tick or widget rebuild.
/// Equal timestamps retain the same ordering as the legacy descending sort.
class PreparedStressHistory {
  factory PreparedStressHistory(Object? raw) {
    final original = (raw is List ? raw : const [])
        .whereType<Map>()
        .where((e) => e['timestamp'] is Timestamp)
        .map(
          (e) => (
            time: e['timestamp'] as Timestamp,
            score: (e['score'] as num?)?.toDouble(),
          ),
        )
        .toList();
    final sorted = [...original]..sort((a, b) => b.time.compareTo(a.time));
    final hasTies = Iterable.generate(
      sorted.isNotEmpty ? sorted.length - 1 : 0,
    ).any((i) => sorted[i].time == sorted[i + 1].time);
    return PreparedStressHistory._(
      List.unmodifiable(sorted),
      hasTies ? List.unmodifiable(original) : null,
    );
  }
  const PreparedStressHistory._(this.entries, this._sourceOrder);
  final List<({Timestamp time, double? score})> entries;
  final List<({Timestamp time, double? score})>? _sourceOrder;

  double? at(DateTime cutoff) {
    // Dart sort is not stable for ties. For the rare duplicate-timestamp case,
    // retain the legacy filter-then-sort ordering rather than choose a new tie.
    if (_sourceOrder != null) {
      final matching =
          _sourceOrder
              .where(
                (e) =>
                    !e.time.toDate().isAfter(cutoff) &&
                    cutoff.difference(e.time.toDate()) <=
                        const Duration(hours: 2),
              )
              .toList()
            ..sort((a, b) => b.time.compareTo(a.time));
      return matching.firstOrNull?.score;
    }
    var low = 0;
    var high = entries.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (entries[mid].time.toDate().isAfter(cutoff)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low == entries.length ||
        cutoff.difference(entries[low].time.toDate()) >
            const Duration(hours: 2)) {
      return null;
    }
    return entries[low].score;
  }

  @override
  bool operator ==(Object other) =>
      other is PreparedStressHistory &&
      const ListEquality().equals(entries, other.entries) &&
      const ListEquality().equals(_sourceOrder, other._sourceOrder);
  @override
  int get hashCode => Object.hash(
    const ListEquality().hash(entries),
    const ListEquality().hash(_sourceOrder),
  );
}

/// Field-level reads avoid doc.data(), which recursively decodes every metric.
/// Firestore still delivers the full document over the platform channel.
Map<String, dynamic> projectScreenFields(
  MetricFieldReader read,
  MetricsProjection projection, {
  required bool isToday,
}) {
  final fields = switch (projection) {
    MetricsProjection.homeToday => const {
      'stress': ['current', 'avg', 'computedAt'],
      'hrv': ['stressScore'],
      'sleep': ['avg', 'source'],
      'steps': ['sum'],
      'active_calories': ['sum'],
      'exercise_time': ['sum'],
      'mood': ['avg', 'label'],
      'wellness': ['avg'],
    },
    MetricsProjection.homeHistory => const {
      'stress': ['anchor', 'current', 'avg'],
    },
    MetricsProjection.dailyBrief => const {
      'sleep': ['avg'],
      'stress': ['current', 'avg', 'algorithm_version', 'computedAt'],
      'hrv': ['stressScore'],
    },
    MetricsProjection.activity => throw ArgumentError(
      'Use activity projection',
    ),
  };
  final result = PerformanceTrace.measure(
    'metrics.extract.${projection.name}',
    () {
      return <String, dynamic>{
        for (final metric in fields.entries)
          metric.key: Map<String, dynamic>.unmodifiable({
            for (final field in metric.value)
              field: read('${metric.key}.$field'),
          }),
      };
    },
  );
  final sleep = result['sleep'] as Map?;
  if (sleep != null && sleep.values.every((v) => v == null)) {
    result.remove('sleep');
  }
  if (projection == MetricsProjection.homeToday) {
    // Driver lists are small. Copy only the leaf fields that their formatter
    // consumes, never unrelated nested data supplied in a driver object.
    final raw = read('stress.top_drivers');
    const keys = [
      'label',
      'name',
      'signal',
      'metric',
      'driver',
      'feature',
      'status',
      'direction',
      'effect',
      'detail',
      'reason',
      'percentage',
      'percent',
      'weight',
      'contribution',
      'influence',
      'reason_code',
    ];
    result['stress'] = Map<String, dynamic>.unmodifiable({
      ...result['stress'] as Map<String, dynamic>,
      'top_drivers': raw is List
          ? List<Object?>.unmodifiable(
              raw.map(
                (item) => item is Map
                    ? Map<String, dynamic>.unmodifiable({
                        for (final key in keys)
                          if (item[key] is String || item[key] is num)
                            key: item[key],
                      })
                    : item is String
                    ? item
                    : null,
              ),
            )
          : null,
    });
  }
  if (projection == MetricsProjection.dailyBrief && !isToday) {
    final raw = PerformanceTrace.measure(
      'metrics.extract.stressHistory',
      () => read('stress.entries'),
    );
    result[preparedStressKey] = PerformanceTrace.measure(
      'metrics.prepare.stressHistory',
      () => PreparedStressHistory(raw),
    );
  }
  return Map.unmodifiable(result);
}

PreparedHeartRate projectHeartRate(MetricFieldReader read, String dayKey) {
  final data = PerformanceTrace.measure('metrics.extract.heartRate', () {
    Map<String, dynamic>? metric(String path) {
      final source = read('$path.source');
      final entries = read('$path.entries');
      final avg = read('$path.avg');
      final last = read('$path.lastReadingAt');
      final synced = read('$path.syncedAt');
      if (source == null &&
          entries == null &&
          avg == null &&
          last == null &&
          synced == null) {
        // An explicitly empty dedicated map also suppresses the legacy copy.
        // Only check the parent after ruling out its known histories.
        return read(path) is Map ? <String, dynamic>{} : null;
      }
      return {
        'source': source,
        'entries': entries,
        'avg': avg,
        'lastReadingAt': last,
        'syncedAt': synced,
      };
    }

    return <String, dynamic>{
      'heart_rate': metric('heart_rate'),
      'heart_rate_scan': metric('heart_rate_scan'),
      'heart_rate_sources': {
        for (final source in [
          'apple_health',
          'whoop_ble',
          'fitbit_ble',
          'wearable_ble',
        ])
          source: metric('heart_rate_sources.$source'),
      },
    };
  });
  return PerformanceTrace.measure('metrics.prepare.heartRate', () {
    final readings = mergedHeartRateHistory(
      data,
      fallbackDate: DateTime.tryParse(dayKey) ?? DateTime.now(),
    );
    HeartRateHistoryReading? latestBle;
    for (final reading in readings) {
      if (const [
        'whoop_ble',
        'fitbit_ble',
        'wearable_ble',
      ].contains(reading.source)) {
        latestBle = reading;
      }
    }
    return PreparedHeartRate(readings.lastOrNull, latestBle);
  });
}
