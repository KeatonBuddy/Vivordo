import 'dart:async';
import '../widgets/visible_stream_builder.dart';
import '../src/services/metrics_repository.dart';
import '../widgets/calendar_event_summary_sheet.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'profile_screen.dart';
import 'package:vivordo_health/src/services/metrics_service.dart';
import 'package:vivordo_health/src/services/check_in_reminder.dart';
import 'package:vivordo_health/src/services/wind_down_reminder.dart';
import 'package:vivordo_health/src/services/stress_score_service.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:vivordo_health/src/services/outlook_calendar_service.dart';
import 'package:vivordo_health/src/services/notification_service.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/services/circle_profile_service.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';
import 'package:vivordo_health/src/utils/day_agenda.dart';
import 'package:vivordo_health/src/utils/day_effort.dart';
import 'package:vivordo_health/src/utils/day_wrap_up.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'package:vivordo_health/widgets/morning_check_in_card.dart';
import 'package:vivordo_health/src/utils/home_day_load.dart';
import 'package:vivordo_health/src/utils/owned_stream_snapshot.dart';
import 'package:vivordo_health/widgets/add_calendar_event_sheet.dart';
import 'package:vivordo_health/widgets/add_priority_sheet.dart';
import 'package:vivordo_health/widgets/plan_slot_sheet.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/utils/latest_heart_rate.dart';
import 'package:vivordo_health/src/utils/energy_fit.dart';
import 'package:vivordo_health/src/utils/energy_forecast.dart';
import 'package:vivordo_health/src/utils/sleep_schedule.dart';
import 'package:vivordo_health/src/utils/home_metrics_summary.dart';
import 'package:vivordo_health/src/utils/home_stress_card_logic.dart';
import 'package:vivordo_health/widgets/energy_forecast_view.dart';
import 'package:vivordo_health/widgets/hourly_heart_insight_card.dart';
import 'package:vivordo_health/widgets/home_stress_card.dart';
import 'package:vivordo_health/widgets/vivordo_time_picker.dart';
import 'package:vivordo_health/src/services/home_widget_service.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'circle_screen.dart';
import 'heart_rate_detail_screen.dart';
import 'sleep_detail_screen.dart';
import 'steps_detail_screen.dart';
import 'stress_detail_screen.dart';

/// Up to three overlapping avatars. An entry without an initial is an
/// invite placeholder.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack(this.people);

  final List<({String? initial, String? photoUrl})> people;

  static const _size = 32.0;
  static const _step = 22.0;
  static const _tints = [
    (Color(0xFFE4E0FF), Color(0xFF6B5CE7)),
    (Color(0xFFDCF7EB), Color(0xFF16A874)),
    (Color(0xFFFFE7CE), Color(0xFFF28A18)),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _size + (people.length - 1) * _step,
    height: _size,
    child: Stack(
      children: [
        for (var i = 0; i < people.length; i++)
          Positioned(left: i * _step, child: _avatar(context, i)),
      ],
    ),
  );

  Widget _avatar(BuildContext context, int index) {
    final person = people[index];
    final (background, foreground) = _tints[index % _tints.length];
    final initial = person.initial;
    final fallback = initial != null
        ? Text(
            initial,
            style: TextStyle(
              color: foreground,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          )
        : Icon(Icons.person_add_alt_1_rounded, color: foreground, size: 15);
    final photoUrl = person.photoUrl;
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: context.vivordoColors.card, width: 2),
      ),
      child: photoUrl?.isNotEmpty == true
          ? ClipOval(
              child: Image.network(
                photoUrl!,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                cacheWidth: 96,
                cacheHeight: 96,
                errorBuilder: (_, _, _) => fallback,
              ),
            )
          : fallback,
    );
  }
}

class _HomeCircleProfileButton extends StatelessWidget {
  const _HomeCircleProfileButton({required this.profile, required this.onTap});

  final CircleProfile? profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final username = profile?.username.trim() ?? '';
    final photoUrl = profile?.photoUrl;
    final fallback = username.isNotEmpty
        ? Text(
            username[0].toUpperCase(),
            style: const TextStyle(
              color: _HomeScreenState.accentPurple,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          )
        : const Icon(
            Icons.person_rounded,
            color: _HomeScreenState.accentPurple,
            size: 22,
          );

    return Tooltip(
      message: 'Circle profile',
      child: Material(
        color: context.vivordoColors.card,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(3),
            child: ClipOval(
              child: photoUrl?.isNotEmpty == true
                  ? Image.network(
                      photoUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      cacheHeight: 120,
                      errorBuilder: (_, _, _) => Center(child: fallback),
                    )
                  : ColoredBox(
                      color: _HomeScreenState.accentPurple.withValues(
                        alpha: .12,
                      ),
                      child: Center(child: fallback),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final VoidCallback? onScanTap;
  final VoidCallback? onFitnessTap;
  final VoidCallback? onMyDayTap;
  final bool revealStress;
  final bool isActive;
  final bool openMoodCheckIn;
  const HomeScreen({
    super.key,
    this.onScanTap,
    this.onFitnessTap,
    this.onMyDayTap,
    this.revealStress = true,
    this.isActive = true,
    this.openMoodCheckIn = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeWidgetSnapshot {
  const _HomeWidgetSnapshot({
    required this.stressScore,
    required this.steps,
    required this.activeCalories,
    required this.exerciseMinutes,
    required this.goals,
  });

  final double? stressScore;
  final int steps;
  final int activeCalories;
  final int exerciseMinutes;
  final ActivityGoals goals;

  String get signature => <Object?>[
    stressScore?.round(),
    steps,
    activeCalories,
    exerciseMinutes,
    goals.steps,
    goals.activeCalories,
    goals.exerciseMinutes,
  ].join('|');
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _hourlyHeartKey = GlobalKey<HourlyHeartInsightCardState>();
  String _currentMood = 'Good';
  double _currentMoodScore = 75;
  String? _pendingMoodSync;
  double? _pendingMoodScoreSync;
  bool _isSavingMood = false;
  // _messageCopied removed — smart message card replaced with calendar

  // Single stream for today's unified metrics doc
  late Stream<MetricWindow> _todayStream;
  late Stream<MetricWindow> _latestScanStream;
  late final Stream<CircleProfile?> _circleProfileStream;
  // Friends is a single-listen stream, so these reconnect from a factory.
  final _friendsSnapshot = OwnedStreamSnapshot<List<CircleProfile>>();
  final _engagementSnapshot = OwnedStreamSnapshot<CircleDailyEngagement>();
  final _prioritySnapshot = OwnedStreamSnapshot<List<DailyPriority>>();

  /// Local day and account the metric listeners above were built for.
  String? _streamsDayKey;
  String? _streamsUid;
  Timer? _dayRolloverTimer;
  HomeMetricsSummaryCache _metricsSummaryCache = HomeMetricsSummaryCache();
  Future<List<gcal.Event>>? _reachableWindowEventsFuture;
  DateTime? _reachableWindowEventsDate;
  Future<List<_ScoredReachableEvent>>? _reachableWindowScoresFuture;
  DateTime? _reachableWindowScoresDate;
  Future<List<_ScheduleEvent>?>? _scheduleEventsFuture;
  DateTime? _scheduleEventsDate;
  Future<_EffortContext>? _effortContextFuture;
  DateTime? _effortContextDate;
  Future<({int minutes, DateTime? first})?>? _tomorrowPlanFuture;
  DateTime? _tomorrowPlanDate;
  ActivityGoals _activityGoals = const ActivityGoals();
  StreamSubscription<ActivityGoals>? _activityGoalsSubscription;
  _HomeWidgetSnapshot? _latestHomeWidgetSnapshot;
  _HomeWidgetSnapshot? _queuedHomeWidgetSnapshot;
  String? _lastPublishedHomeWidgetSignature;
  String? _homeWidgetPublishInProgressSignature;
  bool _homeWidgetPublishScheduled = false;
  bool _homeWidgetPublishInProgress = false;

  static const Color accentPurple = VivordoTheme.brand;
  static const Color textGrey = Color(0xFF8E8E93);
  static const Color greenColor = Color(0xFF34C759);
  static const Color orangeColor = Color(0xFFFF9500);
  static const _heartRed = Color(0xFFFF3B30);
  static const _moodOrange = Color(0xFFF97316);
  static const _calorieOrange = Color(0xFFFB923C);
  static const _exerciseGreen = Color(0xFF34D399);

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: compute BaaS stress score on every home screen load
    StressScoreService.computeAndSave().catchError((_) {});
    // Fire-and-forget: send any complete, mood-labelled days to the BaaS
    // validation/learning loop. No-op when nothing is pending, so it is safe
    // on every load. This is where yesterday's check-in actually gets
    // submitted — by now its day is closed and its metrics are complete.
    StressScoreService.submitPendingFeedback().catchError((_) {});
    WidgetsBinding.instance.addObserver(this);
    _connectMetricStreams();
    // Events added or moved anywhere (My Day, Vivordo AI) reload Your Day.
    CalendarService.eventsChanged.addListener(_refreshHomeCalendarCards);
    if (widget.openMoodCheckIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showMoodCheck());
      });
    }
    _circleProfileStream = CircleProfileService.watchCurrentProfile();
    _friendsSnapshot.connectFactory(CircleProfileService.watchFriends);
    _activityGoalsSubscription = ActivityGoalsService.watch().listen(
      (goals) {
        if (mounted) setState(() => _activityGoals = goals);
        final snapshot = _latestHomeWidgetSnapshot;
        if (snapshot == null) return;
        _queueHomeWidgetPublish(
          _HomeWidgetSnapshot(
            stressScore: snapshot.stressScore,
            steps: snapshot.steps,
            activeCalories: snapshot.activeCalories,
            exerciseMinutes: snapshot.exerciseMinutes,
            goals: goals,
          ),
        );
      },
      onError: (Object error) {
        debugPrint('Activity goals listener failed: $error');
      },
    );
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      final snapshot = _latestHomeWidgetSnapshot;
      if (snapshot != null) _queueHomeWidgetPublish(snapshot);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    _prioritySnapshot.setActive(active);
    _friendsSnapshot.setActive(active);
    _engagementSnapshot.setActive(active);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CalendarService.eventsChanged.removeListener(_refreshHomeCalendarCards);
    _sleepRefreshTimer?.cancel();
    _prioritySnapshot.dispose();
    _friendsSnapshot.dispose();
    _engagementSnapshot.dispose();
    _dayRolloverTimer?.cancel();
    _activityGoalsSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The metrics window and today's document are both pinned to the local
    // day and account they were built for, so a day that turned over — or an
    // account that changed — while the app was away needs fresh queries.
    if (state == AppLifecycleState.resumed) _reconnectMetricStreamsIfStale();
  }

  /// Fires at the next local midnight so a session left open across the date
  /// change does not keep querying yesterday. Resume alone is not enough: an
  /// app sitting in the foreground, or on another tab, gets no lifecycle
  /// event at midnight.
  void _scheduleDayRollover() {
    _dayRolloverTimer?.cancel();
    _dayRolloverTimer = Timer(durationUntilNextLocalDay(DateTime.now()), () {
      _reconnectMetricStreamsIfStale();
      // Re-arm regardless: if the clock drifted and the day has not actually
      // turned over yet, the next timer covers the remainder.
      if (mounted) _scheduleDayRollover();
    });
  }

  void _reconnectMetricStreamsIfStale() {
    if (!mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_streamsDayKey == _todayPeriod() && _streamsUid == uid) return;
    setState(_connectMetricStreams);
  }

  /// Points both metric listeners at the current local day.
  ///
  /// The history listener carries a [kHomeMetricsWindowDays] window rather
  /// than every day the account has recorded, bounded by a range on the
  /// `YYYY-MM-DD` document ids.
  ///
  /// The repository uses ascending document IDs; derived values explicitly
  /// choose the latest measurement instead of depending on query order.
  void _connectMetricStreams() {
    final today = _todayPeriod();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _streamsDayKey = today;
    _streamsUid = uid;
    _metricsSummaryCache = HomeMetricsSummaryCache();
    _scheduleDayRollover();
    final day = DateTime.now();
    _prioritySnapshot.connectFactory(() => DailyPriorityService.watch(day));
    // Today's engagement window is fixed when the query is built.
    _engagementSnapshot.connectFactory(
      CircleProfileService.watchTodayEngagement,
    );
    _todayStream = uid != null
        ? MetricsRepository.instance.watch(
            uid: uid,
            startDay: today,
            endDay: today,
            projection: MetricsProjection.homeToday,
          )
        : const Stream.empty();
    final now = DateTime.now();
    _latestScanStream = uid != null
        ? combineMetricWindows(
            MetricsRepository.instance.watch(
              uid: uid,
              startDay: homeMetricsWindowStartKey(
                now,
                days: kHomeRecentWindowDays,
              ),
              endDay: today,
              projection: MetricsProjection.homeHistory,
            ),
            MetricsRepository.instance.watch(
              uid: uid,
              startDay: homeMetricsWindowStartKey(now),
              endDay: homeMetricsWindowStartKey(
                now,
                days: kHomeRecentWindowDays + 1,
              ),
              projection: MetricsProjection.homeHistory,
            ),
          )
        : const Stream.empty();
  }

  /// Derived Home values for [snapshot], reused across rebuilds that did not
  /// change the data, the local day, or the signed-in account.
  HomeMetricsSummary _metricsSummaryFor(MetricWindow? snapshot) {
    final now = DateTime.now();
    return _metricsSummaryCache.summarize(
      snapshotKey: snapshot?.days,
      dayKey: _todayPeriod(),
      uid: FirebaseAuth.instance.currentUser?.uid,
      now: now,
      days: () =>
          (snapshot?.days.entries ??
                  const <MapEntry<String, Map<String, dynamic>>>[])
              .map((doc) => MetricDayEntry(dayKey: doc.key, data: doc.value))
              .toList(growable: false),
    );
  }

  /// Today's wake time as last seen, so new sleep can refresh Your Day.
  Object? _seenWakeTime;
  Timer? _sleepRefreshTimer;

  /// The forecast's sleep times arrive with the metrics stream, but its sleep
  /// need comes from Capacity, which the server recalculates once the sleep
  /// lands. Refetch it shortly after today's sleep changes.
  void _refreshForNewSleep(Object? wakeTime) {
    final key = (_streamsDayKey, wakeTime);
    if (_seenWakeTime == null) {
      _seenWakeTime = key;
      return;
    }
    if (_seenWakeTime == key) return;
    _seenWakeTime = key;
    _sleepRefreshTimer?.cancel();
    _sleepRefreshTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _effortContextFuture = null;
        _effortContextDate = null;
      });
    });
  }

