DateTime? priorityReminderTime({
  required DateTime? start,
  required int minutesBefore,
  required bool completed,
  required bool allDay,
  required DateTime now,
  DateTime? priorityDate,
  int? reminderTimeMinutes,
}) {
  if (completed) return null;
  if (start == null || allDay) {
    if (priorityDate == null ||
        reminderTimeMinutes == null ||
        reminderTimeMinutes < 0 ||
        reminderTimeMinutes >= 1440)
      return null;
    final time = DateTime(
      priorityDate.year,
      priorityDate.month,
      priorityDate.day,
      reminderTimeMinutes ~/ 60,
      reminderTimeMinutes % 60,
    );
    return time.isAfter(now) ? time : null;
  }
  final time = start.subtract(Duration(minutes: minutesBefore));
  return time.isAfter(now) ? time : null;
}

// Stable across launches; keep priority IDs separate from other reminders.
int priorityNotificationId(String path) {
  var hash = 2166136261;
  for (final unit in path.codeUnits) {
    hash = ((hash ^ unit) * 16777619) & 0x3fffffff;
  }
  return 10000 + hash;
}
