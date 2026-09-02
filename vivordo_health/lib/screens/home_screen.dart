import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'profile_screen.dart';
import 'package:vivordo_health/src/services/metrics_service.dart';
import 'package:vivordo_health/src/services/stress_score_service.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:vivordo_health/src/services/outlook_calendar_service.dart';
import 'package:vivordo_health/src/services/notification_service.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/services/circle_profile_service.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/src/utils/latest_heart_rate.dart';
import 'package:vivordo_health/src/utils/home_stress_card_logic.dart';
import 'package:vivordo_health/src/utils/heart_rate_calendar_insight.dart';
import 'package:vivordo_health/widgets/home_stress_card.dart';
import 'package:vivordo_health/widgets/vivordo_time_picker.dart';
import 'package:vivordo_health/src/services/home_widget_service.dart';
import 'package:vivordo_health/src/services/calendar_cognitive_load_service.dart';
import 'circle_screen.dart';
import 'heart_rate_detail_screen.dart';
import 'steps_detail_screen.dart';
import 'stress_detail_screen.dart';

class _CircleAvatarCluster extends StatelessWidget {
  const _CircleAvatarCluster({required this.initial, this.photoUrl});

  final String initial;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 72,
    height: 66,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 17,
          top: 0,
          child: _circle(
            text: initial,
            photoUrl: photoUrl,
            background: const Color(0xFFE4E0FF),
            foreground: const Color(0xFF6B5CE7),
          ),
        ),
        Positioned(
          left: 3,
          bottom: 0,
          child: _circle(
            icon: Icons.person_add_alt_1_rounded,
            background: const Color(0xFFDCF7EB),
            foreground: const Color(0xFF16A874),
          ),
        ),
        Positioned(
          right: 3,
          bottom: 0,
          child: _circle(
            icon: Icons.person_add_alt_1_rounded,
            background: const Color(0xFFFFE7CE),
            foreground: const Color(0xFFF28A18),
          ),
        ),
      ],
    ),
  );

  Widget _circle({
    String? text,
    String? photoUrl,
    IconData? icon,
    required Color background,
    required Color foreground,
  }) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: background,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withValues(alpha: .82), width: 2),
    ),
    alignment: Alignment.center,
    child: photoUrl?.isNotEmpty == true
        ? ClipOval(
            child: Image.network(
              photoUrl!,
              width: 42,
              height: 42,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _initialOrIcon(
                text: text,
                icon: icon,
                foreground: foreground,
              ),
            ),
          )
        : _initialOrIcon(text: text, icon: icon, foreground: foreground),
  );

  Widget _initialOrIcon({
    String? text,
    IconData? icon,
    required Color foreground,
  }) => text != null
      ? Text(
          text,
          style: TextStyle(
            color: foreground,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        )
      : Icon(icon, color: foreground, size: 17);
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
  final bool revealStress;
  final bool isActive;
  const HomeScreen({
    super.key,
    this.onScanTap,
    this.onFitnessTap,
    this.revealStress = true,
    this.isActive = true,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeWidgetSnapshot {
  const _HomeWidgetSnapshot({
    required this.stressScore,
    required this.wellnessScore,
    required this.steps,
    required this.activeCalories,
    required this.exerciseMinutes,
    required this.goals,
  });

  final double? stressScore;
  final double? wellnessScore;
  final int steps;
  final int activeCalories;
  final int exerciseMinutes;
  final ActivityGoals goals;

  String get signature => <Object?>[
    stressScore?.round(),
    wellnessScore?.round(),
    steps,
    activeCalories,
    exerciseMinutes,
    goals.steps,
    goals.activeCalories,
    goals.exerciseMinutes,
  ].join('|');
}

class _HomeScreenState extends State<HomeScreen> {
  String _currentMood = 'Good';
  double _currentMoodScore = 75;
  String? _pendingMoodSync;
  double? _pendingMoodScoreSync;
  bool _isSavingMood = false;
  // _messageCopied removed — smart message card replaced with calendar

  // Single stream for today's unified metrics doc
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _todayStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _latestScanStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _goalsStreamCached;
  late final Stream<CircleProfile?> _circleProfileStream;
  Future<List<gcal.Event>>? _reachableWindowEventsFuture;
  DateTime? _reachableWindowEventsDate;
  Future<List<_ScoredReachableEvent>>? _reachableWindowScoresFuture;
  DateTime? _reachableWindowScoresDate;
  Future<_ScheduleInsight?>? _scheduleInsightFuture;
  DateTime? _scheduleInsightDate;
  Future<HeartRateCalendarInsight>? _heartInsightFuture;
  DateTime? _heartInsightReadingTime;
  int? _heartInsightReadingBpm;
  ActivityGoals _activityGoals = const ActivityGoals();
  StreamSubscription<ActivityGoals>? _activityGoalsSubscription;
  _HomeWidgetSnapshot? _latestHomeWidgetSnapshot;
  _HomeWidgetSnapshot? _queuedHomeWidgetSnapshot;
  String? _lastPublishedHomeWidgetSignature;
  String? _homeWidgetPublishInProgressSignature;
  bool _homeWidgetPublishScheduled = false;
  bool _homeWidgetPublishInProgress = false;

  static const Color accentPurple = Color(0xFF7B6EF6);
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color textGrey = Color(0xFF8E8E93);
  static const Color greenColor = Color(0xFF34C759);
  static const Color orangeColor = Color(0xFFFF9500);

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
    final today = _todayPeriod();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _todayStream = uid != null
        ? FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('metrics_daily')
              .doc(today)
              .snapshots()
        : const Stream.empty();
    _latestScanStream = uid != null
        ? FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('metrics_daily')
              .snapshots()
        : const Stream.empty();
    _circleProfileStream = CircleProfileService.watchCurrentProfile();
    _goalsStreamCached = _goalsStream();
    _activityGoalsSubscription = ActivityGoalsService.watch().listen(
      (goals) {
        _activityGoals = goals;
        final snapshot = _latestHomeWidgetSnapshot;
        if (snapshot == null) return;
        _queueHomeWidgetPublish(
          _HomeWidgetSnapshot(
            stressScore: snapshot.stressScore,
            wellnessScore: snapshot.wellnessScore,
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
  void dispose() {
    _activityGoalsSubscription?.cancel();
    super.dispose();
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
          wellnessScore: snapshot.wellnessScore,
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

  LatestHeartRateReading? _latestHeartRateFrom(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sortedDocs = [...docs]..sort((a, b) => b.id.compareTo(a.id));
    return latestHeartRateReadingFromMetricDays(
      sortedDocs.map((doc) => doc.data()),
    );
  }

  /// Returns the personalized value a new stress day should open at while the
  /// first BaaS reading is still being computed.
  ///
  /// The accumulating stress scorer persists an `anchor` with every successful
  /// response. That anchor is the user's learned reset point for the start of a
  /// local day, so it is a better midnight fallback than yesterday's final
  /// score. Older documents predate anchors and fall back to their last live or
  /// daily value instead.
  double? _latestStressAnchorFrom(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sortedDocs = [...docs]..sort((a, b) => b.id.compareTo(a.id));

    for (final doc in sortedDocs) {
      final stress = doc.data()['stress'] as Map?;
      if (stress == null) continue;

      final anchor = stress['anchor'];
      if (anchor is num) return anchor.toDouble();

      final current = stress['current'];
      if (current is num) return current.toDouble();

      final average = stress['avg'];
      if (average is num) return average.toDouble();
    }
    return null;
  }

  double? _sevenDayStressAverage(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final today = DateUtils.dateOnly(DateTime.now());
    final oldest = today.subtract(const Duration(days: 7));
    final values = <double>[];
    for (final doc in docs) {
      final date = DateTime.tryParse(doc.id);
      if (date == null || date.isBefore(oldest) || !date.isBefore(today)) {
        continue;
      }
      final stress = doc.data()['stress'] as Map?;
      final value =
          (stress?['avg'] as num?)?.toDouble() ??
          (stress?['current'] as num?)?.toDouble();
      if (value != null) values.add(value);
    }
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
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

  Stream<QuerySnapshot<Map<String, dynamic>>> _goalsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('goals')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .snapshots();
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
        sleepVal: '--',
        sleepLoading: false,
        stepsVal: '--',
        steps: 0,
        activeCalories: 0,
        exerciseMinutes: 0,
        stepsLoading: false,
        hrVal: '--',
        latestHeartRate: null,
        hrLoading: false,
        moodVal: '--',
        moodLoading: false,
        wellnessVal: '--',
        goalTitle: 'No goal set',
        goalProgress: 0,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _todayStream,
      builder: (context, todaySnap) {
        final bool loading =
            !todaySnap.hasData &&
            todaySnap.connectionState == ConnectionState.waiting;
        final data = todaySnap.data?.data();

        final stressMap = data?['stress'] as Map?;
        final hrvMap = data?['hrv'] as Map?;
        final sleepMap = data?['sleep'] as Map?;
        final stepsMap = data?['steps'] as Map?;
        final activeCaloriesMap = data?['active_calories'] as Map?;
        final exerciseTimeMap = data?['exercise_time'] as Map?;
        final moodMap = data?['mood'] as Map?;
        final wellnessMap = data?['wellness'] as Map?;

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

        final sleepVal = sleepMap != null
            ? '${(sleepMap['avg'] as num?)?.toStringAsFixed(1) ?? '--'}h'
            : '--';

        final steps = (stepsMap?['sum'] as num?)?.toInt();
        final activeCalories =
            (activeCaloriesMap?['sum'] as num?)?.round() ?? 0;
        final exerciseMinutes = (exerciseTimeMap?['sum'] as num?)?.round() ?? 0;
        final stepsVal = steps != null
            ? (steps >= 1000
                  ? '${(steps / 1000).toStringAsFixed(1)}k'
                  : steps.toString())
            : '--';

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
        final moodVal = savedMoodScore?.round().toString() ?? '--';

        final wellnessVal = wellnessMap != null
            ? '${(wellnessMap['avg'] as num?)?.round() ?? '--'}'
            : '--';

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _latestScanStream,
          builder: (context, scanSnap) {
            final metricDocs = scanSnap.data?.docs ?? [];
            final latestHeartRate = _latestHeartRateFrom(metricDocs);
            final latestHeartRateBpm = latestHeartRate?.bpm;
            final hrVal = latestHeartRateBpm == null
                ? '--'
                : '$latestHeartRateBpm bpm';
            final displayedStressScore =
                stressScore ?? _latestStressAnchorFrom(metricDocs);
            final sevenDayStressAverage = _sevenDayStressAverage(metricDocs);
            final stressDrivers = homeStressDrivers(stressMap?['top_drivers']);
            final stressStillLoading =
                loading ||
                (stressScore == null &&
                    scanSnap.connectionState == ConnectionState.waiting &&
                    !scanSnap.hasData);

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _goalsStreamCached,
              builder: (context, goalSnap) {
                final goalDocs = goalSnap.data?.docs ?? [];
                final goalData = goalDocs.isNotEmpty
                    ? goalDocs.first.data()
                    : null;
                final goalTitle =
                    goalData?['title'] as String? ?? 'No active goal';
                final rawPercent =
                    (goalData?['progress']?['completionPercent'] as num?)
                        ?.toDouble() ??
                    0;
                final goalProgress = (rawPercent / 100).clamp(0.0, 1.0);

                if (data != null) {
                  _queueHomeWidgetPublish(
                    _HomeWidgetSnapshot(
                      stressScore: displayedStressScore,
                      wellnessScore: (wellnessMap?['avg'] as num?)?.toDouble(),
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
                    sleepVal: sleepVal,
                    sleepLoading: loading,
                    stepsVal: stepsVal,
                    steps: steps ?? 0,
                    activeCalories: activeCalories,
                    exerciseMinutes: exerciseMinutes,
                    stepsLoading: loading,
                    hrVal: hrVal,
                    latestHeartRate: latestHeartRate,
                    hrLoading:
                        scanSnap.connectionState == ConnectionState.waiting &&
                        !scanSnap.hasData,
                    moodVal: moodVal,
                    moodLoading: loading,
                    wellnessVal: wellnessVal,
                    goalTitle: goalTitle,
                    goalProgress: goalProgress,
                  ),
                );
              },
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
      final hasTightTransition = timedEvents.any((other) {
        if (identical(other, event) ||
            other.start?.dateTime == null ||
            other.end?.dateTime == null) {
          return false;
        }
        final otherStart = other.start!.dateTime!.toLocal();
        final otherEnd = other.end!.dateTime!.toLocal();
        final gapBefore = start.difference(otherEnd).inMinutes;
        final gapAfter = otherStart.difference(end).inMinutes;
        return (gapBefore >= 0 && gapBefore <= 15) ||
            (gapAfter >= 0 && gapAfter <= 15);
      });
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
          hasTightTransition: hasTightTransition,
        ),
      );
    }

    final scores = await CalendarCognitiveLoadService.scoreEvents(inputs);
    return List.generate(
      timedEvents.length,
      (index) => _ScoredReachableEvent(
        event: timedEvents[index],
        score: scores[index],
      ),
    );
  }

  String _reachableEventKey(gcal.Event event, int index) =>
      'google:${event.id ?? event.iCalUID ?? index}';

  Widget _buildScaffold({
    required double? stressScore,
    required DateTime? stressUpdatedAt,
    required double? sevenDayStressAverage,
    required List<HomeStressDriver> stressDrivers,
    bool stressUpdating = false,
    required bool stressLoading,
    required String sleepVal,
    required bool sleepLoading,
    required String stepsVal,
    required int steps,
    required int activeCalories,
    required int exerciseMinutes,
    required bool stepsLoading,
    required String hrVal,
    required LatestHeartRateReading? latestHeartRate,
    required bool hrLoading,
    required String moodVal,
    required bool moodLoading,
    required String wellnessVal,
    required String goalTitle,
    required double goalProgress,
  }) {
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StressDetailScreen()),
                ),
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
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      'Sleep',
                      sleepVal,
                      Icons.bedtime_rounded,
                      accentPurple,
                      loading: sleepLoading,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      'Steps',
                      stepsVal,
                      Icons.directions_walk_rounded,
                      greenColor,
                      loading: stepsLoading,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StepsDetailScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      'Heart Rate',
                      hrVal,
                      Icons.favorite_rounded,
                      const Color(0xFFFF3B30),
                      showConnectHint: false,
                      loading: hrLoading,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const HeartRateDetailScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricTile(
                      'Mood',
                      moodVal,
                      Icons.mood_rounded,
                      const Color(0xFFF97316),
                      loading: moodLoading,
                      onTap: _showMoodCheck,
                      emptyAction: _showMoodCheck,
                      emptyActionLabel: 'Check in →',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildFitnessSummaryCard(
                steps: steps,
                activeCalories: activeCalories,
                exerciseMinutes: exerciseMinutes,
              ),
              const SizedBox(height: 14),
              _buildCircleCard(),
              const SizedBox(height: 28),
              _buildSectionTitle("TODAY'S INSIGHTS"),
              const SizedBox(height: 12),
              _buildScheduleInsightCard(),
              if (sleepVal != '--')
                _buildInsightCard(
                  icon: Icons.nightlight_round,
                  iconColor: accentPurple,
                  iconBg: const Color(0x1F7B6EF6),
                  title: _getSleepInsightTitle(sleepVal),
                  subtitle: _getSleepInsightSubtitle(sleepVal, hrVal),
                ),
              if (sleepVal != '--') const SizedBox(height: 10),
              if (latestHeartRate != null)
                _buildHeartRateInsightCard(latestHeartRate),
              if (sleepVal == '--' && hrVal == '--')
                _buildInsightCard(
                  icon: Icons.info_outline_rounded,
                  iconColor: textGrey,
                  iconBg: const Color(0x1F8E8E93),
                  title: 'No insights yet',
                  subtitle:
                      'Connect Apple Health or complete a scan to see your daily insights.',
                ),
              const SizedBox(height: 28),
              _buildReachableWindowsTitle(),
              const SizedBox(height: 12),
              _buildReachableWindows(),
              const SizedBox(height: 160),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_getGreeting()},',
                style: const TextStyle(
                  color: textGrey,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _getFirstName(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.vivordoColors.textPrimary,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('👋', style: TextStyle(fontSize: 26)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<CircleProfile?>(
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

  Widget _buildFitnessSummaryCard({
    required int steps,
    required int activeCalories,
    required int exerciseMinutes,
  }) {
    return StreamBuilder<ActivityGoals>(
      stream: ActivityGoalsService.watch(),
      initialData: const ActivityGoals(),
      builder: (context, snapshot) {
        final goals = snapshot.data ?? const ActivityGoals();
        final stepsProgress = (steps / goals.steps).clamp(0.0, 1.0);
        final caloriesProgress = (activeCalories / goals.activeCalories).clamp(
          0.0,
          1.0,
        );
        final exerciseProgress = (exerciseMinutes / goals.exerciseMinutes)
            .clamp(0.0, 1.0);
        final overallPercent =
            ((stepsProgress + caloriesProgress + exerciseProgress) / 3 * 100)
                .round();

        return InkWell(
          onTap: widget.onFitnessTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.vivordoColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 70,
                        height: 70,
                        child: CircularProgressIndicator(
                          value: stepsProgress,
                          strokeWidth: 7,
                          color: accentPurple,
                          backgroundColor: Color(0xFFECECF3),
                        ),
                      ),
                      SizedBox(
                        width: 50,
                        height: 50,
                        child: CircularProgressIndicator(
                          value: caloriesProgress,
                          strokeWidth: 7,
                          color: Color(0xFFFB923C),
                          backgroundColor: Color(0xFFECECF3),
                        ),
                      ),
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                          value: exerciseProgress,
                          strokeWidth: 6,
                          color: Color(0xFF34D399),
                          backgroundColor: Color(0xFFECECF3),
                        ),
                      ),
                      Text(
                        '$overallPercent%',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: context.vivordoColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today’s Activity',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: context.vivordoColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Steps $steps/${goals.steps}',
                        style: const TextStyle(fontSize: 10, color: textGrey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Active calories $activeCalories/${goals.activeCalories}',
                        style: const TextStyle(fontSize: 10, color: textGrey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Exercise $exerciseMinutes/${goals.exerciseMinutes} minutes',
                        style: const TextStyle(fontSize: 10, color: textGrey),
                      ),
                    ],
                  ),
                ),
                const _HomeWorkoutStreakBadge(),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: textGrey),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricTile(
    String label,
    String value,
    IconData icon,
    Color color, {
    bool showConnectHint = true,
    bool loading = false,
    VoidCallback? onTap,
    VoidCallback? emptyAction,
    String emptyActionLabel = 'Connect Health →',
  }) {
    final bool isEmpty = value == '--';
    return Semantics(
      button: onTap != null,
      label: onTap == null ? null : '$label, $value. Tap to view details.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: context.vivordoColors.card,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              child: Column(
                children: [
                  Icon(
                    icon,
                    color: isEmpty ? const Color(0xFFC7C7CC) : color,
                    size: 20,
                  ),
                  const SizedBox(height: 6),
                  loading
                      ? Container(
                          width: 36,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E5EA),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )
                      : Text(
                          value,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isEmpty
                                ? context.vivordoColors.textSecondary
                                : context.vivordoColors.textPrimary,
                          ),
                        ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: context.vivordoColors.textPrimary,
                    ),
                  ),
                  if (isEmpty && showConnectHint) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap:
                          emptyAction ??
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                      child: Text(
                        emptyActionLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: context.vivordoColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: textGrey,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildReachableWindowsTitle() => Row(
    children: [
      Expanded(child: _buildSectionTitle('TODAY\'S REACHABLE WINDOWS')),
      Semantics(
        button: true,
        label: 'How reachable windows work',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: _showReachableWindowsInfo,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: textGrey,
              ),
            ),
          ),
        ),
      ),
    ],
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
              'How reachable windows work',
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
          'Vivordo scores your calendar events based on how mentally demanding they may be, helping highlight periods that could require more focus and open times when your schedule is lighter.\n\nUse these windows to plan demanding tasks, take a break, or make the most of your available time. Scores are estimates based on your calendar details.',
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
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    final initial = displayName?.isNotEmpty == true
        ? displayName![0].toUpperCase()
        : 'Y';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const CircleScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                StreamBuilder<CircleProfile?>(
                  stream: _circleProfileStream,
                  builder: (context, snapshot) {
                    final profile = snapshot.data;
                    final profileInitial = profile?.username.isNotEmpty == true
                        ? profile!.username[0].toUpperCase()
                        : initial;
                    return _CircleAvatarCluster(
                      initial: profileInitial,
                      photoUrl: profile?.photoUrl,
                    );
                  },
                ),
                const SizedBox(width: 14),
                StreamBuilder<CircleDailyEngagement>(
                  stream: CircleProfileService.watchTodayEngagement(),
                  initialData: const CircleDailyEngagement(
                    likes: 0,
                    comments: 0,
                  ),
                  builder: (context, engagementSnapshot) {
                    final engagement = engagementSnapshot.data!;
                    return Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Circle',
                                  style: TextStyle(
                                    color: context.vivordoColors.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                StreamBuilder<List<CircleProfile>>(
                                  stream: CircleProfileService.watchFriends(),
                                  builder: (context, snapshot) {
                                    final friendCount =
                                        snapshot.data?.length ?? 0;
                                    final comments = engagement.comments;
                                    return Text(
                                      '$friendCount ${friendCount == 1 ? 'friend' : 'friends'} · '
                                      '$comments ${comments == 1 ? 'update' : 'updates'}',
                                      style: const TextStyle(
                                        color: textGrey,
                                        fontSize: 13,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 3),
                                const Text(
                                  'No active challenges',
                                  style: TextStyle(
                                    color: textGrey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: accentPurple.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.favorite_border_rounded,
                                  color: accentPurple,
                                  size: 17,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${engagement.likes} new',
                                  style: const TextStyle(
                                    color: accentPurple,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: textGrey,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInsightCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 15,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleInsightCard() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    return FutureBuilder<_ScheduleInsight?>(
      future: _getScheduleInsightFuture(todayStart),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildInsightCard(
              icon: Icons.calendar_today_rounded,
              iconColor: const Color(0xFF007AFF),
              iconBg: const Color(0x1F007AFF),
              title: 'Reviewing your schedule',
              subtitle:
                  'Checking today’s calendar load for useful timing insights.',
            ),
          );
        }

        final insight = snapshot.data;
        if (insight == null) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildInsightCard(
            icon: insight.icon,
            iconColor: insight.color,
            iconBg: insight.color.withValues(alpha: 0.12),
            title: insight.title,
            subtitle: insight.subtitle,
          ),
        );
      },
    );
  }

  Future<_ScheduleInsight?> _getScheduleInsightFuture(DateTime todayStart) {
    if (_scheduleInsightFuture != null &&
        _scheduleInsightDate != null &&
        _scheduleInsightDate!.year == todayStart.year &&
        _scheduleInsightDate!.month == todayStart.month &&
        _scheduleInsightDate!.day == todayStart.day) {
      return _scheduleInsightFuture!;
    }

    _scheduleInsightDate = todayStart;
    _scheduleInsightFuture = _loadScheduleInsight(todayStart);
    return _scheduleInsightFuture!;
  }

  Future<_ScheduleInsight?> _loadScheduleInsight(DateTime todayStart) async {
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

    return _buildScheduleInsight(todayEvents, todayStart);
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

  Future<void> _createReachableEvent(DateTime start, DateTime end) async {
    final draft = await showDialog<_CalendarEventDraft>(
      context: context,
      builder: (_) =>
          _CreateCalendarEventDialog(initialStart: start, initialEnd: end),
    );
    if (draft == null || !mounted) return;
    final eventStart = DateTime(
      draft.date.year,
      draft.date.month,
      draft.date.day,
      draft.startTime.hour,
      draft.startTime.minute,
    );
    var eventEnd = DateTime(
      draft.date.year,
      draft.date.month,
      draft.date.day,
      draft.endTime.hour,
      draft.endTime.minute,
    );
    if (!eventEnd.isAfter(eventStart)) {
      eventEnd = eventEnd.add(const Duration(days: 1));
    }
    try {
      await CalendarService.createEvent(
        title: draft.title,
        start: eventStart,
        end: eventEnd,
        recurrence: draft.recurrence,
      );
      _refreshHomeCalendarCards();
      _showHomeCalendarMessage('Event created.');
    } catch (error) {
      _showHomeCalendarMessage('Could not create event: $error');
    }
  }

  void _refreshHomeCalendarCards() {
    if (!mounted) return;
    setState(() {
      _reachableWindowEventsFuture = null;
      _reachableWindowEventsDate = null;
      _reachableWindowScoresFuture = null;
      _reachableWindowScoresDate = null;
      _scheduleInsightFuture = null;
      _scheduleInsightDate = null;
    });
  }

  void _showHomeCalendarMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildReachableWindows() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    return FutureBuilder<List<_ScoredReachableEvent>>(
      future: _getReachableWindowScoresFuture(todayStart),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.vivordoColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.vivordoColors.border),
            ),
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
                    'Analyzing your calendar for cognitive load windows…',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.vivordoColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final scoredEvents =
            (snapshot.data ?? const <_ScoredReachableEvent>[]).where((item) {
              final event = item.event;
              final start = event.start?.dateTime?.toLocal();
              return start != null &&
                  start.year == now.year &&
                  start.month == now.month &&
                  start.day == now.day;
            }).toList()..sort((a, b) {
              final aStart = a.event.start?.dateTime?.toLocal() ?? todayStart;
              final bStart = b.event.start?.dateTime?.toLocal() ?? todayStart;
              return aStart.compareTo(bStart);
            });
        final events = scoredEvents.map((item) => item.event).toList();

        final workStart = DateTime(now.year, now.month, now.day, 9);
        final workEnd = DateTime(now.year, now.month, now.day, 17);

        DateTime clampStart(DateTime value) =>
            value.isBefore(workStart) ? workStart : value;
        DateTime clampEnd(DateTime value) =>
            value.isAfter(workEnd) ? workEnd : value;

        String formatTime(DateTime value) {
          final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
          final minute = value.minute.toString().padLeft(2, '0');
          final suffix = value.hour >= 12 ? 'PM' : 'AM';
          return '$hour:$minute $suffix';
        }

        String formatRange(DateTime start, DateTime end) =>
            '${formatTime(start)} - ${formatTime(end)}';

        String durationLabel(Duration duration) {
          final minutes = duration.inMinutes;
          if (minutes >= 60) {
            final hours = minutes ~/ 60;
            final remainder = minutes % 60;
            return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
          }
          return '${minutes}m';
        }

        final highLoadWindows =
            scoredEvents
                .where((item) => item.score.level == CognitiveLoadLevel.high)
                .map((item) {
                  final event = item.event;
                  final start = event.start?.dateTime?.toLocal();
                  final end = event.end?.dateTime?.toLocal();
                  if (start == null || end == null) return null;

                  final clippedStart = clampStart(start);
                  final clippedEnd = clampEnd(end);
                  if (!clippedEnd.isAfter(clippedStart)) return null;

                  return {
                    'time': formatRange(clippedStart, clippedEnd),
                    'label': event.summary?.trim().isNotEmpty == true
                        ? event.summary!.trim()
                        : 'Calendar event',
                    'duration': clippedEnd.difference(clippedStart),
                    'event': event,
                    'score': item.score.score,
                  };
                })
                .whereType<Map<String, dynamic>>()
                .toList()
              ..sort(
                (a, b) => (b['score'] as int).compareTo(a['score'] as int),
              );

        final lowLoadWindows = <Map<String, dynamic>>[];
        var cursor = workStart;

        for (final event in events) {
          final start = event.start?.dateTime?.toLocal();
          final end = event.end?.dateTime?.toLocal();
          if (start == null || end == null) continue;

          final clippedStart = clampStart(start);
          final clippedEnd = clampEnd(end);

          if (clippedStart.isAfter(cursor)) {
            final gap = clippedStart.difference(cursor);
            if (gap.inMinutes >= 30) {
              lowLoadWindows.add({
                'time': formatRange(cursor, clippedStart),
                'label': '${durationLabel(gap)} open',
                'duration': gap,
                'start': cursor,
                'end': clippedStart,
              });
            }
          }

          if (clippedEnd.isAfter(cursor)) {
            cursor = clippedEnd;
          }
        }

        if (cursor.isBefore(workEnd)) {
          final gap = workEnd.difference(cursor);
          if (gap.inMinutes >= 30) {
            lowLoadWindows.add({
              'time': formatRange(cursor, workEnd),
              'label': '${durationLabel(gap)} open',
              'duration': gap,
              'start': cursor,
              'end': workEnd,
            });
          }
        }

        highLoadWindows.sort((a, b) {
          final scoreComparison = (b['score'] as int).compareTo(
            a['score'] as int,
          );
          if (scoreComparison != 0) return scoreComparison;
          return (b['duration'] as Duration).compareTo(
            a['duration'] as Duration,
          );
        });
        lowLoadWindows.sort(
          (a, b) =>
              (b['duration'] as Duration).compareTo(a['duration'] as Duration),
        );

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.vivordoColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.vivordoColors.border),
            boxShadow: [
              BoxShadow(
                color: context.vivordoColors.shadow,
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCognitiveLoadSection(
                title: 'Here are your times of high cognitive load',
                icon: Icons.psychology_alt_rounded,
                color: orangeColor,
                emptyText: 'No high cognitive-load events found today.',
                windows: highLoadWindows.take(2).toList(),
              ),
              const SizedBox(height: 18),
              _buildCognitiveLoadSection(
                title: 'Here are your times with the lowest cognitive load',
                icon: Icons.self_improvement_rounded,
                color: greenColor,
                emptyText: 'No open 30+ minute windows found today.',
                windows: lowLoadWindows.take(2).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCognitiveLoadSection({
    required String title,
    required IconData icon,
    required Color color,
    required String emptyText,
    required List<Map<String, dynamic>> windows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.vivordoColors.textPrimary,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (windows.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.vivordoColors.cardMuted,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              emptyText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.vivordoColors.textSecondary,
              ),
            ),
          )
        else
          ...windows.map((window) {
            final event = window['event'] as gcal.Event?;
            final openStart = window['start'] as DateTime?;
            final openEnd = window['end'] as DateTime?;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: context.vivordoColors.cardMuted,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: event == null
                      ? openStart == null || openEnd == null
                            ? null
                            : () => _createReachableEvent(openStart, openEnd)
                      : () => _editReachableEvent(event),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                window['time'] as String,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: context.vivordoColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                window['label'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: context.vivordoColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (event != null ||
                            (openStart != null && openEnd != null))
                          Icon(
                            Icons.chevron_right_rounded,
                            color: color,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  String _getSleepInsightTitle(String sleepVal) {
    final hours = double.tryParse(sleepVal.replaceAll('h', '')) ?? 0;
    if (hours >= 8) return 'Excellent sleep last night';
    if (hours >= 7) return 'Good sleep last night';
    if (hours >= 6) return 'Moderate sleep last night';
    return 'Low sleep last night';
  }

  String _getSleepInsightSubtitle(String sleepVal, String hrVal) {
    return '$sleepVal of sleep recorded';
  }

  Widget _buildHeartRateInsightCard(LatestHeartRateReading reading) {
    return FutureBuilder<HeartRateCalendarInsight>(
      future: _getHeartRateInsightFuture(reading),
      builder: (context, snapshot) {
        final insight =
            snapshot.data ??
            buildHeartRateCalendarInsight(
              bpm: reading.bpm,
              timestamp: reading.timestamp,
            );
        return _buildInsightCard(
          icon: Icons.favorite_rounded,
          iconColor: const Color(0xFFFF3B30),
          iconBg: const Color(0x1FFF3B30),
          title: insight.title,
          subtitle: insight.subtitle,
        );
      },
    );
  }

  Future<HeartRateCalendarInsight> _getHeartRateInsightFuture(
    LatestHeartRateReading reading,
  ) {
    if (_heartInsightFuture != null &&
        _heartInsightReadingTime == reading.timestamp &&
        _heartInsightReadingBpm == reading.bpm) {
      return _heartInsightFuture!;
    }
    _heartInsightReadingTime = reading.timestamp;
    _heartInsightReadingBpm = reading.bpm;
    _heartInsightFuture = _loadHeartRateInsight(reading);
    return _heartInsightFuture!;
  }

  Future<HeartRateCalendarInsight> _loadHeartRateInsight(
    LatestHeartRateReading reading,
  ) async {
    final timestamp = reading.timestamp;
    if (timestamp == null) {
      return buildHeartRateCalendarInsight(bpm: reading.bpm, timestamp: null);
    }

    final events = <HeartRateCalendarEvent>[];
    try {
      if (await CalendarService.isSignedIn()) {
        final googleEvents = await CalendarService.getWeekEvents(
          timestamp.toLocal(),
        ).timeout(const Duration(seconds: 8), onTimeout: () => <gcal.Event>[]);
        for (final event in googleEvents) {
          if (event.status == 'cancelled') continue;
          final start = event.start?.dateTime?.toLocal();
          final end = event.end?.dateTime?.toLocal();
          if (start == null || end == null) continue;
          events.add(
            HeartRateCalendarEvent(
              title: event.summary?.trim().isNotEmpty == true
                  ? event.summary!.trim()
                  : 'Calendar event',
              start: start,
              end: end,
            ),
          );
        }
      }
    } catch (error) {
      debugPrint('Heart insight Google Calendar match failed: $error');
    }

    try {
      if (await OutlookCalendarService.isSignedIn()) {
        final outlookEvents =
            await OutlookCalendarService.getWeekEvents(
              timestamp.toLocal(),
            ).timeout(
              const Duration(seconds: 8),
              onTimeout: () => <OutlookEvent>[],
            );
        for (final event in outlookEvents) {
          events.add(
            HeartRateCalendarEvent(
              title: event.subject.trim().isNotEmpty
                  ? event.subject.trim()
                  : 'Calendar event',
              start: event.start.toLocal(),
              end: event.end.toLocal(),
            ),
          );
        }
      }
    } catch (error) {
      debugPrint('Heart insight Outlook Calendar match failed: $error');
    }

    return buildHeartRateCalendarInsight(
      bpm: reading.bpm,
      timestamp: timestamp,
      events: events,
    );
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

  String _formatHour(int hour) {
    if (hour == 12) return '12 PM';
    if (hour > 12) return '${hour - 12} PM';
    return '$hour AM';
  }

  List<Map<String, dynamic>> _getTodayEvents(DateTime now) {
    // Seed events based on day of week so they feel consistent
    final day = now.weekday;
    final events = <Map<String, dynamic>>[];

    // Monday
    if (day == 1) {
      events.addAll([
        {
          'hour': 9,
          'title': 'Team Standup',
          'subtitle': '15 min · Google Meet',
          'color': accentPurple,
          'icon': Icons.groups_rounded,
        },
        {
          'hour': 11,
          'title': 'Product Review',
          'subtitle': '1 hr · Conference Room A',
          'color': const Color(0xFF007AFF),
          'icon': Icons.slideshow_rounded,
        },
        {
          'hour': 13,
          'title': 'Lunch with Sarah',
          'subtitle': 'The Kitchen, Floor 2',
          'color': greenColor,
          'icon': Icons.restaurant_rounded,
        },
        {
          'hour': 15,
          'title': 'Sprint Planning',
          'subtitle': '2 hrs · Zoom',
          'color': const Color(0xFFFF9500),
          'icon': Icons.task_rounded,
        },
      ]);
    }
    // Tuesday
    else if (day == 2) {
      events.addAll([
        {
          'hour': 9,
          'title': '1:1 with Manager',
          'subtitle': '30 min · Office',
          'color': accentPurple,
          'icon': Icons.person_rounded,
        },
        {
          'hour': 10,
          'title': 'Design Review',
          'subtitle': '1 hr · Figma call',
          'color': const Color(0xFFFF3B30),
          'icon': Icons.design_services_rounded,
        },
        {
          'hour': 14,
          'title': 'Client Call — Acme',
          'subtitle': '45 min · Zoom',
          'color': const Color(0xFF007AFF),
          'icon': Icons.business_rounded,
        },
        {
          'hour': 16,
          'title': 'Focus Time',
          'subtitle': 'Blocked — deep work',
          'color': greenColor,
          'icon': Icons.do_not_disturb_on_rounded,
        },
      ]);
    }
    // Wednesday
    else if (day == 3) {
      events.addAll([
        {
          'hour': 9,
          'title': 'All Hands Meeting',
          'subtitle': '1 hr · Main Hall',
          'color': const Color(0xFFFF9500),
          'icon': Icons.groups_rounded,
        },
        {
          'hour': 11,
          'title': '🎂 Alex\'s Birthday',
          'subtitle': 'Team celebration at 3PM',
          'color': const Color(0xFFFF3B30),
          'icon': Icons.cake_rounded,
        },
        {
          'hour': 13,
          'title': 'Lunch & Learn',
          'subtitle': 'AI in Healthcare — Cafeteria',
          'color': accentPurple,
          'icon': Icons.school_rounded,
        },
        {
          'hour': 15,
          'title': 'Code Review',
          'subtitle': '1 hr · PR #142',
          'color': greenColor,
          'icon': Icons.code_rounded,
        },
      ]);
    }
    // Thursday
    else if (day == 4) {
      events.addAll([
        {
          'hour': 9,
          'title': 'Team Standup',
          'subtitle': '15 min · Google Meet',
          'color': accentPurple,
          'icon': Icons.groups_rounded,
        },
        {
          'hour': 10,
          'title': 'Investor Update',
          'subtitle': '1 hr · Board Room',
          'color': const Color(0xFF007AFF),
          'icon': Icons.trending_up_rounded,
        },
        {
          'hour': 12,
          'title': 'Working Lunch',
          'subtitle': 'Q3 roadmap discussion',
          'color': greenColor,
          'icon': Icons.restaurant_rounded,
        },
        {
          'hour': 14,
          'title': 'User Research',
          'subtitle': '2 hrs · User interviews',
          'color': const Color(0xFFFF9500),
          'icon': Icons.people_rounded,
        },
        {
          'hour': 16,
          'title': 'Retrospective',
          'subtitle': '1 hr · Zoom',
          'color': const Color(0xFFFF3B30),
          'icon': Icons.refresh_rounded,
        },
      ]);
    }
    // Friday
    else if (day == 5) {
      events.addAll([
        {
          'hour': 9,
          'title': 'Team Standup',
          'subtitle': '15 min · Google Meet',
          'color': accentPurple,
          'icon': Icons.groups_rounded,
        },
        {
          'hour': 11,
          'title': 'Demo Day',
          'subtitle': '2 hrs · All teams',
          'color': const Color(0xFFFF9500),
          'icon': Icons.slideshow_rounded,
        },
        {
          'hour': 14,
          'title': 'Friday Wind Down',
          'subtitle': 'Optional — team social',
          'color': greenColor,
          'icon': Icons.celebration_rounded,
        },
      ]);
    }
    // Weekend
    else {
      events.addAll([
        {
          'hour': 10,
          'title': 'Morning Run',
          'subtitle': '5km · Riverside Trail',
          'color': greenColor,
          'icon': Icons.directions_run_rounded,
        },
        {
          'hour': 12,
          'title': 'Brunch with Family',
          'subtitle': 'Home',
          'color': const Color(0xFFFF9500),
          'icon': Icons.home_rounded,
        },
        {
          'hour': 15,
          'title': 'Personal Project',
          'subtitle': 'Focus time',
          'color': accentPurple,
          'icon': Icons.lightbulb_rounded,
        },
      ]);
    }

    return events;
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
  Widget build(BuildContext context) => StreamBuilder<List<SavedWorkout>>(
    stream: _workoutsStream,
    builder: (context, snapshot) {
      final streak = WorkoutService.calculateCurrentStreak(
        snapshot.data ?? const [],
      );
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1E7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.local_fire_department_rounded,
              size: 16,
              color: Colors.orange,
            ),
            const SizedBox(width: 3),
            Text(
              '$streak-day',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.orange,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ScheduleEvent {
  const _ScheduleEvent({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

class _ScoredReachableEvent {
  const _ScoredReachableEvent({required this.event, required this.score});

  final gcal.Event event;
  final CognitiveLoadScore score;
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

class WeeklyCalendar extends StatefulWidget {
  const WeeklyCalendar({super.key});
  @override
  State<WeeklyCalendar> createState() => _WeeklyCalendarState();
}

class _WeeklyCalendarState extends State<WeeklyCalendar> {
  int _weekOffset = 0;
  final ScrollController _scrollController = ScrollController();
  List<gcal.Event> _googleEvents = [];
  List<OutlookEvent> _outlookEvents = [];
  bool _isGoogleConnected = false;
  bool _isOutlookConnected = false;
  bool _isLoading = false;
  DateTime? _lastGoogleCalendarAttempt;
  DateTime? _lastGoogleCalendarFailure;
  int? _lastGoogleCalendarWeekOffset;
  bool get _hasConnectedCalendar => _isGoogleConnected || _isOutlookConnected;

  static const double _cellH = 52;
  static const double _timeColW = 52;
  static const Color _accentPurple = Color(0xFF7B6EF6);
  static const Color _textDark = Color(0xFF1C1C1E);
  static const Color _textGrey = Color(0xFF8E8E93);
  static const Color _border = Color(0xFFE5E5EA);

  static const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _hours = [
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
  ];

  @override
  void initState() {
    super.initState();
    CalendarService.connectionNotifier.addListener(
      _handleGoogleCalendarConnectionChange,
    );
    _loadExistingGoogleCalendar();
    _loadExistingOutlookCalendar();
  }

  void _scrollToFirstTodayEvent() {
    if (_weekOffset != 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final now = DateTime.now();
      final starts =
          <DateTime>[
              ..._googleEvents
                  .map((event) => event.start?.dateTime?.toLocal())
                  .whereType<DateTime>(),
              ..._outlookEvents.map((event) => event.start.toLocal()),
            ].where((start) {
              return start.year == now.year &&
                  start.month == now.month &&
                  start.day == now.day;
            }).toList()
            ..sort();

      final firstStart = starts.isEmpty ? now : starts.first;
      final eventHour = firstStart.hour + (firstStart.minute / 60);
      final scrollTo = (eventHour * _cellH) - _cellH;
      _scrollController.animateTo(
        scrollTo.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _loadExistingGoogleCalendar({bool force = false}) async {
    if (_isLoading) return;

    final now = DateTime.now();

    if (!force &&
        _lastGoogleCalendarAttempt != null &&
        _lastGoogleCalendarWeekOffset == _weekOffset &&
        now.difference(_lastGoogleCalendarAttempt!) <
            const Duration(seconds: 30)) {
      debugPrint('Google Calendar load skipped: cooldown active');
      return;
    }

    if (!force &&
        _lastGoogleCalendarFailure != null &&
        now.difference(_lastGoogleCalendarFailure!) <
            const Duration(minutes: 2)) {
      debugPrint(
        'Google Calendar load skipped: recent failure cooldown active',
      );
      return;
    }

    _lastGoogleCalendarAttempt = now;
    _lastGoogleCalendarWeekOffset = _weekOffset;

    setState(() => _isLoading = true);
    try {
      final signedIn = await CalendarService.isSignedIn().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      if (!signedIn) {
        if (!mounted) return;
        setState(() {
          _isGoogleConnected = false;
          _isLoading = false;
        });
        _publishCalendarWidgetSnapshot();
        return;
      }

      final dates = _getWeekDates();
      final weekStart = dates.first;
      final events = await CalendarService.getWeekEvents(
        weekStart,
      ).timeout(const Duration(seconds: 8), onTimeout: () => <gcal.Event>[]);

      if (!mounted) return;
      setState(() {
        _googleEvents = events;
        _isGoogleConnected = CalendarService.connectionNotifier.value;
        _isLoading = false;
      });
      _publishCalendarWidgetSnapshot();
      _scrollToFirstTodayEvent();
    } catch (e) {
      debugPrint('Calendar silent load error: $e');
      _lastGoogleCalendarFailure = DateTime.now();
      if (!mounted) return;
      setState(() {
        _isGoogleConnected = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadExistingOutlookCalendar() async {
    try {
      final signedIn = await OutlookCalendarService.isSignedIn().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );

      if (!signedIn) {
        if (!mounted) return;
        setState(() {
          _outlookEvents = [];
          _isOutlookConnected = false;
        });
        _publishCalendarWidgetSnapshot();
        return;
      }

      final dates = _getWeekDates();
      final weekStart = dates.first;
      final events = await OutlookCalendarService.getWeekEvents(
        weekStart,
      ).timeout(const Duration(seconds: 8), onTimeout: () => <OutlookEvent>[]);

      if (!mounted) return;
      setState(() {
        _outlookEvents = events;
        _isOutlookConnected = true;
      });
      _publishCalendarWidgetSnapshot();
      _scrollToFirstTodayEvent();
    } catch (e) {
      debugPrint('Existing Outlook calendar load failed: $e');
      if (!mounted) return;
      setState(() {
        _outlookEvents = [];
        _isOutlookConnected = false;
      });
      _publishCalendarWidgetSnapshot();
    }
  }

  @override
  void dispose() {
    CalendarService.connectionNotifier.removeListener(
      _handleGoogleCalendarConnectionChange,
    );
    _scrollController.dispose();
    super.dispose();
  }

  void _handleGoogleCalendarConnectionChange() {
    if (!mounted) return;
    if (CalendarService.connectionNotifier.value) {
      _lastGoogleCalendarAttempt = null;
      _lastGoogleCalendarFailure = null;
      _lastGoogleCalendarWeekOffset = null;
      if (!_isLoading) {
        _loadExistingGoogleCalendar(force: true);
      }
      return;
    }
    setState(() {
      _googleEvents = [];
      _isGoogleConnected = false;
      _isLoading = false;
      _lastGoogleCalendarAttempt = null;
      _lastGoogleCalendarFailure = null;
      _lastGoogleCalendarWeekOffset = null;
    });
    _publishCalendarWidgetSnapshot();
  }

  void _publishCalendarWidgetSnapshot() {
    unawaited(
      HomeWidgetService.publishCalendarEvents(
        googleEvents: _googleEvents,
        outlookEvents: _outlookEvents,
      ),
    );
  }

  Future<void> _connectGoogle() async {
    setState(() => _isLoading = true);
    try {
      final dates = _getWeekDates();
      final weekStart = dates.first;
      _lastGoogleCalendarAttempt = null;
      _lastGoogleCalendarFailure = null;
      _lastGoogleCalendarWeekOffset = null;

      final events = await CalendarService.connectAndGetWeekEvents(weekStart);
      if (!mounted) return;
      setState(() {
        _googleEvents = events;
        _isGoogleConnected = true;
      });
      _publishCalendarWidgetSnapshot();
      _scrollToFirstTodayEvent();
    } catch (e) {
      debugPrint('Calendar error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _connectOutlook() async {
    setState(() => _isLoading = true);
    try {
      final dates = _getWeekDates();
      final weekStart = dates.first;
      final events = await OutlookCalendarService.connectAndGetWeekEvents(
        weekStart,
      );
      if (!mounted) return;
      setState(() {
        _outlookEvents = events;
        _isOutlookConnected = true;
      });
      _publishCalendarWidgetSnapshot();
      _scrollToFirstTodayEvent();
    } catch (e) {
      debugPrint('Outlook calendar connect error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<DateTime> _getWeekDates() {
    final now = DateTime.now();
    final monday = now
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: _weekOffset * 7));
    return List.generate(
      7,
      (i) => DateTime(monday.year, monday.month, monday.day + i),
    );
  }

  String _fmt12(int h) {
    if (h == 0) return '12 AM';
    if (h == 12) return '12 PM';
    if (h > 12) return '${h - 12} PM';
    return '$h AM';
  }

  String _monthLabel(List<DateTime> dates) {
    final start = dates.first;
    final end = dates.last;
    if (start.month == end.month) {
      return '${_months[start.month - 1]} ${start.year}';
    }
    return '${_months[start.month - 1]} – ${_months[end.month - 1]} ${start.year}';
  }

  String _formatEventDateTime(DateTime? dateTime) {
    if (dateTime == null) return 'Unknown time';
    final local = dateTime.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${_days[local.weekday % 7]}, ${_months[local.month - 1]} ${local.day} at $hour:$minute $suffix';
  }

  String _formatEventTimeRange(gcal.Event event) {
    final start = event.start?.dateTime?.toLocal();
    final end = event.end?.dateTime?.toLocal();
    if (start == null) return 'Unknown time';

    final startHour = start.hour % 12 == 0 ? 12 : start.hour % 12;
    final startMinute = start.minute.toString().padLeft(2, '0');
    final startSuffix = start.hour >= 12 ? 'PM' : 'AM';

    if (end == null) {
      return '${_formatEventDateTime(start)}';
    }

    final endHour = end.hour % 12 == 0 ? 12 : end.hour % 12;
    final endMinute = end.minute.toString().padLeft(2, '0');
    final endSuffix = end.hour >= 12 ? 'PM' : 'AM';

    return '${_days[start.weekday % 7]}, ${_months[start.month - 1]} ${start.day}, '
        '$startHour:$startMinute $startSuffix – $endHour:$endMinute $endSuffix';
  }

  DateTime _withTime(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  String _eventRecurrence(gcal.Event event) {
    final rule = event.recurrence?.join(' ').toUpperCase() ?? '';
    if (rule.contains('FREQ=DAILY')) return 'daily';
    if (rule.contains('FREQ=MONTHLY')) return 'monthly';
    if (rule.contains('FREQ=WEEKLY') || event.recurringEventId != null) {
      return 'weekly';
    }
    return 'none';
  }

  void showCreateEvent(DateTime initialStart, DateTime initialEnd) {
    _createEvent(initialStart, initialEnd: initialEnd);
  }

  Future<void> _createEvent(
    DateTime initialStart, {
    DateTime? initialEnd,
  }) async {
    final draft = await showDialog<_CalendarEventDraft>(
      context: context,
      builder: (_) => _CreateCalendarEventDialog(
        initialStart: initialStart,
        initialEnd: initialEnd,
      ),
    );
    if (!context.mounted || draft == null) return;

    final start = _withTime(draft.date, draft.startTime);
    var end = _withTime(draft.date, draft.endTime);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    setState(() => _isLoading = true);
    try {
      await CalendarService.createEvent(
        title: draft.title,
        start: start,
        end: end,
        recurrence: draft.recurrence,
      );
      if (!context.mounted) return;
      setState(() => _isLoading = false);
      await _loadExistingGoogleCalendar(force: true);
      if (!context.mounted) return;
      _showCalendarMessage('Event created.');
    } catch (e) {
      _showCalendarMessage('Could not create event: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editEvent(gcal.Event event) async {
    final originalStart = event.start?.dateTime?.toLocal();
    final originalEnd = event.end?.dateTime?.toLocal();
    if (originalStart == null || originalEnd == null) {
      _showCalendarMessage('All-day events cannot be edited here yet.');
      return;
    }

    var date = DateTime(
      originalStart.year,
      originalStart.month,
      originalStart.day,
    );
    var startTime = TimeOfDay.fromDateTime(originalStart);
    var endTime = TimeOfDay.fromDateTime(originalEnd);
    var recurrence = _eventRecurrence(event);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Edit event'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_rounded),
                title: const Text('Date'),
                subtitle: Text(
                  '${_months[date.month - 1]} ${date.day}, ${date.year}',
                ),
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
                  if (picked != null) setDialogState(() => startTime = picked);
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
              DropdownButtonFormField<String>(
                initialValue: recurrence,
                decoration: const InputDecoration(
                  labelText: 'Repeats',
                  prefixIcon: Icon(Icons.repeat_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'none',
                    child: Text('Does not repeat'),
                  ),
                  DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => recurrence = value);
                },
              ),
            ],
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

    final start = _withTime(date, startTime);
    var end = _withTime(date, endTime);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    setState(() => _isLoading = true);
    try {
      await CalendarService.updateEventTimeAndRecurrence(
        event,
        start: start,
        end: end,
        recurrence: recurrence,
      );
      if (mounted) setState(() => _isLoading = false);
      await _loadExistingGoogleCalendar(force: true);
      _showCalendarMessage('Event updated.');
    } catch (e) {
      _showCalendarMessage('Could not update event: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeEvent(gcal.Event event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove event?'),
        content: Text(
          'This will remove “${event.summary ?? 'Untitled event'}” from Google Calendar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await CalendarService.deleteEvent(event);
      if (mounted) setState(() => _isLoading = false);
      await _loadExistingGoogleCalendar(force: true);
      _showCalendarMessage('Event removed.');
    } catch (e) {
      _showCalendarMessage('Could not remove event: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCalendarMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openMaps(String location) async {
    final googleWebUri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': location,
    });

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final googleAppUri = Uri.parse(
        'comgooglemaps://?q=${Uri.encodeQueryComponent(location)}',
      );
      if (await canLaunchUrl(googleAppUri)) {
        await launchUrl(googleAppUri, mode: LaunchMode.externalApplication);
        return;
      }

      final appleMapsUri = Uri.https('maps.apple.com', '/', {'q': location});
      if (await launchUrl(appleMapsUri, mode: LaunchMode.externalApplication)) {
        return;
      }
    } else if (await launchUrl(
      googleWebUri,
      mode: LaunchMode.externalApplication,
    )) {
      return;
    }

    _showCalendarMessage('Could not open a maps app.');
  }

  void showEventDetails(gcal.Event event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final title = event.summary ?? 'Untitled event';
        final location = event.location;
        final description = event.description;
        final attendees = event.attendees ?? const <gcal.EventAttendee>[];

        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F0FE),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.event_rounded,
                          color: Color(0xFF1A73E8),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: context.vivordoColors.textPrimary,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatEventTimeRange(event),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _textGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (location != null && location.trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _EventDetailRow(
                      icon: Icons.place_rounded,
                      label: 'Location',
                      value: location,
                      onTap: () => _openMaps(location),
                    ),
                  ],
                  if (description != null && description.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _EventDetailRow(
                      icon: Icons.notes_rounded,
                      label: 'Description',
                      value: description,
                      maxValueHeight: 140,
                    ),
                  ],
                  if (attendees.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _EventDetailRow(
                      icon: Icons.people_rounded,
                      label: 'Attendees',
                      value: attendees
                          .map(
                            (attendee) =>
                                attendee.displayName ??
                                attendee.email ??
                                'Guest',
                          )
                          .take(6)
                          .join(', '),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _removeEvent(event);
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Remove'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _editEvent(event);
                          },
                          icon: const Icon(Icons.edit_rounded),
                          label: const Text('Edit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentPurple,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dates = _getWeekDates();
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0F000000),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: context.vivordoColors.border,
                    width: 0.5,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: _accentPurple,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _monthLabel(dates),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.vivordoColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        if (!_isGoogleConnected)
                          GestureDetector(
                            onTap: _isLoading ? null : _connectGoogle,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1a73e8),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Connect Google',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        if (!_isOutlookConnected) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: _isLoading ? null : _connectOutlook,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0078D4),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Connect Outlook',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        _navBtn(Icons.chevron_left_rounded, () {
                          setState(() => _weekOffset--);
                          if (_isGoogleConnected) _loadExistingGoogleCalendar();
                          if (_isOutlookConnected)
                            _loadExistingOutlookCalendar();
                        }),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => setState(() => _weekOffset = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: context.vivordoColors.border,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Today',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.vivordoColors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _navBtn(Icons.chevron_right_rounded, () {
                          setState(() => _weekOffset++);
                          if (_isGoogleConnected) _loadExistingGoogleCalendar();
                          if (_isOutlookConnected)
                            _loadExistingOutlookCalendar();
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Day headers
            Row(
              children: [
                SizedBox(width: _timeColW),
                ...dates.map((d) {
                  final isToday =
                      _weekOffset == 0 &&
                      d.day == now.day &&
                      d.month == now.month &&
                      d.year == now.year;
                  return Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: context.vivordoColors.border,
                            width: 0.5,
                          ),
                          right: BorderSide(
                            color: context.vivordoColors.border,
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _days[d.weekday % 7],
                            style: const TextStyle(
                              fontSize: 10,
                              color: _textGrey,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: isToday
                                  ? const Color(0xFF1a73e8)
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${d.day}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: isToday
                                      ? Colors.white
                                      : context.vivordoColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),

            // Body
            if (!_hasConnectedCalendar)
              Container(
                height: 220,
                alignment: Alignment.center,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 48,
                        color: context.vivordoColors.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No calendar connected',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.vivordoColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Connect Google or Outlook above\nto see your events here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: _textGrey,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: _isLoading ? null : _connectGoogle,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1a73e8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.calendar_month_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Connect Google Calendar',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _isLoading ? null : _connectOutlook,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0078D4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.calendar_month_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Connect Outlook Calendar',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 400,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Time column
                      SizedBox(
                        width: _timeColW,
                        child: Column(
                          children: _hours
                              .map(
                                (h) => SizedBox(
                                  height: _cellH,
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        right: 8,
                                        top: 4,
                                      ),
                                      child: Text(
                                        _fmt12(h),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: _textGrey,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),

                      // Day columns
                      ...dates.map((d) {
                        final dow = d.weekday % 7;
                        final isToday =
                            _weekOffset == 0 &&
                            d.day == now.day &&
                            d.month == now.month &&
                            d.year == now.year;
                        const dayEvents = <_CalEvent>[];
                        final googleDayEvents = _isGoogleConnected
                            ? _googleEvents.where((e) {
                                final start = e.start?.dateTime?.toLocal();
                                return start != null &&
                                    start.day == d.day &&
                                    start.month == d.month;
                              }).toList()
                            : <gcal.Event>[];
                        final outlookDayEvents = _isOutlookConnected
                            ? _outlookEvents.where((e) {
                                final start = e.start.toLocal();
                                return start.day == d.day &&
                                    start.month == d.month &&
                                    start.year == d.year;
                              }).toList()
                            : <OutlookEvent>[];

                        return Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: context.vivordoColors.border,
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Stack(
                              children: [
                                // Hour cells
                                Column(
                                  children: _hours
                                      .map(
                                        (h) => InkWell(
                                          onTap: _isGoogleConnected
                                              ? () => _createEvent(
                                                  DateTime(
                                                    d.year,
                                                    d.month,
                                                    d.day,
                                                    h,
                                                  ),
                                                )
                                              : null,
                                          child: Container(
                                            height: _cellH,
                                            decoration: BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: context
                                                      .vivordoColors
                                                      .border,
                                                  width: 0.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),

                                // Google Calendar events
                                ...googleDayEvents.map((ev) {
                                  final start = ev.start?.dateTime?.toLocal();
                                  final end = ev.end?.dateTime?.toLocal();
                                  if (start == null)
                                    return const SizedBox.shrink();
                                  final startH =
                                      start.hour + start.minute / 60.0;
                                  final endH = end != null
                                      ? end.hour + end.minute / 60.0
                                      : startH + 1;
                                  final top = startH * _cellH;
                                  final height = ((endH - startH) * _cellH - 2)
                                      .clamp(18.0, double.infinity);
                                  return Positioned(
                                    top: top,
                                    left: 2,
                                    right: 2,
                                    height: height,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(4),
                                        onTap: () => showEventDetails(ev),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? context
                                                      .vivordoColors
                                                      .cardMuted
                                                : const Color(0xFFe8f0fe),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: const Border(
                                              left: BorderSide(
                                                color: Color(0xFF1a73e8),
                                                width: 3,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            ev.summary ?? 'Event',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? context
                                                        .vivordoColors
                                                        .textPrimary
                                                  : const Color(0xFF1557b0),
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                                // Outlook Calendar events
                                ...outlookDayEvents.map((ev) {
                                  final start = ev.start.toLocal();
                                  final end = ev.end.toLocal();
                                  final startH =
                                      start.hour + start.minute / 60.0;
                                  final endH = end.hour + end.minute / 60.0;
                                  final top = startH * _cellH;
                                  final height = ((endH - startH) * _cellH - 2)
                                      .clamp(18.0, double.infinity);
                                  return Positioned(
                                    top: top,
                                    left: 4,
                                    right: 0,
                                    height: height,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(4),
                                        onTap: () {},
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                Theme.of(context).brightness ==
                                                    Brightness.dark
                                                ? context
                                                      .vivordoColors
                                                      .cardMuted
                                                : const Color(0xFFE6F2FB),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: const Border(
                                              left: BorderSide(
                                                color: Color(0xFF0078D4),
                                                width: 3,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            ev.subject,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  Theme.of(
                                                        context,
                                                      ).brightness ==
                                                      Brightness.dark
                                                  ? context
                                                        .vivordoColors
                                                        .textPrimary
                                                  : const Color(0xFF005A9E),
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),

                                // Now line
                                if (isToday)
                                  Positioned(
                                    top: (now.hour + now.minute / 60) * _cellH,
                                    left: 0,
                                    right: 0,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFea4335),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            height: 2,
                                            color: const Color(0xFFea4335),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: context.vivordoColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 15, color: context.vivordoColors.textPrimary),
      ),
    );
  }
}

class _CalendarEventDraft {
  const _CalendarEventDraft({
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.recurrence,
  });

  final String title;
  final DateTime date;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String recurrence;
}

class _CreateCalendarEventDialog extends StatefulWidget {
  const _CreateCalendarEventDialog({
    required this.initialStart,
    this.initialEnd,
  });

  final DateTime initialStart;
  final DateTime? initialEnd;

  @override
  State<_CreateCalendarEventDialog> createState() =>
      _CreateCalendarEventDialogState();
}

class _CreateCalendarEventDialogState
    extends State<_CreateCalendarEventDialog> {
  late final TextEditingController _titleController;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  String _recurrence = 'none';
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _date = DateUtils.dateOnly(widget.initialStart);
    _startTime = TimeOfDay.fromDateTime(widget.initialStart);
    _endTime = TimeOfDay.fromDateTime(
      widget.initialEnd ?? widget.initialStart.add(const Duration(hours: 1)),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!context.mounted || picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showVivordoTimePicker(
      context: context,
      initialTime: _startTime,
      title: 'Start Time',
    );
    if (!context.mounted || picked == null) return;
    setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showVivordoTimePicker(
      context: context,
      initialTime: _endTime,
      title: 'End Time',
    );
    if (!context.mounted || picked == null) return;
    setState(() => _endTime = picked);
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Enter an event title');
      return;
    }
    Navigator.pop(
      context,
      _CalendarEventDraft(
        title: title,
        date: _date,
        startTime: _startTime,
        endTime: _endTime,
        recurrence: _recurrence,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text('Create event'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Event title',
                prefixIcon: const Icon(Icons.event_rounded),
                errorText: _titleError,
              ),
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_rounded),
              title: const Text('Date'),
              subtitle: Text(
                MaterialLocalizations.of(context).formatFullDate(_date),
              ),
              onTap: _pickDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Start time'),
              trailing: Text(_startTime.format(context)),
              onTap: _pickStartTime,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('End time'),
              trailing: Text(_endTime.format(context)),
              onTap: _pickEndTime,
            ),
            DropdownButtonFormField<String>(
              initialValue: _recurrence,
              decoration: const InputDecoration(
                labelText: 'Repeats',
                prefixIcon: Icon(Icons.repeat_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Does not repeat')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _recurrence = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}

class _CalEvent {
  final int dow;
  final int h;
  final int m;
  final double dur;
  final String title;
  final String sub;
  final Color color;
  final Color bg;
  const _CalEvent({
    required this.dow,
    required this.h,
    required this.m,
    required this.dur,
    required this.title,
    required this.sub,
    required this.color,
    required this.bg,
  });
}

class _EventDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double? maxValueHeight;
  final VoidCallback? onTap;

  const _EventDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.maxValueHeight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: onTap == null ? 0 : 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: const Color(0xFF8E8E93)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8E8E93),
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: maxValueHeight ?? double.infinity,
                      ),
                      child: SingleChildScrollView(
                        physics: maxValueHeight == null
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: context.vivordoColors.textPrimary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: Color(0xFF1A73E8),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