  void _syncMoodAfterBuild(String savedMood, double savedMoodScore) {
    if ((savedMood == _currentMood &&
            savedMoodScore.round() == _currentMoodScore.round()) ||
        (savedMood == _pendingMoodSync &&
            savedMoodScore.round() == _pendingMoodScoreSync?.round())) {
      return;
    }
    _pendingMoodSync = savedMood;
    _pendingMoodScoreSync = savedMoodScore;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final mood = _pendingMoodSync;
      final score = _pendingMoodScoreSync;
      _pendingMoodSync = null;
      _pendingMoodScoreSync = null;
      if (mood == null || score == null) return;
      if (mood == _currentMood && score.round() == _currentMoodScore.round()) {
        return;
      }
      setState(() {
        _currentMood = mood;
        _currentMoodScore = score;
      });
    });
  }

  void _queueHomeWidgetPublish(_HomeWidgetSnapshot snapshot) {
    _latestHomeWidgetSnapshot = snapshot;
    if (!widget.isActive ||
        snapshot.signature == _lastPublishedHomeWidgetSignature ||
        snapshot.signature == _homeWidgetPublishInProgressSignature ||
        snapshot.signature == _queuedHomeWidgetSnapshot?.signature) {
      return;
    }
    _queuedHomeWidgetSnapshot = snapshot;
    if (_homeWidgetPublishScheduled || _homeWidgetPublishInProgress) return;
    _homeWidgetPublishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeWidgetPublishScheduled = false;
      if (!mounted) return;
      unawaited(_drainHomeWidgetPublishQueue());
    });
  }

  Future<void> _drainHomeWidgetPublishQueue() async {
    if (_homeWidgetPublishInProgress || !mounted || !widget.isActive) return;
    _homeWidgetPublishInProgress = true;
    try {
      while (mounted && widget.isActive) {
        final snapshot = _queuedHomeWidgetSnapshot;
        if (snapshot == null) break;
        _queuedHomeWidgetSnapshot = null;
        _homeWidgetPublishInProgressSignature = snapshot.signature;
        await HomeWidgetService.publish(
          stressScore: snapshot.stressScore,
          steps: snapshot.steps,
          activeCalories: snapshot.activeCalories,
          exerciseMinutes: snapshot.exerciseMinutes,
          goals: snapshot.goals,
        );
        if (!mounted) return;
        _lastPublishedHomeWidgetSignature = snapshot.signature;
      }
    } finally {
      _homeWidgetPublishInProgressSignature = null;
      _homeWidgetPublishInProgress = false;
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _getFirstName() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Alex';
    return displayName.split(' ').first;
  }

  String _todayPeriod() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  DateTime? _stressUpdatedAt(Map? stress) {
    final raw = stress?['computedAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  void _showStressScoreExplanation() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your stress score'),
        content: const Text(
          'Vivordo combines signals such as heart rate, HRV, sleep, activity, '
          'and mood with your personal baseline. Lower scores generally mean '
          'your body is showing fewer signs of stress.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser == null) {
      return _buildScaffold(
        stressScore: null,
        stressUpdatedAt: null,
        sevenDayStressAverage: null,
        stressDrivers: const [],
        stressLoading: false,
        sleepHours: null,
        sleepIsWhoop: false,
        steps: 0,
        activeCalories: 0,
        exerciseMinutes: 0,
        metricsLoading: false,
        latestHeartRate: null,
        hrLoading: false,
        moodScore: null,
      );
    }

    return VisibleStreamBuilder<MetricWindow>(
      key: ValueKey((_streamsUid, _streamsDayKey)),
      stream: _todayStream,
      builder: (context, todaySnap) {
        final bool loading =
            !todaySnap.hasData &&
            todaySnap.connectionState == ConnectionState.waiting;
        final data = todaySnap.data?.days[_streamsDayKey];

        final stressMap = data?['stress'] as Map?;
        final hrvMap = data?['hrv'] as Map?;
        final sleepMap = data?['sleep'] as Map?;
        final sleepIsWhoop = sleepMap?['source'] == 'whoop';
        if (!loading) _refreshForNewSleep(sleepMap?['wakeTime']);
        final stepsMap = data?['steps'] as Map?;
        final activeCaloriesMap = data?['active_calories'] as Map?;
        final exerciseTimeMap = data?['exercise_time'] as Map?;
        final moodMap = data?['mood'] as Map?;
        final checkIn = data?['morning_check_in'] as Map?;

        // Stress: prefer the LIVE accumulating BaaS value, then the day's
        // mean, then the HRV-derived fallback.
        //
        // `current` is where the score stands right now — it opens each day at
        // the user's personal anchor and builds through the day. `avg` is that
        // day's mean across every reading, which is the right number for the
        // history chart but lags the live one here: at 9 PM after a hard day
        // the mean still carries the calm morning. Documents written before
        // the intraday layer have no `current` and fall through to `avg`,
        // rendering exactly as they did before.
        final double? stressScore =
            (stressMap?['current'] as num?)?.toDouble() ??
            (stressMap?['avg'] as num?)?.toDouble() ??
            (hrvMap?['stressScore'] as num?)?.toDouble();

        final sleepHours = (sleepMap?['avg'] as num?)?.toDouble();

        final steps = (stepsMap?['sum'] as num?)?.toInt();
        final activeCalories =
            (activeCaloriesMap?['sum'] as num?)?.round() ?? 0;
        final exerciseMinutes = (exerciseTimeMap?['sum'] as num?)?.round() ?? 0;

        final savedMoodLabel = moodMap?['label'] as String?;
        final savedMoodScore =
            (moodMap?['avg'] as num?)?.toDouble() ??
            (savedMoodLabel == null
                ? null
                : MetricsService.moodScoreForLabel(savedMoodLabel));
        final savedMood =
            savedMoodLabel ??
            (savedMoodScore == null
                ? null
                : MetricsService.moodLabelForScore(savedMoodScore));
        if (savedMood != null && savedMoodScore != null && !_isSavingMood) {
          _syncMoodAfterBuild(savedMood, savedMoodScore);
        }

        return VisibleStreamBuilder<MetricWindow>(
          stream: _latestScanStream,
          builder: (context, scanSnap) {
            if (scanSnap.hasError || scanSnap.data?.error != null) {
              // Keep a transport failure distinguishable from missing readings;
              // the repository retains the last successfully received window.
              debugPrint(
                'HomeScreen: metrics history listener failed, heart rate '
                'may be cached: ${scanSnap.error ?? scanSnap.data?.error}',
              );
            }
            final metricsSummary = _metricsSummaryFor(scanSnap.data);
            final latestHeartRate = metricsSummary.latestHeartRate;
            final displayedStressScore =
                stressScore ?? metricsSummary.stressAnchor;
            final sevenDayStressAverage = metricsSummary.sevenDayStressAverage;
            final stressDrivers = homeStressDrivers(stressMap?['top_drivers']);
            final stressStillLoading =
                loading ||
                (stressScore == null &&
                    scanSnap.connectionState == ConnectionState.waiting &&
                    !scanSnap.hasData);

            if (data != null) {
              _queueHomeWidgetPublish(
                _HomeWidgetSnapshot(
                  stressScore: displayedStressScore,
                  steps: steps ?? 0,
                  activeCalories: activeCalories,
                  exerciseMinutes: exerciseMinutes,
                  goals: _activityGoals,
                ),
              );
            }

            // isComputing reflects a computeAndSave() network round trip
            // actually in flight — separate from stressStillLoading
            // (which is about the Firestore listener) — so the UI can
            // show a small "Updating…" hint over displayedStressScore
            // (today's, or the anchor fallback) while a fresh one is
            // being fetched, same as any other syncing tracked metric.
            return ValueListenableBuilder<bool>(
              valueListenable: StressScoreService.isComputing,
              builder: (context, computingStress, _) => _buildScaffold(
                stressScore: displayedStressScore,
                stressUpdatedAt: _stressUpdatedAt(stressMap),
                sevenDayStressAverage: sevenDayStressAverage,
                stressDrivers: stressDrivers,
                stressUpdating: computingStress,
                stressLoading: stressStillLoading,
                sleepHours: sleepHours,
                sleepIsWhoop: sleepIsWhoop,
                steps: steps ?? 0,
                activeCalories: activeCalories,
                exerciseMinutes: exerciseMinutes,
                metricsLoading: loading,
                latestHeartRate: latestHeartRate,
                hrLoading:
                    scanSnap.connectionState == ConnectionState.waiting &&
                    !scanSnap.hasData,
                moodScore: savedMoodScore,
                sleepNights: metricsSummary.sleepNights,
                checkIn: loading ? null : checkIn ?? const {},
              ),
            );
          },
        );
      },
    );
  }

  Future<List<gcal.Event>> _loadReachableWindowEvents(
    DateTime todayStart,
  ) async {
    try {
      final events = await CalendarService.getWeekEvents(
        todayStart,
      ).timeout(const Duration(seconds: 15), onTimeout: () => <gcal.Event>[]);
      // ponytail: Google events only; add Outlook's here if it's unbenched
      // (OutlookCalendarService.enabled), or tonight's reminder can miss an
      // early Outlook start until My Day reschedules it.
      // Keeps the next week of morning check-in reminders scheduled.
      unawaited(CheckInReminders.sync());
      unawaited(
        WindDownReminders.sync(
          tomorrowFirstEvent: _firstTimedStart(
            events,
            todayStart.add(const Duration(days: 1)),
          ),
        ),
      );
      final signedIn = await CalendarService.isSignedIn();
      if (!signedIn) {
        await NotificationService().cancelCalendarCheckIn();
        return [];
      }

      await _scheduleFinalEventCheckIn(events, todayStart);
      return events;
    } catch (e) {
      debugPrint('Reachable windows calendar load failed: $e');
      return [];
    }
  }

  /// The first timed, uncancelled event starting on [day].
  DateTime? _firstTimedStart(List<gcal.Event> events, DateTime day) {
    final next = day.add(const Duration(days: 1));
    return (events
            .where((event) => event.status != 'cancelled')
            .map((event) => event.start?.dateTime?.toLocal())
            .whereType<DateTime>()
            .where((start) => !start.isBefore(day) && start.isBefore(next))
            .toList()
          ..sort())
        .firstOrNull;
  }

  Future<void> _scheduleFinalEventCheckIn(
    List<gcal.Event> events,
    DateTime todayStart,
  ) async {
    final tomorrow = todayStart.add(const Duration(days: 1));
    final eventEnds =
        events
            .where((event) => event.status != 'cancelled')
            .map((event) => event.end?.dateTime?.toLocal())
            .whereType<DateTime>()
            .where((end) => !end.isBefore(todayStart) && end.isBefore(tomorrow))
            .toList()
          ..sort();

    if (eventEnds.isEmpty) {
      await NotificationService().cancelCalendarCheckIn();
      return;
    }

    await NotificationService().scheduleCalendarCheckIn(eventEnds.last);
  }

  Future<List<gcal.Event>> _getReachableWindowEventsFuture(
    DateTime todayStart,
  ) {
    final normalizedDate = DateTime(
      todayStart.year,
      todayStart.month,
      todayStart.day,
    );

    if (_reachableWindowEventsFuture != null &&
        _reachableWindowEventsDate != null &&
        _reachableWindowEventsDate!.year == normalizedDate.year &&
        _reachableWindowEventsDate!.month == normalizedDate.month &&
        _reachableWindowEventsDate!.day == normalizedDate.day) {
      return _reachableWindowEventsFuture!;
    }

    _reachableWindowEventsDate = normalizedDate;
    _reachableWindowEventsFuture = _loadReachableWindowEvents(normalizedDate);
    return _reachableWindowEventsFuture!;
  }

  Future<List<_ScoredReachableEvent>> _getReachableWindowScoresFuture(
    DateTime todayStart,
  ) {
    final normalizedDate = DateUtils.dateOnly(todayStart);
    if (_reachableWindowScoresFuture != null &&
        DateUtils.isSameDay(_reachableWindowScoresDate, normalizedDate)) {
      return _reachableWindowScoresFuture!;
    }

    _reachableWindowScoresDate = normalizedDate;
    _reachableWindowScoresFuture = _loadReachableWindowScores(normalizedDate);
    return _reachableWindowScoresFuture!;
  }

  Future<List<_ScoredReachableEvent>> _loadReachableWindowScores(
    DateTime todayStart,
  ) async {
    final events = await _getReachableWindowEventsFuture(todayStart);
    final timedEvents = events.where((event) {
      return event.status != 'cancelled' &&
          event.transparency != 'transparent' &&
          !(event.attendees?.any(
                (a) => a.self == true && a.responseStatus == 'declined',
              ) ??
              false) &&
          event.start?.dateTime != null &&
          event.end?.dateTime != null;
    }).toList();

    final inputs = <CalendarCognitiveEvent>[];
    for (var i = 0; i < timedEvents.length; i++) {
      final event = timedEvents[i];
      final start = event.start!.dateTime!.toLocal();
      final end = event.end!.dateTime!.toLocal();
      final selfAttendee = event.attendees
          ?.where((attendee) => attendee.self == true)
          .firstOrNull;
      inputs.add(
        CalendarCognitiveEvent(
          id: _reachableEventKey(event, i),
          title: event.summary ?? 'Calendar event',
          description: event.description ?? '',
          start: start,
          end: end,
          attendeeCount: event.attendees?.length ?? 0,
          isOrganizer: event.organizer?.self == true,
          isOptional: selfAttendee?.optional == true,
          isOnlineMeeting:
              event.hangoutLink?.isNotEmpty == true ||
              event.conferenceData != null,
          showsAsFree: event.transparency == 'transparent',
        ),
      );
    }

    // Claude sorts what the local rules can't, with the user's AI consent,
    // so the chart matches the server's Effort.
    final scores = await CalendarCognitiveLoadService.scoreEvents(
      inputs,
      allowAi: true,
    );
    return List.generate(
      timedEvents.length,
      (index) => _ScoredReachableEvent(
        event: timedEvents[index],
        score: scores[index],
        input: inputs[index],
      ),
    );
  }

  String _reachableEventKey(gcal.Event event, int index) =>
      'google:${CalendarService.calendarIdForEvent(event) ?? ''}:'
      '${event.id ?? event.iCalUID ?? index}:${event.start?.dateTime?.toUtc().toIso8601String()}';

  Widget _buildScaffold({
    required double? stressScore,
    required DateTime? stressUpdatedAt,
    required double? sevenDayStressAverage,
    required List<HomeStressDriver> stressDrivers,
    bool stressUpdating = false,
    required bool stressLoading,
    required double? sleepHours,
    required bool sleepIsWhoop,
    required int steps,
    required int activeCalories,
    required int exerciseMinutes,
    required bool metricsLoading,
    required LatestHeartRateReading? latestHeartRate,
    required bool hrLoading,
    required double? moodScore,
    List<SleepPeriod> sleepNights = const [],
    Map? checkIn,
  }) {
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            _refreshHomeCalendarCards();
            await _hourlyHeartKey.currentState?.refresh(force: true);
          },
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _push(const StressDetailScreen()),
                  child: HomeStressCard(
                    score: stressScore,
                    updatedAt: stressUpdatedAt,
                    sevenDayAverage: sevenDayStressAverage,
                    drivers: stressDrivers,
                    steps: steps,
                    loading: stressLoading,
                    updating: stressUpdating,
                    revealScore: widget.revealStress,
                    onInfoTap: _showStressScoreExplanation,
                    showWhoopBadge:
                        sleepIsWhoop || latestHeartRate?.source == 'whoop_ble',
                  ),
                ),
                _buildCheckIn(checkIn, sleepHours),
                const SizedBox(height: 12),
                _buildVitals(
                  sleepHours: sleepHours,
                  heartRate: latestHeartRate?.bpm,
                  moodScore: moodScore,
                  loading: metricsLoading,
                  hrLoading: hrLoading,
                ),
                const SizedBox(height: 12),
                _buildActivityCard(
                  steps: steps,
                  activeCalories: activeCalories,
                  exerciseMinutes: exerciseMinutes,
                ),
                const SizedBox(height: 12),
                _buildCircleCard(),
                _buildSectionTitle(
                  "YOUR DAY",
                  trailing: [
                    _infoButton(
                      label: 'How Your Day works',
                      onTap: _showReachableWindowsInfo,
                    ),
                    TextButton(
                      onPressed: widget.onMyDayTap,
                      style: TextButton.styleFrom(
                        foregroundColor: accentPurple,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Open My Day ›'),
                    ),
                  ],
                ),
                _buildDayLoad(sleepNights),
                _buildSectionTitle('INSIGHTS'),
                _buildInsights(
                  sleepHours: sleepHours,
                  hasHeartRate: latestHeartRate != null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The daily check-in (docs/scores.md §4), from 5 AM until both questions
  /// are answered or it's dismissed. "How do you feel?" also counts as
  /// today's mood check-in. [checkIn] is null until today's metrics load.
  Widget _buildCheckIn(Map? checkIn, double? sleepHours) {
    if (!checkInDue(checkIn, DateTime.now())) return const SizedBox.shrink();
    final feel = checkIn!['feel'];
    final sleep = checkIn['sleep'];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: MorningCheckInCard(
        feel: feel is num ? MetricsService.moodLabelForScore(feel) : null,
        sleep: sleep is num
            ? sleepCheckInScores.entries
                  .where((e) => e.value == sleep)
                  .firstOrNull
                  ?.key
            : null,
        sleepHours: sleepHours,
        onFeel: (label) => _saveCheckIn({
          'feel': MetricsService.moodScoreForLabel(label),
        }, mood: label),
        onSleep: (label) => _saveCheckIn({'sleep': sleepCheckInScores[label]!}),
        onDismiss: () => _saveCheckIn({'dismissed': true}),
      ),
    );
  }

  /// Saves answers to today's `metrics_daily.morning_check_in`, which the
  /// server's Capacity reads. [mood] is also saved as the mood check-in.
  Future<void> _saveCheckIn(Map<String, Object> fields, {String? mood}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('metrics_daily')
            .doc(localDayKey(DateTime.now()))
            .set({'morning_check_in': fields}, SetOptions(merge: true)),
        if (mood != null) MetricsService.saveMoodCheckIn(mood),
      ]);
      // Answered or dismissed: today's 10 AM reminder isn't needed.
      unawaited(CheckInReminders.sync());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save your check-in.')),
        );
      }
    }
  }

  void _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  /// The card every Home section sits on, in My Day's style.
  Widget _card({required Widget child, VoidCallback? onTap}) => Material(
    color: context.vivordoColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Colors.black.withValues(alpha: .07)),
    ),
    clipBehavior: Clip.antiAlias,
    child: onTap == null ? child : InkWell(onTap: onTap, child: child),
  );

  Widget _divider() => VerticalDivider(
    width: 1,
    thickness: 1,
    color: context.vivordoColors.border,
  );

  Widget _buildHeader() {
    final colors = context.vivordoColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${DateFormat('EEE, MMM d').format(DateTime.now())} · '
                '${_getGreeting()}',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _getFirstName(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VisibleStreamBuilder<CircleProfile?>(
              stream: _circleProfileStream,
              builder: (context, snapshot) {
                final profile = snapshot.data;
                return _HomeCircleProfileButton(
                  profile: profile,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => profile == null
                          ? const CircleScreen()
                          : CircleUserProfilePage(
                              profile: profile,
                              isOwner: true,
                            ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'App Settings',
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: context.vivordoColors.card,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 12,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.settings_rounded,
                    color: accentPurple,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVitals({
    required double? sleepHours,
    required int? heartRate,
    required double? moodScore,
    required bool loading,
    required bool hrLoading,
  }) => _card(
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _vital(
              icon: Icons.bedtime_rounded,
              color: accentPurple,
              value: sleepHours == null ? null : _sleepLabel(sleepHours),
              label: 'Sleep',
              loading: loading,
              onTap: () => _push(const SleepDetailScreen()),
            ),
          ),
          _divider(),
          Expanded(
            child: _vital(
              icon: Icons.favorite_rounded,
              color: _heartRed,
              value: heartRate?.toString(),
              label: heartRate == null ? 'Heart rate' : 'bpm',
              loading: hrLoading,
              onTap: () => _push(const HeartRateDetailScreen()),
            ),
          ),
          _divider(),
          Expanded(
            child: _vital(
              icon: Icons.mood_rounded,
              color: _moodOrange,
              value: moodScore?.round().toString(),
              label: 'Mood',
              loading: loading,
              emptyAction: 'Check in',
              onTap: _showMoodCheck,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _vital({
    required IconData icon,
    required Color color,
    required String? value,
    required String label,
    required bool loading,
    required VoidCallback onTap,
    String? emptyAction,
  }) {
    final colors = context.vivordoColors;
    final shown = value ?? emptyAction ?? 'No data';
    return Semantics(
      button: true,
      label: loading ? '$label, loading' : '$label, $shown',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 17),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      Container(
                        width: 34,
                        height: 15,
                        margin: const EdgeInsets.only(bottom: 3),
                        decoration: BoxDecoration(
                          color: colors.cardMuted,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    else
                      Text(
                        shown,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: value == null ? 13 : 15.5,
                          fontWeight: FontWeight.w800,
                          color: value != null
                              ? colors.textPrimary
                              : emptyAction != null
                              ? accentPurple
                              : colors.textSecondary,
                        ),
                      ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sleepLabel(double hours) {
    final minutes = (hours * 60).round();
    return minutes % 60 == 0
        ? '${minutes ~/ 60}h'
        : '${minutes ~/ 60}h ${minutes % 60}m';
  }

  Widget _buildActivityCard({
    required int steps,
    required int activeCalories,
    required int exerciseMinutes,
  }) {
    final colors = context.vivordoColors;
    final goals = _activityGoals;
    double progress(int value, int goal) =>
        goal <= 0 ? 0 : (value / goal).clamp(0.0, 1.0);
    Widget ring(double size, double value, Color color, double stroke) =>
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: value,
            strokeWidth: stroke,
            color: color,
            backgroundColor: colors.cardMuted,
          ),
        );
    return _card(
      onTap: widget.onFitnessTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Semantics(
              label:
                  'Activity: steps $steps of ${goals.steps}, '
                  '$activeCalories of ${goals.activeCalories} calories, '
                  '$exerciseMinutes of ${goals.exerciseMinutes} exercise minutes',
              child: SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ring(52, progress(steps, goals.steps), accentPurple, 6),
                    ring(
                      36,
                      progress(activeCalories, goals.activeCalories),
                      _calorieOrange,
                      6,
                    ),
                    ring(
                      20,
                      progress(exerciseMinutes, goals.exerciseMinutes),
                      _exerciseGreen,
                      5,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _activityNumber(
                        NumberFormat.decimalPattern().format(steps),
                        'steps',
                        first: true,
                        onTap: () => _push(const StepsDetailScreen()),
                      ),
                    ),
                    _divider(),
                    Expanded(child: _activityNumber('$activeCalories', 'cal')),
                    _divider(),
                    Expanded(
                      child: _activityNumber('${exerciseMinutes}m', 'exercise'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            const _HomeWorkoutStreakBadge(),
            Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _activityNumber(
    String value,
    String label, {
    bool first = false,
    VoidCallback? onTap,
  }) {
    final colors = context.vivordoColors;
    final number = Padding(
      padding: EdgeInsets.only(left: first ? 0 : 10, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
          ),
        ],
      ),
    );
    if (onTap == null) return number;
    return Semantics(
      button: true,
      label: '$value $label. Opens step details.',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: number,
      ),
    );
  }

  Widget _buildSectionTitle(String title, {List<Widget> trailing = const []}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 0, 8),
        child: SizedBox(
          height: 36,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    color: context.vivordoColors.textSecondary,
                  ),
                ),
              ),
              ...trailing,
            ],
          ),
        ),
      );

  Widget _infoButton({required String label, required VoidCallback onTap}) =>
      IconButton(
        tooltip: label,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          Icons.info_outline_rounded,
          size: 19,
          color: context.vivordoColors.textSecondary,
        ),
      );

  Future<void> _showReachableWindowsInfo() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: dialogContext.vivordoColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accentPurple.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.psychology_alt_rounded,
              color: accentPurple,
              size: 23,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'How Your Day works',
              style: TextStyle(
                color: dialogContext.vivordoColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Text(
          'Each bar is one hour of your day, 7 AM to 10 PM, stretched to fit anything earlier or later. Solid bars are what the day has taken so far (Effort); outlined bars are what\'s still planned (Demand). Taller, warmer bars are busier hours.\n\n'
          '• Calendar events are rated by how demanding they look. Ones that can\'t be rated count as moderate.\n'
          '• Priorities count once you tick them off, in their time slot, or as a small mark at the hour you finished them.\n'
          '• Workouts are shown in teal.\n\n'
          'Longer items, overlaps and back-to-back runs make an hour busier, and so does anything after your end-of-day time.\n\n'
          'So far compares today with your usual by this time of day, once there are 14 days to compare with.\n\n'
          'Below the bars is your next free stretch of 30+ minutes. Tap Plan it to fill it, or tap a bar to see its busiest event.\n\n'
          'Effort and ratings are estimates.',
          style: TextStyle(
            color: dialogContext.vivordoColors.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: accentPurple,
            foregroundColor: Colors.white,
          ),
          child: const Text('Got it'),
        ),
      ],
    ),
  );

  Widget _buildCircleCard() {
    final colors = context.vivordoColors;
    return _card(
      onTap: () => _push(const CircleScreen()),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
        child: ListenableBuilder(
          listenable: Listenable.merge([_friendsSnapshot, _engagementSnapshot]),
          builder: (context, _) {
            final friends =
                _friendsSnapshot.value.data ?? const <CircleProfile>[];
            final engagement =
                _engagementSnapshot.value.data ??
                const CircleDailyEngagement(likes: 0, comments: 0);
            final comments = engagement.comments;
            return Row(
              children: [
                if (friends.isEmpty)
                  VisibleStreamBuilder<CircleProfile?>(
                    stream: _circleProfileStream,
                    builder: (context, snapshot) {
                      final profile = snapshot.data;
                      final name = profile?.username.trim() ?? '';
                      return _AvatarStack([
                        (
                          initial: name.isEmpty ? 'Y' : name[0].toUpperCase(),
                          photoUrl: profile?.photoUrl,
                        ),
                        // No friends yet: invite someone.
                        (initial: null, photoUrl: null),
                      ]);
                    },
                  )
                else
                  _AvatarStack([
                    for (final friend in friends.take(3))
                      (
                        initial: friend.username.trim().isEmpty
                            ? '?'
                            : friend.username.trim()[0].toUpperCase(),
                        photoUrl: friend.photoUrl,
                      ),
                  ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Circle',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${friends.length} '
                        '${friends.length == 1 ? 'friend' : 'friends'} · '
                        '$comments ${comments == 1 ? 'update' : 'updates'}',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (engagement.likes > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: accentPurple.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.favorite_border_rounded,
                          color: accentPurple,
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${engagement.likes} new',
                          style: const TextStyle(
                            color: accentPurple,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDayLoad(List<SleepPeriod> sleepNights) {
    final now = DateTime.now();
    final todayStart = DateUtils.dateOnly(now);
    final loading = _card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: accentPurple,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Reviewing today’s calendar…',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.vivordoColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return FutureBuilder<List<_ScoredReachableEvent>>(
      future: _getReachableWindowScoresFuture(todayStart),
      builder: (context, scoresSnapshot) =>
          FutureBuilder<List<_ScheduleEvent>?>(
            future: _getScheduleEventsFuture(todayStart),
            builder: (context, eventsSnapshot) {
              if (scoresSnapshot.connectionState == ConnectionState.waiting ||
                  eventsSnapshot.connectionState == ConnectionState.waiting) {
                return loading;
              }
              return FutureBuilder<_EffortContext>(
                future: _getEffortContextFuture(todayStart),
                builder: (context, contextSnapshot) =>
                    ValueListenableBuilder<AsyncSnapshot<List<DailyPriority>>>(
                      valueListenable: _prioritySnapshot,
                      builder: (context, prioritySnapshot, _) => _dayLoadCard(
                        now: now,
                        sleepNights: sleepNights,
                        scored: scoresSnapshot.data ?? const [],
                        events: eventsSnapshot.data,
                        priorities: prioritySnapshot.data ?? const [],
                        effortContext:
                            contextSnapshot.data ?? const _EffortContext(),
                      ),
                    ),
              );
            },
          ),
    );
  }

  Widget _dayLoadCard({
    required DateTime now,
    required List<SleepPeriod> sleepNights,
    required List<_ScoredReachableEvent> scored,
    required List<_ScheduleEvent>? events,
    required List<DailyPriority> priorities,
    required _EffortContext effortContext,
  }) {
    final colors = context.vivordoColors;
    final today = DateUtils.dateOnly(now);
    final eventKeys = {for (final event in events ?? const []) event.key};
    // Timed priorities today. A priority linked to a calendar event is
    // already counted by that event, as on My Day's timeline.
    final timed = [
      for (final priority in priorities)
        if (!priority.isAllDay &&
            priority.sourceStart != null &&
            DateUtils.isSameDay(priority.sourceStart, now) &&
            !eventKeys.contains(priority.sourceEventKey))
          priority,
    ];
    // Untimed priorities (and timed ones from other days) ticked off today.
    final untimedDone = [
      for (final priority in priorities)
        if (priority.completed &&
            !timed.contains(priority) &&
            !eventKeys.contains(priority.sourceEventKey) &&
            priority.completedAt != null &&
            DateUtils.isSameDay(priority.completedAt, now))
          (doneAt: priority.completedAt!, effort: priority.planning['effort']),
    ];
    final (:from, :until) = dayLoadRange(now, [
      for (final event in events ?? const <_ScheduleEvent>[])
        (start: event.start, end: event.end),
      for (final priority in timed)
        (start: priority.sourceStart!, end: priority.timelineEnd!),
    ]);
    // Outlook events have no rating here, so they count as unknown (30), as
    // in the server's Effort.
    final outlook = [
      for (final (i, event) in (events ?? const <_ScheduleEvent>[]).indexed)
        if (event.key == null)
          (
            event: CalendarCognitiveEvent(
              id: 'outlook:$i',
              title: event.title,
              start: event.start,
              end: event.end,
            ),
            score: CognitiveLoadScore(
              eventId: 'outlook:$i',
              score: 0,
              category: 'unknown',
              reason: 'Outlook event',
              usedAi: false,
            ),
          ),
    ];
    final items = <EffortItem>[
      for (final e in scored)
        (event: e.input, score: e.score, done: false, open: false),
      for (final e in outlook)
        (event: e.event, score: e.score, done: false, open: false),
      for (final priority in timed)
        if (priorityLoadInput(
              id: 'priority:${priority.reference.path}',
              title: priority.title,
              start: priority.sourceStart!,
              end: priority.timelineEnd!,
              effort: priority.planning['effort'],
            )
            case final input)
          (
            event: input.event,
            score: input.score,
            done: priority.completed,
            open: !priority.completed,
          ),
    ];
    final effort = buildDayEffort(
      now: now,
      from: from,
      until: until,
      wrapUp: today.add(Duration(minutes: effortContext.wrapUpMinutes)),
      items: items,
      untimedDone: untimedDone,
      workouts: effortContext.workouts,
    );
    // The energy forecast (docs/scores.md §8), once any night is recorded
    // or your usual sleep times are set. Tomorrow's first event sets bed-by.
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final energy = sleepNights.isEmpty && effortContext.sleepSchedule == null
        ? null
        : forecastEnergy(
            day: today,
            nights: sleepNights,
            sleepNeedHours: effortContext.sleepNeedHours,
            schedule: effortContext.sleepSchedule,
            tomorrowFirstEvent: ([
              for (final event in events ?? const <_ScheduleEvent>[])
                if (!event.start.isBefore(tomorrow) &&
                    event.start.isBefore(tomorrow.add(const Duration(days: 1))))
                  event.start,
            ]..sort()).firstOrNull,
          );
    final fits = energy == null
        ? const <EnergyFit>[]
        : fitDayToEnergy(forecast: energy, items: items, now: now);
    final clash = fits.where((f) => f.kind == EnergyFitKind.clash).firstOrNull;
    if (energy != null) {
      final evening = !now.isBefore(
        today.add(Duration(minutes: effortContext.wrapUpMinutes)),
      );
      latestEnergy = (
        text: energyContext(
          today: energy,
          fits: fits,
          tomorrow: evening
              ? tomorrowEnergyForecast(
                  tonight: energy,
                  today: today,
                  nights: sleepNights,
                  schedule: effortContext.sleepSchedule,
                )
              : null,
        ),
        at: now,
      );
    }
    final opening = nextDayOpening(now, [
      for (final event in events ?? const <_ScheduleEvent>[])
        AgendaItem(event.title, event.start, event.end),
      for (final priority in timed)
        if (!priority.completed)
          AgendaItem(
            priority.title,
            priority.sourceStart!,
            priority.timelineEnd!,
          ),
    ]);
    final nowFraction =
        now.difference(from).inMinutes / until.difference(from).inMinutes;
    final soFar = effortSoFarWord(
      soFar: effort.soFar,
      now: now,
      pastByHour: effortContext.pastByHour,
    );

    return _card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _effortStat('SO FAR', soFar, null)),
                  VerticalDivider(width: 24, color: colors.border),
                  Expanded(
                    child: effort.aheadMinutes > 0
                        ? _effortStat(
                            'STILL AHEAD',
                            '${_durationLabel(Duration(minutes: effort.aheadMinutes))} planned',
                            [
                              switch (effort.aheadLevel) {
                                DayLoadLevel.heavy => 'Mostly heavy',
                                DayLoadLevel.focused => 'Mostly focused',
                                _ => 'Mostly light',
                              },
                              if (effort.nextStart case final next?)
                                'next ${DateFormat.jm().format(next).replaceAll(':00', '')}',
                            ].join(' · '),
                          )
                        : FutureBuilder<({int minutes, DateTime? first})?>(
                            future: _getTomorrowPlanFuture(today),
                            builder: (context, snapshot) {
                              final plan = snapshot.data;
                              return _effortStat(
                                'TOMORROW',
                                plan == null
                                    ? '…'
                                    : plan.minutes == 0
                                    ? 'Nothing planned yet'
                                    : '${_durationLabel(Duration(minutes: plan.minutes))} planned',
                                plan?.first == null
                                    ? null
                                    : 'First at ${DateFormat.jm().format(plan!.first!)}',
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 60,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < effort.hours.length; i++) ...[
                          if (i > 0) const SizedBox(width: 5),
                          Expanded(
                            child: _effortBar(
                              hour: effort.hours[i],
                              scored: scored,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (energy != null)
                      Positioned.fill(
                        child: EnergyCurve(
                          forecast: energy,
                          from: from,
                          until: until,
                        ),
                      ),
                    if (nowFraction >= 0 && nowFraction <= 1)
                      Positioned(
                        left: constraints.maxWidth * nowFraction - 1,
                        top: -4,
                        bottom: -4,
                        child: IgnorePointer(
                          child: Container(
                            width: 2,
                            decoration: BoxDecoration(
                              color: colors.textPrimary.withValues(alpha: .8),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < effort.hours.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      i % 3 == 0
                          ? _shortHour(from.add(Duration(hours: i)).hour)
                          : '',
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final (label, color, outlined) in [
                  ('Light', _loadColor(DayLoadLevel.light), false),
                  ('Focused', _loadColor(DayLoadLevel.focused), false),
                  ('Heavy', _loadColor(DayLoadLevel.heavy), false),
                  ('Workout', _workoutTeal, false),
                  ('Ahead', accentPurple, true),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: outlined ? null : color,
                          border: outlined
                              ? Border.all(color: color, width: 1.5)
                              : null,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (energy != null) ...[
              const SizedBox(height: 12),
              EnergyChips(
                forecast: energy,
                onTap: () => showEnergyForecastSheet(context, energy),
              ),
              if (clash != null) ...[
                const SizedBox(height: 8),
                Text(
                  energyClashText(
                    title: clash.item.event.title,
                    start: clash.item.event.start,
                    phase: clash.phase,
                  ),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ],
            if (events == null) ...[
              const SizedBox(height: 10),
              Text(
                'Connect a calendar in My Day to include your events.',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
            Divider(height: 28, color: colors.border),
            _openingRow(opening),
          ],
        ),
      ),
    );
  }

  static const _workoutTeal = Color(0xFF5DCAA5);

  Widget _effortStat(String label, String value, String? detail) {
    final colors = context.vivordoColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            letterSpacing: .6,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(
            detail,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ],
    );
  }

  static String _shortHour(int hour) =>
      '${hour % 12 == 0 ? 12 : hour % 12}${hour < 12 ? 'a' : 'p'}';

  Color _loadColor(DayLoadLevel level) => switch (level) {
    DayLoadLevel.none => context.vivordoColors.cardMuted,
    DayLoadLevel.light => _exerciseGreen.withValues(alpha: .55),
    DayLoadLevel.focused => accentPurple.withValues(alpha: .55),
    DayLoadLevel.heavy => const Color(0xFFF97316),
  };

  /// One hour's bar: workouts (teal) and what happened (solid, by level)
  /// at the bottom, what's still planned (outlined) on top, and a dot for
  /// each untimed priority ticked off. Tapping opens the hour's heaviest
  /// calendar event.
  Widget _effortBar({
    required EffortHour hour,
    required List<_ScoredReachableEvent> scored,
  }) {
    final colors = context.vivordoColors;
    final hourEnd = hour.start.add(const Duration(hours: 1));
    final top =
        (scored
                .where(
                  (e) =>
                      e.input.start.isBefore(hourEnd) &&
                      e.input.end.isAfter(hour.start),
                )
                .toList()
              ..sort((a, b) => b.score.score.compareTo(a.score.score)))
            .firstOrNull;
    final total = hour.workout + hour.done + hour.ahead;
    // Scale down when the parts add up to more than a full bar.
    final scale = total > 100 ? 100 / total : 1.0;
    final doneLevel = dayLoadLevel(hour.done);
    final label = [
      if (hour.done > 0) '${doneLevel.name} so far',
      if (hour.workout > 0) 'workout',
      if (hour.ahead > 0) '${dayLoadLevel(hour.ahead).name} still planned',
      if (hour.ticks > 0) '${hour.ticks} priority done',
    ];
    Widget part(double value, {Color? fill, Color? outline}) => Flexible(
      flex: (value * scale * 10).round().clamp(1, 1000),
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          border: outline == null
              ? null
              : Border.all(color: outline, width: 1.5),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
    return Semantics(
      label:
          '${DateFormat.j().format(hour.start)}, ${label.isEmpty ? 'open' : label.join(', ')}',
      button: top != null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: top == null ? null : () => _showReachableEventSummary(top.event),
        child: Column(
          children: [
            Expanded(
              child: total <= 0
                  ? Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: .08,
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _loadColor(DayLoadLevel.none),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    )
                  : Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: (total * scale / 100).clamp(.18, 1.0),
                        widthFactor: 1,
                        child: Column(
                          verticalDirection: VerticalDirection.up,
                          children: [
                            if (hour.workout > 0)
                              part(hour.workout, fill: _workoutTeal),
                            if (hour.done > 0)
                              part(hour.done, fill: _loadColor(doneLevel)),
                            if (hour.ahead > 0)
                              part(
                                hour.ahead,
                                outline: accentPurple.withValues(alpha: .75),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (hour.ticks > 0)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 9,
                  color: colors.textSecondary,
                ),
              )
            else
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<_EffortContext> _getEffortContextFuture(DateTime day) {
    if (_effortContextFuture != null &&
        DateUtils.isSameDay(_effortContextDate, day)) {
      return _effortContextFuture!;
    }
    _effortContextDate = day;
    return _effortContextFuture = _loadEffortContext(day);
  }

  /// Today's in-app workouts, the user's end-of-day time, and earlier days'
  /// hour-by-hour Effort (scores_daily, last 28 days) for "So far".
  Future<_EffortContext> _loadEffortContext(DateTime day) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const _EffortContext();
    final user = FirebaseFirestore.instance.collection('users').doc(uid);
    final dayStart = DateUtils.dateOnly(day);
    try {
      final [workouts, scores, profile, todayScores] = await Future.wait([
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
                DateTime(day.year, day.month, day.day - 28),
              ),
            )
            .where(FieldPath.documentId, isLessThan: localDayKey(day))
            .get(),
        user.get(),
        user.collection('scores_daily').doc(localDayKey(day)).get(),
      ]);
      final preferences =
          (profile as DocumentSnapshot<Map<String, dynamic>>)
                  .data()?['preferences']
              as Map?;
      final wrapUp = preferences?['dayWrapUpMinutes'];
      return _EffortContext(
        sleepSchedule: SleepSchedule.fromPreferences(preferences),
        sleepNeedHours:
            (((todayScores as DocumentSnapshot<Map<String, dynamic>>)
                            .data()?['capacity']
                        as Map?)?['sleepNeed']
                    as num?)
                ?.toDouble(),
        wrapUpMinutes: wrapUp is int ? wrapUp : kDefaultDayWrapUpMinutes,
        workouts: [
          for (final doc
              in (workouts as QuerySnapshot<Map<String, dynamic>>).docs)
            if (doc.data()['startedAt'] case final Timestamp start)
              (
                start: start.toDate(),
                end:
                    (doc.data()['completedAt'] as Timestamp?)?.toDate() ??
                    start.toDate().add(
                      Duration(
                        seconds:
                            (((doc.data()['durationMinutes'] as num?) ?? 0) *
                                    60)
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
        pastByHour: [
          for (final doc
              in (scores as QuerySnapshot<Map<String, dynamic>>).docs)
            if (doc.data()['effort'] case {
              'version': 1,
              'byHour': final List byHour,
            })
              byHour.whereType<num>().toList(),
        ],
      );
    } catch (error) {
      debugPrint('Home Effort context failed: $error');
      return const _EffortContext();
    }
  }

  Future<({int minutes, DateTime? first})?> _getTomorrowPlanFuture(
    DateTime today,
  ) {
    if (_tomorrowPlanFuture != null &&
        DateUtils.isSameDay(_tomorrowPlanDate, today)) {
      return _tomorrowPlanFuture!;
    }
    _tomorrowPlanDate = today;
    return _tomorrowPlanFuture = _loadTomorrowPlan(today);
  }

  /// Tomorrow's planned time (calendar events and timed priorities, overlaps
  /// counted once) and its first start, for the evening's "Tomorrow".
  Future<({int minutes, DateTime? first})?> _loadTomorrowPlan(
    DateTime today,
  ) async {
    final start = DateTime(today.year, today.month, today.day + 1);
    final end = DateTime(today.year, today.month, today.day + 2);
    final intervals = <(DateTime, DateTime)>[];
    try {
      if (await CalendarService.isSignedIn()) {
        for (final event in await CalendarService.getEventsBetween(
          start,
          end,
        )) {
          final s = event.start?.dateTime?.toLocal();
          final e = event.end?.dateTime?.toLocal();
          if (s == null ||
              e == null ||
              event.status == 'cancelled' ||
              event.transparency == 'transparent' ||
              (event.attendees?.any(
                    (a) => a.self == true && a.responseStatus == 'declined',
                  ) ??
                  false)) {
            continue;
          }
          intervals.add((s, e));
        }
      }
      if (await OutlookCalendarService.isSignedIn()) {
        for (final event in await OutlookCalendarService.getEventsBetween(
          start,
          end,
        )) {
          if (!event.isAllDay) {
            intervals.add((event.start.toLocal(), event.end.toLocal()));
          }
        }
      }
      for (final priority in await DailyPriorityService.forDay(
        start,
        includeCompleted: false,
        source: Source.serverAndCache,
      )) {
        if (!priority.isAllDay &&
            priority.sourceStart != null &&
            DateUtils.isSameDay(priority.sourceStart, start)) {
          intervals.add((priority.sourceStart!, priority.timelineEnd!));
        }
      }
    } catch (error) {
      debugPrint('Home tomorrow plan failed: $error');
      return null;
    }
    final clipped = [
      for (final (s, e) in intervals)
        if (e.isAfter(start) && s.isBefore(end))
          (s.isBefore(start) ? start : s, e.isAfter(end) ? end : e),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    var minutes = 0;
    DateTime? coveredUntil;
    for (final (s, e) in clipped) {
      final from = coveredUntil != null && coveredUntil.isAfter(s)
          ? coveredUntil
          : s;
      if (e.isAfter(from)) minutes += e.difference(from).inMinutes;
      if (coveredUntil == null || e.isAfter(coveredUntil)) coveredUntil = e;
    }
    return (minutes: minutes, first: clipped.firstOrNull?.$1);
  }

  Widget _openingRow(({DateTime start, DateTime? end, String? next})? opening) {
    final colors = context.vivordoColors;
    final time = DateFormat.jm();
    final String title;
    final String detail;
    if (opening == null) {
      title = 'No openings left today';
      detail = 'Nothing free for 30 minutes or more.';
    } else if (opening.end == null) {
      title = 'Open from ${time.format(opening.start)}';
      detail = 'Free for the rest of today';
    } else {
      final end = opening.end!;
      title = 'Open ${time.format(opening.start)} – ${time.format(end)}';
      final span = _durationLabel(end.difference(opening.start));
      detail = opening.next == null ? span : '$span · then ${opening.next}';
    }
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: opening == null ? colors.border : _exerciseGreen,
            shape: BoxShape.circle,
            boxShadow: [
              if (opening != null)
                BoxShadow(
                  color: _exerciseGreen.withValues(alpha: .18),
                  spreadRadius: 5,
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
            ],
          ),
        ),
        if (opening != null) ...[
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () => _planOpening(opening.start, opening.end),
            style: FilledButton.styleFrom(
              backgroundColor: accentPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Plan it'),
          ),
        ],
      ],
    );
  }

  /// Same Priority / Event sheet and saving as My Day's openings.
  Future<void> _planOpening(DateTime start, DateTime? end) async {
    final result = await showPlanSlotSheet(context, start: start, end: end);
    if (!mounted) return;
    try {
      switch (result) {
        case PriorityDraft draft:
          final warning = await savePriorityDraft(draft);
          _showHomeCalendarMessage(warning ?? 'Priority added.');
          if (draft.addToCalendar) _refreshHomeCalendarCards();
        case CalendarEventDraft draft:
          await saveEventDraft(draft);
          _refreshHomeCalendarCards();
          _showHomeCalendarMessage('Event added to Google Calendar.');
      }
    } catch (error) {
      _showHomeCalendarMessage(
        result is PriorityDraft
            ? 'Could not add priority: $error'
            : 'Could not create event: $error',
      );
    }
  }

  Widget _buildInsights({
    required double? sleepHours,
    required bool hasHeartRate,
  }) {
    final todayStart = DateUtils.dateOnly(DateTime.now());
    final divider = Divider(height: 1, color: context.vivordoColors.border);
    final schedule = FutureBuilder<List<_ScheduleEvent>?>(
      future: _getScheduleEventsFuture(todayStart),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: [
              const HomeInsightRow(
                icon: Icons.calendar_today_rounded,
                color: Color(0xFF007AFF),
                title: 'Reviewing your schedule',
                subtitle: 'Checking today’s calendar load for useful timing.',
              ),
              divider,
            ],
          );
        }
        final events = snapshot.data;
        if (events == null) return const SizedBox.shrink();
        final insight = _buildScheduleInsight(events, todayStart);
        return Column(
          children: [
            HomeInsightRow(
              icon: insight.icon,
              color: insight.color,
              title: insight.title,
              subtitle: insight.subtitle,
            ),
            divider,
          ],
        );
      },
    );
    final rows = <Widget>[
      if (sleepHours != null)
        HomeInsightRow(
          icon: Icons.nightlight_round,
          color: accentPurple,
          title: _getSleepInsightTitle(sleepHours),
          subtitle: '${_sleepLabel(sleepHours)} of sleep recorded',
        ),
      HourlyHeartInsightCard(key: _hourlyHeartKey, isActive: widget.isActive),
      if (sleepHours == null && !hasHeartRate)
        const HomeInsightRow(
          icon: Icons.info_outline_rounded,
          color: textGrey,
          title: 'No insights yet',
          subtitle:
              'Connect Apple Health or complete a scan to see your daily insights.',
        ),
    ];
    return _card(
      child: Column(
        children: [
          schedule,
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) divider,
            rows[i],
          ],
        ],
      ),
    );
  }

  /// Today's timed Google and Outlook events, or null when no calendar is
  /// connected.
  Future<List<_ScheduleEvent>?> _getScheduleEventsFuture(DateTime todayStart) {
    if (_scheduleEventsFuture != null &&
        DateUtils.isSameDay(_scheduleEventsDate, todayStart)) {
      return _scheduleEventsFuture!;
    }

    _scheduleEventsDate = todayStart;
    _scheduleEventsFuture = _loadScheduleEvents(todayStart);
    return _scheduleEventsFuture!;
  }

  Future<List<_ScheduleEvent>?> _loadScheduleEvents(DateTime todayStart) async {
    final todayEnd = todayStart.add(const Duration(days: 1));
    final events = <_ScheduleEvent>[];

    bool googleSignedIn = false;
    bool outlookSignedIn = false;

    try {
      googleSignedIn = await CalendarService.isSignedIn().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (_) {
      googleSignedIn = false;
    }

    try {
      outlookSignedIn = await OutlookCalendarService.isSignedIn().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
    } catch (_) {
      outlookSignedIn = false;
    }

    if (!googleSignedIn && !outlookSignedIn) return null;

    if (googleSignedIn) {
      try {
        final googleEvents = await _getReachableWindowEventsFuture(todayStart);
        events.addAll(
          googleEvents.where((event) => event.status != 'cancelled').map((
            event,
          ) {
            final start = event.start?.dateTime?.toLocal();
            final end = event.end?.dateTime?.toLocal();
            if (start == null || end == null) return null;
            return _ScheduleEvent(
              title: event.summary?.trim().isNotEmpty == true
                  ? event.summary!.trim()
                  : 'Calendar event',
              start: start,
              end: end,
              key: 'google:${event.id}',
            );
          }).whereType<_ScheduleEvent>(),
        );
      } catch (e) {
        debugPrint('Schedule insight Google load failed: $e');
      }
    }

    if (outlookSignedIn) {
      try {
        final outlookEvents =
            await OutlookCalendarService.getWeekEvents(todayStart).timeout(
              const Duration(seconds: 8),
              onTimeout: () => <OutlookEvent>[],
            );
        events.addAll(
          outlookEvents.map((event) {
            return _ScheduleEvent(
              title: event.subject.trim().isNotEmpty
                  ? event.subject.trim()
                  : 'Calendar event',
              start: event.start.toLocal(),
              end: event.end.toLocal(),
            );
          }),
        );
      } catch (e) {
        debugPrint('Schedule insight Outlook load failed: $e');
      }
    }

    final todayEvents = events.where((event) {
      return event.start.isBefore(todayEnd) && event.end.isAfter(todayStart);
    }).toList()..sort((a, b) => a.start.compareTo(b.start));

    return todayEvents;
  }

  _ScheduleInsight _buildScheduleInsight(
    List<_ScheduleEvent> events,
    DateTime todayStart,
  ) {
    if (events.isEmpty) {
      return const _ScheduleInsight(
        icon: Icons.event_available_rounded,
        color: greenColor,
        title: 'Light schedule today',
        subtitle:
            'No calendar events found today. This is a good window for focus, recovery, or goal progress.',
      );
    }

    final workStart = DateTime(
      todayStart.year,
      todayStart.month,
      todayStart.day,
      9,
    );
    final workEnd = DateTime(
      todayStart.year,
      todayStart.month,
      todayStart.day,
      17,
    );

    DateTime clampStart(DateTime value) =>
        value.isBefore(workStart) ? workStart : value;
    DateTime clampEnd(DateTime value) =>
        value.isAfter(workEnd) ? workEnd : value;

    int scheduledMinutes = 0;
    int afternoonEvents = 0;
    _ScheduleEvent? longestEvent;

    for (final event in events) {
      final clippedStart = clampStart(event.start);
      final clippedEnd = clampEnd(event.end);
      if (clippedEnd.isAfter(clippedStart)) {
        scheduledMinutes += clippedEnd.difference(clippedStart).inMinutes;
      }
      if (event.start.hour >= 12) afternoonEvents++;
      if (longestEvent == null || event.duration > longestEvent.duration) {
        longestEvent = event;
      }
    }

    var tightTransitions = 0;
    for (var i = 1; i < events.length; i++) {
      final gap = events[i].start.difference(events[i - 1].end).inMinutes;
      if (gap >= 0 && gap <= 15) tightTransitions++;
    }

    final scheduledLabel = _durationLabel(Duration(minutes: scheduledMinutes));
    final eventWord = events.length == 1 ? 'event' : 'events';

    if (tightTransitions >= 2) {
      return _ScheduleInsight(
        icon: Icons.event_busy_rounded,
        color: orangeColor,
        title: 'Back-to-back schedule block',
        subtitle:
            'You have ${events.length} $eventWord with tight transitions. Protect a short reset before the busiest block.',
      );
    }

    if (scheduledMinutes >= 240 || events.length >= 5) {
      return _ScheduleInsight(
        icon: Icons.calendar_month_rounded,
        color: orangeColor,
        title: 'Heavy day ahead',
        subtitle:
            '$scheduledLabel is scheduled between 9 AM and 5 PM. Keep one recovery window open if you can.',
      );
    }

    if (afternoonEvents >= 3) {
      return _ScheduleInsight(
        icon: Icons.wb_sunny_rounded,
        color: const Color(0xFFFF9500),
        title: 'Busy afternoon ahead',
        subtitle:
            'Most of today’s calendar load is later in the day. Use the morning for focused or important work.',
      );
    }

    final longest = longestEvent;
    if (longest != null && longest.duration.inMinutes >= 90) {
      return _ScheduleInsight(
        icon: Icons.timelapse_rounded,
        color: const Color(0xFF007AFF),
        title: 'Long calendar block today',
        subtitle:
            '${longest.title} runs ${_durationLabel(longest.duration)}. Plan a quick decompression break afterward.',
      );
    }

    return _ScheduleInsight(
      icon: Icons.event_note_rounded,
      color: const Color(0xFF007AFF),
      title: 'Balanced schedule today',
      subtitle:
          'You have ${events.length} $eventWord today. Your calendar load looks manageable if you keep small buffers between tasks.',
    );
  }

  String _durationLabel(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainder = minutes % 60;
      return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
    }
    return '${minutes}m';
  }

  Future<void> _showReachableEventSummary(gcal.Event event) async {
    final start = event.start?.dateTime?.toLocal() ?? event.start?.date;
    final end = event.end?.dateTime?.toLocal() ?? event.end?.date;
    if (start == null || end == null) return;
    final action = await showCalendarEventSummarySheet(
      context,
      event: CalendarEventSummaryData(
        title: event.summary ?? 'Untitled event',
        start: start,
        end: end,
        isAllDay: event.start?.dateTime == null,
        isRecurring:
            event.recurringEventId != null ||
            event.recurrence?.isNotEmpty == true,
        color: const Color(0xFF4285F4),
        calendarName: 'Google Calendar',
        canEdit: true,
      ),
    );
    if (!mounted || action == null) return;
    if (action == CalendarEventSummaryAction.edit) {
      await _editReachableEvent(event);
      return;
    }
    final scope = await confirmEventDelete(
      context,
      title: event.summary ?? 'Untitled event',
      repeating: event.recurringEventId != null,
    );
    if (scope == null || !mounted) return;
    try {
      await CalendarService.deleteEvent(event, scope: scope);
      if (!mounted) return;
      _refreshHomeCalendarCards();
      _showHomeCalendarMessage('Event deleted.');
    } catch (error) {
      if (mounted) _showHomeCalendarMessage('Could not delete event: $error');
    }
  }

  Future<void> _editReachableEvent(gcal.Event event) async {
    final originalStart = event.start?.dateTime?.toLocal();
    final originalEnd = event.end?.dateTime?.toLocal();
    if (originalStart == null || originalEnd == null) {
      _showHomeCalendarMessage('All-day events cannot be edited here yet.');
      return;
    }

    var title = event.summary ?? '';
    var date = DateUtils.dateOnly(originalStart);
    var startTime = TimeOfDay.fromDateTime(originalStart);
    var endTime = TimeOfDay.fromDateTime(originalEnd);
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Edit event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: title,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Event title',
                    prefixIcon: Icon(Icons.event_rounded),
                  ),
                  onChanged: (value) => title = value,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_rounded),
                  title: const Text('Date'),
                  subtitle: Text(_formatCalendarDate(date)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_rounded),
                  title: const Text('Start time'),
                  trailing: Text(startTime.format(context)),
                  onTap: () async {
                    final picked = await showVivordoTimePicker(
                      context: context,
                      initialTime: startTime,
                      title: 'Start Time',
                    );
                    if (picked != null) {
                      setDialogState(() => startTime = picked);
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('End time'),
                  trailing: Text(endTime.format(context)),
                  onTap: () async {
                    final picked = await showVivordoTimePicker(
                      context: context,
                      initialTime: endTime,
                      title: 'End Time',
                    );
                    if (picked != null) setDialogState(() => endTime = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (shouldSave != true || !mounted) return;
    title = title.trim();
    if (title.isEmpty) {
      _showHomeCalendarMessage('Enter an event title.');
      return;
    }

    final start = DateTime(
      date.year,
      date.month,
      date.day,
      startTime.hour,
      startTime.minute,
    );
    var end = DateTime(
      date.year,
      date.month,
      date.day,
      endTime.hour,
      endTime.minute,
    );
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

    try {
      await CalendarService.updateEvent(
        event,
        title: title,
        start: start,
        end: end,
      );
      _refreshHomeCalendarCards();
      _showHomeCalendarMessage('Event updated.');
    } catch (error) {
      _showHomeCalendarMessage('Could not update event: $error');
    }
  }

  void _refreshHomeCalendarCards() {
    if (!mounted) return;
    setState(() {
      _reachableWindowEventsFuture = null;
      _reachableWindowEventsDate = null;
      _reachableWindowScoresFuture = null;
      _reachableWindowScoresDate = null;
      _scheduleEventsFuture = null;
      _scheduleEventsDate = null;
      _effortContextFuture = null;
      _effortContextDate = null;
      _tomorrowPlanFuture = null;
      _tomorrowPlanDate = null;
    });
  }

  void _showHomeCalendarMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _getSleepInsightTitle(double hours) {
    if (hours >= 8) return 'Excellent sleep last night';
    if (hours >= 7) return 'Good sleep last night';
    if (hours >= 6) return 'Moderate sleep last night';
    return 'Low sleep last night';
  }

  String _formatCalendarDate(DateTime dt) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  Future<void> _showMoodCheck() async {
    var sliderValue = _currentMoodScore.clamp(0, 100).toDouble();
    final navigator = Navigator.of(context);
    final localizations = MaterialLocalizations.of(context);
    final route = ModalBottomSheetRoute<double>(
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 220),
        reverseDuration: Duration(milliseconds: 120),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final colors = sheetContext.vivordoColors;
            final label = MetricsService.moodLabelForScore(sliderValue);
            final accent = _moodColorForScore(sliderValue);
            final emoji = _moodEmojiForScore(sliderValue);

            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(36),
                    topRight: Radius.circular(36),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: accentPurple.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'How are you feeling?',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Move the slider to the value that best reflects how you feel right now.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 28),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accent.withValues(alpha: 0.28),
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 54),
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: Text(
                          '${sliderValue.round()}',
                          key: ValueKey(sliderValue.round()),
                          style: TextStyle(
                            fontSize: 52,
                            height: 1,
                            fontWeight: FontWeight.w800,
                            color: accent,
                            letterSpacing: -2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SliderTheme(
                        data: SliderTheme.of(sheetContext).copyWith(
                          activeTrackColor: accent,
                          inactiveTrackColor: colors.border,
                          thumbColor: accent,
                          overlayColor: accent.withValues(alpha: 0.14),
                          trackHeight: 8,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 13,
                          ),
                        ),
                        child: Slider(
                          value: sliderValue,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          semanticFormatterCallback: (value) =>
                              '${value.round()} out of 100, ${MetricsService.moodLabelForScore(value)}',
                          onChanged: (value) {
                            setSheetState(() => sliderValue = value);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '0 · Very low',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '100 · Excellent',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: () {
                            final score = sliderValue.roundToDouble();
                            Navigator.pop(sheetContext, score);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: accentPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'Save check-in',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Your mood helps personalize your daily insights.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    final selectedScore = await navigator.push(route);
    // Navigator.pop completes the route result before the closing transition
    // has removed its inherited widgets. Wait for the route itself to finish
    // disposal before rebuilding Home or allowing Firestore to emit a mood
    // update into this subtree.
    await route.completed;
    if (!mounted || selectedScore == null) return;
    await _saveMoodCheckIn(selectedScore);
  }

  Future<void> _saveMoodCheckIn(double score) async {
    final roundedScore = score.clamp(0, 100).roundToDouble();
    final label = MetricsService.moodLabelForScore(roundedScore);

    _pendingMoodSync = null;
    _pendingMoodScoreSync = null;
    _isSavingMood = true;
    if (mounted) {
      setState(() {
        _currentMood = label;
        _currentMoodScore = roundedScore;
      });
    }

    try {
      await MetricsService.saveMoodCheckIn(label, moodScore: roundedScore);
    } catch (error) {
      debugPrint('Mood save failed: $error');
    } finally {
      _isSavingMood = false;
    }
  }

  Color _moodColorForScore(double score) {
    if (score >= 80) return const Color(0xFF22C55E);
    if (score >= 60) return const Color(0xFF34C759);
    if (score >= 40) return const Color(0xFFFF9500);
    if (score >= 20) return accentPurple;
    return const Color(0xFFEF4444);
  }

  String _moodEmojiForScore(double score) {
    if (score >= 80) return '🤩';
    if (score >= 60) return '😊';
    if (score >= 40) return '😐';
    if (score >= 20) return '😔';
    return '😫';
  }
}

class _HomeWorkoutStreakBadge extends StatefulWidget {
  const _HomeWorkoutStreakBadge();

  @override
  State<_HomeWorkoutStreakBadge> createState() =>
      _HomeWorkoutStreakBadgeState();
}

class _HomeWorkoutStreakBadgeState extends State<_HomeWorkoutStreakBadge> {
  late final Stream<List<SavedWorkout>> _workoutsStream;

  @override
  void initState() {
    super.initState();
    _workoutsStream = WorkoutService.watchAll();
  }

  @override
  Widget build(BuildContext context) =>
      VisibleStreamBuilder<List<SavedWorkout>>(
        stream: _workoutsStream,
        builder: (context, snapshot) {
          final streak = WorkoutService.calculateCurrentStreak(
            snapshot.data ?? const [],
          );
          if (streak == 0) return const SizedBox.shrink();
          return Semantics(
            label: '$streak-day workout streak',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    size: 15,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '$streak',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

/// What Home's Effort card needs besides the calendar and priorities.
class _EffortContext {
  const _EffortContext({
    this.wrapUpMinutes = kDefaultDayWrapUpMinutes,
    this.workouts = const [],
    this.pastByHour = const [],
    this.sleepNeedHours,
    this.sleepSchedule,
  });

  final int wrapUpMinutes;

  /// Your usual sleep times, for the forecast when no sleep is tracked.
  final SleepSchedule? sleepSchedule;

  /// Today's sleep need from the server's Capacity, for the energy forecast.
  final double? sleepNeedHours;
  final List<({DateTime start, DateTime end, double intensity})> workouts;
  final List<List<num>> pastByHour;
}

class _ScheduleEvent {
  const _ScheduleEvent({
    required this.title,
    required this.start,
    required this.end,
    this.key,
  });

  final String title;
  final DateTime start;
  final DateTime end;

  /// The Google key a linked priority stores as its `sourceEventKey`.
  final String? key;

  Duration get duration => end.difference(start);
}

class _ScoredReachableEvent {
  const _ScoredReachableEvent({
    required this.event,
    required this.score,
    required this.input,
  });

  final gcal.Event event;
  final CognitiveLoadScore score;
  final CalendarCognitiveEvent input;
}

class _ScheduleInsight {
  const _ScheduleInsight({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
}
