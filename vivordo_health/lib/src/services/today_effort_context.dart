import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;

import '../utils/day_effort.dart';
import '../utils/day_key.dart';

/// What today's Effort so far needs besides the calendar and priorities:
/// the day's in-app workouts and the usual active calories that extra
/// activity is measured against (the server's `effort.usualCalories`).
typedef TodayEffortContext = ({
  List<({DateTime start, DateTime end, double intensity})> workouts,
  double? usualCalories,
});

// ponytail: Home's Your Day card reads the same two things in its own
// _loadEffortContext (home_screen.dart); move it onto this loader so the two
// can't drift.
Future<TodayEffortContext> loadTodayEffortContext(DateTime day) async {
  const none = (
    workouts: <({DateTime start, DateTime end, double intensity})>[],
    usualCalories: null,
  );
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return none;
  final user = FirebaseFirestore.instance.collection('users').doc(uid);
  final dayStart = DateUtils.dateOnly(day);
  try {
    final (workouts, scores) = await (
      user
          .collection('workouts')
          .where(
            'startedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart),
          )
          .where(
            'startedAt',
            isLessThan: Timestamp.fromDate(
              dayStart.add(const Duration(days: 1)),
            ),
          )
          .get(),
      user
          .collection('scores_daily')
          .where(
            FieldPath.documentId,
            isGreaterThanOrEqualTo: localDayKey(
              DateTime(day.year, day.month, day.day - 7),
            ),
          )
          .where(
            FieldPath.documentId,
            isLessThanOrEqualTo: localDayKey(dayStart),
          )
          .get(),
    ).wait;
    return (
      workouts: [
        for (final doc in workouts.docs)
          if (doc.data()['startedAt'] case final Timestamp start)
            (
              start: start.toDate(),
              end:
                  (doc.data()['completedAt'] as Timestamp?)?.toDate() ??
                  start.toDate().add(
                    Duration(
                      seconds:
                          (((doc.data()['durationMinutes'] as num?) ?? 0) * 60)
                              .round(),
                    ),
                  ),
              intensity: workoutIntensity(
                [
                  doc.data()['activityName'],
                  doc.data()['activityCategory'],
                  for (final e
                      in (doc.data()['exercises'] as List? ?? const []))
                    if (e is Map) e['category'],
                ].whereType<String>().join(' '),
              ),
            ),
      ],
      // Today's, else the latest day's.
      usualCalories: scores.docs.reversed
          .map((d) => (d.data()['effort'] as Map?)?['usualCalories'])
          .whereType<num>()
          .firstOrNull
          ?.toDouble(),
    );
  } catch (error) {
    debugPrint('Today\'s effort context unavailable: $error');
    return none;
  }
}
