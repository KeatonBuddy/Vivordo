import 'dart:async';
import '../widgets/contextual_insight_bar.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';

import '../src/services/calendar_cognitive_load_service.dart';
import '../src/services/calendar_service.dart';
import '../src/services/daily_priority_service.dart';
import '../src/services/day_record_service.dart';
import '../src/services/outlook_calendar_service.dart';
import '../src/utils/back_to_back_events.dart';
import '../src/utils/body_reaction.dart';
import '../src/utils/daily_brief_metrics.dart';
import '../src/utils/daily_brief_analysis.dart';
import '../src/utils/day_agenda.dart';
import '../src/utils/day_effort.dart';
import '../src/utils/day_wrap_up.dart';
import '../src/utils/heart_rate_history.dart';
import '../src/utils/home_day_load.dart';
import '../src/utils/my_day_planning_insight.dart';
import '../src/utils/home_metrics_summary.dart';
import '../widgets/add_calendar_event_sheet.dart';
import '../widgets/add_priority_sheet.dart';
import '../widgets/apple_ui.dart';
import '../widgets/body_reaction_view.dart';
import '../widgets/day_timeline.dart';
import '../widgets/swipe_to_delete.dart';
import '../widgets/habit_chips.dart';
import '../src/utils/priority_schedule.dart';
import '../widgets/plan_slot_sheet.dart';
import 'journal_screen.dart';
import 'month_calendar_screen.dart';
import 'all_priorities_screen.dart';
import '../widgets/tomorrow_preview.dart';
import '../widgets/daily_brief_card.dart';
import '../src/utils/owned_stream_snapshot.dart';
import '../src/utils/server_capacity.dart';
import '../src/services/metrics_repository.dart';
import '../src/utils/day_key.dart';
import '../widgets/burnout_card.dart';
import '../widgets/training_load_card.dart';
import '../widgets/meeting_patterns_view.dart';
import '../src/services/meeting_patterns_service.dart';
import '../src/utils/meeting_patterns.dart';
import '../src/utils/training_load_view.dart';
import '../src/utils/burnout_view.dart';
import '../src/utils/day_fixes.dart';
import '../src/utils/energy_fit.dart';
import '../src/utils/energy_forecast.dart';
import '../src/utils/sleep_schedule.dart';
import '../src/services/wind_down_reminder.dart';
import '../widgets/day_fixes_card.dart';
import '../widgets/energy_forecast_view.dart';

class MyDayScreen extends StatefulWidget {
  const MyDayScreen({
    super.key,
    this.actionsKey,
    this.briefKey,
    this.nowKey,
    this.prioritiesKey,
    this.timelineKey,
    this.tomorrowKey,
  });

  /// Spotlight targets for the My Day tour.
  final Key? actionsKey;
  final Key? briefKey;
  final Key? nowKey;
  final Key? prioritiesKey;
  final Key? timelineKey;
  final Key? tomorrowKey;

  static const purple = Color(0xFF6B5CE7);
  static const background = Color(0xFFF2F2F7);
  static const ink = Color(0xFF17172B);
  static const muted = Color(0xFF85859B);

