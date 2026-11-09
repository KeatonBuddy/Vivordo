import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import 'calendar_service.dart';

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
    this.responses = const {},
    this.cancelled = false,
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
        responses: Map<String, String>.from(data['responses'] as Map? ?? {}),
        cancelled: data['status'] == 'cancelled',
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

  /// uid → pending, accepted or declined.
  final Map<String, String> responses;
  final bool cancelled;

  /// Still waiting on [uid]'s answer, and still worth answering.
  bool pendingFor(String uid, DateTime now) =>
      !cancelled && responses[uid] == 'pending' && end.isAfter(now);

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
  }) => _functions.httpsCallable('sendEventInvites').call({
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    'allDay': allDay,
    'recipientUids': recipientUids,
    'senderEventId': senderEventId,
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
        recurrence: 'none',
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
    if (copy?.id != null && uid != null) {
      // Private to you: which calendar event is this invite's copy, so a
      // change from the sender can follow it later.
      await _firestore
          .doc('users/$uid/event_invite_copies/${invite.id}')
          .set({
            'eventId': copy!.id,
            'calendarId': CalendarService.calendarIdForEvent(copy),
            'createdAt': FieldValue.serverTimestamp(),
          })
          .catchError((Object e) => debugPrint('Invite copy not saved: $e'));
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
