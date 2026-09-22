import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'heart_rate_history.dart';

class HeartActivityWindow {
  const HeartActivityWindow(this.start, this.end);
  final DateTime start;
  final DateTime end;
  bool contains(DateTime time) => !time.isBefore(start) && !time.isAfter(end);
}

class HourlyHeartInsight {
  const HourlyHeartInsight(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

/// Descriptive wellness heuristics, not medical thresholds or diagnosis.
/// Historical minutes are weighted equally per day to avoid dense workout
/// recordings dominating a personal comparison. No daily averages are samples.
HourlyHeartInsight summarizeHeartHour({
  required DateTime now,
  required List<HeartRateHistoryReading> readings,
  required List<HeartActivityWindow> workouts,
  required List<HeartActivityWindow> sleep,
}) {
  final cutoff = now.subtract(const Duration(hours: 1));
  final byMinute = <int, HeartRateHistoryReading>{};
  for (final r in readings) {
    if (r.bpm.isFinite && r.bpm > 0 && !r.timestamp.isAfter(now)) {
      byMinute[r.timestamp.millisecondsSinceEpoch ~/ 60000] = r;
    }
  }
  final all = byMinute.values.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final hour = all.where((r) => !r.timestamp.isBefore(cutoff)).toList();
  if (hour.isEmpty)
    return const HourlyHeartInsight(
      'No recent heart-rate data',
      'No readings are available from the past hour.',
    );
  final quarters = hour
      .map((r) => r.timestamp.difference(cutoff).inMinutes ~/ 15)
      .toSet();
  if (hour.length < 12 ||
      quarters.length < 4 ||
      now.difference(hour.last.timestamp).inMinutes > 10) {
    return const HourlyHeartInsight(
      'Limited readings',
      'There aren’t enough recent readings to reliably summarize the past hour.',
    );
  }
  bool exercising(DateTime t) => workouts.any((w) => w.contains(t));
  bool asleep(DateTime t) => sleep.any((w) => w.contains(t));
  final days = <String, List<double>>{};
  final today = DateTime(now.year, now.month, now.day);
  for (final r in all) {
    final t = r.timestamp.toLocal();
    final distance = (t.hour - now.hour).abs();
    if (t.isBefore(today) &&
        !t.isBefore(today.subtract(const Duration(days: 28))) &&
        math.min(distance, 24 - distance) <= 2 &&
        !exercising(t) &&
        !asleep(t)) {
      days.putIfAbsent(DateFormat('yyyy-MM-dd').format(t), () => []).add(r.bpm);
    }
  }
  double percentile(List<double> values, double p) {
    final sorted = [...values]..sort();
    return sorted[((sorted.length - 1) * p).round()];
  }

  final reliableDays = days.values.where((v) => v.length >= 12).toList();
  if (reliableDays.length < 7) {
    final values = hour.map((r) => r.bpm).toList();
    return HourlyHeartInsight(
      'Your past hour',
      'Your recorded heart rate ranged from ${values.reduce(math.min).round()}–${values.reduce(math.max).round()} bpm. We’re still learning your usual range.',
    );
  }
  final lower = percentile(
    reliableDays.map((v) => percentile(v, .1)).toList(),
    .5,
  );
  final upper = percentile(
    reliableDays.map((v) => percentile(v, .9)).toList(),
    .5,
  );
  final center = percentile(
    reliableDays.map((v) => percentile(v, .5)).toList(),
    .5,
  );
  final spikeThreshold = math.max(upper + 10, center + 20);
  final spikes = <HeartRateHistoryReading>[];
  for (var i = 1; i < hour.length; i++) {
    final a = hour[i - 1], b = hour[i];
    if (a.bpm > spikeThreshold &&
        b.bpm > spikeThreshold &&
        b.timestamp.difference(a.timestamp).inMinutes <= 3 &&
        (spikes.isEmpty ||
            a.timestamp.difference(spikes.last.timestamp).inMinutes > 10))
      spikes.add(a);
  }
  final workoutSpikes = spikes.where((r) => exercising(r.timestamp)).toList();
  final otherSpikes = spikes.where((r) => !exercising(r.timestamp)).toList();
  final quiet = hour
      .where((r) => !exercising(r.timestamp) && !asleep(r.timestamp))
      .toList();
  if (quiet.length < 12) {
    return HourlyHeartInsight(
      'Activity over the past hour',
      workoutSpikes.isNotEmpty
          ? 'A heart-rate rise around ${DateFormat.jm().format(workoutSpikes.first.timestamp.toLocal())} coincided with your recorded workout.'
          : 'Much of the available data overlaps recorded sleep or exercise; there isn’t enough other data for a usual-range comparison.',
    );
  }
  final within =
      quiet.where((r) => r.bpm >= lower && r.bpm <= upper).length /
      quiet.length;
  final high = quiet.where((r) => r.bpm > upper).length / quiet.length;
  var title = within >= .7
      ? 'Steady over the past hour'
      : high >= .6
      ? 'Higher than usual'
      : 'Your past hour';
  var detail = within >= .7
      ? 'Your recorded heart rate stayed mostly within your usual range.'
      : high >= .6
      ? 'Most readings outside recorded exercise were above your usual range.'
      : 'Your readings varied compared with your usual range.';
  if (otherSpikes.isNotEmpty && high < .6) {
    title = within >= .7
        ? 'Mostly steady, with a brief rise'
        : 'Heart-rate rises';
    detail +=
        ' A rise was recorded around ${otherSpikes.take(2).map((r) => DateFormat.jm().format(r.timestamp.toLocal())).join(' and ')}.';
  }
  if (workoutSpikes.isNotEmpty)
    detail +=
        ' A rise around ${DateFormat.jm().format(workoutSpikes.first.timestamp.toLocal())} coincided with your recorded workout.';
  return HourlyHeartInsight(title, detail);
}
