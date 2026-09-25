import 'heart_rate_history.dart';
import 'latest_heart_rate.dart';
import 'screen_metric_projection.dart';
import 'performance_trace.dart';

/// Number of calendar days of metric history Home keeps live, counting today.
const int kHomeMetricsWindowDays = 90;

/// One `metrics_daily` document reduced to what Home derives values from.
class MetricDayEntry {
  const MetricDayEntry({required this.dayKey, required this.data});

  /// The document id, expected to be a `YYYY-MM-DD` local day key.
  final String dayKey;
  final Map<String, dynamic> data;
}

/// Values Home derives from the metrics-history snapshot.
class HomeMetricsSummary {
  const HomeMetricsSummary({
    this.latestHeartRate,
    this.stressAnchor,
    this.sevenDayStressAverage,
  });

  /// Newest heart-rate reading in the window, or null when the window holds
  /// none. Never substituted with a placeholder value.
  final LatestHeartRateReading? latestHeartRate;

  /// Most recent stress anchor in the window, or null when the window holds
  /// none.
  final double? stressAnchor;

  /// Mean stress across the seven days before today, or null when none of
  /// those days carry a stress value.
  final double? sevenDayStressAverage;
}

/// How long until the next local day begins, plus a second of slack so a
/// timer scheduled with it never fires a hair before the date actually
/// changes.
///
/// Calendar arithmetic, so the wait stays correct across a daylight saving
/// change: on a 23- or 25-hour day the gap to midnight is not 24 hours minus
/// the time of day.
Duration durationUntilNextLocalDay(
  DateTime now, {
  Duration slack = const Duration(seconds: 1),
}) {
  final nextDay = DateTime(now.year, now.month, now.day + 1);
  return nextDay.difference(now) + slack;
}

/// Inclusive lower bound for Home's metrics-history query: the day key
/// [kHomeMetricsWindowDays] calendar days back, counting [now] as day one.
String homeMetricsWindowStartKey(
  DateTime now, {
  int days = kHomeMetricsWindowDays,
}) {
  // Calendar arithmetic rather than Duration subtraction: a fixed number of
  // 24h spans lands on the previous day when the window crosses a daylight
  // saving change, which would silently shift the query bound.
  final start = DateTime(now.year, now.month, now.day - (days - 1));
  return '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';
}

/// Derives Home's fallback values from [days], in any order.
///
/// Ordering is established here rather than assumed from the query. Both the
/// latest-reading and anchor lookups walk newest to oldest and take the first
/// match, so borrowing the query's ordering would silently invert them if that
/// query ever changed. Sorting costs one pass per snapshot, not per rebuild,
/// because the caller caches the result.
HomeMetricsSummary summarizeHomeMetrics({
  required List<MetricDayEntry> days,
  required DateTime now,
}) {
  final newestFirst = [...days]..sort((a, b) => b.dayKey.compareTo(a.dayKey));
  return HomeMetricsSummary(
    latestHeartRate: _latestHeartRate(newestFirst, now),
    stressAnchor: _latestStressAnchor(newestFirst),
    sevenDayStressAverage: _sevenDayStressAverage(newestFirst, now),
  );
}

bool _isLiveBleSource(String? source) =>
    source == 'whoop_ble' || source == 'fitbit_ble' || source == 'wearable_ble';

