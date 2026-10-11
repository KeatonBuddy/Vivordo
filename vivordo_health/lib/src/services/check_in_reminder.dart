import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/day_key.dart';
import 'notification_service.dart';

/// When the morning check-in reminder fires: late enough to have woken,
/// early enough to still be the morning.
const checkInReminderMinutes = 10 * 60;

/// The opt-in morning check-in reminder (`preferences.checkInMorningReminder`,
/// off unless switched on in Settings): at 10 AM on days the Home check-in
/// is still open. Today's is dropped once it's answered or dismissed.
class CheckInReminders {
  CheckInReminders._();

  static DocumentReference<Map<String, dynamic>>? get _user {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static Future<void> setEnabled(bool enabled) async {
    final user = _user;
    if (user == null) return;
    await user.set({
      'preferences': {'checkInMorningReminder': enabled},
    }, SetOptions(merge: true));
    await sync();
  }

  /// Schedules today (if the check-in is still open) and the next six
  /// mornings, or cancels them all when the reminder is off.
  static Future<void> sync() async {
    final user = _user;
    if (user == null) return;
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final results = await Future.wait([
        user.get(),
        user.collection('metrics_daily').doc(localDayKey(today)).get(),
      ]);
      final on =
          (results[0].data()?['preferences']
              as Map?)?['checkInMorningReminder'] ==
          true;
      if (!on) {
        await NotificationService().cancelCheckInReminders();
        return;
      }
      final checkIn = results[1].data()?['morning_check_in'] as Map?;
      // Still open: answers missing and not dismissed. Unlike checkInDue,
      // before 5 AM still counts, since the reminder is for 10 AM.
      final todayOpen =
          checkIn?['dismissed'] != true &&
          !(checkIn?['feel'] is num && checkIn?['sleep'] is num);
      await NotificationService().scheduleCheckInReminders(
        checkInReminderTimes(today, todayOpen: todayOpen),
      );
    } catch (error) {
      debugPrint('Check-in reminders not synced: $error');
    }
  }
}

/// 10 AM today (only while today's check-in is open) and the next six days.
@visibleForTesting
List<DateTime> checkInReminderTimes(
  DateTime today, {
  required bool todayOpen,
}) => [
  for (var i = todayOpen ? 0 : 1; i < 7; i++)
    DateTime(
      today.year,
      today.month,
      today.day + i,
    ).add(const Duration(minutes: checkInReminderMinutes)),
];
