import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'daily_brief_analysis.dart';
import 'daily_outlook_score.dart';
import 'home_metrics_summary.dart';

/// A decoded snapshot retained between clock ticks. Firestore documents are
/// decoded once on arrival, never from a widget builder.
class DailyBriefMetrics {
  DailyBriefMetrics(this.documents, {this.isFromCache = false});
  final List<MetricDayEntry> documents;
  final bool isFromCache;
  DateTime? _minute;
  DailyBriefMetricsSummary? _summary;

  DailyBriefMetricsSummary summarize(DateTime now) {
    final minute = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    if (_minute == minute && _summary != null) return _summary!;
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final todayDocuments = documents.where((d) => d.dayKey == todayKey);
    final data = todayDocuments.isEmpty ? null : todayDocuments.first.data;
    final previous = documents.where((d) => d.dayKey.compareTo(todayKey) < 0);
    final usualSleep = sleepBaseline(
      previous.map(
        (d) => ((d.data['sleep'] as Map?)?['avg'] as num?)?.toDouble() ?? 0,
      ),
    );
    final sleep = ((data?['sleep'] as Map?)?['avg'] as num?)?.toDouble();
    final stressMap = data?['stress'] as Map?;
    final hrvMap = data?['hrv'] as Map?;
    final stress =
        (stressMap?['current'] as num?)?.toDouble() ??
        (stressMap?['avg'] as num?)?.toDouble() ??
        (hrvMap?['stressScore'] as num?)?.toDouble();
    final latestHeartRate = data == null
        ? null
        : summarizeHomeMetrics(
            days: [MetricDayEntry(dayKey: todayKey, data: data)],
            now: now,
          ).latestHeartRate;
    final capacity = calculateDailyCapacity(
      sleepHours: sleep,
      stressScore: stress,
    );
    final computedAt = stressMap?['computedAt'];
    final stressTime = computedAt is Timestamp ? computedAt.toDate() : null;
    final healthTime = latestHeartRate?.timestamp;
    final stale =
        sleep == null ||
        sleep <= 0 ||
        stressTime == null ||
        stressTime.isAfter(now) ||
        now.difference(stressTime) > const Duration(hours: 2);
    final historyCapacity = <double>[];
    for (final document in previous) {
      final day = document.data;
      if (stress != null &&
          (stressMap?['algorithm_version'] == null ||
              (day['stress'] as Map?)?['algorithm_version'] !=
                  stressMap?['algorithm_version'])) {
        continue;
      }
      final pastSleep = ((day['sleep'] as Map?)?['avg'] as num?)?.toDouble();
      final historicalDay = DateTime.tryParse(document.dayKey);
      if (historicalDay == null) continue;
      final cutoff = DateTime(
        historicalDay.year,
        historicalDay.month,
        historicalDay.day,
        now.hour,
        now.minute,
      );
      final entries =
          ((day['stress'] as Map?)?['entries'] as List? ?? [])
              .whereType<Map>()
              .where((entry) {
                final timestamp = entry['timestamp'];
                return timestamp is Timestamp &&
                    !timestamp.toDate().isAfter(cutoff) &&
                    cutoff.difference(timestamp.toDate()) <=
                        const Duration(hours: 2);
              })
              .toList()
            ..sort(
              (a, b) => (b['timestamp'] as Timestamp).compareTo(
                a['timestamp'] as Timestamp,
              ),
            );
      final pastStress = entries.isEmpty
          ? null
          : (entries.first['score'] as num?)?.toDouble();
      if ((pastSleep != null) != (sleep != null) ||
          (pastStress != null) != (stress != null)) {
        continue;
      }
      final value = calculateDailyCapacity(
        sleepHours: pastSleep,
        stressScore: pastStress,
      ).score;
      if (value != null) historyCapacity.add(value.toDouble());
    }
    historyCapacity.sort();
    final usualCapacity = historyCapacity.length < 7 || stale
        ? null
        : historyCapacity.length.isOdd
        ? historyCapacity[historyCapacity.length ~/ 2]
        : (historyCapacity[historyCapacity.length ~/ 2 - 1] +
                  historyCapacity[historyCapacity.length ~/ 2]) /
              2;
    final capacityNote = usualCapacity == null || capacity.score == null
        ? 'Building your capacity baseline'
        : (capacity.score! - usualCapacity).abs() < 10
        ? 'Near your recent capacity estimate'
        : capacity.score! < usualCapacity
        ? 'Below your recent capacity estimate'
        : 'Above your recent capacity estimate';

    _minute = minute;
    return _summary = DailyBriefMetricsSummary(
      sleep: sleep,
      usualSleep: usualSleep,
      capacity: capacity,
      capacityNote: capacityNote,
      stale: stale,
      stressTime: stressTime,
      healthTime: healthTime,
      isFromCache: isFromCache,
      priorNights: previous
          .where((d) => ((d.data['sleep'] as Map?)?['avg'] as num? ?? 0) > 0)
          .length,
    );
  }
}

class DailyBriefMetricsSummary {
  const DailyBriefMetricsSummary({
    required this.sleep,
    required this.usualSleep,
    required this.capacity,
    required this.capacityNote,
    required this.stale,
    required this.stressTime,
    required this.healthTime,
    required this.isFromCache,
    required this.priorNights,
  });
  final double? sleep;
  final double? usualSleep;
  final DailyCapacityResult capacity;
  final String capacityNote;
  final bool stale;
  final DateTime? stressTime;
  final DateTime? healthTime;
  final bool isFromCache;
  final int priorNights;
}
