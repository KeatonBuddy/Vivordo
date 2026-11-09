import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../utils/energy_forecast.dart';
import '../utils/event_repeat.dart';
import '../utils/invite_fit.dart';
import 'calendar_service.dart';
import 'wind_down_reminder.dart';

/// A calendar invite between Circle friends (event_invites/{id}). Only the
/// title and time are shared; the invite callables do every write.
class EventInvite {
  const EventInvite({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.title,
    required this.start,
    required this.end,
    this.fromPhotoUrl,
    this.allDay = false,
    this.recipientUids = const [],
    this.recipientNames = const {},
    this.responses = const {},
    this.cancelled = false,
    this.recurrence,
    this.expireAt,
  });

  factory EventInvite.fromMap(String id, Map<String, dynamic> data) =>
      EventInvite(
        id: id,
        fromUid: data['fromUid'] as String? ?? '',
        fromName: data['fromName'] as String? ?? 'A Circle friend',
        fromPhotoUrl: data['fromPhotoUrl'] as String?,
        title: data['title'] as String? ?? 'Event',
        start: (data['start'] as Timestamp?)?.toDate() ?? DateTime(0),
        end: (data['end'] as Timestamp?)?.toDate() ?? DateTime(0),
        allDay: data['allDay'] == true,
        recipientUids: List<String>.from(data['recipientUids'] as List? ?? []),
        recipientNames: Map<String, String>.from(
          data['recipientNames'] as Map? ?? {},
        ),
        responses: Map<String, String>.from(data['responses'] as Map? ?? {}),
        cancelled: data['status'] == 'cancelled',
        recurrence: data['recurrence'] as String?,
        expireAt: (data['expireAt'] as Timestamp?)?.toDate(),
      );

  final String id;
  final String fromUid;
  final String fromName;
  final String? fromPhotoUrl;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final List<String> recipientUids;

  /// uid → username, for the sender's list of who said what.
  final Map<String, String> recipientNames;

  /// uid → pending, accepted or declined.
  final Map<String, String> responses;
  final bool cancelled;

  /// The series' RRULE line; null for a one-off. [start]/[end] are then the
  /// first occurrence.
  final String? recurrence;

  /// When the invite lapses: a series' last occurrence (or six months out).
  final DateTime? expireAt;

  EventRepeat get repeat =>
      EventRepeat.parse(recurrence == null ? null : [recurrence!]);

  /// Until when the invite is still on: the event's end, or a series' last
  /// occurrence.
  DateTime get activeUntil => recurrence == null ? end : (expireAt ?? end);

  /// Still waiting on [uid]'s answer, and still worth answering.
  bool pendingFor(String uid, DateTime now) =>
      !cancelled && responses[uid] == 'pending' && activeUntil.isAfter(now);

  /// [uid] said yes and it hasn't happened yet, so they can still back out.
  bool goingFor(String uid, DateTime now) =>
      !cancelled && responses[uid] == 'accepted' && activeUntil.isAfter(now);

  /// [uid] said no but it hasn't happened yet, so they can still change
  /// their mind.
  bool notGoingFor(String uid, DateTime now) =>
      !cancelled && responses[uid] == 'declined' && activeUntil.isAfter(now);

  int count(String answer) => responses.values.where((a) => a == answer).length;
}

/// Thrown when accepting needs a calendar and none is connected.
class NoCalendarConnected implements Exception {
  const NoCalendarConnected();
}

