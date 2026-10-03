import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'energy_forecast.dart';

/// Your usual bed and wake times (`preferences.sleepSchedule`), in minutes
/// after midnight. Asked in onboarding and changed from the Sleep screen;
/// the energy forecast uses it until enough sleep is tracked, and on nights
/// nothing is. It's a plan, never counted as sleep.
class SleepSchedule {
  const SleepSchedule({
    required this.bed,
    required this.wake,
    this.weekendBed,
    this.weekendWake,
  });

  /// 11:30 PM to 7 AM, the starting point before anything is chosen.
  static const fallback = SleepSchedule(bed: 23 * 60 + 30, wake: 7 * 60);

  final int bed, wake;

  /// Friday and Saturday nights, when they differ from the rest of the week.
  final int? weekendBed, weekendWake;

  bool get weekendsDiffer => weekendBed != null && weekendWake != null;

  /// Your usual times from tracked [nights], for prefilling the schedule:
  /// medians rounded to quarter-hours, with weekend times when at least two
  /// weekend nights differ by half an hour or more. Null under three nights.
  static SleepSchedule? fromNights(Iterable<SleepPeriod> nights) {
    final all = nights.where((n) => n.end.isAfter(n.start)).toList();
    if (all.length < 3) return null;
    bool weekend(SleepPeriod n) => n.end.weekday >= DateTime.saturday;
    // Minutes from the wake day's midnight, so an 11:30 PM bedtime is -30
    // and the median doesn't wrap.
    int clock(DateTime t, DateTime wake) =>
        t.difference(DateTime(wake.year, wake.month, wake.day)).inMinutes;
    ({int bed, int wake}) usual(List<SleepPeriod> ns) {
      int median(Iterable<int> values) =>
          (values.toList()..sort())[values.length ~/ 2];
      int quarter(int minutes) => (minutes / 15).round() * 15 % 1440;
      return (
        bed: quarter(median([for (final n in ns) clock(n.start, n.end)])),
        wake: quarter(median([for (final n in ns) clock(n.end, n.end)])),
      );
    }

    final weekdays = all.where((n) => !weekend(n)).toList();
    final weekends = all.where(weekend).toList();
    final week = usual(weekdays.length >= 2 ? weekdays : all);
    final end = weekends.length >= 2 ? usual(weekends) : null;
    int apart(int a, int b) {
      final d = (a - b).abs() % 1440;
      return d < 720 ? d : 1440 - d;
    }

    final differs =
        end != null &&
        (apart(end.bed, week.bed) >= 30 || apart(end.wake, week.wake) >= 30);
    return SleepSchedule(
      bed: week.bed,
      wake: week.wake,
      weekendBed: differs ? end.bed : null,
      weekendWake: differs ? end.wake : null,
    );
  }

  static SleepSchedule? fromPreferences(Map? preferences) {
    final map = preferences?['sleepSchedule'];
    if (map is! Map) return null;
    int? minutes(String key) => (map[key] as num?)?.toInt();
    final bed = minutes('bed');
    final wake = minutes('wake');
    if (bed == null || wake == null) return null;
    return SleepSchedule(
      bed: bed,
      wake: wake,
      weekendBed: minutes('weekendBed'),
      weekendWake: minutes('weekendWake'),
    );
  }

  Map<String, int> toMap() => {
    'bed': bed,
    'wake': wake,
    if (weekendsDiffer) ...{
      'weekendBed': weekendBed!,
      'weekendWake': weekendWake!,
    },
  };

  /// The usual night ending on [day]'s morning: weekend times for Saturday
  /// and Sunday mornings.
  SleepPeriod nightEnding(DateTime day) {
    final weekend = weekendsDiffer && day.weekday >= DateTime.saturday;
    final date = DateTime(day.year, day.month, day.day);
    final end = date.add(Duration(minutes: weekend ? weekendWake! : wake));
    var start = date.add(Duration(minutes: weekend ? weekendBed! : bed));
    // An 11:30 PM bedtime is the evening before; 12:30 AM is the same date.
    if (!start.isBefore(end)) start = start.subtract(const Duration(days: 1));
    return (start: start, end: end);
  }
}

/// Saves [schedule] for the signed-in user, replacing the whole map so
/// turning "Weekends are different" off drops the weekend times.
Future<void> saveSleepSchedule(SleepSchedule schedule) {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return FirebaseFirestore.instance.collection('users').doc(uid).set({
    'preferences': {'sleepSchedule': schedule.toMap()},
  }, SetOptions(mergeFields: ['preferences.sleepSchedule']));
}