/// The most recent heart rate on record, from any source.
///
/// Built on [mergedHeartRateHistory] — the same resolution the detail,
/// dashboard, sleep and hourly-insight screens use — so Home agrees with the
/// rest of the app about what the latest reading is. A wearable sample stays
/// visible however long ago it was taken; only a *live* strap gets to override
/// a later sample from another source, because Apple Health can backfill
/// samples whose timestamps land ahead of the strap that is still on the wrist.
LatestHeartRateReading? _latestHeartRate(
  List<MetricDayEntry> newestFirst,
  DateTime now,
) {
  for (final entry in newestFirst) {
    final prepared = entry.data[preparedHeartKey];
    if (prepared is PreparedHeartRate) {
      final reading = prepared.at(now);
      if (reading != null) return reading;
      continue;
    }
    final readings = mergedHeartRateHistory(
      entry.data,
      fallbackDate: DateTime.tryParse(entry.dayKey) ?? now,
    );
    if (readings.isEmpty) continue;

    final live = readings
        .where(
          (reading) =>
              _isLiveBleSource(reading.source) &&
              now.difference(reading.timestamp) <= const Duration(minutes: 5),
        )
        .toList(growable: false);

    final chosen = (live.isEmpty ? readings : live).reduce(
      (a, b) => b.timestamp.isAfter(a.timestamp) ? b : a,
    );
    return LatestHeartRateReading(
      bpm: chosen.bpm.round(),
      timestamp: chosen.timestamp,
      source: chosen.source,
    );
  }
  return null;
}

/// The personalized value a new stress day should open at while the first
/// reading of the day is still being computed.
double? _latestStressAnchor(List<MetricDayEntry> newestFirst) {
  for (final entry in newestFirst) {
    final stress = entry.data['stress'] as Map?;
    if (stress == null) continue;

    final anchor = stress['anchor'];
    if (anchor is num) return anchor.toDouble();

    final current = stress['current'];
    if (current is num) return current.toDouble();

    final average = stress['avg'];
    if (average is num) return average.toDouble();
  }
  return null;
}

double? _sevenDayStressAverage(List<MetricDayEntry> entries, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final oldest = today.subtract(const Duration(days: 7));
  final values = <double>[];
  for (final entry in entries) {
    final date = DateTime.tryParse(entry.dayKey);
    if (date == null || date.isBefore(oldest) || !date.isBefore(today)) {
      continue;
    }
    final stress = entry.data['stress'] as Map?;
    final value =
        (stress?['avg'] as num?)?.toDouble() ??
        (stress?['current'] as num?)?.toDouble();
    if (value != null) values.add(value);
  }
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

/// Holds the last [HomeMetricsSummary] so unrelated rebuilds reuse it instead
/// of re-deriving from the whole window.
///
/// The cache is keyed on the identity of the snapshot the rows came from, the
/// local day, and the signed-in user — a new snapshot, a day rollover, or an
/// account switch all invalidate it.
class HomeMetricsSummaryCache {
  Object? _snapshotKey;
  String? _dayKey;
  String? _uid;
  HomeMetricsSummary? _summary;
  DateTime? _computedAt;
  DateTime? _liveReadingExpiresAt;

  /// Number of times a summary was actually derived. Test-only signal.
  int get computeCount => _computeCount;
  int _computeCount = 0;

  HomeMetricsSummary summarize({
    required Object? snapshotKey,
    required String dayKey,
    required String? uid,
    required DateTime now,
    required List<MetricDayEntry> Function() days,
  }) {
    final cached = _summary;
    if (cached != null &&
        identical(_snapshotKey, snapshotKey) &&
        _dayKey == dayKey &&
        _uid == uid &&
        !now.isBefore(_computedAt!) &&
        (_liveReadingExpiresAt == null ||
            !now.isAfter(_liveReadingExpiresAt!))) {
      return cached;
    }

    _computeCount++;
    final summary = PerformanceTrace.measure(
      'metrics.summary.homeHistory',
      () => summarizeHomeMetrics(days: days(), now: now),
    );
    _snapshotKey = snapshotKey;
    _dayKey = dayKey;
    _uid = uid;
    _summary = summary;
    _computedAt = now;
    // Replaying unchanged repository data after a hidden interval must not
    // keep an expired BLE reading ahead of a newer Apple Health reading.
    final reading = summary.latestHeartRate;
    final expiresAt = reading?.timestamp?.add(const Duration(minutes: 5));
    _liveReadingExpiresAt =
        reading != null &&
            expiresAt != null &&
            _isLiveBleSource(reading.source) &&
            !now.isAfter(expiresAt)
        ? expiresAt
        : null;
    return summary;
  }
}