class EventInviteService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  static CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection('event_invites');

  static List<EventInvite> _parse(QuerySnapshot<Map<String, dynamic>> s) =>
      [for (final doc in s.docs) EventInvite.fromMap(doc.id, doc.data())]
        ..sort((a, b) => a.start.compareTo(b.start));

  // expireAt (end + 1 day) keeps past invites out until TTL deletes them.
  static Stream<List<EventInvite>> _watch(
    Query<Map<String, dynamic>> Function(String uid) query,
  ) => FirebaseAuth.instance.userChanges().asyncExpand((user) {
    if (user == null) return Stream.value(const <EventInvite>[]);
    return query(
      user.uid,
    ).where('expireAt', isGreaterThan: Timestamp.now()).snapshots().map(_parse);
  });

  /// Invites friends sent you (answered ones too).
  static Stream<List<EventInvite>> watchReceived() =>
      _watch((uid) => _invites.where('recipientUids', arrayContains: uid));

  /// Invites you sent that are still running.
  static Stream<List<EventInvite>> watchSent() =>
      _watch((uid) => _invites.where('fromUid', isEqualTo: uid)).map(
        (invites) => [
          for (final i in invites)
            if (!i.cancelled) i,
        ],
      );

  /// How many invites wait on your answer, for the My Day badge.
  static Stream<int> watchPendingCount() => watchReceived().map((invites) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final now = DateTime.now();
    return uid == null
        ? 0
        : invites.where((i) => i.pendingFor(uid, now)).length;
  });

  static Future<void> send({
    required String title,
    required DateTime start,
    required DateTime end,
    required bool allDay,
    required List<String> recipientUids,
    String? senderEventId,
    String? recurrence,
  }) => _functions.httpsCallable('sendEventInvites').call({
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    'allDay': allDay,
    'recipientUids': recipientUids,
    'senderEventId': senderEventId,
    'recurrence': recurrence,
  });

  /// Accepting adds the event to your default calendar first, so a failed
  /// calendar write never shows you as going.
  static Future<void> respond(
    EventInvite invite, {
    required bool accept,
  }) async {
    gcal.Event? copy;
    if (accept) {
      if (!await CalendarService.isAnyConnected()) {
        throw const NoCalendarConnected();
      }
      copy = await CalendarService.createEvent(
        title: invite.title,
        start: invite.start,
        end: invite.end,
        recurrence: invite.recurrence ?? 'none',
        isAllDay: invite.allDay,
      );
    }
    try {
      await _functions.httpsCallable('respondToEventInvite').call({
        'inviteId': invite.id,
        'accept': accept,
      });
    } catch (_) {
      if (copy != null) {
        await CalendarService.deleteEvent(copy).catchError((_) {});
      }
      rethrow;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!accept && uid != null) await _removeCopy(uid, invite.id);
    if (copy?.id != null && uid != null) {
      // Private to you: which calendar event is this invite's copy, so a
      // change from the sender can follow it later.
      await _firestore
          .doc('users/$uid/event_invite_copies/${invite.id}')
          .set(_copyFields(invite, copy!))
          .catchError((Object e) => debugPrint('Invite copy not saved: $e'));
    }
  }

  /// What a calendar copy was made from, so [syncCopies] can tell when the
  /// sender changed it.
  static Map<String, Object?> _copyFields(
    EventInvite invite,
    gcal.Event copy,
  ) => {
    'eventId': copy.id,
    'calendarId': CalendarService.calendarIdForEvent(copy),
    'title': invite.title,
    'start': Timestamp.fromDate(invite.start),
    'end': Timestamp.fromDate(invite.end),
    'allDay': invite.allDay,
    'recurrence': invite.recurrence,
    'activeUntil': Timestamp.fromDate(invite.activeUntil),
    'syncedAt': FieldValue.serverTimestamp(),
  };

  static Future<void>? _syncing;

  /// Brings your calendar copies of accepted invites in line with the
  /// invites: moved when the sender changed the event, removed when it was
  /// cancelled or you're no longer on it. Runs when the app opens or
  /// resumes, since only this device can write your calendar.
  static Future<void> syncCopies() =>
      _syncing ??= _syncCopies().whenComplete(() => _syncing = null);

  static Future<void> _syncCopies() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final copies = await _firestore
          .collection('users/$uid/event_invite_copies')
          .get();
      if (copies.docs.isEmpty || !await CalendarService.isAnyConnected()) {
        return;
      }
      for (final doc in copies.docs) {
        EventInvite? invite;
        try {
          final snapshot = await _invites.doc(doc.id).get();
          if (snapshot.exists) {
            invite = EventInvite.fromMap(snapshot.id, snapshot.data()!);
          }
        } on FirebaseException catch (error) {
          // Taken off the invite (unfriended): it no longer applies.
          if (error.code != 'permission-denied') rethrow;
        }
        await _applyCopyAction(
          doc.reference,
          doc.data(),
          invite,
          copyAction(
            copy: doc.data(),
            invite: invite,
            uid: uid,
            now: DateTime.now(),
          ),
        );
      }
    } catch (error) {
      debugPrint('Invite calendar copies not synced: $error');
    }
  }

  static Future<void> _applyCopyAction(
    DocumentReference<Map<String, dynamic>> reference,
    Map<String, dynamic> copy,
    EventInvite? invite,
    CopyAction action,
  ) async {
    if (action == CopyAction.keep) return;
    final eventId = copy['eventId'] as String?;
    if (action != CopyAction.forget && eventId != null) {
      await CalendarService.deleteEventById(
        eventId,
        calendarId: copy['calendarId'] as String?,
      );
    }
    if (action == CopyAction.replace && invite != null) {
      final event = await CalendarService.createEvent(
        title: invite.title,
        start: invite.start,
        end: invite.end,
        recurrence: invite.recurrence ?? 'none',
        isAllDay: invite.allDay,
      );
      await reference.set(_copyFields(invite, event));
      return;
    }
    await reference.delete();
  }

  /// Puts an invite you just declined back to waiting (the toast's Undo).
  static Future<void> undoDecline(EventInvite invite) => _functions
      .httpsCallable('respondToEventInvite')
      .call({'inviteId': invite.id, 'accept': null});

  /// How [invite] sits in your day, read from your own calendar on this
  /// device (nothing goes to the sender). Null for all-day invites or when
  /// no calendar can be read.
  static Future<InviteFit?> fitFor(EventInvite invite) async {
    if (invite.allDay || !await CalendarService.isAnyConnected()) return null;
    try {
      if (invite.recurrence == null) {
        return await _dayFit(invite.start, invite.end);
      }
      // A series: the next few occurrences, each against its own day.
      final length = invite.end.difference(invite.start);
      final starts = invite.repeat.nextOccurrences(
        invite.start,
        from: DateTime.now().subtract(length),
      );
      final fits = await Future.wait([
        for (final start in starts) _dayFit(start, start.add(length)),
      ]);
      return seriesFit(fits);
    } catch (error) {
      debugPrint('Invite fit not loaded: $error');
      return null;
    }
  }

  static Future<InviteFit> _dayFit(DateTime start, DateTime end) async {
    final day = DateTime(start.year, start.month, start.day);
    final (events, forecast) = await (
      CalendarService.getEventsBetween(day, day.add(const Duration(days: 1))),
      WindDownReminders.forecastFor(day).catchError((_) => null),
    ).wait;
    return inviteFit(
      start: start,
      end: end,
      dip: forecast?.window(EnergyPhase.dip),
      dayEvents: [
        for (final event in events)
          if (event.start?.dateTime != null && event.end?.dateTime != null)
            (
              title: event.summary ?? 'Busy',
              start: event.start!.dateTime!.toLocal(),
              end: event.end!.dateTime!.toLocal(),
            ),
      ],
    );
  }

  /// Backing out of an invite you'd accepted takes its event off your
  /// calendar. Best effort: your answer is already recorded.
  static Future<void> _removeCopy(String uid, String inviteId) async {
    final reference = _firestore.doc(
      'users/$uid/event_invite_copies/$inviteId',
    );
    try {
      final copy = (await reference.get()).data();
      final eventId = copy?['eventId'] as String?;
      if (eventId == null) return;
      await CalendarService.deleteEventById(
        eventId,
        calendarId: copy?['calendarId'] as String?,
      );
      await reference.delete();
    } catch (error) {
      debugPrint('Invite calendar copy not removed: $error');
    }
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _sentFor(
    String? eventId,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || eventId == null) return const [];
    final snapshot = await _invites
        .where('fromUid', isEqualTo: uid)
        .where('senderEventId', isEqualTo: eventId)
        .where('status', isEqualTo: 'active')
        .get();
    return snapshot.docs;
  }

  /// After you edit an event you invited friends to, their invite follows.
  static Future<void> senderEventChanged(gcal.Event event) async {
    final start = event.start?.dateTime ?? event.start?.date;
    final end = event.end?.dateTime ?? event.end?.date;
    if (start == null || end == null) return;
    for (final doc in await _sentFor(event.id)) {
      await _functions.httpsCallable('updateEventInvite').call({
        'inviteId': doc.id,
        'title': event.summary ?? doc.data()['title'],
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'allDay': event.start?.dateTime == null,
        'recurrence': event.recurrence
            ?.where((line) => line.startsWith('RRULE:'))
            .firstOrNull,
      });
    }
  }

  /// After you delete an event you invited friends to, the invite is off.
  static Future<void> senderEventDeleted(String? eventId) async {
    for (final doc in await _sentFor(eventId)) {
      await _functions.httpsCallable('cancelEventInvite').call({
        'inviteId': doc.id,
      });
    }
  }
}

