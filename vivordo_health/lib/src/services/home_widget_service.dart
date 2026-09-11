import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/src/services/outlook_calendar_service.dart';

class HomeWidgetService {
  const HomeWidgetService._();

  static const MethodChannel _channel = MethodChannel(
    'com.vivordo.health/home_widgets',
  );
  static String? _lastSignature;
  static String? _lastCalendarSignature;
  static bool _publishing = false;
  static bool _publishingCalendar = false;
  static DateTime? _lastCalendarRefresh;

  static Future<void> configureLaunchHandler(
    Future<void> Function(String destination) onWidgetLaunch,
  ) async {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'widgetTapped') return;
      final destination = call.arguments as String?;
      if (destination != null) await onWidgetLaunch(destination);
    });

    try {
      final destination = await _channel.invokeMethod<String>(
        'consumeWidgetLaunch',
      );
      if (destination != null) await onWidgetLaunch(destination);
    } on MissingPluginException {
      // Expected until the native widget-enabled build has been installed.
    } on PlatformException catch (error) {
      debugPrint('Home widget launch could not be consumed: $error');
    }
  }

  static void clearLaunchHandler() {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler(null);
  }

  static Future<void> clearAccountSnapshot() async {
    _lastSignature = null;
    _lastCalendarSignature = null;
    _lastCalendarRefresh = null;
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('updateSnapshot', {
        'stressScore': 0,
        'wellnessScore': 0,
        'wellnessDelta': 0,
        'steps': 0,
        'stepsGoal': 0,
        'activeCalories': 0,
        'activeCaloriesGoal': 0,
        'exerciseMinutes': 0,
        'exerciseGoal': 0,
        'calendarEvents': <Map<String, Object>>[],
        'calendarWeekUpdatedAt': 0,
      });
    } on MissingPluginException {
      // The native widget is available after installing an iOS build.
    } on PlatformException catch (error) {
      debugPrint('Home widget account cleanup failed: ${error.message}');
    }
  }

  static Future<void> publish({
    required double? stressScore,
    required double? wellnessScore,
    required int steps,
    required int activeCalories,
    required int exerciseMinutes,
    required ActivityGoals goals,
  }) async {
    if (!Platform.isIOS) return;
    unawaited(refreshCalendarSnapshot());
    if (_publishing) return;
    _publishing = true;

    try {
      var wellnessDelta = 0;
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && wellnessScore != null) {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('metrics_daily')
            .doc(DateFormat('yyyy-MM-dd').format(yesterday))
            .get();
        final prior = ((snapshot.data()?['wellness'] as Map?)?['avg'] as num?)
            ?.toDouble();
        if (prior != null) wellnessDelta = (wellnessScore - prior).round();
      }

      final values = <String, Object>{
        'stressScore': stressScore?.round().clamp(0, 100) ?? 0,
        'wellnessScore': wellnessScore?.round().clamp(0, 100) ?? 0,
        'wellnessDelta': wellnessDelta,
        'steps': steps,
        'stepsGoal': goals.steps,
        'activeCalories': activeCalories,
        'activeCaloriesGoal': goals.activeCalories,
        'exerciseMinutes': exerciseMinutes,
        'exerciseGoal': goals.exerciseMinutes,
      };
      final signature = values.entries
          .map((entry) => '${entry.key}:${entry.value}')
          .join('|');
      if (_lastSignature == signature) return;
      _lastSignature = signature;

      await _channel.invokeMethod<void>('updateSnapshot', values);
    } on MissingPluginException {
      // Widgets are an iOS-only enhancement; Android and tests can ignore it.
    } on PlatformException catch (error) {
      debugPrint('Home widget update failed: ${error.message}');
    } catch (error) {
      debugPrint('Home widget snapshot failed: $error');
    } finally {
      _publishing = false;
    }
  }

  static Future<void> refreshCalendarSnapshot({bool force = false}) async {
    if (!Platform.isIOS || _publishingCalendar) return;
    final now = DateTime.now();
    if (!force &&
        _lastCalendarRefresh != null &&
        now.difference(_lastCalendarRefresh!) < const Duration(minutes: 15)) {
      return;
    }

    _publishingCalendar = true;
    _lastCalendarRefresh = now;
    try {
      final monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      final googleFuture = CalendarService.getWeekEvents(monday);
      final outlookFuture = OutlookCalendarService.getWeekEvents(monday);
      final googleEvents = await googleFuture;
      final outlookEvents = await outlookFuture;
      await publishCalendarEvents(
        googleEvents: googleEvents,
        outlookEvents: outlookEvents,
      );
    } catch (error) {
      debugPrint('Calendar widget refresh failed: $error');
    } finally {
      _publishingCalendar = false;
    }
  }

  static Future<void> publishCalendarEvents({
    required List<gcal.Event> googleEvents,
    required List<OutlookEvent> outlookEvents,
  }) async {
    if (!Platform.isIOS) return;

    final events = <Map<String, Object>>[];
    for (final event in googleEvents) {
      if (event.status == 'cancelled') continue;
      final DateTime? timedStart = event.start?.dateTime?.toLocal();
      final DateTime? allDayStart = event.start?.date?.toLocal();
      final start = timedStart ?? allDayStart;
      if (start == null) continue;
      final DateTime? timedEnd = event.end?.dateTime?.toLocal();
      final DateTime? allDayEnd = event.end?.date?.toLocal();
      final end = timedEnd ?? allDayEnd ?? start.add(const Duration(hours: 1));
      final title = event.summary?.trim();
      events.add(
        _calendarEventMap(
          title: title?.isNotEmpty == true ? title! : 'Calendar event',
          start: start,
          end: end,
          isAllDay: timedStart == null,
        ),
      );
    }

    for (final event in outlookEvents) {
      events.add(
        _calendarEventMap(
          title: event.subject.trim().isNotEmpty
              ? event.subject.trim()
              : 'Calendar event',
          start: event.start.toLocal(),
          end: event.end.toLocal(),
          isAllDay: event.isAllDay,
        ),
      );
    }

    events.sort((a, b) => (a['startAt'] as int).compareTo(b['startAt'] as int));

    final seen = <String>{};
    final perDay = <String, int>{};
    final compactEvents = <Map<String, Object>>[];
    for (final event in events) {
      final start = DateTime.fromMillisecondsSinceEpoch(
        event['startAt'] as int,
      );
      final dayKey = DateFormat('yyyy-MM-dd').format(start);
      final signature = '${event['title']}|${event['startAt']}';
      if (!seen.add(signature) || (perDay[dayKey] ?? 0) >= 3) continue;
      perDay[dayKey] = (perDay[dayKey] ?? 0) + 1;
      compactEvents.add(event);
    }

    final signature = compactEvents
        .map(
          (event) => '${event['title']}:${event['startAt']}:${event['kind']}',
        )
        .join('|');
    if (_lastCalendarSignature == signature) return;
    _lastCalendarSignature = signature;

    try {
      await _channel.invokeMethod<void>('updateSnapshot', {
        'calendarEvents': compactEvents,
        'calendarWeekUpdatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } on MissingPluginException {
      // The native calendar widget is available after installing an iOS build.
    } on PlatformException catch (error) {
      debugPrint('Calendar widget update failed: ${error.message}');
    }
  }

  static Map<String, Object> _calendarEventMap({
    required String title,
    required DateTime start,
    required DateTime end,
    required bool isAllDay,
  }) {
    return <String, Object>{
      'title': title,
      'startAt': start.millisecondsSinceEpoch,
      'endAt': end.millisecondsSinceEpoch,
      'isAllDay': isAllDay,
      'kind': _calendarEventKind(title),
    };
  }

  static String _calendarEventKind(String title) {
    final normalized = title.toLowerCase();
    if (RegExp(r'run|jog|walk|hike').hasMatch(normalized)) return 'running';
    if (RegExp(
      r'workout|gym|strength|lift|yoga|pilates|cycling|swim',
    ).hasMatch(normalized)) {
      return 'fitness';
    }
    if (RegExp(
      r'soccer|basketball|football|hockey|tennis|pickleball|volleyball|baseball|golf|rugby|boxing|badminton|ski|lacrosse|squash',
    ).hasMatch(normalized)) {
      return 'sport';
    }
    return 'calendar';
  }
}
