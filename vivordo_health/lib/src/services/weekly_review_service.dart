import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/day_effort.dart';
import '../utils/day_key.dart';
import '../utils/day_wrap_up.dart';
import '../utils/meeting_patterns.dart';
import '../utils/priority_schedule.dart';
import '../utils/weekly_review.dart';
import 'daily_priority_service.dart';
import 'day_record_service.dart';
import 'notification_service.dart';

/// What My Day's Sunday card needs: the review, whether it's the first one
/// (with the intro and the reminder switch), and the reminder's state.
typedef WeeklyReviewCardState = ({
  WeeklyReview review,
  bool intro,
  bool reminder,
});

/// Builds, saves and reads the Sunday weekly review
/// (`users/{uid}/weekly_reviews/{the reviewed week's Sunday}`). A review is
/// made once, the first time the app opens after its week ends, and never
/// changes afterwards except for the "anything else going on" answer.
class WeeklyReviewService {
  WeeklyReviewService._();

  static CollectionReference<Map<String, dynamic>>? get _reviews {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('weekly_reviews');
  }

  static Future<WeeklyReview?>? _current;
  static String? _currentFor;

  /// The review of the week before [now] (the Sunday-to-Saturday that last
  /// ended): saved if it already exists, otherwise built and saved. Null
  /// with too little data that week, or signed out.
  static Future<WeeklyReview?> current({DateTime? now}) {
    final today = now ?? DateTime.now();
    final key =
        '${FirebaseAuth.instance.currentUser?.uid}:'
        '${localDayKey(reviewWeekStart(today))}';
    if (_current != null && _currentFor == key) return _current!;
    _currentFor = key;
    return _current = _load(today).catchError((Object error) {
      debugPrint('Weekly review unavailable: $error');
      _current = null;
      return null;
    });
  }

  static Future<WeeklyReview?> _load(DateTime today) async {
    final reviews = _reviews;
    if (reviews == null) return null;
    final weekStart = reviewWeekStart(today);
    final key = localDayKey(weekStart);
    final saved = await reviews.doc(key).get();
    if (WeeklyReview.fromMap(saved.data()) case final review?) return review;

    final review = await _build(today, weekStart);
    if (review == null) return null;
    await reviews.doc(key).set({
      ...review.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return review;
  }

  static Future<WeeklyReview?> _build(
    DateTime today,
    DateTime weekStart,
  ) async {
    final user = FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid);
    final from = localDayKey(weekStart.subtract(const Duration(days: 28)));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final to = localDayKey(weekEnd.subtract(const Duration(days: 1)));
    Future<Map<String, Map<String, dynamic>>> range(
      String name,
      String start,
    ) async {
      final snapshot = await user
          .collection(name)
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: start)
          .where(FieldPath.documentId, isLessThanOrEqualTo: to)
          .get();
      return {for (final d in snapshot.docs) d.id: d.data()};
    }

    final weekFrom = localDayKey(weekStart);
    final nightsFrom = localDayKey(weekStart.subtract(const Duration(days: 1)));
    final results = await Future.wait([
      range('scores_daily', from),
      range('event_reactions', weekFrom),
      range('daily_tags', nightsFrom),
      range('day_fixes', weekFrom),
      user
          .collection('workouts')
          .where(
            'completedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart),
          )
          .where('completedAt', isLessThan: Timestamp.fromDate(weekEnd))
          .count()
          .get(),
      user.get(),
      _reviews!
          .doc(localDayKey(weekStart.subtract(const Duration(days: 7))))
          .get(),
    ]);
    final scores = results[0] as Map<String, Map<String, dynamic>>;
    final reactions = results[1] as Map<String, Map<String, dynamic>>;
    final tags = results[2] as Map<String, Map<String, dynamic>>;
    final fixes = results[3] as Map<String, Map<String, dynamic>>;
    final workouts = (results[4] as AggregateQuerySnapshot).count ?? 0;
    final preferences =
        (results[5] as DocumentSnapshot<Map<String, dynamic>>)
                .data()?['preferences']
            as Map?;
    final previous = WeeklyReview.fromMap(
      (results[6] as DocumentSnapshot<Map<String, dynamic>>).data(),
    );

    final day = DateTime(today.year, today.month, today.day);
    final open = await DailyPriorityService.watch(
      day,
    ).first.timeout(const Duration(seconds: 8), onTimeout: () => const []);

    // The week ahead, priced as My Day prices a day: only when the review
    // is made on the Sunday, so "next week" is still ahead.
    final nextWeek = <({DateTime day, double demand})>[];
    if (day == weekEnd) {
      final monday = day.add(const Duration(days: 1));
      final wrapUp =
          (preferences?['dayWrapUpMinutes'] as num?)?.toInt() ??
          kDefaultDayWrapUpMinutes;
      try {
        final items = await DayRecordService.plannedItems(
          monday,
          monday.add(const Duration(days: 5)),
        ).timeout(const Duration(seconds: 15));
        for (var i = 0; i < 5; i++) {
          final d = monday.add(Duration(days: i));
          nextWeek.add((
            day: d,
            demand: buildDayEffort(
              now: d,
              from: d,
              until: d.add(const Duration(days: 1)),
              wrapUp: d.add(Duration(minutes: wrapUp)),
              items: items,
            ).demand,
          ));
        }
      } catch (error) {
        // Without the calendar, the review leaves out the week ahead.
        debugPrint('Weekly review: next week unavailable: $error');
      }
    }

    final lastNote = [
      ...?previous?.context,
      if (previous?.note?.trim().isNotEmpty ?? false) previous!.note!.trim(),
    ];
    return buildWeeklyReview(
      WeeklyReviewInput(
        weekStart: weekStart,
        scores: scores,
        reactions: MeetingReaction.fromDays(reactions),
        nightTags: {
          for (final e in tags.entries)
            e.key: [
              ...(e.value['tags'] as List? ?? const []).whereType<String>(),
            ],
        },
        dayFixes: fixes,
        workouts: workouts,
        openPriorities: [
          for (final p in open)
            if (overdueSince(p, day) case final since?)
              (title: p.title, since: since),
        ],
        nextWeek: nextWeek,
        lastWeekNote: lastNote.isEmpty ? null : lastNote.join(', '),
      ),
    );
  }

