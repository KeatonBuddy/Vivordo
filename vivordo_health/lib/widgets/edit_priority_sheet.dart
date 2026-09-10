import 'package:flutter/material.dart';
import '../src/services/daily_priority_service.dart';
import 'add_priority_sheet.dart';

Future<PriorityDraft?> showEditPrioritySheet(
  BuildContext context,
  DailyPriority priority,
) {
  final start = priority.sourceStart;
  final date = priority.date ?? start ?? DateTime.now();
  return showPriorityEditor(
    context,
    PriorityDraft(
      title: priority.title,
      date: DateUtils.dateOnly(date),
      time: start == null || priority.isAllDay
          ? null
          : TimeOfDay.fromDateTime(start),
      addToCalendar: false,
      repeat: PriorityRepeat.once,
      selectedWeekdays: {date.weekday},
      repeatEnd: null,
      reminderMinutes: priority.reminderMinutes,
      reminderTimeMinutes: priority.reminderTimeMinutes,
      completed: priority.completed,
    ),
    occurrenceOnly: priority.source != 'manual',
  );
}
