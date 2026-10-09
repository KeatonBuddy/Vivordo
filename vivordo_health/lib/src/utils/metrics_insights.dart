import 'day_key.dart';
import 'physical_health_view.dart';

enum MetricsInsightKind { sleep, energy, effort, afterHours, physical }

/// How an insight reads: worth a look, good news, or plain information.
enum MetricsInsightTone { concern, good, neutral }

class MetricsInsight {
  const MetricsInsight(this.kind, this.tone, this.text);

  final MetricsInsightKind kind;
  final MetricsInsightTone tone;
  final String text;
}

/// The Metrics screen's insights, from the `scores_daily` documents it
/// already streams for Physical Health (keyed by day). "This week" is the
/// last 7 days; "usual" is the 28 days before that. Concerns come first,
/// then the Physical Health win, then good news; at most [limit].
List<MetricsInsight> metricsInsights(
  Map<String, Map<String, dynamic>> days,
  DateTime today, {
  int limit = 3,
}) {
  final date = DateTime(today.year, today.month, today.day);
  final week = [for (var i = 0; i < 7; i++) localDayKey(_back(date, i))];
  final usual = [for (var i = 7; i < 35; i++) localDayKey(_back(date, i))];
  // Today's Effort is still growing, so Effort compares finished days.
  final finishedWeek = [
    for (var i = 1; i < 8; i++) localDayKey(_back(date, i)),
  ];
  final finishedUsual = [
    for (var i = 8; i < 36; i++) localDayKey(_back(date, i)),
  ];

  double? value(String day, String score, String field) =>
      ((days[day]?[score] as Map?)?[field] as num?)?.toDouble();
  List<double> values(List<String> keys, String score, String field) => [
    for (final day in keys) ?value(day, score, field),
  ];

  final concerns = <MetricsInsight>[];
  final good = <MetricsInsight>[];

  // Sleep against the person's own need (Capacity's 90-day median).
  final sleep = values(week, 'capacity', 'sleepHours');
  final need = [
    for (final day in week) ?value(day, 'capacity', 'sleepNeed'),
  ].firstOrNull;
  if (sleep.length >= 4 && need != null) {
    final average = _mean(sleep);
    final shortMinutes = ((need - average) * 60).round();
    if (shortMinutes >= 20) {
      concerns.add(
        MetricsInsight(
          MetricsInsightKind.sleep,
          MetricsInsightTone.concern,
          'Sleep averaged ${_hoursMinutes(average)} this week, '
          '$shortMinutes min under your need of ${_hoursMinutes(need)}.',
        ),
      );
    } else if (shortMinutes <= 0) {
      good.add(
        MetricsInsight(
          MetricsInsightKind.sleep,
          MetricsInsightTone.good,
          'Sleep averaged ${_hoursMinutes(average)} this week, '
          'meeting your need of ${_hoursMinutes(need)}.',
        ),
      );
    }
  }

  // Capacity this week against the weeks before.
  final energy = values(week, 'capacity', 'score');
  final usualEnergy = values(usual, 'capacity', 'score');
  if (energy.length >= 4 && usualEnergy.length >= 7) {
    final now = _mean(energy).round();
    final before = _mean(usualEnergy).round();
    if (now <= before - 5) {
      concerns.add(
        MetricsInsight(
          MetricsInsightKind.energy,
          MetricsInsightTone.concern,
          'Your energy is lower than usual: Capacity averaged $now this '
          'week, against your usual $before.',
        ),
      );
    } else if (now >= before + 5) {
      good.add(
        MetricsInsight(
          MetricsInsightKind.energy,
          MetricsInsightTone.good,
          'Your energy is up: Capacity averaged $now this week, against '
          'your usual $before.',
        ),
      );
    }
  }

  // Heavier days than usual.
  final effort = values(finishedWeek, 'effort', 'total');
  final usualEffort = values(finishedUsual, 'effort', 'total');
  if (effort.length >= 4 && usualEffort.length >= 7) {
    final now = _mean(effort);
    final before = _mean(usualEffort);
    if (now >= before * 1.25 && now - before >= 5) {
      concerns.add(
        MetricsInsight(
          MetricsInsightKind.effort,
          MetricsInsightTone.concern,
          'Your days have been heavier than usual: Effort averaged '
          '${now.round()} a day this week, against your usual '
          '${before.round()}.',
        ),
      );
    }
  }

  // Plans after the person's own wrap-up time.
  final afterHours = values(finishedWeek, 'effort', 'afterHoursMinutes');
  final afterHoursTotal = afterHours.fold<double>(0, (a, b) => a + b).round();
  if (afterHoursTotal >= 120) {
    concerns.add(
      MetricsInsight(
        MetricsInsightKind.afterHours,
        MetricsInsightTone.concern,
        'You had ${_hoursMinutes(afterHoursTotal / 60)} of plans after '
        'your wrap-up time this past week.',
      ),
    );
  }

  // Physical Health's easiest win, which it already works out.
  final physical = PhysicalHealthView.fromDays(days);
  final win = physical?.score == null ? null : physical!.insights.firstOrNull;
  final physicalInsights = [
    if (win != null)
      MetricsInsight(
        MetricsInsightKind.physical,
        win.startsWith('You\'re meeting')
            ? MetricsInsightTone.good
            : MetricsInsightTone.neutral,
        win,
      ),
  ];

  return [...concerns, ...physicalInsights, ...good].take(limit).toList();
}

DateTime _back(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day - days);

double _mean(List<double> values) =>
    values.reduce((a, b) => a + b) / values.length;

String _hoursMinutes(double hours) {
  final minutes = (hours * 60).round();
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}
