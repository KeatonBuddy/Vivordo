import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/daily_priority_service.dart';
import 'day_key.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The day [p] is due: the day it was planned for, else the day it was
/// saved on, else its start.
DateTime? priorityDueDay(DailyPriority p) {
  final planned = DateTime.tryParse(p.planning['plannedDay'] as String? ?? '');
  final due = planned ?? p.date ?? p.sourceStart;
  return due == null ? null : _day(due);
}

/// The day an open priority was due, when that is before [today]: it carried
/// over unfinished. Null when it isn't overdue.
DateTime? overdueSince(DailyPriority p, DateTime today) {
  if (p.completed) return null;
  final due = priorityDueDay(p);
  return due != null && due.isBefore(_day(today)) ? due : null;
}

/// "From yesterday", "From Mon" within the past week, else "From Sep 28".
String overdueLabel(DateTime since, DateTime today) {
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(since.year, since.month, since.day)).inDays;
  if (days <= 1) return 'From yesterday';
  if (days < 7) return 'From ${DateFormat('EEE').format(since)}';
  return 'From ${DateFormat('MMM d').format(since)}';
}

/// [p]'s length in minutes: its estimate, else its calendar time. Null
/// when neither is known.
int? priorityMinutes(DailyPriority p) {
  final estimate = (p.planning['minutes'] as num?)?.toInt();
  if (estimate != null && estimate > 0) return estimate;
  final start = p.sourceStart, end = p.sourceEnd;
  if (start == null || end == null || !end.isAfter(start) || p.isAllDay) {
    return null;
  }
  return end.difference(start).inMinutes;
}

/// "45 min", "1h", "1h 45m".
String formatPriorityMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Scheduled days done in a row, counting back from [today]. Today adds
/// once done; while still open it doesn't break the streak.
/// ponytail: looks back at most 400 days.
int habitStreak(
  Set<String> doneDays,
  bool Function(DateTime day) scheduled,
  DateTime today,
) {
  var streak = 0;
  for (var back = 0; back < 400; back++) {
    final day = DateTime(today.year, today.month, today.day - back);
    if (!scheduled(day)) continue;
    if (doneDays.contains(localDayKey(day))) {
      streak++;
    } else if (back > 0) {
      break;
    }
  }
  return streak;
}

/// An icon for a habit, picked from its title; null when nothing fits.
IconData? habitIcon(String title) {
  final t = title.toLowerCase();
  bool has(List<String> words) => words.any(t.contains);
  if (has(['water', 'drink', 'hydrat'])) return Icons.water_drop_outlined;
  if (has(['meditat', 'breath', 'mindful'])) return Icons.spa_outlined;
  if (has(['med', 'pill', 'vitamin', 'supplement', 'tablet'])) {
    return Icons.medication_outlined;
  }
  if (has(['run', 'jog'])) return Icons.directions_run_rounded;
  if (has(['walk', 'steps'])) return Icons.directions_walk_rounded;
  if (has(['stretch', 'yoga', 'mobility'])) {
    return Icons.self_improvement_rounded;
  }
  if (has(['read', 'book'])) return Icons.menu_book_outlined;
  if (has(['journal', 'write', 'gratitude'])) return Icons.edit_note_rounded;
  if (has(['gym', 'workout', 'lift', 'exercise'])) {
    return Icons.fitness_center_rounded;
  }
  if (has(['sleep', 'bed'])) return Icons.bedtime_outlined;
  if (has(['fruit', 'veg', 'eat', 'meal'])) return Icons.restaurant_outlined;
  return null;
}
