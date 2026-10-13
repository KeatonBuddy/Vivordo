import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../utils/day_effort.dart';
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
  DateTime? doneAt,
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
                e.score.category != 'rest' &&
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
            if (p.done && p.doneAt != null)
              'doneAt': Timestamp.fromDate(p.doneAt!),
          },
    ],
  };
}

/// The UTC hour of 11 PM on [now]'s local day.
int nightlyPushUtcHour(DateTime now) =>
    DateTime(now.year, now.month, now.day, 23).toUtc().hour;

/// The calendar events fetched for day records, kept so priority changes
/// don't refetch the calendar.
typedef _Calendar = ({
  String uid,
  DateTime from,
  DateTime until,
  DateTime fetchedAt,
  bool available,
  List<DayRecordEvent> events,
});

/// Writes the day records the server calculates Effort from: when the app
/// opens or comes back (today and yesterday, so a day is recorded even if
/// the app was last opened before it ended), when a priority changes, when
/// My Day's schedule is refreshed, and from the nightly silent push.
class DayRecordService {
  DayRecordService._();

  static const _openInterval = Duration(minutes: 15);
  static final _written = <String, Map<String, Object?>>{};
  static const _equality = DeepCollectionEquality();
  static _Calendar? _calendar;
  static Timer? _soon;

  /// App opened or came back: syncs today and yesterday, at most every 15
  /// minutes within a day. A calendar change made elsewhere is picked up on the next
  /// open after that, or by the nightly push.
  static Future<void> syncOnOpen() async {
    final last = _calendar;
    final now = DateTime.now();
    // A new day always syncs, so yesterday's last changes aren't held back.
    if (last != null &&
        last.uid == FirebaseAuth.instance.currentUser?.uid &&
        localDayKey(last.fetchedAt) == localDayKey(now) &&
        now.difference(last.fetchedAt) < _openInterval) {
      return;
    }
    await sync(days: 2);
  }

  /// Days of calendar history recorded once per account, so Effort has a
  /// usual from day one (docs/scores.md §3).
  static const historyDays = 28;

