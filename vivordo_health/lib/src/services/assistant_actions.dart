import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';

import '../../widgets/apple_ui.dart';

import 'calendar_service.dart';
import 'daily_priority_service.dart';
import 'panda_priority_action.dart';
import 'panda_types.dart';

// Applying the changes Vivordo AI proposes. The server has already checked
// them (functions/assistant.js); these re-check against the live data and ask
// the user to confirm before anything changes.

/// Reviews and applies one priority change proposed by Vivordo AI: the same
/// checks and confirmation dialog the old chat used. Returns what to tell the
/// user (saved, cancelled, or why it failed); never throws.
Future<String> applyPriorityAction(
  BuildContext context,
  Map<String, dynamic>? raw,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  try {
    if (uid == null || raw == null) {
      throw StateError(
        'Please specify the priority, date, and change you want.',
      );
    }
    final action = PandaPriorityAction(raw);
    DailyPriority? existing;
    if (action.operation != 'create') {
      final matches = await DailyPriorityService.findByTitle(
        action.targetTitle!,
        day: action.targetDate,
      );
      if (matches.length != 1) {
        throw StateError(
          matches.isEmpty
              ? 'I could not find that priority. Please give its exact title and original date.'
              : 'Several priorities match. Please specify the original date.',
        );
      }
      existing = matches.single;
      if (action.operation == 'update' && existing.sourceEventKey != null) {
        throw StateError(
          'Please edit this calendar-linked priority in My Day so its calendar event stays in sync.',
        );
      }
    }
    final title = action.operation == 'delete'
        ? existing!.title
        : action.title ?? existing!.title;
    final date =
        action.date ??
        action.scheduledAt ??
        action.reminderAt ??
        existing?.date ??
        DateTime.now();
    final oldTime = existing?.sourceStart;
    final scheduled =
        action.scheduledAt ??
        (oldTime == null
            ? null
            : DateTime(
                date.year,
                date.month,
                date.day,
                oldTime.hour,
                oldTime.minute,
              ));
    final reminder = action.reminderAt;
    if (reminder != null &&
        (!reminder.isAfter(DateTime.now()) ||
            (scheduled != null && reminder.isAfter(scheduled)))) {
      throw StateError(
        'Choose a future reminder at or before the priority’s scheduled time.',
      );
    }
    final minutesBefore = reminder != null && scheduled != null
        ? scheduled.difference(reminder).inMinutes
        : existing?.reminderMinutes ?? 0;
    final reminderClock = reminder != null && scheduled == null
        ? reminder.hour * 60 + reminder.minute
        : existing?.reminderTimeMinutes;
    if (!context.mounted) return 'Cancelled — no priority changes made.';
    final verb = action.operation == 'create'
        ? 'Create'
        : action.operation == 'update'
        ? 'Edit'
        : 'Delete';
    final confirmed = await confirmAction(
      context,
      title: '$verb priority?',
      message: [
        title,
        DateFormat('EEE, MMM d, yyyy').format(date),
        scheduled == null
            ? 'No scheduled time'
            : 'Scheduled: ${DateFormat('h:mm a').format(scheduled)}',
        if (reminder != null)
          'Remind: ${DateFormat('MMM d, h:mm a').format(reminder)}',
        if (reminder == null &&
            scheduled != null &&
            action.operation != 'delete')
          'Reminder: $minutesBefore minutes before scheduled time',
        if (reminder == null &&
            scheduled == null &&
            reminderClock != null &&
            action.operation != 'delete')
          'Reminder: ${DateFormat('h:mm a').format(DateTime(date.year, date.month, date.day, reminderClock ~/ 60, reminderClock % 60))}',
        if (existing?.templateId != null)
          'This occurrence only; future repetitions stay unchanged.',
        if (existing?.sourceEventKey != null)
          'The calendar event will not be deleted.',
        if (action.operation != 'delete')
          reminder == null && scheduled == null && reminderClock == null
              ? 'No timed reminder notification'
              : 'Notifications depend on your device notification permissions.',
      ].join('\n\n'),
      confirmLabel: action.operation == 'update' ? 'Save' : verb,
      destructive: action.operation == 'delete',
    );
    if (!confirmed) return 'Cancelled — no priority changes made.';
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Your account changed. Please try again.');
    }
    if (reminder != null && !reminder.isAfter(DateTime.now())) {
      throw StateError(
        'That reminder time has passed. Please choose a new time.',
      );
    }
    if (existing != null) {
      final latest = await DailyPriorityService.findByTitle(
        existing.title,
        day: existing.date,
      );
      final same = latest.where(
        (p) => p.reference.path == existing!.reference.path,
      );
      if (same.length != 1 ||
          same.single.sourceStart != existing.sourceStart ||
          same.single.completed != existing.completed ||
          same.single.reminderMinutes != existing.reminderMinutes ||
          same.single.reminderTimeMinutes != existing.reminderTimeMinutes) {
        throw StateError(
          'That priority changed. Please ask again to review its latest details.',
        );
      }
    }
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Your account changed. Please try again.');
    }
    if (action.operation == 'delete') {
      await DailyPriorityService.delete(existing!);
    } else if (existing == null) {
      final saved = await DailyPriorityService.createManual(
        title: title,
        date: date,
        scheduledAt: scheduled,
        reminderMinutes: minutesBefore,
        reminderTimeMinutes: reminderClock,
      );
      if (saved == null) throw StateError('Could not save the priority.');
    } else {
      final saved = await DailyPriorityService.editPriority(
        existing,
        title: title,
        date: date,
        scheduledAt: scheduled,
        completed: existing.completed,
        reminderMinutes: minutesBefore,
        reminderTimeMinutes: reminderClock,
      );
      if (saved == null) throw StateError('Could not save the priority.');
    }
    return action.operation == 'delete'
        ? 'Priority removed.'
        : 'Priority saved in My Day.${reminder != null ? ' Reminder requested; notifications must be enabled on your device.' : ''}';
  } catch (error) {
    return error.toString().replaceFirst(
      RegExp(r'^(Bad state|FormatException): '),
      '',
    );
  }
}

