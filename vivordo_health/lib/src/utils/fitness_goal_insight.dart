import '../services/activity_goals_service.dart';

/// Compares recorded daily totals, never same-time-of-day activity.
String fitnessGoalInsight(
  Map<String, dynamic>? data,
  ActivityGoals goals, {
  required Map<String, Map<String, dynamic>> history,
  required DateTime now,
}) {
  num? total(Map<String, dynamic>? day, String key) {
    final entry = day?[key];
    final value = entry is Map ? entry['sum'] : null;
    return value is num && value.isFinite && value >= 0 ? value : null;
  }

  final today = DateTime(now.year, now.month, now.day);
  final start = DateTime(now.year, now.month, now.day - 14);
  final days = history.entries
      .where((entry) {
        final date = DateTime.tryParse(entry.key);
        return date != null && !date.isBefore(start) && date.isBefore(today);
      })
      .map((entry) => entry.value)
      .toList();
  final comparisons = <String, List<String>>{};
  final building = <String>[];
  final missing = <String>[];
  var reached = 0;
  for (final metric in [
    ('steps', 'steps', goals.steps),
    ('active_calories', 'active calories', goals.activeCalories),
    ('exercise_time', 'exercise minutes', goals.exerciseMinutes),
  ]) {
    final current = total(data, metric.$1);
    if (current == null) {
      missing.add(metric.$2);
      continue;
    }
    if (metric.$3 > 0 && current >= metric.$3) reached++;
    final values = days
        .map((day) => total(day, metric.$1))
        .whereType<num>()
        .toList();
    if (values.length < 7) {
      building.add(metric.$2);
      continue;
    }
    final average =
        values.fold<double>(0, (sum, value) => sum + value) / values.length;
    final description = average == 0
        ? current == 0
              ? 'match'
              : 'are above'
        : ((current - average) / average).abs() <= .1
        ? 'are close to'
        : current > average
        ? 'are above'
        : 'are below';
    (comparisons[description] ??= []).add(metric.$2);
  }
  String joinMetrics(List<String> metrics) => metrics.length < 3
      ? metrics.join(' and ')
      : '${metrics.take(metrics.length - 1).join(', ')}, and ${metrics.last}';
  return [
    for (final group in comparisons.entries)
      'Your ${joinMetrics(group.value)} ${group.key} your recent daily average.',
    if (building.isNotEmpty)
      'Building your average for ${building.join(', ')} (at least 7 recorded days needed).',
    if (missing.isNotEmpty) 'No data today for ${missing.join(', ')}.',
    if (reached == 3) 'You’ve also reached all three saved goals today.',
    if (missing.length < 3)
      'A quieter day is okay. Want help choosing activity that fits how you feel?'
    else
      'Sync a connected source to compare your activity.',
  ].join(' ');
}