  /// Records the last [historyDays] days for the history import. False,
  /// with nothing written, when no calendar is connected or the read came
  /// back empty: those days would be recorded as quiet ones for good.
  static Future<bool> syncHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !await calendarConnected()) return false;
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day - historyDays + 1);
    final end = DateTime(now.year, now.month, now.day + 1);
    final calendar = _calendar = await _fetchCalendar(uid, first, end);
    // A failed read throws; four weeks read fine but with no events at all
    // is still likelier a wrong calendar than a real month, so not recorded.
    if (calendar.events.isEmpty) return false;
    await _sync(historyDays, true);
    return true;
  }

  /// Whether Google Calendar (with calendar access) or Outlook is connected.
  static Future<bool> calendarConnected() async {
    final (:google, :outlook) = await _connected();
    return google || outlook;
  }

  /// A priority changed: syncs today 2 seconds later, so quick ticks become
  /// one write, reusing the last calendar fetch.
  static void syncSoon() {
    _soon?.cancel();
    _soon = Timer(
      const Duration(seconds: 2),
      () => unawaited(sync(reuseCalendar: true)),
    );
  }

  /// Records the [days] days ending today, from a fresh calendar read
  /// unless [reuseCalendar] and the last fetch covers those days.
  static Future<void> sync({int days = 1, bool reuseCalendar = false}) async {
    try {
      await _sync(days, reuseCalendar);
    } catch (error) {
      // Best effort: the next open or tick tries again.
      debugPrint('Day record sync failed: $error');
    }
  }

  static Future<void> _sync(int days, bool reuseCalendar) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(today.year, today.month, today.day - days + 1);
    final end = DateTime(today.year, today.month, today.day + 1);

    // At least yesterday and today, so one fetch serves every kind of sync.
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final from = first.isBefore(yesterday) ? first : yesterday;
    final cached = _calendar;
    final calendar =
        reuseCalendar &&
            cached != null &&
            cached.uid == user.uid &&
            !cached.from.isAfter(from) &&
            !cached.until.isBefore(end)
        ? cached
        : _calendar = await _fetchCalendar(user.uid, from, end);

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
      // Server normally; the phone's copy when offline. None before the
      // account existed, so the history import doesn't read for them.
      final created = user.metadata.creationTime;
      final priorities =
          created != null &&
              DateTime(day.year, day.month, day.day + 1).isBefore(created)
          ? const <DailyPriority>[]
          : await DailyPriorityService.forDay(
              day,
              source: Source.serverAndCache,
            );
      final record = buildDayRecord(
        day: day,
        wrapUpMinutes: wrapUp is int ? wrapUp : kDefaultDayWrapUpMinutes,
        calendarAvailable: calendar.available,
        events: calendar.events,
        priorities: [
          for (final p in priorities)
            (
              start: p.isAllDay ? null : p.sourceStart,
              end: p.isAllDay ? null : p.timelineEnd,
              effort: p.planning['effort'],
              minutes: (p.planning['minutes'] as num?)?.toInt(),
              done: p.completed,
              doneAt: p.completedAt,
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

  /// The connected calendars' rated events from [from] to [until] as Demand
  /// items, as the day record counts them: the weekly review prices the
  /// week ahead with these. Empty when signed out.
  static Future<List<EffortItem>> plannedItems(
    DateTime from,
    DateTime until,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];
    final calendar = await _fetchCalendar(uid, from, until);
    return [
      for (final e in calendar.events)
        if (e.event.contributesToSchedule && e.score.category != 'rest')
          (event: e.event, score: e.score, done: false, open: false),
    ];
  }

  /// Fetches and rates the connected calendars' events from [from] to
  /// [until]. A failed fetch throws, so a day is never recorded as falsely
  /// empty: the scoring reads say when they couldn't read the calendar,
  /// where the screens' reads just come back empty.
  static Future<_Calendar> _fetchCalendar(
    String uid,
    DateTime from,
    DateTime until,
  ) async {
    final (:google, :outlook) = await _connected();
    // Google's and Outlook's, merged.
    final events = google || outlook
        ? await CalendarService.getScoringEvents(
            from,
            until,
          ).timeout(const Duration(seconds: 20))
        : const <gcal.Event>[];
    if (events == null) throw StateError('The calendar could not be read.');
    final inputs = <(CalendarCognitiveEvent, String?)>[
      for (final event in events)
        if (_fromGoogle(event) case final input?)
          (input, CalendarService.eventKey(event)),
    ];
    // Claude sorts what the local rules can't, with the user's AI consent.
    // In twenties: each call sorts at most 20 uncertain events and rates
    // the rest by the rules, and weeks of history can hold far more.
    final scores = <CognitiveLoadScore>[
      for (var i = 0; i < inputs.length; i += 20)
        ...await CalendarCognitiveLoadService.scoreEvents([
          for (final (event, _) in inputs.skip(i).take(20)) event,
        ], allowAi: true),
    ];
    return (
      uid: uid,
      from: from,
      until: until,
      fetchedAt: DateTime.now(),
      available: google || outlook,
      events: [
        for (var i = 0; i < inputs.length; i++)
          (event: inputs[i].$1, score: scores[i], key: inputs[i].$2),
      ],
    );
  }

  /// Google counts only with calendar access: signing in to Vivordo with
  /// Google alone doesn't grant it, and its days aren't empty ones.
  static Future<({bool google, bool outlook})> _connected() async => (
    google: await CalendarService.hasCalendarAccess()
        .timeout(const Duration(seconds: 5), onTimeout: () => false)
        .catchError((_) => false),
    outlook: await OutlookCalendarService.isSignedIn()
        .timeout(const Duration(seconds: 5), onTimeout: () => false)
        .catchError((_) => false),
  );

  static CalendarCognitiveEvent? _fromGoogle(gcal.Event event) {
    final start = event.start?.dateTime;
    final end = event.end?.dateTime;
    if (start == null || end == null) return null;
    return CalendarCognitiveEvent(
      id: '${CalendarService.eventKey(event)}:${start.toUtc().toIso8601String()}',
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