/// What to do with your calendar copy of an accepted invite.
enum CopyAction {
  /// Still matches the invite.
  keep,

  /// The sender changed it: replace the copy with the new details.
  replace,

  /// Cancelled, declined or you're off the invite: take it off your calendar.
  remove,

  /// The event is over: keep it in your calendar, stop tracking it.
  forget,
}

/// Compares a saved [copy] (its title, start, end and allDay at the time)
/// with its [invite], which is null when the invite is gone or unreadable.
CopyAction copyAction({
  required Map<String, dynamic> copy,
  required EventInvite? invite,
  required String uid,
  required DateTime now,
}) {
  if (invite == null) {
    // Gone before it happened (the sender deleted their account or you
    // were removed) means it's off; gone afterwards is just tidy-up.
    final end = ((copy['activeUntil'] ?? copy['end']) as Timestamp?)?.toDate();
    return end != null && end.isAfter(now)
        ? CopyAction.remove
        : CopyAction.forget;
  }
  if (!invite.activeUntil.isAfter(now)) return CopyAction.forget;
  if (invite.cancelled || invite.responses[uid] != 'accepted') {
    return CopyAction.remove;
  }
  final same =
      copy['title'] == invite.title &&
      copy['allDay'] == invite.allDay &&
      copy['recurrence'] == invite.recurrence &&
      (copy['start'] as Timestamp?)?.toDate() == invite.start &&
      (copy['end'] as Timestamp?)?.toDate() == invite.end;
  return same ? CopyAction.keep : CopyAction.replace;
}