  /// Saves "anything else going on" for the review of [weekStart].
  static Future<void> saveContext(
    String weekStart,
    List<String> context,
    String? note,
  ) async {
    final trimmed = note?.trim();
    await _reviews?.doc(weekStart).update({
      'context': context,
      'note': trimmed == null || trimmed.isEmpty ? null : trimmed,
    });
    _current = null;
  }

  static DocumentReference<Map<String, dynamic>>? get _user {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  /// My Day's card on Sundays ([day]), once the morning check-in is
  /// answered or dismissed (or from noon, when its pop-up stops, for anyone
  /// who skips it), until hidden for the day; null otherwise.
  static Stream<WeeklyReviewCardState?> watchCard(DateTime day) {
    final user = _user;
    if (user == null || day.weekday != DateTime.sunday) {
      return Stream.value(null);
    }
    final key = localDayKey(day);
    Map<String, dynamic>? preferences;
    Map? checkIn;
    var checkInLoaded = false;
    late final StreamController<WeeklyReviewCardState?> controller;
    final subscriptions = <StreamSubscription<Object?>>[];
    Timer? noon;
    Future<void> emit() async {
      if (preferences == null || !checkInLoaded) return;
      final settled =
          checkIn?['dismissed'] == true ||
          (checkIn?['feel'] is num && checkIn?['sleep'] is num) ||
          DateTime.now().hour >= 12;
      if (!settled || preferences!['weeklyReviewHidden'] == key) {
        controller.add(null);
        return;
      }
      final review = await current(now: day);
      if (controller.isClosed) return;
      controller.add(
        review == null
            ? null
            : (
                review: review,
                intro: preferences!['weeklyReviewIntroSeen'] != true,
                reminder: preferences!['weeklyReviewReminder'] != false,
              ),
      );
    }

    controller = StreamController<WeeklyReviewCardState?>(
      onListen: () {
        final untilNoon = DateTime(
          day.year,
          day.month,
          day.day,
          12,
        ).difference(DateTime.now());
        if (!untilNoon.isNegative) noon = Timer(untilNoon, emit);
        subscriptions
          ..add(
            user.snapshots().listen((doc) {
              preferences = {
                ...?(doc.data()?['preferences'] as Map?)
                    ?.cast<String, dynamic>(),
              };
              unawaited(emit());
            }, onError: controller.addError),
          )
          ..add(
            user.collection('metrics_daily').doc(key).snapshots().listen((doc) {
              checkIn = doc.data()?['morning_check_in'] as Map?;
              checkInLoaded = true;
              unawaited(emit());
            }, onError: controller.addError),
          );
      },
      onCancel: () async {
        noon?.cancel();
        for (final s in subscriptions) {
          await s.cancel();
        }
        subscriptions.clear();
      },
    );
    return controller.stream;
  }

  /// The card's ✕: hidden until tomorrow.
  static Future<void> hideForToday() => _setPreferences({
    'weeklyReviewHidden': localDayKey(DateTime.now()),
    'weeklyReviewIntroSeen': true,
  });

  static Future<void> markIntroSeen() =>
      _setPreferences({'weeklyReviewIntroSeen': true});

  /// The Sunday 11 AM reminder (`preferences.weeklyReviewReminder`, on
  /// unless switched off).
  static Future<void> setReminder(bool enabled) async {
    await _setPreferences({
      'weeklyReviewReminder': enabled,
      'weeklyReviewIntroSeen': true,
    });
    await syncReminder();
  }

  /// Schedules or cancels the reminder to match the preference, so a new
  /// install picks it back up.
  static Future<void> syncReminder() async {
    final user = _user;
    if (user == null) return;
    try {
      final on =
          ((await user.get()).data()?['preferences']
              as Map?)?['weeklyReviewReminder'] !=
          false;
      await (on
          ? NotificationService().scheduleWeeklyReviewReminder()
          : NotificationService().cancelWeeklyReviewReminder());
    } catch (error) {
      debugPrint('Weekly review reminder not synced: $error');
    }
  }

  static Future<void> _setPreferences(Map<String, Object?> values) async =>
      _user?.set({'preferences': values}, SetOptions(merge: true));

  /// Every saved review, newest first, for Journal.
  static Stream<List<WeeklyReview>> watchAll() {
    final reviews = _reviews;
    if (reviews == null) return const Stream.empty();
    return reviews
        .orderBy(FieldPath.documentId, descending: true)
        .limit(104)
        .snapshots()
        .map((s) => [for (final d in s.docs) ?WeeklyReview.fromMap(d.data())]);
  }
}