  @override
  State<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends State<MyDayScreen> with WidgetsBindingObserver {
  List<_CalendarEvent> _events = const [];
  List<_CalendarEvent> _tomorrowEvents = const [];

  /// Ratings for today's and tomorrow's events (Claude sorts the ones the
  /// local rules can't, with AI consent), keyed by sourceEventKey.
  Map<String, CognitiveLoadScore> _eventScores = const {};
  int _wrapUpMinutes = kDefaultDayWrapUpMinutes;

  /// Your usual sleep times, for the energy forecast when no sleep is tracked.
  SleepSchedule? _sleepSchedule;

  /// `preferences.windDownReminder`: null until asked, then on or off.
  bool? _windDownReminder;

  /// The day the fixes card was hidden with its X (day_fixes/{day}.hidden).
  String? _fixesHiddenDay;

  /// The evening the tomorrow card was hidden with its X (stored as
  /// day_fixes/{tomorrow}.eveningHidden); it comes back as the morning card.
  String? _eveningFixesHiddenDay;

  /// The day the fix being applied belongs to, for logging it.
  DateTime? _openFixDay;

  /// Earlier days' fix outcomes (day_fixes, last 4 weeks), for learning
  /// which kinds of fix this person uses.
  List<FixDay> _fixHistory = const [];

  /// "day:kind" already logged as shown, so each logs once a day.
  final _fixesShown = <String>{};
  String? _calendarLoadError;
  int _loadGeneration = 0;
  bool _isLoading = true;
  DateTime? _calendarLoadedAt;
  bool _showCompleted = false;
  bool _showEarlier = false;
  Timer? _clockTimer;
  bool _screenActive = false;
  late DateTime _priorityDay;
  final _briefSnapshot = OwnedStreamSnapshot<DailyBriefMetricsSummary>();
  final _capacitySnapshot = OwnedStreamSnapshot<ServerCapacity?>();
  final _burnoutSnapshot = OwnedStreamSnapshot<BurnoutView?>();
  final _trainingLoadSnapshot = OwnedStreamSnapshot<TrainingLoadView?>();

  /// The latest nightly burnout check: it's saved on the day that just
  /// ended, so look back a few days.
  Stream<BurnoutView?> _burnoutStreamFor(DateTime day) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('scores_daily')
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: localDayKey(
            DateTime(day.year, day.month, day.day - 3),
          ),
        )
        .where(FieldPath.documentId, isLessThanOrEqualTo: localDayKey(day))
        .snapshots()
        .map((snapshot) {
          for (final doc in snapshot.docs.reversed) {
            final burnout = doc.data()['burnout'];
            if (burnout is Map<String, dynamic>) {
              return BurnoutView.fromMap(burnout, doc.id);
            }
          }
          return null;
        });
  }

  DailyBriefMetrics? _briefMetrics;

  /// Server Capacity (docs/scores.md §4) for [day], with the 28 days before
  /// it for the "usual" comparison. These are small score documents.
  Stream<ServerCapacity?> _capacityStreamFor(DateTime day) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    final format = DateFormat('yyyy-MM-dd');
    final dayKey = format.format(day);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('scores_daily')
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: format.format(
            DateTime(day.year, day.month, day.day - 28),
          ),
        )
        .where(FieldPath.documentId, isLessThanOrEqualTo: dayKey)
        .snapshots()
        .map(
          (snapshot) => serverCapacityFor({
            for (final doc in snapshot.docs) doc.id: doc.data(),
          }, dayKey),
        );
  }

  void _connectBriefMetrics(DateTime day) {
    _briefMetrics = null;
    _capacitySnapshot.connect(_capacityStreamFor(day));
    _burnoutSnapshot.connect(_burnoutStreamFor(day));
    _trainingLoadSnapshot.connect(watchTrainingLoad(day));
    final stream = _metricsStreamFor(day);
    _briefSnapshot.connect(
      (stream ?? const Stream<MetricWindow>.empty()).map((snapshot) {
        if (snapshot.error != null && snapshot.days.isEmpty) {
          throw snapshot.error!;
        }
        final metrics = DailyBriefMetrics(
          snapshot.days.entries
              .map((d) => MetricDayEntry(dayKey: d.key, data: d.value))
              .toList(),
          isFromCache: snapshot.isFromCache || snapshot.error != null,
        );
        _briefMetrics = metrics;
        return metrics.summarize(DateTime.now());
      }),
    );
  }

  void _refreshBriefClock() {
    final metrics = _briefMetrics;
    if (metrics == null || _briefSnapshot.value.hasError) return;
    final summary = metrics.summarize(DateTime.now());
    if (!identical(summary, _briefSnapshot.value.data)) {
      _briefSnapshot.value = AsyncSnapshot.withData(
        _briefSnapshot.value.connectionState,
        summary,
      );
    }
  }

  final _prioritySnapshot = OwnedStreamSnapshot<List<DailyPriority>>();
  final _tomorrowPrioritySnapshot = OwnedStreamSnapshot<List<DailyPriority>>();
  final _habitSnapshot = OwnedStreamSnapshot<List<DailyPriority>>();
  final _templateSnapshot =
      OwnedStreamSnapshot<Map<String, PriorityTemplate>>();
  DateTime get _tomorrow =>
      DateTime(_priorityDay.year, _priorityDay.month, _priorityDay.day + 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _priorityDay = DateUtils.dateOnly(DateTime.now());
    _connectBriefMetrics(_priorityDay);
    _connectPriorities();
    _loadTodayEvents();
    unawaited(_loadWrapUp());
    unawaited(_loadFixHistory());
    CalendarService.eventsChanged.addListener(_onEventsChanged);
  }

  /// Set when the calendar changed while this tab was hidden.
  bool _eventsStale = false;

  /// An event was added, moved or deleted somewhere (Home, Vivordo AI, the
  /// calendar screen): reload now, or when this tab is next shown.
  void _onEventsChanged() {
    if (!mounted) return;
    if (_screenActive) {
      unawaited(_loadTodayEvents());
    } else {
      _eventsStale = true;
    }
  }

  Future<void> _loadWrapUp() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final preferences =
          (await FirebaseFirestore.instance.collection('users').doc(uid).get())
                  .data()?['preferences']
              as Map?;
      final minutes = preferences?['dayWrapUpMinutes'];
      if (!mounted) return;
      setState(() {
        if (minutes is int) _wrapUpMinutes = minutes;
        _sleepSchedule = SleepSchedule.fromPreferences(preferences);
        _windDownReminder = preferences?['windDownReminder'] as bool?;
      });
    } catch (_) {
      // Keeps the 5 PM default.
    }
  }

  CalendarCognitiveEvent _cognitiveInput(_CalendarEvent e) =>
      CalendarCognitiveEvent(
        id: e.sourceEventKey,
        title: e.title,
        description: e.googleEvent?.description ?? '',
        start: e.start,
        end: e.end,
        attendeeCount: e.attendeeCount,
        isOrganizer: e.googleEvent?.organizer?.self == true,
        showsAsFree: e.googleEvent?.transparency == 'transparent',
        isDeclined:
            e.googleEvent?.attendees?.any(
              (a) => a.self == true && a.responseStatus == 'declined',
            ) ??
            false,
      );

  Future<void> _rateEvents(List<_CalendarEvent> events) async {
    final inputs = [
      for (final e in events)
        if (!e.isAllDay) _cognitiveInput(e),
    ];
    final scores = await CalendarCognitiveLoadService.scoreEvents(
      inputs,
      allowAi: true,
    );
    if (!mounted) return;
    setState(
      () => _eventScores = {
        for (var i = 0; i < inputs.length; i++) inputs[i].id: scores[i],
      },
    );
    if (_heartHistoryDay != null) _updateReactions();
  }

  /// Heart rate for how your body reacted to today's past events: today's
  /// readings (refetched with the schedule, and every 15 minutes) and the two
  /// weeks before (once a day). One-shot reads rather than listeners: these
  /// day documents carry large heart-rate arrays.
  List<HeartRateHistoryReading> _heartToday = const [];
  List<HeartRateHistoryReading> _heartHistory = const [];
  String? _heartHistoryDay;
  DateTime? _heartLoadedAt;

  /// Today's past events with enough heart rate to judge, by sourceEventKey.
  Map<String, BodyReaction> _reactions = const {};

  /// Repeating meetings' patterns, for the tags on upcoming events.
  MeetingPatterns _patterns = MeetingPatterns.empty;

  Future<void> _loadPatterns() async {
    final loaded = await MeetingPatternsService.load();
    if (mounted) setState(() => _patterns = loaded.patterns);
  }

  /// What each reaction was last saved with (readings and category), so it's
  /// saved again only when late-syncing samples or the event's rating change.
  final _reactionsSaved = <String, String>{};

  Future<void> _loadHeart() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final day = _priorityDay;
    final key = localDayKey(day);
    _heartLoadedAt = DateTime.now();
    final days = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily');
    List<HeartRateHistoryReading> readings(
      String id,
      Map<String, dynamic>? data,
    ) => data == null
        ? const []
        : mergedHeartRateHistory(
            data,
            fallbackDate: DateTime.parse(id),
            includeDailyFallback: false,
          );
    try {
      var history = _heartHistory;
      if (_heartHistoryDay != key) {
        final docs = await days
            .orderBy(FieldPath.documentId)
            .startAt([localDayKey(DateTime(day.year, day.month, day.day - 14))])
            .endBefore([key])
            .get();
        history = [
          for (final doc in docs.docs) ...readings(doc.id, doc.data()),
        ];
      }
      final today = await days.doc(key).get();
      if (!mounted || !DateUtils.isSameDay(day, _priorityDay)) return;
      _heartHistory = history;
      _heartHistoryDay = key;
      _heartToday = readings(key, today.data());
      _updateReactions();
      if (DateUtils.isSameDay(day, DateTime.now())) {
        unawaited(_catchUpYesterday(day));
      }
    } catch (error) {
      debugPrint('Could not load heart rate for event reactions: $error');
    }
  }

  /// The day whose yesterday was last caught up, once per app day.
  static String? _caughtUpFor;

  /// Saves reactions for yesterday's events that ended after My Day was
  /// last open (they're only worked out while it's on screen), so meeting
  /// patterns don't miss a meeting late in the day. Yesterday's readings
  /// are in [_heartHistory] already.
  Future<void> _catchUpYesterday(DateTime today) async {
    final key = localDayKey(today);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _caughtUpFor == '$uid:$key') return;
    _caughtUpFor = '$uid:$key';
    final from = DateTime(today.year, today.month, today.day - 1);
    final until = DateTime(today.year, today.month, today.day);
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('event_reactions')
            .doc(localDayKey(from))
            .get(),
        CalendarService.getEventsBetween(from, until),
        OutlookCalendarService.getEventsBetween(from, until),
      ]).timeout(const Duration(seconds: 15));
      final saved =
          (results[0] as DocumentSnapshot<Map<String, dynamic>>).data() ??
          const {};
      final events = [
        ...(results[1] as List<gcal.Event>)
            .map(_CalendarEvent.fromGoogle)
            .whereType<_CalendarEvent>(),
        ...(results[2] as List<OutlookEvent>).map(_CalendarEvent.fromOutlook),
      ];
      var added = false;
      for (final e in events) {
        // Declined, free and all-day events: not time you spent in them.
        if (!_cognitiveInput(e).contributesToSchedule ||
            !DateUtils.isSameDay(e.start, from) ||
            looksLikeExercise(e.title) ||
            saved.containsKey(reactionKey(e.sourceEventKey))) {
          continue;
        }
        final reaction = bodyReactionFor(
          start: e.start,
          end: e.end,
          today: _heartHistory,
          history: _heartHistory,
        );
        if (reaction == null) continue;
        await _saveReaction(
          e,
          reaction,
          CalendarCognitiveLoadService.scoreLocally(
            _cognitiveInput(e),
          ).category,
        );
        added = true;
      }
      if (added) MeetingPatternsService.invalidate();
    } catch (error) {
      debugPrint('Could not catch up yesterday\'s event reactions: $error');
    }
  }

  void _updateReactions() {
    final now = DateTime.now();
    final reactions = <String, BodyReaction>{};
    for (final e in _events) {
      // Exercise isn't judged: a raised heart rate there is the point.
      // Declined, free and all-day events aren't time you spent in them.
      if (!_cognitiveInput(e).contributesToSchedule ||
          e.end.isAfter(now) ||
          !DateUtils.isSameDay(e.start, now) ||
          looksLikeExercise(e.title)) {
        continue;
      }
      final reaction = bodyReactionFor(
        start: e.start,
        end: e.end,
        today: _heartToday,
        history: _heartHistory,
      );
      if (reaction == null) continue;
      reactions[e.sourceEventKey] = reaction;
      final category = _categoryOf(e);
      final saved = '${reaction.readings}:$category';
      if (_reactionsSaved[e.sourceEventKey] != saved) {
        _reactionsSaved[e.sourceEventKey] = saved;
        unawaited(_saveReaction(e, reaction, category));
      }
    }
    setState(() => _reactions = reactions);
  }

  /// Per-event history with no titles or calendar IDs (hashed keys only),
  /// for learning which kinds of event you react to. Privacy policy item 18.
  String _categoryOf(_CalendarEvent e) =>
      (_eventScores[e.sourceEventKey] ??
              CalendarCognitiveLoadService.scoreLocally(_cognitiveInput(e)))
          .category;

  Future<void> _saveReaction(
    _CalendarEvent e,
    BodyReaction r,
    String category,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final series = e.googleEvent?.recurringEventId;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('event_reactions')
          .doc(localDayKey(e.start))
          .set({
            reactionKey(e.sourceEventKey): {
              if (series != null) 'series': reactionKey('google:$series'),
              'category': category,
              'guests': e.attendeeCount,
              'minutes': e.end.difference(e.start).inMinutes,
              'startHour': e.start.hour,
              'level': r.level.name,
              'median': r.median.round(),
              'peak': r.peak.round(),
              'usual': r.usualMedian.round(),
              'readings': r.readings,
              'savedAt': FieldValue.serverTimestamp(),
              'v': 1,
            },
          }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Could not save event reaction: $error');
    }
  }

  void _showReaction(_CalendarEvent e, BodyReaction reaction) =>
      showBodyReactionSheet(
        context,
        title: e.title,
        start: e.start,
        end: e.end,
        reaction: reaction,
      );

  /// Rated items for Demand: [events] and the timed priorities on [day]
  /// that aren't linked to one of them.
  List<EffortItem> _effortItems(
    DateTime day,
    List<_CalendarEvent> events,
    List<DailyPriority> priorities,
  ) {
    final keys = {for (final e in events) e.sourceEventKey};
    return [
      for (final e in events)
        if (!e.isAllDay)
          if (_cognitiveInput(e) case final input)
            (
              event: input,
              score:
                  _eventScores[e.sourceEventKey] ??
                  CalendarCognitiveLoadService.scoreLocally(input),
              done: false,
              open: false,
            ),
      for (final p in priorities)
        if (!p.isAllDay &&
            p.sourceStart != null &&
            DateUtils.isSameDay(p.sourceStart, day) &&
            !keys.contains(_linkedKey(p)))
          if (priorityLoadInput(
                id: 'priority:${p.reference.path}',
                title: p.title,
                start: p.sourceStart!,
                end: p.timelineEnd!,
                effort: p.planning['effort'],
              )
              case final input)
            (
              event: input.event,
              score: input.score,
              done: p.completed,
              open: !p.completed,
            ),
    ];
  }

  /// Efforts of the open priorities on [day] that have no time slot there.
  List<Object?> _untimedOpen(DateTime day, List<DailyPriority> priorities) => [
    for (final p in priorities)
      if (!p.completed &&
          (p.isAllDay ||
              p.sourceStart == null ||
              !DateUtils.isSameDay(p.sourceStart, day)))
        p.planning['effort'],
  ];

  void _connectPriorities() {
    final today = _priorityDay;
    final tomorrow = _tomorrow;
    _prioritySnapshot.connectFactory(() => DailyPriorityService.watch(today));
    _tomorrowPrioritySnapshot.connectFactory(
      () => DailyPriorityService.watch(tomorrow),
    );
    _habitSnapshot.connectFactory(
      () => DailyPriorityService.watch(today, habits: true),
    );
    _templateSnapshot.connectFactory(DailyPriorityService.watchTemplates);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    _briefSnapshot.setActive(active);
    _capacitySnapshot.setActive(active);
    _burnoutSnapshot.setActive(active);
    _trainingLoadSnapshot.setActive(active);
    _prioritySnapshot.setActive(active);
    _tomorrowPrioritySnapshot.setActive(active);
    _habitSnapshot.setActive(active);
    _templateSnapshot.setActive(active);
    if (_screenActive == active) return;
    _screenActive = active;
    _clockTimer?.cancel();
    if (!active) return;
    if (!_handleDayRollover()) {
      _refreshBriefClock();
      if (_eventsStale) unawaited(_loadTodayEvents());
    }
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (!_handleDayRollover()) {
        _refreshBriefClock();
        setState(() {});
        final loaded = _heartLoadedAt;
        if (loaded != null &&
            DateTime.now().difference(loaded) > const Duration(minutes: 15)) {
          unawaited(_loadHeart());
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _screenActive) {
      if (!_handleDayRollover()) {
        _refreshBriefClock();
        // Pick up events added in the Calendar app while we were away. The
        // calendar cache (30 s) absorbs quick app switches.
        unawaited(_loadTodayEvents());
      }
    } else if (state == AppLifecycleState.resumed) {
      _eventsStale = true; // reloads when this tab is next shown
    }
  }

  bool _handleDayRollover() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (DateUtils.isSameDay(today, _priorityDay)) return false;

    setState(() {
      _priorityDay = today;
      _connectBriefMetrics(today);
      _connectPriorities();
    });
    unawaited(_loadTodayEvents());
    return true;
  }

  Stream<MetricWindow>? _metricsStreamFor(DateTime day) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final period = DateFormat('yyyy-MM-dd').format(day);
    return MetricsRepository.instance.watch(
      uid: uid,
      endDay: period,
      projection: MetricsProjection.dailyBrief,
      startDay: DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime(day.year, day.month, day.day - 28)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CalendarService.eventsChanged.removeListener(_onEventsChanged);
    _clockTimer?.cancel();
    _briefSnapshot.dispose();
    _capacitySnapshot.dispose();
    _burnoutSnapshot.dispose();
    _trainingLoadSnapshot.dispose();
    _prioritySnapshot.dispose();
    _tomorrowPrioritySnapshot.dispose();
    _habitSnapshot.dispose();
    _templateSnapshot.dispose();
    super.dispose();
  }

  /// [forceRefresh] bypasses the shared calendar cache. Used by pull-to-refresh
  /// and after the user edits an event, where reusing a cached range would
  /// show them what they just changed away from.
  Future<void> _loadTodayEvents({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    _eventsStale = false;
    if (mounted) setState(() => _isLoading = true);
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = DateTime(now.year, now.month, now.day + 1);
    final tomorrowEnd = DateTime(now.year, now.month, now.day + 2);

    late List<dynamic> results;
    try {
      results = await Future.wait([
        CalendarService.getEventsBetween(
          dayStart,
          tomorrowEnd,
          forceRefresh: forceRefresh,
        ).timeout(const Duration(seconds: 8)),
        OutlookCalendarService.getEventsBetween(
          dayStart,
          tomorrowEnd,
          forceRefresh: forceRefresh,
        ).timeout(const Duration(seconds: 8)),
      ]);
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _calendarLoadError =
              'Could not refresh the schedule. Pull down to retry.';
        });
      }
      return;
    }

    final googleEvents = results[0] as List<gcal.Event>;
    final outlookEvents = results[1] as List<OutlookEvent>;
    MeetingPatternsService.rememberNames(googleEvents);
    final allEvents = <_CalendarEvent>[
      ...googleEvents
          .map(_CalendarEvent.fromGoogle)
          .whereType<_CalendarEvent>(),
      ...outlookEvents.map(_CalendarEvent.fromOutlook),
    ].toList()..sort((a, b) => a.start.compareTo(b.start));
    final events = allEvents
        .where((e) => e.start.isBefore(dayEnd) && e.end.isAfter(dayStart))
        .toList();
    final tomorrowEvents = allEvents
        .where((e) => e.start.isBefore(tomorrowEnd) && e.end.isAfter(dayEnd))
        .toList();

    if (!mounted || generation != _loadGeneration) return;
    // The schedule may have just changed (pull to refresh, an edit).
    if (forceRefresh) unawaited(DayRecordService.sync(forceRefresh: true));
    setState(() {
      _calendarLoadedAt = DateTime.now();
      _events = events;
      _tomorrowEvents = tomorrowEvents;
      unawaited(_rateEvents([...events, ...tomorrowEvents]));
      // Tonight's reminder moves earlier for an early start tomorrow.
      unawaited(
        WindDownReminders.sync(tomorrowFirstEvent: _tomorrowFirst()?.start),
      );
      _calendarLoadError = null;
      _isLoading = false;
    });
    unawaited(_loadHeart());
    unawaited(_loadPatterns());
    try {
      await DailyPriorityService.materializeRecurring(dayStart);
      await DailyPriorityService.seedFromCalendar(
        dayStart,
        events
            .where((event) => !event.isPriorityLinked)
            .map((event) => event.priorityCandidate),
      );
      await DailyPriorityService.materializeRecurring(dayEnd);
      await DailyPriorityService.seedFromCalendar(
        dayEnd,
        tomorrowEvents
            .where((e) => !e.isPriorityLinked)
            .map((e) => e.priorityCandidate),
      );
    } catch (error) {
      debugPrint('Could not generate daily priorities: $error');
    }
  }

  Future<void> _handleEventTap(_CalendarEvent event) async {
    final googleEvent = event.googleEvent;
    if (!mounted) return;
    final action = await showModalBottomSheet<_EventSummaryAction>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EventSummarySheet(
        event: event,
        reaction: _reactions[event.sourceEventKey],
        onReaction: _showReaction,
      ),
    );
    if (googleEvent == null || !mounted) return;
    switch (action) {
      case _EventSummaryAction.edit:
        await _editGoogleEvent(googleEvent);
        return;
      case _EventSummaryAction.delete:
        await _deleteGoogleEvent(googleEvent);
        return;
      case null:
        return;
    }
  }

  Future<void> _editGoogleEvent(gcal.Event event) async {
    final result = await showEditCalendarEventSheet(context, event: event);
    if (result == null || !mounted) return;

    try {
      setState(() => _isLoading = true);
      final allEvents = result.scope == EventScope.allEvents;
      if (result.action == CalendarEventEditAction.delete) {
        await CalendarService.deleteEvent(event, scope: result.scope);
      } else {
        final draft = result.draft!;
        await CalendarService.updateEvent(
          event,
          title: draft.title,
          start: draft.start,
          end: draft.end,
          recurrence: result.recurrenceChanged ? draft.recurrence : null,
          calendarId: draft.calendarId,
          isAllDay: draft.isAllDay,
          allEvents: allEvents,
        );
      }
      await _loadTodayEvents();
      _showMessage(
        result.action == CalendarEventEditAction.delete
            ? 'Event deleted.'
            : 'Event updated.',
      );
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Save calendar event failed: $error');
      _showMessage("Couldn't save the event. Try again.", error: true);
    }
  }

  Future<void> _deleteGoogleEvent(gcal.Event event) async {
    final scope = await confirmEventDelete(
      context,
      title: event.summary ?? 'Untitled event',
      repeating: event.recurringEventId != null,
    );
    if (scope == null || !mounted) return;

    try {
      setState(() => _isLoading = true);
      await CalendarService.deleteEvent(event, scope: scope);
      await _loadTodayEvents();
      _showMessage('Event deleted.');
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Delete calendar event failed: $error');
      _showMessage("Couldn't delete the event. Try again.", error: true);
    }
  }

  Future<void> _createGoogleEvent() async {
    final now = DateTime.now();
    final initialStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.minute < 30 ? now.hour : now.hour + 1,
      now.minute < 30 ? 30 : 0,
    );
    final draft = await showAddCalendarEventSheet(
      context,
      initialStart: initialStart,
      initialEnd: initialStart.add(const Duration(hours: 1)),
    );
    if (draft == null || !mounted) return;
    await _saveGoogleEvent(draft);
  }

  Future<void> _saveGoogleEvent(CalendarEventDraft draft) async {
    try {
      setState(() => _isLoading = true);
      await saveEventDraft(draft);
      await _loadTodayEvents();
      _showMessage('Event added to Google Calendar.');
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Create calendar event failed: $error');
      _showMessage("Couldn't add the event. Try again.", error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    showToast(context, message, kind: error ? ToastKind.error : ToastKind.info);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final timedEvents = _events.where((event) => !event.isAllDay).toList();
    final watchItem = findNextBackToBackEventBlock(
      timedEvents.map(
        (event) => ScheduledEventWindow(
          title: event.title,
          start: event.start,
          end: event.end,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: colors.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadTodayEvents(forceRefresh: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 140),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Day',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('EEEE, MMMM d').format(DateTime.now()),
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    key: widget.actionsKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const JournalScreen(),
                          ),
                        ),
                        tooltip: 'Journal',
                        icon: const Icon(
                          Icons.menu_book_rounded,
                          color: MyDayScreen.purple,
                        ),
                      ),
                      IconButton(
                        onPressed: _openCalendar,
                        tooltip: 'Calendar',
                        icon: const Icon(
                          Icons.calendar_month_rounded,
                          color: MyDayScreen.purple,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (_calendarLoadError != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _calendarLoadError!,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              KeyedSubtree(
                key: widget.briefKey,
                child: _buildDayOutlookCard(timedEvents: timedEvents),
              ),
              ValueListenableBuilder<AsyncSnapshot<BurnoutView?>>(
                valueListenable: _burnoutSnapshot,
                builder: (context, snapshot, _) => snapshot.data == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: BurnoutCard(view: snapshot.data!),
                      ),
              ),
              // High or Strained only; Fitness shows every state.
              ValueListenableBuilder<AsyncSnapshot<TrainingLoadView?>>(
                valueListenable: _trainingLoadSnapshot,
                builder: (context, snapshot, _) => snapshot.data?.alert != true
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TrainingLoadAlert(view: snapshot.data!),
                      ),
              ),
              _buildEnergyEvening(),
              const SizedBox(height: 24),
              KeyedSubtree(
                key: widget.nowKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionLabel('NOW'),
                    const SizedBox(height: 10),
                    _SectionCard(child: _buildNowCard(timedEvents, watchItem)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildHabits(),
              KeyedSubtree(
                key: widget.prioritiesKey,
                child: _buildPriorities(),
              ),
              const SizedBox(height: 24),
              KeyedSubtree(
                key: widget.timelineKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: _SectionLabel("TODAY'S TIMELINE"),
                        ),
                        IconButton(
                          onPressed: _isLoading ? null : _createGoogleEvent,
                          tooltip: 'Add event',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.add_rounded,
                            color: MyDayScreen.purple,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildTimeline(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ValueListenableBuilder<AsyncSnapshot<List<DailyPriority>>>(
                valueListenable: _tomorrowPrioritySnapshot,
                builder: (context, snapshot, _) => TomorrowPreview(
                  key: widget.tomorrowKey,
                  day: _tomorrow,
                  loading:
                      _isLoading ||
                      snapshot.connectionState == ConnectionState.waiting,
                  error:
                      _calendarLoadError ??
                      (snapshot.hasError
                          ? 'Could not load tomorrow’s priorities.'
                          : null),
                  events: _tomorrowEvents
                      .map(
                        (e) => TomorrowPreviewEvent(
                          title: e.title,
                          start: e.start,
                          end: e.end,
                          allDay: e.isAllDay,
                          onTap: () => _handleEventTap(e),
                        ),
                      )
                      .toList(),
                  priorities: snapshot.data ?? const [],
                  onEdit: _editPriority,
                  onToggle: _togglePriority,
                  onViewDay: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MonthCalendarScreen(initialDay: _tomorrow),
                      ),
                    );
                    if (mounted) await _loadTodayEvents();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tomorrow's first timed event, which sets tonight's bed-by.
  _CalendarEvent? _tomorrowFirst() => ([
    for (final e in _tomorrowEvents)
      if (!e.isAllDay) e,
  ]..sort((a, b) => a.start.compareTo(b.start))).firstOrNull;

  Future<void> _setWindDownReminder(bool on, DateTime? firstEvent) async {
    final before = _windDownReminder;
    setState(() => _windDownReminder = on);
    try {
      await WindDownReminders.setEnabled(on, tomorrowFirstEvent: firstEvent);
      if (!on) {
        _showMessage(
          'No wind-down reminder. You can turn it on any time in Settings '
          'or from the Sleep screen.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _windDownReminder = before);
      _showMessage("Couldn't update your reminder.", error: true);
    }
  }

  /// Today's energy forecast (docs/scores.md §8), once any night is
  /// recorded or your usual sleep times are set. Tomorrow's first timed event
  /// sets tonight's bed-by.
  EnergyForecast? _energyForecast(DateTime today) {
    final nights = _briefSnapshot.value.data?.sleepNights ?? const [];
    if (nights.isEmpty && _sleepSchedule == null) return null;
    return forecastEnergy(
      day: today,
      nights: nights,
      sleepNeedHours: _capacitySnapshot.value.data?.sleepNeedHours,
      tomorrowFirstEvent: _tomorrowFirst()?.start,
      schedule: _sleepSchedule,
    );
  }

  /// After the end-of-day time: wind-down, bed-by and tomorrow's forecast.
  Widget _buildEnergyEvening() => ListenableBuilder(
    listenable: Listenable.merge([_briefSnapshot, _capacitySnapshot]),
    builder: (context, _) {
      final now = DateTime.now();
      final today = DateUtils.dateOnly(now);
      if (now.isBefore(today.add(Duration(minutes: _wrapUpMinutes)))) {
        return const SizedBox.shrink();
      }
      final tonight = _energyForecast(today);
      if (tonight == null) return const SizedBox.shrink();
      final first = _tomorrowFirst();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: EnergyEveningCard(
          tonight: tonight,
          tomorrow: tomorrowEnergyForecast(
            tonight: tonight,
            today: today,
            nights: _briefSnapshot.value.data?.sleepNights ?? const [],
            schedule: _sleepSchedule,
          ),
          firstEventTitle: first?.title,
          firstEventStart: first?.start,
          onTap: () => showEnergyForecastSheet(context, tonight),
          bigDayRatio: _capacitySnapshot.value.data?.todayBigDayRatio,
          reminder: _windDownReminder,
          onReminder: (on) => _setWindDownReminder(on, first?.start),
        ),
      );
    },
  );

  Widget _buildDayOutlookCard({
    required List<_CalendarEvent> timedEvents,
  }) => ValueListenableBuilder<AsyncSnapshot<DailyBriefMetricsSummary>>(
    valueListenable: _briefSnapshot,
    builder: (context, snapshot, _) {
      final summary = snapshot.data;
      final sleep = summary?.sleep;
      final usualSleep = summary?.usualSleep;
      final capacity = summary?.capacity;
      final capacityNote = summary?.capacityNote ?? 'Still learning your usual';
      final stale = summary?.stale ?? true;
      final stressTime = summary?.stressTime;
      final healthTime = summary?.healthTime;
      final now = DateTime.now();
      final calendarReady = !_isLoading && _calendarLoadError == null;
      return ValueListenableBuilder<AsyncSnapshot<ServerCapacity?>>(
        valueListenable: _capacitySnapshot,
        builder: (context, serverSnapshot, _) => ListenableBuilder(
          // Tomorrow's too: the evening brief and card are about it.
          listenable: Listenable.merge([
            _prioritySnapshot,
            _tomorrowPrioritySnapshot,
          ]),
          builder: (context, _) {
            final priorities = _prioritySnapshot.value;
            // ponytail: falls back to the old on-device Capacity until
            // computeDailyCapacity is deployed and backfilled; remove the
            // fallback (and calculateDailyCapacity) after the rollout.
            final server = serverSnapshot.data;
            final capacityScore = server?.score ?? capacity?.score;
            final capacityStale = server != null ? server.provisional : stale;
            final briefEvents = timedEvents
                .map(
                  (e) => BriefCommitment(
                    e.sourceEventKey,
                    e.title,
                    e.start,
                    e.end,
                  ),
                )
                .toList();
            final briefPriorities = (priorities.data ?? [])
                .map(
                  (p) => BriefPriority(
                    id: p.id,
                    completed: p.completed,
                    start: p.isAllDay ? null : p.sourceStart,
                    plannedDay: DateTime.tryParse(
                      p.planning['plannedDay'] as String? ?? '',
                    ),
                    minutes: (p.planning['minutes'] as num?)?.toInt(),
                    effort: p.planning['effort'] as String?,
                    eventKey: _linkedKey(p),
                  ),
                )
                .toList();
            final ready =
                calendarReady && priorities.hasData && !priorities.hasError;
            // Demand: Effort still ahead today (docs/scores.md §2). In
            // the evening, once nothing is left, tomorrow's expected
            // Demand instead.
            final today = DateUtils.dateOnly(now);
            final tomorrow = today.add(const Duration(days: 1));
            final todayPriorities = priorities.data ?? const [];
            final todayDemand = buildDayEffort(
              now: now,
              from: today,
              until: tomorrow,
              wrapUp: today.add(Duration(minutes: _wrapUpMinutes)),
              items: _effortItems(today, timedEvents, todayPriorities),
              untimedOpen: _untimedOpen(today, todayPriorities),
            );
            // Evening: past the end-of-day time with nothing timed left.
            // Open untimed priorities carry over, so they count towards
            // tomorrow rather than holding off the evening view.
            final evening =
                todayDemand.aheadMinutes == 0 &&
                !now.isBefore(today.add(Duration(minutes: _wrapUpMinutes)));
            final tomorrowPriorities =
                _tomorrowPrioritySnapshot.value.data ?? const [];
            final demand = evening
                ? buildDayEffort(
                    now: tomorrow,
                    from: tomorrow,
                    until: tomorrow.add(const Duration(days: 1)),
                    wrapUp: tomorrow.add(Duration(minutes: _wrapUpMinutes)),
                    items: _effortItems(tomorrow, [
                      for (final e in _tomorrowEvents)
                        if (!e.isAllDay) e,
                    ], tomorrowPriorities),
                    untimedOpen: _untimedOpen(tomorrow, tomorrowPriorities),
                  ).demand
                : todayDemand.demand;
            // Tomorrow is compared with your usual Capacity: tonight's
            // sleep isn't in yet, so today's says little about it.
            final usualCapacity = server?.usual?.round();
            final tomorrowCapacity = usualCapacity ?? capacityScore;
            final tomorrowHeavy =
                evening &&
                ready &&
                tomorrowCapacity != null &&
                demand > tomorrowCapacity + 15;
            // A big day in the last 3 is lowering Capacity (docs/scores.md
            // §4): say why, unless the body has already bounced back.
            final bigDay = server?.bigDay;
            final recovering = bigDay != null && !bigDay.halved;
            // Demand against Capacity, ±15 (docs/scores.md §2).
            final headline = evening
                ? tomorrowHeavy
                      ? 'Tomorrow looks heavy'
                      : 'Today’s plan is done'
                : _burnoutSnapshot.value.data?.level == 'warning'
                ? 'Give yourself a little more room today'
                : recovering
                ? bigDayHeadline(bigDay, today)
                : capacityScore == null || !ready
                ? 'Make space for your day'
                : demand <= capacityScore - 15
                ? 'Room to spare today'
                : demand > capacityScore + 15
                ? 'More than you’ve got: protect a break'
                : 'A full day ahead';
            final calendarText = ready
                ? remainingToday(
                    timedEvents.where((e) => e.end.isAfter(now)).length,
                    briefPriorities.where((p) => !p.completed).length,
                  )
                : 'Your plan isn’t fully loaded yet.';
            String timeLabel(DateTime? t) =>
                t == null ? 'unknown' : DateFormat('MMM d, h:mm a').format(t);
            if (ready) {
              latestDemand = (
                demand: demand,
                tomorrow: evening,
                headline: headline,
                capacity: capacityScore,
                at: now,
              );
            }
            final brief =
                DailyBriefCard(
                  headline: headline,
                  summary:
                      '${sleepComparison(sleep, usualSleep)} $calendarText',
                  // In the evening it sits beside tomorrow's Demand, so
                  // it shows what tomorrow is compared with.
                  capacityScore: evening && usualCapacity != null
                      ? usualCapacity
                      : capacityScore,
                  capacityLabel: evening && usualCapacity != null
                      ? 'Your usual'
                      : recovering
                      ? 'Recovering'
                      : server != null
                      ? server.note
                      : capacity?.score == null
                      ? 'Needs health data'
                      : capacityNote,
                  scheduleScore: ready ? demand.round().clamp(0, 100) : null,
                  scheduleLabel: !ready
                      ? 'Plan unavailable'
                      : evening
                      ? 'Expected tomorrow'
                      : 'Remaining today',
                  footer: capacityStale || !ready
                      ? 'Limited data'
                      : 'Available data',
                  onDetails: () => showInfoSheet(
                    context,
                    icon: CupertinoIcons.info_circle,
                    title: 'Daily Brief data',
                    summary:
                        'Where today\'s numbers come from. These are wellness estimates, not clinical assessments.',
                    items: [
                      AppleInfoItem(
                        'Calendar loaded',
                        '${timeLabel(_calendarLoadedAt)} (may use a short-lived cache).',
                        icon: CupertinoIcons.calendar,
                      ),
                      AppleInfoItem(
                        'Heart rate measured',
                        '${timeLabel(healthTime)}.',
                        icon: CupertinoIcons.heart,
                      ),
                      AppleInfoItem(
                        'Stress calculated',
                        '${timeLabel(stressTime)}.',
                        icon: CupertinoIcons.waveform_path,
                      ),
                      if (summary?.isFromCache == true)
                        const AppleInfoItem(
                          'Health data',
                          'From the local cache.',
                          icon: CupertinoIcons.tray,
                        ),
                      AppleInfoItem(
                        'Sleep baseline',
                        '${summary?.priorNights ?? 0} prior nights in the last 28 days; at least 7 required.',
                        icon: CupertinoIcons.moon,
                      ),
                      AppleInfoItem(
                        'Capacity',
                        server != null
                            ? 'Compares last night\'s sleep with what you usually need, overnight HRV and resting heart rate with your normal, and how heavy yesterday was. A day of at least twice your usual activity lowers it for the next 3 days, less if your body has already recovered. It\'s compared with your usual after 7 days.'
                            : 'Uses sleep and stress, not raw heart rate. Comparisons need 7 days with matching inputs and stress readings at a similar time of day.',
                        icon: CupertinoIcons.battery_75_percent,
                      ),
                      const AppleInfoItem(
                        'Demand',
                        'The Effort still ahead today: upcoming events (rated by how demanding they look), open priorities, and workouts planned in your calendar, with back-to-backs and anything after your end-of-day time weighing more. It\'s compared with Capacity: within 15 is a full day. In the evening it shows tomorrow\'s expected Demand. Timeline openings are gaps of 30 minutes or more. Untimed work doesn\'t block a specific opening.',
                        icon: CupertinoIcons.chart_bar,
                      ),
                    ],
                    buttonLabel: 'Close',
                  ),
                ).withScreenInsight(
                  ScreenInsight(
                    'my_day',
                    'Your day',
                    myDayPlanningInsight(
                      now: now,
                      events: briefEvents,
                      priorities: briefPriorities,
                      calendarReady: calendarReady,
                      prioritiesReady:
                          priorities.hasData && !priorities.hasError,
                      allDayEvents: _events
                          .where((e) => e.isAllDay && e.end.isAfter(now))
                          .length,
                    ),
                  ),
                );
            // Ways to lighten today (docs/scores.md §2), when Demand
            // outruns Capacity and the card isn't hidden for today.
            // In the evening, the same card for tomorrow's plan.
            final tomorrowEvents = [
              for (final e in _tomorrowEvents)
                if (!e.isAllDay) e,
            ];
            final fixes = evening
                ? !tomorrowHeavy || _eveningFixesHiddenDay == localDayKey(today)
                      ? const <DayFix>[]
                      : _dayFixes(
                          now,
                          tomorrowEvents,
                          tomorrowPriorities,
                          day: tomorrow,
                        )
                : !ready ||
                      capacityScore == null ||
                      demand <= capacityScore + 15 ||
                      _fixesHiddenDay == localDayKey(today)
                ? const <DayFix>[]
                : _dayFixes(now, timedEvents, todayPriorities);
            if (fixes.isEmpty) return brief;
            _logFixesShown(fixes, day: evening ? tomorrow : today);
            return Column(
              children: [
                brief,
                const SizedBox(height: 12),
                DayFixesCard(
                  fixes: fixes,
                  tomorrow: evening,
                  onOpen: (fix) => _openDayFix(
                    fix,
                    demand,
                    evening ? tomorrowEvents : timedEvents,
                    evening ? tomorrowPriorities : todayPriorities,
                    day: evening ? tomorrow : today,
                  ),
                  onHide: evening ? _hideEveningFixes : _hideDayFixes,
                ),
              ],
            );
          },
        ),
      );
    },
  );

  /// Today's Demand as [buildDayEffort] prices it, for trying fixes.
  double _demandToday(
    DateTime now,
    List<EffortItem> items,
    List<Object?> untimed,
  ) {
    final today = DateUtils.dateOnly(now);
    return buildDayEffort(
      now: now,
      from: today,
      until: today.add(const Duration(days: 1)),
      wrapUp: today.add(Duration(minutes: _wrapUpMinutes)),
      items: items,
      untimedOpen: untimed,
    ).demand;
  }

  /// A one-off priority of your own: recurring and calendar ones stay put.
  bool _priorityMovable(DailyPriority p) =>
      !p.completed &&
      p.source == 'manual' &&
      p.templateId == null &&
      _linkedKey(p) == null;

  /// Fixes for today, or with [day] (tomorrow, in the evening) for that
  /// day's whole plan.
  List<DayFix> _dayFixes(
    DateTime now,
    List<_CalendarEvent> events,
    List<DailyPriority> priorities, {
    DateTime? day,
  }) {
    final today = DateUtils.dateOnly(now);
    final planDay = day ?? today;
    // Tomorrow's items are all still ahead.
    final from = day ?? now;
    final items = _effortItems(planDay, events, priorities);
    final byKey = {for (final e in events) e.sourceEventKey: e};
    final byPath = {
      for (final p in priorities) 'priority:${p.reference.path}': p,
    };
    bool canMove(EffortItem item) {
      if (byPath[item.event.id] case final p?) return _priorityMovable(p);
      final event = byKey[item.event.id];
      return event?.googleEvent != null &&
          !event!.isPriorityLinked &&
          !event.isAllDay;
    }

    final tonight = _energyForecast(today);
    final energy = day == null || tonight == null
        ? tonight
        : tomorrowEnergyForecast(
            tonight: tonight,
            today: today,
            nights: _briefSnapshot.value.data?.sleepNights ?? const [],
            schedule: _sleepSchedule,
          );
    // A break goes in Google Calendar, so it needs a connected one.
    final calendar = events.any((e) => e.googleEvent != null);
    final found = findDayFixes(
      now: from,
      items: items,
      // Every kind, so learning chooses the three to show.
      max: DayFixKind.values.length,
      untimed: [
        for (final p in priorities)
          if (_priorityMovable(p) &&
              (p.isAllDay ||
                  p.sourceStart == null ||
                  !DateUtils.isSameDay(p.sourceStart, planDay)))
            (
              id: p.reference.path,
              title: p.title,
              effort: p.planning['effort'],
            ),
      ],
      demandOf: (items, untimed) => _demandToday(from, items, untimed),
      canMove: canMove,
      fits: energy == null
          ? const []
          : fitDayToEnergy(forecast: energy, items: items, now: from),
    ).where((f) => calendar || f.kind != DayFixKind.addBreak).toList();
    return rankByHistory(found, _fixHistory, today);
  }

  /// day_fixes for [day] (default today). Fixes offered the evening before
  /// are filed under the day they're for, marked `evening`.
  DocumentReference<Map<String, dynamic>>? _fixDay([DateTime? day]) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('day_fixes')
              .doc(localDayKey(day ?? DateTime.now()));
  }

  bool _isTomorrow(DateTime? day) =>
      day != null && day.isAfter(DateUtils.dateOnly(DateTime.now()));

  /// Merges [fields] into [day]'s entry for [kind]: what happened to it, and
  /// for later learning the kind of item (never its title).
  Future<void> _logFix(
    DayFixKind kind,
    Map<String, Object?> fields, {
    DateTime? day,
  }) async {
    try {
      await _fixDay(day)?.set({
        'kinds': {
          kind.name: {...fields, if (_isTomorrow(day)) 'evening': true},
        },
      }, SetOptions(merge: true));
    } catch (_) {
      // Learning misses one entry; nothing the person sees changes.
    }
  }

  void _logFixesShown(List<DayFix> fixes, {required DateTime day}) {
    final key = localDayKey(day);
    for (final fix in fixes) {
      if (!_fixesShown.add('$key:${fix.kind.name}')) continue;
      unawaited(
        _logFix(fix.kind, {
          'shown': true,
          'item': {'category': fix.category, 'guests': fix.guests},
        }, day: day),
      );
    }
  }

  /// A fix applied (or, with [undone], taken back), on the day it's for.
  Future<void> _logFixUsed(DayFixKind kind, {bool undone = false}) => _logFix(
    kind,
    {'shown': true, 'used': true, 'undone': undone},
    day: _openFixDay,
  );

  Future<void> _hideDayFixes() async {
    final day = localDayKey(DateTime.now());
    setState(() => _fixesHiddenDay = day);
    Future<void> save(bool hidden) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('day_fixes')
            .doc(day)
            .set({'hidden': hidden}, SetOptions(merge: true));
      } catch (_) {
        // Still hidden (or shown) for this session.
      }
    }

    unawaited(save(true));
    if (await _showUndo('Hidden until tomorrow')) {
      if (mounted) setState(() => _fixesHiddenDay = null);
      await save(false);
    }
  }

  /// The X on the evening card: hidden until morning, when tomorrow's own
  /// card takes over.
  Future<void> _hideEveningFixes() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    setState(() => _eveningFixesHiddenDay = localDayKey(today));
    Future<void> save(bool hidden) async {
      try {
        await _fixDay(
          tomorrow,
        )?.set({'eveningHidden': hidden}, SetOptions(merge: true));
      } catch (_) {
        // Still hidden (or shown) for this session.
      }
    }

    unawaited(save(true));
    if (await _showUndo('Hidden until morning')) {
      if (mounted) setState(() => _eveningFixesHiddenDay = null);
      await save(false);
    }
  }

  /// The last 4 weeks of day_fixes: today's says whether the card is
  /// hidden and what's been logged; earlier days feed learning.
  Future<void> _loadFixHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final today = DateUtils.dateOnly(DateTime.now());
    final day = localDayKey(today);
    final tomorrow = localDayKey(today.add(const Duration(days: 1)));
    try {
      final docs = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('day_fixes')
          .where(
            FieldPath.documentId,
            isGreaterThanOrEqualTo: localDayKey(
              today.subtract(const Duration(days: 28)),
            ),
          )
          // Tomorrow's holds what the evening card did.
          .where(FieldPath.documentId, isLessThanOrEqualTo: tomorrow)
          .get();
      if (!mounted) return;
      Map<String, dynamic>? on(String key) =>
          docs.docs.where((d) => d.id == key).firstOrNull?.data();
      final todays = on(day);
      final tomorrows = on(tomorrow);
      setState(() {
        _fixHistory = [
          for (final doc in docs.docs)
            if (doc.id.compareTo(day) < 0)
              if (DateTime.tryParse(doc.id) case final date?)
                (day: date, data: doc.data()),
        ];
        if (todays?['hidden'] == true) _fixesHiddenDay = day;
        if (tomorrows?['eveningHidden'] == true) _eveningFixesHiddenDay = day;
        for (final (key, data) in [(day, todays), (tomorrow, tomorrows)]) {
          for (final kind in ((data?['kinds'] as Map?) ?? const {}).keys) {
            _fixesShown.add('$key:$kind');
          }
        }
      });
    } catch (_) {
      // No learning this time; the card still shows.
    }
  }

  /// A snackbar with Undo; true when Undo was tapped.
  Future<bool> _showUndo(String message) async {
    if (!mounted) return false;
    var undone = false;
    await showToast(
      context,
      message,
      actionLabel: 'Undo',
      onAction: () => undone = true,
    ).closed;
    return undone;
  }

  /// Opens [fix]'s confirm sheet and applies it; [day] is the day it's for
  /// (tomorrow from the evening card).
  Future<void> _openDayFix(
    DayFix fix,
    double demandNow,
    List<_CalendarEvent> events,
    List<DailyPriority> priorities, {
    required DateTime day,
  }) async {
    _openFixDay = day;
    final tomorrow = _isTomorrow(day);
    final event = events.where((e) => e.sourceEventKey == fix.id).firstOrNull;
    final priority = priorities
        .where(
          (p) =>
              'priority:${p.reference.path}' == fix.id ||
              p.reference.path == fix.id,
        )
        .firstOrNull;
    if (fix.kind == DayFixKind.movePriority) {
      if (priority == null) return;
      final to = await showMovePrioritySheet(
        context,
        fix: fix,
        demandNow: demandNow,
        days: _expectedDemandDays(after: day),
        tomorrow: tomorrow,
      );
      if (to != null) await _movePriority(priority, to, fix.demandSaved);
      return;
    }
    if (!await showDayFixTimeSheet(
      context,
      fix: fix,
      demandNow: demandNow,
      recurring: event?.isRecurring == true,
      tomorrow: tomorrow,
    )) {
      return;
    }
    if (fix.kind == DayFixKind.addBreak) {
      await _addBreak(fix);
    } else if (event?.googleEvent case final google?) {
      await _moveEvent(google, fix);
    } else if (priority != null) {
      await _retimePriority(priority, fix);
    }
  }

  /// A "Break" event in Google Calendar; Undo deletes it.
  Future<void> _addBreak(DayFix fix) async {
    try {
      final created = await CalendarService.createEvent(
        title: 'Break',
        start: fix.newStart!,
        end: fix.newEnd!,
        recurrence: 'none',
      );
      await _loadTodayEvents(forceRefresh: true);
      unawaited(_logFixUsed(fix.kind));
      if (await _showUndo(
        'Break added at ${DateFormat.jm().format(fix.newStart!)}',
      )) {
        unawaited(_logFixUsed(fix.kind, undone: true));
        await CalendarService.deleteEvent(created);
        await _loadTodayEvents(forceRefresh: true);
      }
    } catch (_) {
      _showMessage("Couldn't add the break.", error: true);
    }
  }

  Future<void> _moveEvent(gcal.Event google, DayFix fix) async {
    try {
      final moved = await CalendarService.updateEvent(
        google,
        start: fix.newStart,
        end: fix.newEnd,
      );
      await _loadTodayEvents(forceRefresh: true);
      unawaited(_logFixUsed(fix.kind));
      if (await _showUndo(_movedText(fix))) {
        unawaited(_logFixUsed(fix.kind, undone: true));
        await CalendarService.updateEvent(
          moved,
          start: fix.start,
          end: fix.end,
        );
        await _loadTodayEvents(forceRefresh: true);
      }
    } catch (_) {
      _showMessage("Couldn't move ${fix.title}.", error: true);
    }
  }

  /// A timed priority to a better energy slot today.
  Future<void> _retimePriority(DailyPriority p, DayFix fix) async {
    Future<void> setStart(DailyPriority priority, DateTime start) =>
        DailyPriorityService.editPriority(
          priority,
          title: priority.title,
          date: start,
          scheduledAt: start,
          completed: priority.completed,
          reminderMinutes: priority.reminderMinutes,
          reminderTimeMinutes: priority.reminderTimeMinutes,
          // editPriority drops the end, so keep the length as its estimate.
          planning: {
            ...priority.planning,
            'minutes': fix.end!.difference(fix.start!).inMinutes,
          },
        );
    try {
      await setStart(p, fix.newStart!);
      unawaited(_logFixUsed(fix.kind));
      if (await _showUndo(_movedText(fix))) {
        unawaited(_logFixUsed(fix.kind, undone: true));
        final now = await _priorityOn(fix.newStart!, p.id);
        if (now != null) await setStart(now, fix.start!);
      }
    } catch (_) {
      _showMessage("Couldn't move ${fix.title}.", error: true);
    }
  }

  /// A priority to another day, keeping its time of day if it has one.
  Future<void> _movePriority(
    DailyPriority p,
    DateTime day,
    double saved,
  ) async {
    final from = p.date ?? DateUtils.dateOnly(DateTime.now());
    Future<void> moveTo(DailyPriority priority, DateTime to) =>
        DailyPriorityService.editPriority(
          priority,
          title: priority.title,
          date: to,
          scheduledAt: p.sourceStart == null
              ? null
              : DateTime(
                  to.year,
                  to.month,
                  to.day,
                  p.sourceStart!.hour,
                  p.sourceStart!.minute,
                ),
          completed: false,
          reminderMinutes: priority.reminderMinutes,
          reminderTimeMinutes: priority.reminderTimeMinutes,
          planning: {
            ...priority.planning,
            if (priority.planning['plannedDay'] != null)
              'plannedDay': localDayKey(to),
            if (p.sourceStart != null && p.sourceEnd != null)
              'minutes': p.sourceEnd!.difference(p.sourceStart!).inMinutes,
          },
        );
    try {
      await moveTo(p, day);
      unawaited(_logFixUsed(DayFixKind.movePriority));
      final undo = await _showUndo(
        '"${p.title}" moved to ${DateFormat('EEEE').format(day)} · '
        '−${saved.round()}',
      );
      if (undo) {
        unawaited(_logFixUsed(DayFixKind.movePriority, undone: true));
        final moved = await _priorityOn(day, p.id);
        if (moved != null) await moveTo(moved, from);
      }
    } catch (_) {
      _showMessage("Couldn't move \"${p.title}\".", error: true);
    }
  }

  Future<DailyPriority?> _priorityOn(DateTime day, String id) async =>
      (await DailyPriorityService.forDay(
        day,
      )).where((p) => p.id == id).firstOrNull;

  String _movedText(DayFix fix) =>
      '${fix.title} moved to ${DateFormat.jm().format(fix.newStart!)}'
      '${fix.demandSaved >= 0.5 ? ' · −${fix.demandSaved.round()}' : ''}';

  /// Expected Demand for the 5 days after [after], for the move-priority
  /// picker.
  Future<List<({DateTime day, double demand})>> _expectedDemandDays({
    required DateTime after,
  }) async {
    final start = DateUtils.dateOnly(after).add(const Duration(days: 1));
    final days = [for (var i = 0; i < 5; i++) start.add(Duration(days: i))];
    final results = await Future.wait([
      CalendarService.getEventsBetween(
        start,
        start.add(const Duration(days: 5)),
      ),
      for (final day in days) DailyPriorityService.forDay(day),
    ]);
    final events = [
      for (final e in results.first as List<gcal.Event>)
        ?_CalendarEvent.fromGoogle(e),
    ];
    // Only what belongs to each day: untimed priorities carried over from
    // earlier days would otherwise count on every day alike.
    List<DailyPriority> own(int i) => [
      for (final p in results[i + 1] as List<DailyPriority>)
        if (DateUtils.isSameDay(p.date, days[i]) ||
            p.planning['plannedDay'] == localDayKey(days[i]))
          p,
    ];
    return [
      for (final (i, day) in days.indexed)
        (
          day: day,
          demand: buildDayEffort(
            now: day,
            from: day,
            until: day.add(const Duration(days: 1)),
            wrapUp: day.add(Duration(minutes: _wrapUpMinutes)),
            items: _effortItems(day, [
              for (final e in events)
                if (!e.isAllDay && DateUtils.isSameDay(e.start, day)) e,
            ], own(i)),
            untimedOpen: _untimedOpen(day, own(i)),
          ).demand,
        ),
    ];
  }

  Widget _buildWatchStrip(BackToBackEventBlock block) {
    final colors = context.vivordoColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: colors.cardMuted,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: MyDayScreen.purple,
                size: 17,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${block.events.length} events back to back from ${formatClock(block.start)}',
                  style: const TextStyle(
                    color: MyDayScreen.purple,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final event in block.events)
                Expanded(
                  child: _WatchSegment(event.title, color: MyDayScreen.purple),
                ),
              const Expanded(
                child: _WatchSegment('Reset', color: timelineOpenGreen),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Protect a 10-min reset after ${block.events.last.title}',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _openCalendar() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MonthCalendarScreen()),
    );
    if (mounted) await _loadTodayEvents();
  }

  Widget _buildNowCard(
    List<_CalendarEvent> timedEvents,
    BackToBackEventBlock? watchItem,
  ) {
    if (_isLoading && _calendarLoadedAt == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final colors = context.vivordoColors;
    final now = DateTime.now();
    final current = timedEvents
        .where((e) => !e.start.isAfter(now) && e.end.isAfter(now))
        .firstOrNull;
    final next = timedEvents.where((e) => e.start.isAfter(now)).firstOrNull;
    final (title, detail) = current != null
        ? (
            current.title,
            'Now · ends ${formatClock(current.end)} · ${formatSpan(current.end.difference(now))} left',
          )
        : next != null
        ? (
            'Free until ${formatClock(next.start)}',
            '${formatSpan(next.start.difference(now))} open',
          )
        : ('Free now', 'No more events today');
    final upNext = next != null
        ? 'Next: ${next.title} at ${formatClock(next.start)}'
        : current != null
        ? 'Nothing after this today'
        : null;
    return Column(
      children: [
        InkWell(
          onTap: current == null ? null : () => _handleEventTap(current),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: current == null
                        ? timelineDoneGreen
                        : const Color(0xFFFF9F0A),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (upNext != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          upNext,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (current == null) ...[
                  const SizedBox(width: 8),
                  TimelinePill(
                    'Plan it',
                    color: timelineOpenGreen,
                    onTap: () => _planSlot(now, next?.start),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (watchItem != null) _buildWatchStrip(watchItem),
      ],
    );
  }

  Widget _buildPriorities() =>
      ValueListenableBuilder<AsyncSnapshot<List<DailyPriority>>>(
        valueListenable: _prioritySnapshot,
        builder: (context, snapshot, _) {
          final colors = context.vivordoColors;
          final priorities = snapshot.data ?? const <DailyPriority>[];
          final open = priorities.where((p) => !p.completed).toList();
          final done = priorities.where((p) => p.completed).toList();
          Widget row(DailyPriority priority) => _PriorityRow(
            key: ValueKey(priority.reference.path),
            priority: priority,
            onToggle: () => _togglePriority(priority),
            onDelete: () => _deletePriority(priority),
            onEdit: () => _editPriority(priority),
          );
          const divider = Divider(height: 1, indent: 54, endIndent: 16);

          final Widget body;
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            body = const SizedBox(
              height: 72,
              child: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            body = Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Could not load today’s priorities',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
            );
          } else {
            body = Column(
              children: [
                for (final priority in open) ...[row(priority), divider],
                _ListAction(
                  icon: Icons.add_rounded,
                  label: 'Add a priority',
                  onTap: _addManualPriority,
                ),
                if (done.isNotEmpty) ...[
                  const Divider(height: 1),
                  _ListAction(
                    icon: _showCompleted
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    label: '${done.length} completed',
                    muted: true,
                    onTap: () =>
                        setState(() => _showCompleted = !_showCompleted),
                  ),
                  if (_showCompleted)
                    for (final priority in done) ...[divider, row(priority)],
                ],
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SectionLabel(
                      priorities.isEmpty
                          ? 'PRIORITIES'
                          : 'PRIORITIES · ${done.length} OF ${priorities.length}',
                    ),
                  ),
                  TextButton(
                    onPressed: _openAllPriorities,
                    child: const Text('View all'),
                  ),
                ],
              ),
              if (priorities.isNotEmpty) ...[
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: done.length / priorities.length,
                    minHeight: 4,
                    color: timelineDoneGreen,
                    backgroundColor: colors.border,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _SectionCard(child: body),
            ],
          );
        },
      );

  Future<void> _openAllPriorities({bool repeating = false}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AllPrioritiesScreen(
            startOnRepeating: repeating,
            onAdd: (sheetContext) =>
                _addManualPriority(sheetContext: sheetContext),
            onEdit: (sheetContext, priority) =>
                _editPriority(priority, sheetContext: sheetContext),
          ),
        ),
      );

  /// Today's habits as chips; nothing until there are some.
  Widget _buildHabits() => ListenableBuilder(
    listenable: Listenable.merge([_habitSnapshot, _templateSnapshot]),
    builder: (context, _) {
      final habits = _habitSnapshot.value.data ?? const <DailyPriority>[];
      if (habits.isEmpty) return const SizedBox.shrink();
      final done = habits.where((h) => h.completed).length;
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _SectionLabel('HABITS · $done OF ${habits.length}'),
                ),
                TextButton(
                  onPressed: () => _openAllPriorities(repeating: true),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            HabitChips(
              habits: habits,
              templates: _templateSnapshot.value.data ?? const {},
              today: _priorityDay,
              onChanged: _setHabitCount,
            ),
          ],
        ),
      );
    },
  );

  Future<void> _setHabitCount(DailyPriority habit, int count) async {
    try {
      await DailyPriorityService.setHabitCount(habit, count);
    } catch (error) {
      debugPrint('Habit update failed: $error');
      _showMessage("Couldn't update the habit. Try again.", error: true);
    }
  }

  Future<void> _togglePriority(DailyPriority priority) async {
    try {
      await DailyPriorityService.setCompleted(priority, !priority.completed);
    } catch (error) {
      debugPrint('Toggle priority failed: $error');
      _showMessage("Couldn't update the priority. Try again.", error: true);
    }
  }

  Future<void> _deletePriority(DailyPriority priority) async {
    try {
      await DailyPriorityService.delete(priority);
    } catch (error) {
      debugPrint('Delete priority failed: $error');
      _showMessage("Couldn't delete the priority. Try again.", error: true);
    }
  }

  Future<void> _editPriority(
    DailyPriority priority, {
    BuildContext? sheetContext,
  }) async {
    final result = await showEditPrioritySheet(
      sheetContext ?? context,
      priority,
    );
    if (result == null || !mounted) return;
    try {
      if (result.deleteRequested) {
        await DailyPriorityService.delete(priority);
        return;
      }
      final templateId = priority.templateId;
      if (result.habit && templateId != null) {
        // Made a habit: that changes the whole schedule, not this day.
        await DailyPriorityService.updateSchedule(
          templateId,
          title: result.title,
          habit: true,
          target: result.target,
          reminderTimeMinutes: result.reminderTimeMinutes,
        );
        return;
      }
      final destination = await DailyPriorityService.editPriority(
        priority,
        title: result.title,
        planning: result.planning,
        date: result.date,
        scheduledAt: result.scheduledAt,
        completed: result.completed,
        reminderMinutes: result.reminderMinutes,
        reminderTimeMinutes: result.reminderTimeMinutes,
        recurrence: result.recurrence,
        selectedWeekdays: result.selectedWeekdays,
        recurrenceEnd: result.repeatEnd,
      );
      final linkedKey = _linkedKey(priority);
      if (linkedKey != null && linkedKey.startsWith('google:')) {
        final linked = _events
            .where((e) => e.sourceEventKey == linkedKey)
            .firstOrNull;
        if (linked?.googleEvent != null) {
          final start = result.scheduledAt ?? DateUtils.dateOnly(result.date);
          await CalendarService.updateEvent(
            linked!.googleEvent!,
            title: result.title,
            start: start,
            end: result.scheduledAt == null
                ? start.add(const Duration(days: 1))
                : start.add(
                    Duration(
                      minutes:
                          (result.planning['minutes'] as num?)?.toInt() ??
                          linked.end.difference(linked.start).inMinutes,
                    ),
                  ),
            isAllDay: result.scheduledAt == null,
          );
          await _loadTodayEvents(forceRefresh: true);
        } else {
          _showMessage(
            'Priority saved. Its linked calendar event was not available to update.',
          );
        }
      } else if (result.addToCalendar &&
          linkedKey == null &&
          destination != null) {
        await _addPriorityCalendarEvent(result, reference: destination);
      }
    } catch (error) {
      debugPrint('Edit priority failed: $error');
      const message = "Couldn't update the priority. Try again.";
      if (sheetContext != null && sheetContext.mounted) {
        showToast(sheetContext, message, kind: ToastKind.error);
      } else {
        _showMessage(message, error: true);
      }
    }
  }

  Future<void> _addManualPriority({BuildContext? sheetContext}) async {
    final draft = await showAddPrioritySheet(sheetContext ?? context);
    if (draft == null || !mounted) return;
    await _saveManualPriority(draft);
  }

  /// Opens the Priority / Event sheet for an open slot starting at [start].
  Future<void> _planSlot(DateTime start, [DateTime? end]) async {
    final result = await showPlanSlotSheet(context, start: start, end: end);
    if (!mounted) return;
    switch (result) {
      case PriorityDraft draft:
        await _saveManualPriority(draft);
      case CalendarEventDraft draft:
        await _saveGoogleEvent(draft);
    }
  }

  Future<void> _saveManualPriority(PriorityDraft draft) async {
    final String? warning;
    try {
      warning = await savePriorityDraft(draft);
    } catch (error) {
      debugPrint('Add priority failed: $error');
      _showMessage("Couldn't add the priority. Try again.", error: true);
      return;
    }
    if (warning != null) _showMessage(warning);
    if (draft.addToCalendar && mounted) {
      await _loadTodayEvents(forceRefresh: true);
    }
  }

  Future<void> _addPriorityCalendarEvent(
    PriorityDraft draft, {
    required DocumentReference<Map<String, dynamic>> reference,
  }) async {
    final warning = await addPriorityCalendarEvent(draft, reference: reference);
    if (warning != null) _showMessage(warning);
    if (mounted) await _loadTodayEvents(forceRefresh: true);
  }

  String? _linkedKey(DailyPriority priority) {
    for (final event in _events) {
      final google = event.googleEvent;
      if (event.sourceEventKey == priority.sourceEventKey ||
          (google?.recurringEventId != null &&
              'google:${google!.recurringEventId}' ==
                  priority.sourceEventKey) ||
          google?.extendedProperties?.private?['vivordoPriorityReference'] ==
              priority.reference.path) {
        return event.sourceEventKey;
      }
    }
    if (priority.sourceEventKey == null &&
        _events.any(
          (event) =>
              event.isPriorityLinked &&
              event.title.trim().toLowerCase() ==
                  priority.title.trim().toLowerCase() &&
              event.start == priority.sourceStart,
        )) {
      // Old exports have no stable backlink. Exclude ambiguous extra work and
      // disclose the unresolved link rather than counting the same task twice.
      return 'unresolved:${priority.id}';
    }
    return priority.sourceEventKey;
  }

  /// Events and timed priorities in one list, with the gaps between them.
  /// A priority linked to an event shares that event's row.
  Widget _buildTimeline() => ListenableBuilder(
    listenable: Listenable.merge([
      _prioritySnapshot,
      _briefSnapshot,
      _capacitySnapshot,
    ]),
    builder: (context, _) {
      final snapshot = _prioritySnapshot.value;
      if (_isLoading && _calendarLoadedAt == null) {
        return const _SectionCard(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      }
      final colors = context.vivordoColors;
      final now = DateTime.now();
      final eventKeys = {for (final e in _events) e.sourceEventKey};
      final byEvent = <String, DailyPriority>{};
      final items = <AgendaItem<_TimelineItem>>[];
      for (final priority in snapshot.data ?? const <DailyPriority>[]) {
        final key = _linkedKey(priority);
        if (key != null && eventKeys.contains(key)) {
          byEvent[key] = priority;
          continue;
        }
        final start = priority.sourceStart;
        if (key?.startsWith('unresolved:') == true ||
            priority.isAllDay ||
            start == null ||
            !DateUtils.isSameDay(start, now)) {
          continue;
        }
        items.add(
          AgendaItem(
            (event: null, priority: priority),
            start,
            priority.timelineEnd!,
          ),
        );
      }
      for (final event in _events.where((e) => !e.isAllDay)) {
        items.add(
          AgendaItem(
            (event: event, priority: byEvent[event.sourceEventKey]),
            event.start,
            event.end,
          ),
        );
      }
      final earlier = items.where((i) => !i.end.isAfter(now)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      final agenda = buildDayAgenda(now, items);
      final allDay = _events.where((e) => e.isAllDay).toList();
      final today = DateUtils.dateOnly(now);
      final energy = _energyForecast(today);
      final fits = {
        if (energy != null)
          for (final fit in fitDayToEnergy(
            forecast: energy,
            items: _effortItems(
              today,
              _events,
              snapshot.data ?? const <DailyPriority>[],
            ),
            now: now,
          ))
            fit.id: fit,
      };
      if (energy != null) {
        final evening = !now.isBefore(
          today.add(Duration(minutes: _wrapUpMinutes)),
        );
        latestEnergy = (
          text: energyContext(
            today: energy,
            fits: fits.values.toList(),
            tomorrow: evening
                ? tomorrowEnergyForecast(
                    tonight: energy,
                    today: today,
                    nights: _briefSnapshot.value.data?.sleepNights ?? const [],
                    schedule: _sleepSchedule,
                  )
                : null,
          ),
          at: now,
        );
      }

      Widget itemRow(AgendaItem<_TimelineItem> entry, {bool past = false}) {
        final event = entry.item.event;
        final priority = entry.item.priority;
        final knownLength =
            event != null ||
            priority!.sourceEnd != null ||
            priority.planning['minutes'] is num;
        final fit = past
            ? null
            : fits[event?.sourceEventKey ??
                  'priority:${priority!.reference.path}'];
        final phase = past ? null : energy?.phaseAt(entry.start);
        final suggested = fit?.suggestedStart;
        final reaction = past && event != null
            ? _reactions[event.sourceEventKey]
            : null;
        // Upcoming repeating meetings that usually raise or lower your heart rate.
        final pattern =
            past ||
                event == null ||
                !_cognitiveInput(event).contributesToSchedule
            ? null
            : _patterns.bySeries[seriesKeyFor(
                event.googleEvent?.recurringEventId,
              )];
        // A clash Vivordo can move: one tap opens the confirm sheet.
        final canMove =
            fit != null &&
            fit.kind == EnergyFitKind.clash &&
            fit.movable &&
            suggested != null &&
            (event != null
                ? event.googleEvent != null && !event.isPriorityLinked
                : !priority!.completed);
        return TimelineRow(
          start: entry.start,
          title: event?.title ?? priority!.title,
          detail: [
            if (priority != null) 'Priority',
            if (knownLength) formatSpan(entry.end.difference(entry.start)),
            if (fit?.kind == EnergyFitKind.goodFit)
              'in ${energyPhasePhrase(fit!.phase)} ✓',
          ].join(' · '),
          energyColor: phase == null ? null : energyPhaseColor(phase),
          energyNote: fit?.kind == EnergyFitKind.clash
              ? 'Lands in ${energyPhasePhrase(fit!.phase)}'
              : null,
          energyAction: canMove
              ? energyMoveHint(
                  suggested,
                  energy!,
                ).replaceFirst('Try', 'Move to')
              : null,
          onEnergyAction: !canMove
              ? null
              : () => _openDayFix(
                  DayFix(
                    kind: DayFixKind.energySlot,
                    id: fit.id,
                    title: fit.item.event.title,
                    demandSaved: 0,
                    start: fit.item.event.start,
                    end: fit.item.event.end,
                    newStart: suggested,
                  ),
                  0,
                  _events,
                  snapshot.data ?? const <DailyPriority>[],
                  day: DateUtils.dateOnly(DateTime.now()),
                ),
          footer: reaction != null
              ? BodyReactionChip(
                  reaction: reaction,
                  onTap: () => _showReaction(event!, reaction),
                )
              : pattern != null
              ? MeetingPatternTag(
                  pattern: pattern,
                  onTap: () => showMeetingPatternSheet(
                    context,
                    title: event!.title,
                    pattern: pattern,
                  ),
                )
              : null,
          color: priority != null ? timelineDoneGreen : event!.color,
          past: past,
          completed: priority?.completed,
          onToggle: priority == null ? null : () => _togglePriority(priority),
          onTap: event != null
              ? () => _handleEventTap(event)
              : () => _editPriority(priority!),
        );
      }

      final onlyEvents = earlier.every((i) => i.item.priority == null);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (allDay.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final event in allDay)
                  TimelinePill(
                    'All day · ${event.title}',
                    color: MyDayScreen.purple,
                    onTap: () => _handleEventTap(event),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _SectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  if (earlier.isNotEmpty)
                    _ListAction(
                      icon: _showEarlier
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      label:
                          '${earlier.length} earlier ${onlyEvents ? (earlier.length == 1 ? 'event' : 'events') : (earlier.length == 1 ? 'item' : 'items')}',
                      muted: true,
                      onTap: () => setState(() => _showEarlier = !_showEarlier),
                    ),
                  if (_showEarlier)
                    for (final entry in earlier) itemRow(entry, past: true),
                  TimelineNowLine(now),
                  for (final entry in agenda)
                    switch (entry) {
                      AgendaItem<_TimelineItem>() => itemRow(entry),
                      AgendaOpening<_TimelineItem>(:final start, :final end) =>
                        TimelineOpeningRow(
                          start: start,
                          label: end == null
                              ? 'Open · rest of day'
                              : 'Open · ${formatSpan(end.difference(start))}',
                          onPlan: () => _planSlot(start, end),
                        ),
                      AgendaBreak<_TimelineItem>(:final minutes) =>
                        TimelineBreakRow(minutes),
                    },
                  if (agenda.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Nothing else on your timeline today.',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

typedef _TimelineItem = ({_CalendarEvent? event, DailyPriority? priority});

class _WatchSegment extends StatelessWidget {
  const _WatchSegment(this.title, {required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 3),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _ListAction extends StatelessWidget {
  const _ListAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 16, 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: muted ? colors.textSecondary : MyDayScreen.purple,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
      color: context.vivordoColors.textSecondary,
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.black.withValues(alpha: .07)),
    ),
    child: child,
  );
}

@visibleForTesting
Widget priorityRowForTesting({
  required DailyPriority priority,
  required Future<void> Function() onDelete,
  VoidCallback? onEdit,
}) => _PriorityRow(
  priority: priority,
  onToggle: () {},
  onDelete: onDelete,
  onEdit: onEdit,
);

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    super.key,
    required this.priority,
    required this.onToggle,
    required this.onDelete,
    this.onEdit,
  });

  final DailyPriority priority;
  final VoidCallback onToggle;
  final Future<void> Function() onDelete;
  final VoidCallback? onEdit;

  String? get _timeLabel {
    final start = priority.sourceStart;
    final end = priority.sourceEnd;
    if (start == null) return null;
    if (priority.isAllDay) return 'All day';
    if (end == null) return DateFormat('h:mm a').format(start);
    return '${DateFormat('h:mm').format(start)}–${DateFormat('h:mm a').format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final today = DateTime.now();
    final overdue = overdueSince(priority, today);
    // A carried-over priority says where it came from instead of its time.
    final (pill, pillColor) = overdue != null
        ? (overdueLabel(overdue, today), const Color(0xFFE5484D))
        : (_timeLabel, MyDayScreen.purple);
    return SwipeToDelete(
      onTap: onEdit,
      onDelete: onDelete,
      confirmTitle: 'Delete priority?',
      confirmMessage: priorityDeleteMessage(
        priority.title,
        manual: priority.source == 'manual',
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggle,
                customBorder: const CircleBorder(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: priority.completed
                        ? const Color(0xFF54C75B)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: priority.completed
                          ? const Color(0xFF54C75B)
                          : MyDayScreen.muted,
                      width: 2,
                    ),
                  ),
                  child: priority.completed
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                priority.title,
                style: TextStyle(
                  color: priority.completed
                      ? colors.textSecondary
                      : colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  decoration: priority.completed
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            if (pill != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: pillColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  pill,
                  style: TextStyle(
                    color: pillColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _EventSummaryAction { edit, delete }

class _EventSummarySheet extends StatelessWidget {
  const _EventSummarySheet({
    required this.event,
    this.reaction,
    required this.onReaction,
  });

  final _CalendarEvent event;
  final BodyReaction? reaction;
  final void Function(_CalendarEvent, BodyReaction) onReaction;

  (String, Color) get _status {
    final now = DateTime.now();
    if (!now.isBefore(event.end)) {
      return ('COMPLETED', const Color(0xFF20A968));
    }
    if (!now.isBefore(event.start)) {
      return ('IN PROGRESS', const Color(0xFFFF9F0A));
    }
    return ('UPCOMING', MyDayScreen.purple);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final status = _status;
    final time = event.isAllDay
        ? 'All day'
        : '${DateFormat('h:mm a').format(event.start)} – ${DateFormat('h:mm a').format(event.end)}';

    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      'Event Summary',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.cardMuted,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: MyDayScreen.purple.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.calendar_month_rounded,
                              color: MyDayScreen.purple,
                              size: 36,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: status.$2.withValues(alpha: .16),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    status.$1,
                                    style: TextStyle(
                                      color: status.$2,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _SummarySectionLabel('DETAILS'),
                    const SizedBox(height: 10),
                    _SummarySurface(
                      children: [
                        _SummaryDetailRow(
                          icon: Icons.calendar_today_rounded,
                          label: 'Date',
                          value: DateFormat('MMMM d, y').format(event.start),
                        ),
                        _SummaryDetailRow(
                          icon: Icons.schedule_rounded,
                          label: 'Time',
                          value: time,
                        ),
                        _SummaryDetailRow(
                          icon: Icons.hourglass_bottom_rounded,
                          label: 'Duration',
                          value: event.durationLabel,
                        ),
                        _SummaryDetailRow(
                          icon: Icons.repeat_rounded,
                          label: 'Repeats',
                          value: event.isRecurring
                              ? 'Recurring event'
                              : 'Does not repeat',
                          showDivider: false,
                        ),
                      ],
                    ),
                    if (reaction case final reaction?) ...[
                      const SizedBox(height: 24),
                      const _SummarySectionLabel('HOW YOUR BODY REACTED'),
                      const SizedBox(height: 10),
                      _SummarySurface(
                        children: [
                          _SummaryDetailRow(
                            icon: Icons.monitor_heart_outlined,
                            label: 'Heart rate',
                            value:
                                '${switch (reaction.level) {
                                  BodyReactionLevel.calm => 'Calm',
                                  BodyReactionLevel.steady => 'Steady',
                                  BodyReactionLevel.up => 'Up',
                                  BodyReactionLevel.high => 'High',
                                }} · ${reaction.median.round()} bpm avg',
                            showDivider: false,
                            onTap: () => onReaction(event, reaction),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    const _SummarySectionLabel('CALENDAR'),
                    const SizedBox(height: 10),
                    _SummarySurface(
                      children: [
                        _SummaryDetailRow(
                          icon: Icons.calendar_month_rounded,
                          label: 'Calendar',
                          value: event.googleEvent == null
                              ? 'Outlook'
                              : 'Google Calendar',
                          valueDotColor: event.color,
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: event.googleEvent == null
                            ? null
                            : () => Navigator.pop(
                                context,
                                _EventSummaryAction.edit,
                              ),
                        style: FilledButton.styleFrom(
                          backgroundColor: MyDayScreen.purple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          event.googleEvent == null
                              ? 'Outlook event · Read only'
                              : 'Edit Event',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (event.googleEvent != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => Navigator.pop(
                            context,
                            _EventSummaryAction.delete,
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFF453A),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Delete'),
                        ),
                      ),
                    ],
                    if (event.googleEvent == null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Outlook events are currently read-only in Vivordo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySectionLabel extends StatelessWidget {
  const _SummarySectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: MyDayScreen.purple,
      fontSize: 12,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
    ),
  );
}

class _SummarySurface extends StatelessWidget {
  const _SummarySurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: context.vivordoColors.cardMuted,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Column(children: children),
  );
}

class _SummaryDetailRow extends StatelessWidget {
  const _SummaryDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueDotColor,
    this.showDivider = true,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueDotColor;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: MyDayScreen.purple, size: 23),
                const SizedBox(width: 14),
                SizedBox(
                  width: 92,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(color: colors.textPrimary, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (valueDotColor != null) ...[
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: valueDotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (showDivider) Divider(height: 1, color: colors.border),
      ],
    );
  }
}

class _CalendarEvent {
  const _CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.sourceEventKey,
    required this.isRecurring,
    required this.attendeeCount,
    required this.isPriorityLinked,
    required this.icon,
    required this.color,
    this.googleEvent,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final String sourceEventKey;
  final bool isRecurring;
  final int attendeeCount;
  final bool isPriorityLinked;
  final IconData icon;
  final Color color;
  final gcal.Event? googleEvent;

  static _CalendarEvent? fromGoogle(gcal.Event event) {
    if (event.status == 'cancelled') return null;
    final start =
        event.start?.dateTime?.toLocal() ?? event.start?.date?.toLocal();
    final end = event.end?.dateTime?.toLocal() ?? event.end?.date?.toLocal();
    if (start == null || end == null) return null;
    return _CalendarEvent(
      title: event.summary?.trim().isNotEmpty == true
          ? event.summary!.trim()
          : 'Untitled event',
      start: start,
      end: end,
      isAllDay: event.start?.dateTime == null,
      sourceEventKey:
          'google:${event.id ?? event.iCalUID ?? '${event.summary}:$start'}',
      isRecurring:
          event.recurringEventId != null ||
          event.recurrence?.isNotEmpty == true,
      attendeeCount: event.attendees?.length ?? 0,
      isPriorityLinked:
          event.extendedProperties?.private?['vivordoPriority'] == 'true',
      icon: Icons.event_rounded,
      color: const Color(0xFF3978F6),
      googleEvent: event,
    );
  }

  factory _CalendarEvent.fromOutlook(OutlookEvent event) => _CalendarEvent(
    title: event.subject.trim().isEmpty
        ? 'Untitled event'
        : event.subject.trim(),
    start: event.start.toLocal(),
    end: event.end.toLocal(),
    isAllDay: event.isAllDay,
    sourceEventKey: 'outlook:${event.id}',
    isRecurring: false,
    attendeeCount: 0,
    isPriorityLinked: false,
    icon: Icons.event_rounded,
    color: MyDayScreen.purple,
  );

  String get timeLabel =>
      isAllDay ? 'All day' : DateFormat('h:mm a').format(start);

  CalendarPriorityCandidate get priorityCandidate => CalendarPriorityCandidate(
    sourceEventKey: sourceEventKey,
    title: title,
    start: start,
    end: end,
    isAllDay: isAllDay,
    isRecurring: isRecurring,
    attendeeCount: attendeeCount,
  );

  String get durationLabel {
    if (isAllDay) return 'All-day event';
    final minutes = end.difference(start).inMinutes;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }
}
