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
import 'package:vivordo_health/src/services/daily_priority_service.dart';
import 'package:vivordo_health/src/utils/training_load_view.dart';

class HomeWidgetService {
  const HomeWidgetService._();

  static const int siriSnapshotSchemaVersion = 1;

  static const MethodChannel _channel = MethodChannel(
    'com.vivordo.health/home_widgets',
  );
  static String? _lastSignature;
  static String? _lastCalendarSignature;
  static bool _publishing = false;
  static bool _publishingCalendar = false;
  static DateTime? _lastCalendarRefresh;
  static String? _siriUid;
  static String? _siriGeneration;

  /// A token per signed-in account in Siri's snapshot, so Siri never speaks
  /// one account's data after another signs in.
  static String _siriGenerationFor(String uid) {
    if (_siriUid != uid || _siriGeneration == null) {
      _siriUid = uid;
      _siriGeneration =
          '${DateTime.now().microsecondsSinceEpoch}-${uid.hashCode}';
    }
    return _siriGeneration!;
  }

  static StreamSubscription<List<DailyPriority>>? _prioritySubscription;
  static String? _priorityScope;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _capacitySubscription;
  static String? _capacityScope;

  /// Keeps the Capacity widget current: Capacity is calculated on the
  /// server (scores_daily) and changes when sleep syncs, a check-in is
  /// answered or yesterday's Effort settles, not only when Home refreshes.
  static void _watchCapacity() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final yesterday = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime(now.year, now.month, now.day - 1));
    final scope = '${user.uid}|$today';
    if (_capacityScope == scope) return;
    _capacityScope = scope;
    unawaited(_capacitySubscription?.cancel());
    _capacitySubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('scores_daily')
        .where(FieldPath.documentId, whereIn: [yesterday, today])
        .snapshots()
        .listen(
          (snapshot) async {
            if (_capacityScope != scope) return;
            Map<String, dynamic>? day(String key) =>
                snapshot.docs.where((d) => d.id == key).firstOrNull?.data();
            try {
              await _channel.invokeMethod<void>('updateSnapshot', {
                ...capacityWidgetValues(day(today), day(yesterday)),
                'capacityDay': today,
                ...siriScoreValues(day(today), day(yesterday)),
              });
            } catch (error) {
              debugPrint('Capacity widget update failed: $error');
            }
          },
          onError: (Object error) =>
              debugPrint('Widget Capacity unavailable: $error'),
        );
  }

  static int _accountGeneration = 0;

  static void _watchWidgetPriorities() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final scope = '${user.uid}|$day';
    if (_priorityScope == scope) return;
    _priorityScope = scope;
    unawaited(_prioritySubscription?.cancel());
    _prioritySubscription = DailyPriorityService.watch(DateTime.now()).listen(
      (priorities) async {
        if (_priorityScope != scope) return;
        try {
          await _channel.invokeMethod<void>('updateSnapshot', {
            'dashboardPrioritiesDay': day,
            'dashboardPriorities': priorities
                .map(
                  (priority) => {
                    'title': priority.title,
                    'source': priority.source,
                    'isAllDay': priority.isAllDay,
                    if (priority.sourceStart != null)
                      'startAt': priority.sourceStart!.millisecondsSinceEpoch,
                    'completed': priority.completed,
                    'time': priority.isAllDay
                        ? 'All day'
                        : priority.sourceStart == null
                        ? 'Anytime'
                        : DateFormat('h:mm a').format(priority.sourceStart!),
                  },
                )
                .toList(),
          });
        } catch (error) {
          debugPrint('Dashboard widget priorities failed: $error');
        }
      },
      onError: (Object error) =>
          debugPrint('Widget priorities unavailable: $error'),
    );
  }

  static String? _lastDemandSignature;
  static String? _lastMeetingsSignature;

  static Future<void> _publishDemand(
    double demand,
    String headline,
    bool tomorrow,
  ) async {
    if (!Platform.isIOS) return;
    // Tomorrow's Demand (in the evening) isn't today's: Siri leaves it out.
    final value = tomorrow ? -1 : demand.round().clamp(0, 100);
    final signature = '$value|$headline|${DateTime.now().hour}';
    if (_lastDemandSignature == signature) return;
    _lastDemandSignature = signature;
    try {
      await _channel.invokeMethod<void>('updateSnapshot', {
        'siriDemand': value,
        'siriDemandHeadline': tomorrow ? '' : headline,
        'siriDemandAt': DateTime.now().millisecondsSinceEpoch,
      });
    } on MissingPluginException {
      // iOS builds only.
    } on PlatformException catch (error) {
      debugPrint('Siri Demand update failed: ${error.message}');
    }
  }

  static Future<void> _publishMeetings(
    List<({String title, DateTime start, bool high, String lift})> meetings,
  ) async {
    if (!Platform.isIOS) return;
    final values = [
      for (final m in meetings)
        {
          'title': m.title,
          'startAt': m.start.millisecondsSinceEpoch,
          'high': m.high,
          'lift': m.lift,
        },
    ];
    final signature = values.toString();
    if (_lastMeetingsSignature == signature) return;
    _lastMeetingsSignature = signature;
    try {
      await _channel.invokeMethod<void>('updateSnapshot', {
        'siriMeetingPatterns': values,
      });
    } on MissingPluginException {
      // iOS builds only.
    } on PlatformException catch (error) {
      debugPrint('Siri meetings update failed: ${error.message}');
    }
  }

  static Future<void> configureLaunchHandler(
    Future<bool> Function(String destination) onWidgetLaunch,
  ) async {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'widgetTapped') return false;
      final destination = call.arguments as String?;
      if (destination == null) return false;
      return onWidgetLaunch(destination);
    });

    try {
      final destination = await _channel.invokeMethod<String>(
        'consumeWidgetLaunch',
      );
      if (destination != null && await onWidgetLaunch(destination)) {
        await _channel.invokeMethod<void>('completeWidgetLaunch', destination);
      }
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
    _accountGeneration++;
    _priorityScope = null;
    await _prioritySubscription?.cancel();
    _prioritySubscription = null;
    _capacityScope = null;
    await _capacitySubscription?.cancel();
    _capacitySubscription = null;
    _lastSignature = null;
    _lastCalendarSignature = null;
    _lastDemandSignature = null;
    _lastMeetingsSignature = null;
    _lastCalendarRefresh = null;
    _siriUid = null;
    _siriGeneration = null;
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('updateSnapshot', {
        'siriSchemaVersion': 0,
        'siriAccountGeneration': '',
        'siriPublishedAt': 0,
        'siriDataDay': '',
        'stressScore': 0,
        'siriStressScore': -1,
        'stressUpdatedAt': 0,
        'stressDrivers': <String>[],
        ...capacityWidgetValues(null, null),
        ...siriScoreValues(null, null),
        'siriDemand': -1,
        'siriDemandHeadline': '',
        'siriDemandAt': 0,
        'siriMeetingPatterns': <Map<String, Object>>[],
        'steps': 0,
        'stepsGoal': 0,
        'activeCalories': 0,
        'activeCaloriesGoal': 0,
        'exerciseMinutes': 0,
        'exerciseGoal': 0,
        'heartRateLatest': 0,
        'siriHeartRateLatest': -1,
        'heartRateLatestAt': 0,
        'heartRateAverage': 0,
        'siriHeartRateAverage': -1,
        'heartRateMinimum': 0,
        'siriHeartRateMinimum': -1,
        'heartRateMaximum': 0,
        'siriHeartRateMaximum': -1,
        'sleepHours': 0,
        'siriSleepHours': -1,
        'sleepUpdatedAt': 0,
        'sleepStages': <String>[],
        'calendarEvents': <Map<String, Object>>[],
        'siriCalendarEvents': <Map<String, Object>>[],
        'calendarWeekUpdatedAt': 0,
        'dashboardEvents': <Map<String, Object>>[],
        'dashboardPriorities': <Map<String, Object>>[],
        'dashboardPrioritiesDay': '',
        'dashboardMetricsDay': '',
        'dashboardName': '',
        'dashboardHasStress': false,
        'dashboardMetricsUpdatedAt': 0,
        'dashboardCalendarConnected': false,
      });
    } on MissingPluginException {
      // The native widget is available after installing an iOS build.
    } on PlatformException catch (error) {
      debugPrint('Home widget account cleanup failed: ${error.message}');
    }
  }

  static Future<void> publish({
    required double? stressScore,
    required int steps,
    required int activeCalories,
    required int exerciseMinutes,
    required ActivityGoals goals,
    int? latestHeartRate,
    DateTime? latestHeartRateAt,
    double? averageHeartRate,
    double? minimumHeartRate,
    double? maximumHeartRate,
    double? sleepHours,
    DateTime? sleepUpdatedAt,
    List<String> sleepStages = const [],
    DateTime? stressUpdatedAt,
    List<String> stressDrivers = const [],
  }) async {
    if (!Platform.isIOS) return;
    _watchWidgetPriorities();
    _watchCapacity();
    unawaited(refreshCalendarSnapshot());
    if (_publishing) return;
    _publishing = true;
    final generation = _accountGeneration;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await clearAccountSnapshot();
        return;
      }

      final values = <String, Object>{
        'siriSchemaVersion': siriSnapshotSchemaVersion,
        'siriAccountGeneration': _siriGenerationFor(user.uid),
        'siriPublishedAt': DateTime.now().millisecondsSinceEpoch,
        'siriDataDay': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'dashboardName': user.displayName?.trim().split(' ').first ?? '',
        'dashboardMetricsDay': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'dashboardHasStress': stressScore != null,
        'stressScore': stressScore?.round().clamp(0, 100) ?? 0,
        'siriStressScore': stressScore?.round().clamp(0, 100) ?? -1,
        'stressUpdatedAt': stressUpdatedAt?.millisecondsSinceEpoch ?? 0,
        'stressDrivers': stressDrivers,
        'steps': steps,
        'stepsGoal': goals.steps,
        'activeCalories': activeCalories,
        'activeCaloriesGoal': goals.activeCalories,
        'exerciseMinutes': exerciseMinutes,
        'exerciseGoal': goals.exerciseMinutes,
        'heartRateLatest': latestHeartRate ?? 0,
        'siriHeartRateLatest': latestHeartRate ?? -1,
        'heartRateLatestAt': latestHeartRateAt?.millisecondsSinceEpoch ?? 0,
        'heartRateAverage': averageHeartRate ?? 0,
        'siriHeartRateAverage': averageHeartRate ?? -1,
        'heartRateMinimum': minimumHeartRate ?? 0,
        'siriHeartRateMinimum': minimumHeartRate ?? -1,
        'heartRateMaximum': maximumHeartRate ?? 0,
        'siriHeartRateMaximum': maximumHeartRate ?? -1,
        'sleepHours': sleepHours ?? 0,
        'siriSleepHours': sleepHours ?? -1,
        'sleepUpdatedAt': sleepUpdatedAt?.millisecondsSinceEpoch ?? 0,
        'sleepStages': sleepStages,
      };
      final signature = values.entries
          .where((entry) => entry.key != 'siriPublishedAt')
          .map((entry) => '${entry.key}:${entry.value}')
          .join('|');
      if (_lastSignature == signature) return;
      if (generation != _accountGeneration) return;
      _lastSignature = signature;

      // Stamped after the signature so an unchanged snapshot is still skipped.
      await _channel.invokeMethod<void>('updateSnapshot', {
        ...values,
        'dashboardMetricsUpdatedAt': DateTime.now().millisecondsSinceEpoch,
      });
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
    final generation = _accountGeneration;
    _lastCalendarRefresh = now;
    try {
      final monday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      // On Sunday the widgets' "tomorrow" is next Monday, so fetch one extra
      // day. Other days keep the exact week range the calendar screens cache.
      final end = monday.add(
        Duration(days: now.weekday == DateTime.sunday ? 8 : 7),
      );
      final googleFuture = CalendarService.getEventsBetween(monday, end);
      final outlookFuture = OutlookCalendarService.getEventsBetween(
        monday,
        end,
      );
      final googleEvents = await googleFuture;
      final outlookEvents = await outlookFuture;
      if (generation != _accountGeneration) return;
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
    final compactEvents = <Map<String, Object>>[];
    // No per-day cap: the widget hides finished events, so it needs the later
    // ones too.
    for (final event in events) {
      final signature = '${event['title']}|${event['startAt']}';
      if (seen.add(signature)) compactEvents.add(event);
    }

    final signature = compactEvents
        .map(
          (event) =>
              '${event['title']}:${event['startAt']}:${event['endAt']}:${event['kind']}',
        )
        .join('|');
    try {
      final generation = _accountGeneration;
      final connected =
          CalendarService.connectionNotifier.value ||
          await OutlookCalendarService.isSignedIn();
      if (generation != _accountGeneration) return;
      final dashboardSignature =
          '$signature|${events.toString()}|$connected|${DateFormat('yyyy-MM-dd').format(DateTime.now())}';
      if (_lastCalendarSignature == dashboardSignature) return;
      await _channel.invokeMethod<void>('updateSnapshot', {
        'calendarEvents': compactEvents,
        'siriCalendarEvents': compactEvents.take(100).toList(growable: false),
        'dashboardEvents': events,
        'dashboardCalendarConnected': connected,
        'calendarWeekUpdatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      if (generation == _accountGeneration) {
        _lastCalendarSignature = dashboardSignature;
      }
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

/// Siri's training load and sleep need, from the same documents: training
/// load is calculated each morning, so yesterday's stands in until today's.
Map<String, Object> siriScoreValues(
  Map<String, dynamic>? today,
  Map<String, dynamic>? yesterday,
) {
  final load =
      TrainingLoadView.fromMap(today?['trainingLoad'], 'today') ??
      (today?['trainingLoad'] == null
          ? TrainingLoadView.fromMap(yesterday?['trainingLoad'], 'yesterday')
          : null);
  final need = ((today?['capacity'] as Map?)?['sleepNeed'] as num?)?.toDouble();
  return {
    'siriTrainingState': load?.state ?? '',
    'siriTrainingRatio': load?.ratio ?? -1,
    'siriTrainingHardDays': load?.hardDays ?? -1,
    'siriSleepNeed': need ?? -1,
  };
}

/// Siri's copy of My Day's Demand and headline, so "How's my day?" says
/// what My Day says.
Future<void> publishSiriDemand({
  required double demand,
  required String headline,
  required bool tomorrow,
}) => HomeWidgetService._publishDemand(demand, headline, tomorrow);

/// Today's meetings with a heart-rate pattern, for Siri.
Future<void> publishSiriMeetings(
  List<({String title, DateTime start, bool high, String lift})> meetings,
) => HomeWidgetService._publishMeetings(meetings);

/// What the Capacity widget shows, from today's and yesterday's
/// `scores_daily` documents: the score and its label, the change from
/// yesterday (same formula version, and only once today's isn't waiting
/// for sleep), and a note while it's provisional.
Map<String, Object> capacityWidgetValues(
  Map<String, dynamic>? today,
  Map<String, dynamic>? yesterday,
) {
  final capacity = today?['capacity'];
  if (capacity is! Map || capacity['score'] is! num) {
    return {
      'dashboardHasCapacity': false,
      'capacityScore': 0,
      'capacityDelta': 0,
      'capacityLabel': '',
      'capacityNote': '',
    };
  }
  final score = (capacity['score'] as num).round();
  final provisional = capacity['provisional'] == true;
  final prior = yesterday?['capacity'];
  final parts = capacity['parts'];
  return {
    'dashboardHasCapacity': true,
    'capacityScore': score.clamp(0, 100),
    'capacityDelta':
        !provisional &&
            prior is Map &&
            prior['score'] is num &&
            prior['version'] == capacity['version']
        ? score - (prior['score'] as num).round()
        : 0,
    'capacityLabel': capacity['label'] is String ? capacity['label'] : '',
    'capacityNote': !provisional
        ? ''
        : parts is Map && parts['sleep'] == null && parts['body'] == null
        ? 'Based on your check-in'
        : 'Waiting for sleep',
  };
}
