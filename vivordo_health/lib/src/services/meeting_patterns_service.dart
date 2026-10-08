import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../utils/day_key.dart';
import '../utils/heavy_days.dart';
import '../utils/meeting_patterns.dart';

/// Loads meeting patterns and heavy-day comparisons from the last 90 days
/// of small per-day documents (event_reactions, scores_daily), at most once
/// a day per account unless a new reaction is saved. Shared by Home and My
/// Day.
class MeetingPatternsService {
  MeetingPatternsService._();

  static const _days = 90;
  static String? _loadedFor;
  static Future<({MeetingPatterns patterns, HeavyDays heavy})>? _loading;

  /// Repeating series' titles seen in the calendar this session, by series
  /// key: the saved reactions carry no titles, so names come from here.
  static final names = <String, String>{};

  static void rememberNames(Iterable<gcal.Event> events) {
    for (final e in events) {
      final key = seriesKeyFor(e.recurringEventId);
      final title = e.summary?.trim();
      if (key != null && title != null && title.isNotEmpty) names[key] = title;
    }
  }

  /// A series' calendar title, else its description.
  static String nameOf(MeetingPattern p) =>
      p.isSeries ? names[p.id] ?? p.label : p.label;

  /// Drops the cache, after a reaction is saved.
  static void invalidate() => _loading = null;

  static Future<({MeetingPatterns patterns, HeavyDays heavy})> load() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final key = '$uid:${localDayKey(DateTime.now())}';
    if (_loading != null && _loadedFor == key) return _loading!;
    _loadedFor = key;
    return _loading = _load(uid).catchError((Object _) {
      _loading = null;
      return (patterns: MeetingPatterns.empty, heavy: heavyDaysFrom(const {}));
    });
  }

  static Future<({MeetingPatterns patterns, HeavyDays heavy})> _load(
    String? uid,
  ) async {
    if (uid == null) {
      return (patterns: MeetingPatterns.empty, heavy: heavyDaysFrom(const {}));
    }
    final now = DateTime.now();
    final from = localDayKey(DateTime(now.year, now.month, now.day - _days));
    final user = FirebaseFirestore.instance.collection('users').doc(uid);
    Future<Map<String, Map<String, dynamic>>> range(String name) async {
      final snapshot = await user
          .collection(name)
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: from)
          .get();
      return {for (final d in snapshot.docs) d.id: d.data()};
    }

    final results = await Future.wait([
      range('event_reactions'),
      range('scores_daily'),
    ]);
    return (
      patterns: meetingPatternsFrom(MeetingReaction.fromDays(results[0])),
      heavy: heavyDaysFrom(results[1]),
    );
  }
}
