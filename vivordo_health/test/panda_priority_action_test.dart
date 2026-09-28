import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/panda_priority_action.dart';
import 'package:vivordo_health/src/services/panda_prompts.dart';
import 'package:vivordo_health/src/utils/priority_reminder.dart';

void main() {
  test('October bill reminder accepts a date with an optional time', () {
    for (final time in [null, '2026-10-01T09:00']) {
      final reply = PandaPrompts.parseTurnReply(
        jsonEncode({
          'intent': 'priority_action',
          'message': 'Please confirm.',
          'priority_action': {
            'operation': 'create',
            'title': 'Pay internet bill',
            'date': '2026-10-01',
            'reminder_at': ?time,
          },
        }),
      );
      expect(reply.intent, PandaIntent.priorityAction);
      final action = PandaPriorityAction(reply.priorityAction!);
      expect(action.title, 'Pay internet bill');
      expect(action.date, DateTime(2026, 10, 1));
      expect(action.scheduledAt, isNull);
      final reminder = action.reminderAt;
      expect(
        priorityReminderTime(
          start: action.scheduledAt,
          priorityDate: action.date,
          reminderTimeMinutes: reminder == null
              ? null
              : reminder.hour * 60 + reminder.minute,
          minutesBefore: 0,
          allDay: false,
          completed: false,
          now: DateTime(2026, 9, 28),
        ),
        time == null ? null : DateTime(2026, 10, 1, 9),
      );
    }
  });

  test(
    'reminder instructions make time optional and preserve supplied dates',
    () {
      final prompt = PandaPrompts.buildDialoguePrompt(
        userMessage: 'remind me to pay internet bill on Oct 1',
        conversationHistory: const [],
        spikeContext: const [],
        isOnPredefinedPath: false,
        isInDigression: true,
        digressionTurnCount: 0,
      );
      expect(prompt, contains(PandaPrompts.reminderInstructions));
      expect(prompt, contains('never ask for a time or invent one'));
      expect(prompt, contains('omit scheduled_at and reminder_at'));
      expect(prompt, contains('reminder_at YYYY-10-01T09:00'));
      expect(prompt, contains('Oct 1 = October 1'));
    },
  );

  test('priority intent is parsed independently of calendar actions', () {
    final reply = PandaPrompts.parseTurnReply(
      jsonEncode({
        'intent': 'priority_action',
        'message': 'Please confirm.',
        'priority_action': {
          'operation': 'create',
          'title': 'Call Sam',
          'reminder_at': '2026-10-01T14:00',
        },
      }),
    );
    expect(reply.intent, PandaIntent.priorityAction);
    expect(reply.calendarAction, isNull);
    final action = PandaPriorityAction(reply.priorityAction!);
    expect(action.reminderAt, DateTime(2026, 10, 1, 14));
    expect(action.scheduledAt, isNull);
  });
  test('untimed priority and partial edits preserve omitted fields', () {
    expect(
      PandaPriorityAction({'operation': 'create', 'title': 'Read'}).date,
      isNull,
    );
    final edit = PandaPriorityAction({
      'operation': 'update',
      'target_title': 'Read',
      'title': 'Read book',
    });
    expect(edit.date, isNull);
    expect(edit.reminderAt, isNull);
  });
  test('delete requires an explicit target', () {
    expect(
      () => PandaPriorityAction({'operation': 'delete'}),
      throwsFormatException,
    );
    expect(
      PandaPriorityAction({
        'operation': 'delete',
        'target_title': 'Read',
        'target_date': '2026-10-01',
      }).targetDate,
      DateTime(2026, 10, 1),
    );
  });
  test(
    'invalid dates, times, cross-day reminders and extra fields are rejected',
    () {
      for (final field in [
        {'date': '2026-02-30'},
        {'scheduled_at': '2026-10-01T25:00'},
        {'reminder_at': '2026-10-01T14:00Z'},
        {'date': '2026-10-02', 'reminder_at': '2026-10-01T14:00'},
        {'scheduled_at': '2026-10-01T13:00', 'reminder_at': '2026-10-01T14:00'},
        {'recurrence': 'daily'},
        {'reference': 'users/someone-else/items/1'},
      ]) {
        expect(
          () => PandaPriorityAction({
            'operation': 'create',
            'title': 'Read',
            ...field,
          }),
          throwsFormatException,
        );
      }
    },
  );
}
