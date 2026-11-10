import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../widgets/energy_forecast_view.dart' show energyWindowText;
import '../utils/access_recap.dart';
import '../utils/day_key.dart';
import '../utils/energy_forecast.dart';
import '../utils/server_capacity.dart';
import '../utils/sleep_nights.dart';
import 'calendar_service.dart';
import 'meeting_patterns_service.dart';

/// Gathers the paywall's recap when access has ended (access_recap.dart).
/// Each part is read on its own, so one that fails only drops its line.
class AccessRecapService {
  AccessRecapService._();

  /// The recap for access that ended at [endedAt] (now when unknown): the
  /// last month for a [trial], else since the first scored day, up to a
  /// year.
  static Future<AccessRecap> load({
    required String uid,
    required bool trial,
    DateTime? endedAt,
  }) async {
    final now = DateTime.now();
    final to = endedAt == null || endedAt.isAfter(now) ? now : endedAt;
    final user = FirebaseFirestore.instance.collection('users').doc(uid);
    var from = DateTime(to.year, to.month - 1, to.day);
    if (!trial) {
      from = DateTime(to.year - 1, to.month, to.day);
      final first = await _guard(
        () => user
            .collection('scores_daily')
            .orderBy(FieldPath.documentId)
            .where(
              FieldPath.documentId,
              isGreaterThanOrEqualTo: localDayKey(from),
            )
            .limit(1)
            .get(),
      );
      final start = DateTime.tryParse(first?.docs.firstOrNull?.id ?? '');
      if (start != null && start.isAfter(from)) from = start;
    }

    Future<Map<String, Map<String, dynamic>>> range(
      String name,
      DateTime start,
    ) async {
      final snapshot = await _guard(
        () => user
            .collection(name)
            .where(
              FieldPath.documentId,
              isGreaterThanOrEqualTo: localDayKey(start),
            )
            .where(FieldPath.documentId, isLessThanOrEqualTo: localDayKey(to))
            .get(),
      );
      return {for (final d in snapshot?.docs ?? const []) d.id: d.data()};
    }

    final (scores, fixDays, sleep, meetings) = await (
      range('scores_daily', from),
      range('day_fixes', from),
      range('metrics_daily', to.subtract(const Duration(days: 14))),
      _guard(MeetingPatternsService.load),
    ).wait;

    // The forecast's peak on a usual day, from the last two weeks' nights.
    final nights = sleepNights(sleep.values);
    final peak = nights.isEmpty
        ? null
        : forecastEnergy(
            day: to,
            nights: nights,
            sleepNeedHours: latestSleepNeed(scores),
          ).window(EnergyPhase.peak);

    final meeting = [...?meetings?.patterns.high]
        .where((p) => !p.isSeries || MeetingPatternsService.names[p.id] != null)
        .firstOrNull;

    return accessRecap(
      from: from,
      to: to,
      scores: scores,
      fixDays: fixDays,
      focus: peak == null ? null : energyWindowText(peak),
      freeFocusDays: peak == null ? null : await _freeDays(peak, to),
      meeting: meeting,
      meetingName: meeting == null
          ? null
          : MeetingPatternsService.names[meeting.id],
    );
  }

  /// Weekdays a week, over the 4 weeks to [to], when the calendar had
  /// nothing during [peak]'s hours. Null without calendar access.
  static Future<int?> _freeDays(EnergyWindow peak, DateTime to) async {
    final end = DateTime(to.year, to.month, to.day);
    final start = end.subtract(const Duration(days: 28));
    final events = await _guard(() async {
      if (!await CalendarService.hasCalendarAccess()) return null;
      return CalendarService.getEventsBetween(
        start,
        end,
      ).timeout(const Duration(seconds: 10));
    });
    if (events == null) return null;
    var free = 0;
    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      if (d.weekday > DateTime.friday) continue;
      final from = DateTime(
        d.year,
        d.month,
        d.day,
        peak.start.hour,
        peak.start.minute,
      );
      final until = DateTime(
        d.year,
        d.month,
        d.day,
        peak.end.hour,
        peak.end.minute,
      );
      final busy = events.any((e) {
        final s = e.start?.dateTime?.toLocal(), f = e.end?.dateTime?.toLocal();
        return s != null && f != null && s.isBefore(until) && f.isAfter(from);
      });
      if (!busy) free++;
    }
    return (free / 4).round();
  }

  static Future<T?> _guard<T>(Future<T?> Function() read) async {
    try {
      return await read();
    } catch (error) {
      debugPrint('Access recap part failed: $error');
      return null;
    }
  }
}