/// One-line description of a proposed calendar change.
String calendarActionSummary(PandaCalendarAction action) =>
    switch (action.operation) {
      PandaCalendarOperation.create => 'Create “${action.title}”',
      PandaCalendarOperation.update => 'Edit “${action.targetTitle}”',
      PandaCalendarOperation.delete => 'Delete “${action.targetTitle}”',
    };

/// Applies a confirmed calendar change; throws [StateError] with a message
/// for the user when it can't.
Future<void> applyCalendarAction(PandaCalendarAction action) async {
  if (action.operation == PandaCalendarOperation.create) {
    await CalendarService.createEvent(
      title: action.title!,
      start: action.start!,
      end: action.end!,
      recurrence: action.recurrence,
    );
    return;
  }
  final event = await _findCalendarEvent(action);
  if (action.operation == PandaCalendarOperation.delete) {
    await CalendarService.deleteEvent(event);
  } else {
    await CalendarService.updateEvent(
      event,
      title: action.title,
      start: action.start,
      end: action.end,
      recurrence: action.recurrence == 'none' ? null : action.recurrence,
    );
  }
}

Future<gcal.Event> _findCalendarEvent(PandaCalendarAction action) async {
  final anchor = action.start?.toLocal();
  final from = anchor == null
      ? DateTime.now().subtract(const Duration(days: 1))
      : DateTime(anchor.year, anchor.month, anchor.day);
  final to = anchor == null
      ? DateTime.now().add(const Duration(days: 60))
      : from.add(const Duration(days: 1));
  final events = await CalendarService.getEventsBetween(from, to);
  String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  final target = normalize(action.targetTitle ?? '');
  final matches = events
      .where((event) => normalize(event.summary ?? '') == target)
      .toList();
  if (matches.isEmpty) {
    throw StateError(
      'I could not find “${action.targetTitle}” in that date range.',
    );
  }
  if (matches.length > 1) {
    throw StateError(
      'More than one event matches “${action.targetTitle}”. Include its date or time.',
    );
  }
  return matches.single;
}
