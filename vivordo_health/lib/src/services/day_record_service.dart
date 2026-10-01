import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../utils/day_key.dart';
import '../utils/day_wrap_up.dart';
import 'calendar_cognitive_load_service.dart';
import 'calendar_service.dart';
import 'daily_priority_service.dart';
import 'outlook_calendar_service.dart';

/// One rated calendar event for a day record.
typedef DayRecordEvent = ({
  CalendarCognitiveEvent event,
  CognitiveLoadScore score,
  String? key,
});

/// One priority for a day record. [eventKey] is the calendar event it was
/// created from, if any.
typedef DayRecordPriority = ({
  DateTime? start,
  DateTime? end,
  Object? effort,
  int? minutes,
  bool done,
  String? eventKey,
});

/// The day's items that Effort is calculated from (docs/scores.md §3), as
/// written to `users/{uid}/effort_inputs/{day}`. Times, ratings and
/// completion only: never titles, notes or IDs. Unknown events have a null
/// rating; the server prices them. A priority linked to one of the day's
/// events is left out, because the event already counts.
Map<String, Object?> buildDayRecord({
  required DateTime day,
  required int wrapUpMinutes,
  required bool calendarAvailable,
  required List<DayRecordEvent> events,
  required List<DayRecordPriority> priorities,
}) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = DateTime(day.year, day.month, day.day + 1);
  final counted =
      events
          .where(
            (e) =>
                e.event.contributesToSchedule &&
                e.event.start.isBefore(dayEnd) &&
                e.event.end.isAfter(dayStart),
          )
          .toList()
        ..sort((a, b) => a.event.start.compareTo(b.event.start));
  final eventKeys = {for (final e in counted) e.key};
  Object? effort(Object? value) =>
      const {'light', 'moderate', 'demanding'}.contains(value) ? value : null;
  return {
    'version': 1,
    'dayStart': Timestamp.fromDate(dayStart),
    'dayEnd': Timestamp.fromDate(dayEnd),
    'wrapUpAt': Timestamp.fromDate(
      dayStart.add(Duration(minutes: wrapUpMinutes)),
    ),
    'calendarAvailable': calendarAvailable,
    'events': [
      for (final e in counted)
        {
          'start': Timestamp.fromDate(e.event.start),
          'end': Timestamp.fromDate(e.event.end),
          'rating': e.score.isKnown ? e.score.score : null,
          'confidence': e.score.isKnown ? e.score.confidence : 0,
        },
    ],
    'priorities': [
      for (final p in priorities)
        if (p.eventKey == null || !eventKeys.contains(p.eventKey))
          {
            // Timed only when its slot is on this day; a timed priority
            // carried over from another day counts like an untimed one.
            if (p.start != null &&
                !p.start!.isBefore(dayStart) &&
                p.start!.isBefore(dayEnd)) ...{
              'start': Timestamp.fromDate(p.start!),
              'end': Timestamp.fromDate(p.end ?? p.start!),
            },
            'effort': effort(p.effort),
            'minutes': p.minutes,
            'done': p.done,
          },
    ],
  };
}

/// The UTC hour of 11 PM on [now]'s local day.
int nightlyPushUtcHour(DateTime now) =>
    DateTime(now.year, now.month, now.day, 23).toUtc().hour;

/// Writes the day records the server calculates Effort from. Called when
/// the app opens or resumes (today and yesterday, so a day is recorded even
/// if the app was last opened before it ended) and when a priority is
/// ticked off.
class DayRecordService {
  DayRecordService._();

  static final _written = <String, Map<String, Object?>>{};
  static const _equality = DeepCollectionEquality();

  /// Records the [days] days ending today. [forceRefresh] bypasses the
  /// calendar cache, after the schedule was just edited.
  static Future<void> sync({int days = 1, bool forceRefresh = false}) async {
    try {
      await _sync(days, forceRefresh);
    } catch (error) {
      // Best effort: the next open or tick tries again.
      debugPrint('Day record sync failed: $error');
    }
  }

  static Future<void> _sync(int days, bool forceRefresh) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(today.year, today.month, today.day - days + 1);
    final end = DateTime(today.year, today.month, today.day + 1);

    final google = await CalendarService.isSignedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false)
        .catchError((_) => false);
    final outlook = await OutlookCalendarService.isSignedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false)
        .catchError((_) => false);
    // A failed fetch throws, so a day is never recorded as falsely empty.
    final inputs = <(CalendarCognitiveEvent, String?)>[
      if (google)
        for (final event in await CalendarService.getEventsBetween(
          first,
          end,
          forceRefresh: forceRefresh,
        ).timeout(const Duration(seconds: 8)))
          if (_fromGoogle(event) case final input?)
            (input, 'google:${event.id}'),
      if (outlook)
        for (final event in await OutlookCalendarService.getEventsBetween(
          first,
          end,
          forceRefresh: forceRefresh,
        ).timeout(const Duration(seconds: 8)))
          (
            CalendarCognitiveEvent(
              id: 'outlook:${event.id}',
              title: event.subject,
              start: event.start.toLocal(),
              end: event.end.toLocal(),
              isAllDay: event.isAllDay,
            ),
            null,
          ),
    ];
    // Claude sorts what the local rules can't, with the user's AI consent.
    final scores = await CalendarCognitiveLoadService.scoreEvents([
      for (final (event, _) in inputs) event,
    ], allowAi: true);
    final events = [
      for (var i = 0; i < inputs.length; i++)
        (event: inputs[i].$1, score: scores[i], key: inputs[i].$2),
    ];

    final userDocument = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final preferences =
        (await userDocument.get()).data()?['preferences'] as Map?;
    final wrapUp = preferences?['dayWrapUpMinutes'];

    for (
      var day = first;
      day.isBefore(end);
      day = DateTime(day.year, day.month, day.day + 1)
    ) {
      final priorities = await DailyPriorityService.forDay(day);
      final record = buildDayRecord(
        day: day,
        wrapUpMinutes: wrapUp is int ? wrapUp : kDefaultDayWrapUpMinutes,
        calendarAvailable: google || outlook,
        events: events,
        priorities: [
          for (final p in priorities)
            (
              start: p.isAllDay ? null : p.sourceStart,
              end: p.isAllDay ? null : p.timelineEnd,
              effort: p.planning['effort'],
              minutes: (p.planning['minutes'] as num?)?.toInt(),
              done: p.completed,
              eventKey: p.sourceEventKey,
            ),
        ],
      );
      final target = userDocument
          .collection('effort_inputs')
          .doc(localDayKey(day));
      if (_equality.equals(_written[target.path], record)) continue;
      await target.set({...record, 'updatedAt': FieldValue.serverTimestamp()});
      _written[target.path] = record;
    }
  }

  static CalendarCognitiveEvent? _fromGoogle(gcal.Event event) {
    final start = event.start?.dateTime;
    final end = event.end?.dateTime;
    if (start == null || end == null) return null;
    return CalendarCognitiveEvent(
      id: 'google:${event.id}:${start.toUtc().toIso8601String()}',
      title: event.summary ?? '',
      description: event.description ?? '',
      start: start.toLocal(),
      end: end.toLocal(),
      attendeeCount: event.attendees?.length ?? 0,
      isOrganizer: event.organizer?.self == true,
      showsAsFree: event.transparency == 'transparent',
      isCancelled: event.status == 'cancelled',
      isDeclined:
          event.attendees?.any(
            (a) => a.self == true && a.responseStatus == 'declined',
          ) ??
          false,
    );
  }
}
