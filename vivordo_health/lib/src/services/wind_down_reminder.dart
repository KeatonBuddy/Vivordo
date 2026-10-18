import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../widgets/energy_forecast_view.dart';
import '../utils/day_key.dart';
import '../utils/energy_forecast.dart';
import '../utils/server_capacity.dart';
import '../utils/sleep_nights.dart';
import '../utils/sleep_schedule.dart';
import 'notification_service.dart';

/// The opt-in wind-down reminder (docs/scores.md §8, phase 4), stored as
/// `preferences.windDownReminder`: missing until the evening card asks, then
/// true or false. While on, the next seven nights are scheduled as local
/// notifications and rescheduled whenever Home or My Day loads the calendar,
/// so each night follows the latest forecast.
class WindDownReminders {
  WindDownReminders._();

  static DocumentReference<Map<String, dynamic>>? get _user {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  /// Turns the reminder on or off (off also answers the card's offer for
  /// good) and schedules or cancels it.
  static Future<void> setEnabled(
    bool enabled, {
    DateTime? tomorrowFirstEvent,
  }) async {
    final user = _user;
    if (user == null) return;
    await user.set({
      'preferences': {'windDownReminder': enabled},
    }, SetOptions(merge: true));
    await sync(tomorrowFirstEvent: tomorrowFirstEvent, fresh: true);
  }

  /// How long the sleep history and sleep need read for the reminder are
  /// reused, on the same day: a calendar load then doesn't download 15
  /// days of full day documents each time, and last night's sleep (synced
  /// in the morning) still lands well before the evening.
  static const inputsMaxAge = Duration(hours: 3);
  static _Inputs? _inputs;

  /// Whether inputs read at [loadedAt] can still be used at [now].
  @visibleForTesting
  static bool inputsFresh(DateTime loadedAt, DateTime now) =>
      localDayKey(loadedAt) == localDayKey(now) &&
      now.difference(loadedAt) < inputsMaxAge;

  /// Schedules the coming nights from the latest sleep, or cancels them when
  /// the reminder is off. [tomorrowFirstEvent] can move tonight's earlier.
  /// [fresh] rereads the sleep history even if it was read recently.
  static Future<void> sync({
    DateTime? tomorrowFirstEvent,
    bool fresh = false,
  }) async {
    final user = _user;
    if (user == null) return;
    try {
      final preferences = (await user.get()).data()?['preferences'] as Map?;
      if (preferences?['windDownReminder'] != true) {
        await NotificationService().cancelWindDownReminders();
        return;
      }
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      var inputs = _inputs;
      if (fresh ||
          inputs == null ||
          inputs.uid != user.id ||
          !inputsFresh(inputs.at, now)) {
        inputs = _inputs = await _readInputs(user, today);
      }
      final nights = inputs.nights;
      final schedule = SleepSchedule.fromPreferences(preferences);
      // Like the forecast itself: nothing to go on without sleep or times.
      if (nights.isEmpty && schedule == null) {
        await NotificationService().cancelWindDownReminders();
        return;
      }
      await NotificationService().scheduleWindDownReminders(
        windDownReminders(
          today: today,
          nights: nights,
          sleepNeedHours: inputs.need,
          schedule: schedule,
          tomorrowFirstEvent: tomorrowFirstEvent,
        ),
      );
    } catch (error) {
      debugPrint('Wind-down reminders not synced: $error');
    }
  }

  static Future<_Inputs> _readInputs(
    DocumentReference<Map<String, dynamic>> user,
    DateTime today,
  ) async {
    final at = DateTime.now();
    final results = await Future.wait([
      user
          .collection('metrics_daily')
          .where(
            FieldPath.documentId,
            isGreaterThanOrEqualTo: localDayKey(
              DateTime(today.year, today.month, today.day - 14),
            ),
          )
          .get(),
      user
          .collection('scores_daily')
          .where(
            FieldPath.documentId,
            isGreaterThanOrEqualTo: localDayKey(
              DateTime(today.year, today.month, today.day - 14),
            ),
          )
          .get(),
    ]);
    final [days, scores] = results;
    return (
      uid: user.id,
      at: at,
      nights: sleepNights([for (final d in days.docs) d.data()]),
      need: latestSleepNeed({
        for (final doc in scores.docs) doc.id: doc.data(),
      }),
    );
  }
}

typedef _Inputs = ({
  String uid,
  DateTime at,
  List<SleepPeriod> nights,
  double? need,
});
