import 'package:intl/intl.dart';

import '../services/daily_priority_service.dart';

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
