import 'dart:async';
import '../widgets/visible_stream_builder.dart';
import '../widgets/contextual_insight_bar.dart';
import '../src/services/active_workout_navigation.dart';
import '../widgets/workout_rest_timer.dart';
import '../widgets/ios_pull_down_menu.dart';
import '../widgets/apple_ui.dart';
import '../widgets/vivordo_time_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSwitch;
import '../src/services/notification_service.dart';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/data/exercise_library.dart';

import '../src/services/activity_goals_service.dart';
import '../src/services/active_workout_storage.dart';
import '../src/services/health_service.dart';
import '../src/services/recent_activity_service.dart';
import '../src/services/workout_service.dart';
import '../src/services/personal_profile_service.dart';
import '../src/services/workout_live_activity_service.dart';
import '../src/utils/workout_activity_visual.dart';
import '../src/utils/day_key.dart';
import '../src/utils/home_metrics_summary.dart' show durationUntilNextLocalDay;
import '../src/utils/fitness_goal_insight.dart';
import '../src/services/metrics_repository.dart';
import 'exercise_detail_screen.dart';
import 'personal_profile_screen.dart';
import 'workout_summary_screen.dart';

const _purple = Color(0xFF6B5CE7);
const _muted = Color(0xFF85859B);

/// Shared in-memory workout timer state for navigation affordances.
class FitnessWorkoutTimerState {
  const FitnessWorkoutTimerState._();

  static final ValueNotifier<bool> isRunning = ValueNotifier<bool>(false);

  static Future<void> restore() async {
    final stored = await ActiveWorkoutStorage.read();
    isRunning.value = stored != null;
    if (stored == null) {
      await WorkoutLiveActivityService.end();
      return;
    }
    final startedAt = DateTime.tryParse(stored['startedAt'] as String? ?? '');
    if (startedAt == null) return;
    final exercises = stored['exercises'];
    final exerciseList = exercises is List ? exercises : const [];
    final first = exerciseList.isEmpty ? null : exerciseList.first;
    final title = first is Map
        ? (first['name'] as String? ?? 'Workout')
        : 'Workout';
    await WorkoutLiveActivityService.start(
      startedAt: startedAt.toLocal(),
      title: title,
      exerciseCount: exerciseList.length,
    );
  }

  static void start({
    DateTime? startedAt,
    String title = 'Workout',
    int exerciseCount = 0,
  }) {
    isRunning.value = true;
    if (startedAt != null) {
      unawaited(
        WorkoutLiveActivityService.start(
          startedAt: startedAt,
          title: title,
          exerciseCount: exerciseCount,
        ),
      );
    }
  }

  static void update({required String title, required int exerciseCount}) {
    if (!isRunning.value) return;
    unawaited(
      WorkoutLiveActivityService.update(
        title: title,
        exerciseCount: exerciseCount,
      ),
    );
  }

  static void stop() {
    isRunning.value = false;
    unawaited(WorkoutLiveActivityService.end());
  }
}

class FitnessScreen extends StatefulWidget {
  const FitnessScreen({
    super.key,
    this.isActive = true,
    this.actionsKey,
    this.ringsKey,
    this.buttonsKey,
    this.weekKey,
    this.recentKey,
    this.bodyKey,
  });

  final bool isActive;

  /// Spotlight targets for the Fitness tour.
  final Key? actionsKey;
  final Key? ringsKey;
  final Key? buttonsKey;
  final Key? weekKey;
  final Key? recentKey;
  final Key? bodyKey;

  @override
  State<FitnessScreen> createState() => _FitnessScreenState();
}

class _FitnessScreenState extends State<FitnessScreen> {
  bool _deferredInitializationStarted = false;
  bool _deferredInitializationScheduled = false;
  Timer? _deferredInitializationTimer;
  final Map<String, int> _strengthGoals = Map.of(kDefaultStrengthGoals);

  /// The last 30 full days, read by the body card for the latest heart scan
  /// and synced weight/body fat. Created once so rebuilds of this screen
  /// don't reopen the Firestore listener.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _recentDays;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _recentDays = user == null
        ? const Stream.empty()
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('metrics_daily')
              .orderBy(FieldPath.documentId, descending: true)
              .limit(30)
              .snapshots();
    _startDeferredInitializationIfActive();
  }

  @override
  void didUpdateWidget(covariant FitnessScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      _deferredInitializationTimer?.cancel();
      _deferredInitializationTimer = null;
      _deferredInitializationScheduled = false;
    }
    if (!oldWidget.isActive && widget.isActive) {
      _startDeferredInitializationIfActive();
    }
  }

  void _startDeferredInitializationIfActive() {
    if (!widget.isActive ||
        _deferredInitializationStarted ||
        _deferredInitializationScheduled) {
      return;
    }
    _deferredInitializationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isActive) {
        _deferredInitializationScheduled = false;
        return;
      }
      _deferredInitializationTimer = Timer(
        const Duration(milliseconds: 220),
        () {
          _deferredInitializationTimer = null;
          _deferredInitializationScheduled = false;
          if (!mounted || !widget.isActive || _deferredInitializationStarted) {
            return;
          }
          _deferredInitializationStarted = true;
          unawaited(_restoreActiveWorkout());
          unawaited(_backfillLegacyExerciseMinutes());
          unawaited(_backfillPersonalBests());
          unawaited(_loadStrengthGoals());
        },
      );
    });
  }

  @override
  void dispose() {
    _deferredInitializationTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStrengthGoals() async {
    try {
      final goals = await ActivityGoalsService.loadStrengthGoals();
      if (!mounted) return;
      setState(() {
        _strengthGoals
          ..clear()
          ..addAll(goals);
      });
    } catch (error) {
      debugPrint('FitnessScreen: failed to load strength goals: $error');
    }
  }

  Future<void> _backfillLegacyExerciseMinutes() async {
    try {
      final migrated = await WorkoutService.migrateLegacyExerciseMinutesOnce();
      if (migrated > 0) {
        debugPrint(
          'WorkoutService: added $migrated legacy workout(s) to exercise time.',
        );
      }
    } catch (error) {
      debugPrint(
        'WorkoutService: legacy exercise-time backfill failed: $error',
      );
    }
  }

  Future<void> _backfillPersonalBests() async {
    try {
      final updated = await WorkoutService.backfillPersonalBestsOnce();
      if (updated > 0) {
        debugPrint(
          'WorkoutService: checked $updated workout(s) for personal bests.',
        );
      }
    } catch (error) {
      debugPrint('WorkoutService: personal-best backfill failed: $error');
    }
  }

  Future<void> _restoreActiveWorkout() async {
    if (_activeWorkoutDraft != null) return;
    final restored = await _ActiveWorkoutDraft.restore();
    if (restored == null) return;
    _activeWorkoutDraft = restored;
    FitnessWorkoutTimerState.start(
      startedAt: restored.startedAt,
      title: restored.liveActivityTitle,
      exerciseCount: restored.exercises.length,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      backgroundColor: colors.page,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 150),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fitness',
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
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: _WorkoutStreakPill(),
                      ),
                      IconButton(
                        onPressed: _openGoals,
                        tooltip: 'Goals',
                        icon: const Icon(
                          Icons.track_changes_rounded,
                          color: _purple,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              KeyedSubtree(
                key: widget.ringsKey,
                child: _TodayActivityRings(onTap: _openMonthlyRings),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<bool>(
                key: widget.buttonsKey,
                valueListenable: FitnessWorkoutTimerState.isRunning,
                builder: (context, isWorkoutRunning, _) => Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _startWorkout,
                          icon: Icon(
                            isWorkoutRunning && _activeWorkoutDraft != null
                                ? Icons.timer_outlined
                                : Icons.fitness_center_rounded,
                          ),
                          label: _WorkoutButtonLabel(
                            draft: isWorkoutRunning
                                ? _activeWorkoutDraft
                                : null,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _purple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _logActivity,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text(
                          'Log activity',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _purple,
                          side: BorderSide(
                            color: _purple.withValues(alpha: .45),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              KeyedSubtree(
                key: widget.weekKey,
                child: _ThisWeekCard(strengthGoals: _strengthGoals),
              ),
              const SizedBox(height: 24),
              KeyedSubtree(key: widget.recentKey, child: const _RecentFeed()),
              const SizedBox(height: 24),
              KeyedSubtree(key: widget.bodyKey, child: _BodyCard(_recentDays)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logActivity() async {
    // The sheet shows its own saved / will-sync toast before closing.
    await showAppleSheet<bool>(
      context,
      builder: (_) => const _LogActivityDialog(),
    );
  }

  Future<void> _startWorkout() async {
    if (ActiveWorkoutNavigation.focusExisting()) return;
    _activeWorkoutDraft ??= await _ActiveWorkoutDraft.restore();
    _activeWorkoutDraft ??= await _ActiveWorkoutDraft.fresh();
    await _activeWorkoutDraft!.persist();
    if (!mounted) return;
    final draft = _activeWorkoutDraft!;
    FitnessWorkoutTimerState.start(
      startedAt: draft.startedAt,
      title: draft.liveActivityTitle,
      exerciseCount: draft.exercises.length,
    );
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ActiveWorkoutScreen()));
    if (mounted) setState(() {});
  }

  Future<void> _openGoals() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FitnessGoalsScreen(strengthGoals: _strengthGoals),
      ),
    );
    if (mounted) setState(() {});
  }

  void _openMonthlyRings() =>
      showDialog(context: context, builder: (_) => const MonthlyRingsDialog());
}

class _TodayActivityRings extends StatefulWidget {
  const _TodayActivityRings({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_TodayActivityRings> createState() => _TodayActivityRingsState();
}

class _TodayActivityRingsState extends State<_TodayActivityRings>
    with WidgetsBindingObserver {
  StreamSubscription<User?>? _authSubscription;
  Timer? _midnightTimer;
  String? _uid;
  late DateTime _day;
  late String _dayKey;
  late Stream<MetricWindow> _historyStream;
  late Stream<ActivityGoals> _goalsStream;
  Object? _insightKey;
  String _insight = '';
  bool _active = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) _refreshIfStale();
    });
  }

  void _connect() {
    _uid = FirebaseAuth.instance.currentUser?.uid;
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    _dayKey = DateFormat('yyyy-MM-dd').format(_day);
    _insightKey = null;
    var goalsHadError = false;
    _historyStream = _uid == null
        ? Stream.multi((controller) {
            controller.add(const MetricWindow(days: {}));
            controller.close();
          })
        : MetricsRepository.instance.watchActivity(
            uid: _uid!,
            endDay: _dayKey,
            startDay: DateFormat(
              'yyyy-MM-dd',
            ).format(DateTime(now.year, now.month, now.day - 14)),
          );
    _goalsStream = ActivityGoalsService.watch()
        .handleError((Object error, StackTrace stack) {
          goalsHadError = true;
          Error.throwWithStackTrace(error, stack);
        })
        .distinct((a, b) {
          final recovering = goalsHadError;
          goalsHadError = false;
          return !recovering &&
              a.steps == b.steps &&
              a.activeCalories == b.activeCalories &&
              a.exerciseMinutes == b.exerciseMinutes;
        });
  }

  void _refreshIfStale() {
    if (_uid != FirebaseAuth.instance.currentUser?.uid ||
        _dayKey != DateFormat('yyyy-MM-dd').format(DateTime.now())) {
      setState(_connect);
    }
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    if (!_active) return;
    final now = DateTime.now();
    _midnightTimer = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      _refreshIfStale,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = TickerMode.valuesOf(context).enabled;
    _refreshIfStale();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshIfStale();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibleStreamBuilder<MetricWindow>(
      key: ValueKey((_uid, _dayKey)),
      stream: _historyStream,
      builder: (context, snapshot) {
        final history =
            snapshot.data?.days ?? const <String, Map<String, dynamic>>{};
        final data = history[_dayKey];
        final steps = ((data?['steps'] as Map?)?['sum'] as num?)?.round() ?? 0;
        final calories =
            ((data?['active_calories'] as Map?)?['sum'] as num?)?.round() ?? 0;
        final exercise =
            ((data?['exercise_time'] as Map?)?['sum'] as num?)?.round() ?? 0;

        return VisibleStreamBuilder<ActivityGoals>(
          stream: _goalsStream,
          initialData: const ActivityGoals(),
          builder: (context, goalsSnapshot) {
            final goals = goalsSnapshot.data ?? const ActivityGoals();
            final insightKey = (
              history,
              goals.steps,
              goals.activeCalories,
              goals.exerciseMinutes,
              _dayKey,
            );
            if (_insightKey != insightKey) {
              _insightKey = insightKey;
              _insight = fitnessGoalInsight(
                data,
                goals,
                history: history,
                now: _day,
              );
            }
            final number = NumberFormat.decimalPattern();
            final rings = [
              (steps, goals.steps, 'steps'),
              (calories, goals.activeCalories, 'kcal'),
              (exercise, goals.exerciseMinutes, 'min'),
            ];
            final progress = [
              for (final ring in rings)
                ring.$2 <= 0 ? 1.0 : (ring.$1 / ring.$2).clamp(0.0, 1.0),
            ];
            final open = [
              for (var i = 0; i < rings.length; i++)
                if (progress[i] < 1) i,
            ]..sort((a, b) => progress[b].compareTo(progress[a]));
            final next = open.isEmpty ? null : rings[open.first];
            return Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFAA91FF).withValues(alpha: .6),
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF5844ED), Color(0xFF3529AD)],
                  ),
                ),
                child: InkWell(
                  onTap: widget.onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 86,
                              height: 86,
                              child: CustomPaint(
                                painter: ActivityRingsPainter(
                                  move: progress[0],
                                  exercise: progress[1],
                                  stand: progress[2],
                                  moveColor: Colors.white,
                                  trackColor: Colors.white.withValues(
                                    alpha: .18,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TODAY\'S ACTIVITY',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.3,
                                      color: Color(0xFFE8E0FF),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${3 - open.length} of 3 closed',
                                    style: const TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    next == null
                                        ? 'Every goal reached today.'
                                        : '${number.format(next.$2 - next.$1)} ${next.$3} to your next ring',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFF1ECFF),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFFE8E0FF),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: .15),
                        ),
                        const SizedBox(height: 12),
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              for (var i = 0; i < rings.length; i++) ...[
                                if (i > 0)
                                  VerticalDivider(
                                    width: 1,
                                    color: Colors.white.withValues(alpha: .15),
                                  ),
                                Expanded(
                                  child: _HeroStat(
                                    color: i == 0
                                        ? Colors.white
                                        : ActivityRingsPainter.ringColors[i],
                                    value: number.format(rings[i].$1),
                                    detail:
                                        '/ ${number.format(rings[i].$2)} ${rings[i].$3}',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ).withScreenInsight(
              ScreenInsight(
                'fitness',
                'Your activity',
                snapshot.hasError ||
                        snapshot.data?.error != null ||
                        goalsSnapshot.hasError
                    ? 'Your activity or goals could not be loaded. Refresh before comparing progress.'
                    : !snapshot.hasData ||
                          goalsSnapshot.connectionState ==
                              ConnectionState.waiting
                    ? 'Loading your activity and saved goals…'
                    : _insight,
              ),
            );
          },
        );
      },
    );
  }
}

class _WorkoutStreakPill extends StatefulWidget {
  const _WorkoutStreakPill();

  @override
  State<_WorkoutStreakPill> createState() => _WorkoutStreakPillState();
}

class _WorkoutStreakPillState extends State<_WorkoutStreakPill> {
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
          return _PillButton(
            icon: Icons.local_fire_department_rounded,
            label: '$streak-day streak',
            color: Colors.orange,
          );
        },
      );
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: _muted,
        ),
      ),
      const SizedBox(height: 7),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

class _ProfileDivider extends StatelessWidget {
  const _ProfileDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 40, color: context.vivordoColors.border);
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.color,
    required this.value,
    required this.detail,
  });

  final Color color;
  final String value, detail;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          detail,
          style: const TextStyle(fontSize: 11, color: Color(0xFFE8E0FF)),
        ),
      ),
    ],
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
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
        ?trailing,
      ],
    ),
  );
}

class _SectionNote extends StatelessWidget {
  const _SectionNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 12, color: context.vivordoColors.textSecondary),
  );
}

class _ThisWeekCard extends StatefulWidget {
  const _ThisWeekCard({required this.strengthGoals});

  final Map<String, int> strengthGoals;

  @override
  State<_ThisWeekCard> createState() => _ThisWeekCardState();
}

class _ThisWeekCardState extends State<_ThisWeekCard> {
  // ponytail: the week is fixed when the screen first builds; a screen left
  // open across Sunday midnight shows last week until it is rebuilt.
  late final DateTime _monday;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _metrics;
  late final Stream<List<SavedWorkout>> _workouts;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _monday = today.subtract(Duration(days: today.weekday - 1));
    final user = FirebaseAuth.instance.currentUser;
    _metrics = user == null
        ? const Stream.empty()
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('metrics_daily')
              .where(
                FieldPath.documentId,
                isGreaterThanOrEqualTo: localDayKey(_monday),
              )
              .where(
                FieldPath.documentId,
                isLessThanOrEqualTo: localDayKey(
                  _monday.add(const Duration(days: 6)),
                ),
              )
              .orderBy(FieldPath.documentId)
              .snapshots();
    _workouts = WorkoutService.watchBetween(
      start: _monday,
      end: _monday.add(const Duration(days: 7)),
    );
  }

  static double _sum(Map<String, dynamic>? data, String key) =>
      ((data?[key] as Map?)?['sum'] as num?)?.toDouble() ?? 0;

  @override
  Widget build(
    BuildContext context,
  ) => VisibleStreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _metrics,
    builder: (context, metricsSnapshot) => VisibleStreamBuilder<List<SavedWorkout>>(
      stream: _workouts,
      builder: (context, workoutsSnapshot) {
        final colors = context.vivordoColors;
        final today = DateUtils.dateOnly(DateTime.now());
        final byDay = {
          for (final doc
              in metricsSnapshot.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            doc.id: doc.data(),
        };
        final workouts = workoutsSnapshot.data ?? const <SavedWorkout>[];
        final workoutDays = {
          for (final workout in workouts)
            DateUtils.dateOnly(workout.completedAt.toLocal()),
        };
        final days = List.generate(7, (index) {
          final date = _monday.add(Duration(days: index));
          final data = byDay[localDayKey(date)];
          return (
            date: date,
            minutes: _sum(data, 'exercise_time'),
            km: _sum(data, 'distance'),
            calories: _sum(data, 'active_calories'),
            workout: workoutDays.contains(date),
          );
        });
        final minutes = days.fold<double>(0, (t, d) => t + d.minutes);
        final km = days.fold<double>(0, (t, d) => t + d.km);
        final calories = days.fold<double>(0, (t, d) => t + d.calories);
        final maxMinutes = days.fold<double>(
          0,
          (m, d) => math.max(m, d.minutes),
        );
        final activeDays = days
            .where(
              (d) => d.workout || d.minutes > 0 || d.km > 0 || d.calories > 0,
            )
            .length;

        final setsByCategory = {
          for (final category in widget.strengthGoals.keys) category: 0,
        };
        for (final workout in workouts) {
          for (final exercise in workout.exercises) {
            final category = exercise.category.trim().toLowerCase();
            for (final key in setsByCategory.keys) {
              if (key.toLowerCase() == category) {
                setsByCategory[key] =
                    setsByCategory[key]! + exercise.sets.length;
              }
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              'THIS WEEK',
              trailing: _SectionNote(
                '${workouts.length} ${workouts.length == 1 ? 'workout' : 'workouts'} · '
                '$activeDays active ${activeDays == 1 ? 'day' : 'days'}',
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExerciseDetailScreen()),
              ),
              child: _Card(
                child: Column(
                  children: [
                    SizedBox(
                      height: 96,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          for (final day in days)
                            _WeekDayBar(
                              letter: 'MTWTFSS'[day.date.weekday - 1],
                              fraction: maxMinutes == 0
                                  ? 0
                                  : day.minutes / maxMinutes,
                              isToday: day.date == today,
                              workout: day.workout,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _ActivityStat(
                            value: '${minutes.round()} min',
                            label: 'Active',
                          ),
                        ),
                        Expanded(
                          child: _ActivityStat(
                            value: '${km.toStringAsFixed(1)} km',
                            label: 'Distance',
                          ),
                        ),
                        Expanded(
                          child: _ActivityStat(
                            value:
                                '${NumberFormat.decimalPattern().format(calories.round())} kcal',
                            label: 'Burned',
                          ),
                        ),
                      ],
                    ),
                    if (setsByCategory.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Divider(height: 1, color: colors.border),
                      const SizedBox(height: 14),
                      for (final entry in setsByCategory.entries) ...[
                        _StrengthRow(
                          label: entry.key,
                          value: entry.value,
                          goal: widget.strengthGoals[entry.key]!,
                        ),
                        if (entry.key != setsByCategory.keys.last)
                          const SizedBox(height: 11),
                      ],
                    ],
                    if (workoutsSnapshot.hasError ||
                        metricsSnapshot.hasError) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Some of this week’s activity could not be loaded.',
                        style: TextStyle(fontSize: 12, color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _WeekDayBar extends StatelessWidget {
  const _WeekDayBar({
    required this.letter,
    required this.fraction,
    required this.isToday,
    required this.workout,
  });

  final String letter;
  final double fraction;
  final bool isToday, workout;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Container(
        width: 16,
        height: math.max(4, fraction * 60),
        decoration: BoxDecoration(
          color: fraction == 0
              ? context.vivordoColors.input
              : _purple.withValues(alpha: isToday ? 1 : .55),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        letter,
        style: TextStyle(
          fontSize: 11,
          color: isToday ? _purple : _muted,
          fontWeight: isToday ? FontWeight.w800 : null,
        ),
      ),
      const SizedBox(height: 3),
      Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: workout ? _purple : Colors.transparent,
          shape: BoxShape.circle,
        ),
      ),
    ],
  );
}

/// Shown on the screen underneath, since the caller is about to close.
void _showSavedOffline(BuildContext context, String what) => showToast(
  context,
  "$what saved. It'll sync when you're online.",
  kind: ToastKind.offline,
);

enum _RecentFilter {
  all('All'),
  workouts('Workouts'),
  logged('Logged');

  const _RecentFilter(this.label);
  final String label;
}

/// Tracked workouts and logged activities in one newest-first list. The
/// Fitness screen shows the latest three; "See all" opens the full list.
class _RecentFeed extends StatefulWidget {
  const _RecentFeed({this.full = false});

  final bool full;

  @override
  State<_RecentFeed> createState() => _RecentFeedState();
}

class _RecentFeedState extends State<_RecentFeed> {
  static const _previewCount = 3;
  // ponytail: "See all" lists the newest 200 logged activities; page the
  // query if anyone logs more than that.
  static const _fullActivityLimit = 200;

  var _filter = _RecentFilter.all;
  late final Stream<List<SavedWorkout>> _workouts = widget.full
      ? WorkoutService.watchAll()
      : WorkoutService.watchRecent(limit: _previewCount);
  late final Stream<List<RecentActivity>> _activities =
      RecentActivityService.watch(
        limit: widget.full ? _fullActivityLimit : _previewCount,
      );

  @override
  Widget build(BuildContext context) {
    final chips = Wrap(
      spacing: 8,
      children: [
        for (final filter in _RecentFilter.values)
          ChoiceChip(
            label: Text(filter.label),
            selected: _filter == filter,
            showCheckmark: false,
            selectedColor: _purple,
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _filter == filter ? Colors.white : _muted,
            ),
            side: BorderSide(color: context.vivordoColors.border),
            shape: const StadiumBorder(),
            onSelected: (_) => setState(() => _filter = filter),
          ),
      ],
    );

    final feed = VisibleStreamBuilder<List<SavedWorkout>>(
      stream: _workouts,
      builder: (context, workouts) =>
          VisibleStreamBuilder<List<RecentActivity>>(
            stream: _activities,
            builder: (context, activities) {
              if ((workouts.connectionState == ConnectionState.waiting &&
                      !workouts.hasData) ||
                  (activities.connectionState == ConnectionState.waiting &&
                      !activities.hasData)) {
                return const _Card(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final entries = <({DateTime at, Widget row})>[
                if (_filter != _RecentFilter.logged)
                  for (final workout in workouts.data ?? const <SavedWorkout>[])
                    (
                      at: workout.completedAt,
                      row: _RecentWorkoutRow(workout: workout),
                    ),
                if (_filter != _RecentFilter.workouts)
                  for (final activity
                      in activities.data ?? const <RecentActivity>[])
                    (
                      at: activity.day,
                      row: _RecentActivityRow(activity: activity),
                    ),
              ]..sort((a, b) => b.at.compareTo(a.at));
              final rows = widget.full
                  ? entries
                  : entries.take(_previewCount).toList();
              final failed = workouts.hasError || activities.hasError;

              if (rows.isEmpty) {
                return _Card(
                  child: Center(
                    child: Text(
                      failed
                          ? 'Could not load your recent activity.'
                          : switch (_filter) {
                              _RecentFilter.all =>
                                'No workouts or activities yet.',
                              _RecentFilter.workouts =>
                                'No workouts completed yet.',
                              _RecentFilter.logged =>
                                'No activities logged yet.',
                            },
                      style: const TextStyle(color: _muted),
                    ),
                  ),
                );
              }
              if (widget.full) {
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 40),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _Card(child: rows[index].row),
                );
              }
              return _Card(
                child: Column(
                  children: [
                    for (var index = 0; index < rows.length; index++) ...[
                      rows[index].row,
                      if (index < rows.length - 1) const Divider(),
                    ],
                  ],
                ),
              );
            },
          ),
    );

    if (widget.full) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            chips,
            const SizedBox(height: 12),
            Expanded(child: feed),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          'RECENT',
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _AllActivityScreen()),
            ),
            child: const Text('See all'),
          ),
        ),
        chips,
        const SizedBox(height: 8),
        feed,
      ],
    );
  }
}

class _AllActivityScreen extends StatelessWidget {
  const _AllActivityScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    appBar: AppBar(
      backgroundColor: context.vivordoColors.page,
      elevation: 0,
      title: const Text(
        'All Activity',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      centerTitle: true,
    ),
    body: const _RecentFeed(full: true),
  );
}

class _BodyCard extends StatefulWidget {
  const _BodyCard(this.recentDays);

  final Stream<QuerySnapshot<Map<String, dynamic>>> recentDays;

  @override
  State<_BodyCard> createState() => _BodyCardState();
}

class _BodyCardState extends State<_BodyCard> {
  late final Stream<PersonalProfile> _profile = PersonalProfileService.watch();

  static double? _latestMetric(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String key,
  ) {
    for (final doc in docs) {
      final value = ((doc.data()[key] as Map?)?['avg'] as num?)?.toDouble();
      if (value != null) return value;
    }
    return null;
  }

  static String _number(double? value) {
    if (value == null) return '--';
    return value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  }

  static String _updatedLabel(DateTime? updatedAt) {
    if (updatedAt == null) return 'Add your measurements';
    final local = updatedAt.toLocal();
    if (DateUtils.isSameDay(local, DateTime.now())) return 'Updated today';
    return 'Updated ${DateFormat('MMM d').format(local)}';
  }

  @override
  Widget build(BuildContext context) => VisibleStreamBuilder<PersonalProfile>(
    stream: _profile,
    initialData: const PersonalProfile(),
    builder: (context, profileSnapshot) =>
        VisibleStreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.recentDays,
          builder: (context, metricsSnapshot) {
            final profile = profileSnapshot.data ?? const PersonalProfile();
            final docs = metricsSnapshot.data?.docs ?? const [];
            final height = profile.heightCm;
            final weight = profile.weightKg ?? _latestMetric(docs, 'weight');
            final bodyFat =
                profile.bodyFatPercent ?? _latestMetric(docs, 'body_fat');
            final bmi = height != null && height > 0 && weight != null
                ? weight / math.pow(height / 100, 2)
                : null;
            final hasValues =
                height != null || weight != null || bodyFat != null;
            final updatedAt = !hasValues
                ? null
                : profile.updatedAt ??
                      (docs.isEmpty ? null : DateTime.tryParse(docs.first.id));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeader(
                  'BODY',
                  trailing: _SectionNote(_updatedLabel(updatedAt)),
                ),
                const SizedBox(height: 6),
                Material(
                  color: context.vivordoColors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: context.vivordoColors.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    splashColor: _purple.withValues(alpha: .10),
                    highlightColor: _purple.withValues(alpha: .055),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PersonalProfileScreen(),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ProfileMetric(
                              label: 'WEIGHT',
                              value: weight == null
                                  ? '--'
                                  : '${_number(weight * 2.2046226218)} lbs',
                            ),
                          ),
                          const _ProfileDivider(),
                          Expanded(
                            child: _ProfileMetric(
                              label: 'BMI',
                              value: _number(bmi),
                            ),
                          ),
                          const _ProfileDivider(),
                          Expanded(
                            child: _ProfileMetric(
                              label: 'BODY FAT',
                              value: bodyFat == null
                                  ? '--'
                                  : '${_number(bodyFat)}%',
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: _muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
  );
}

class _RecentWorkoutRow extends StatelessWidget {
  const _RecentWorkoutRow({required this.workout});

  final SavedWorkout workout;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _recentDayLabel(workout.completedAt);
    final durationLabel = _durationLabel(workout.durationSeconds);
    final visual = workoutActivityVisual(
      workout.displayName,
      category: workout.displayCategory,
    );

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showSummary(context),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _IconBox(icon: visual.icon, color: visual.color),
          title: Text(
            workout.displayName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            [
              dateLabel,
              durationLabel,
              if (workout.setCount > 0) '${workout.setCount} sets',
              if (workout.primaryCardioOrSportExercise?.distanceKm
                  case final km? when km > 0)
                '${km.toStringAsFixed(1)} km',
            ].join(' · '),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, color: _muted),
        ),
      ),
    );
  }

  String _durationLabel(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes == 0) return '${remainingSeconds}s';
    if (remainingSeconds == 0) return '${minutes}m';
    return '${minutes}m ${remainingSeconds}s';
  }

  Future<void> _showSummary(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutSummaryScreen(workout: workout),
      ),
    );
  }
}

String _recentDayLabel(DateTime date) {
  final today = DateUtils.dateOnly(DateTime.now());
  final day = DateUtils.dateOnly(date.toLocal());
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat(
    day.year == today.year ? 'EEE, MMM d' : 'MMM d, y',
  ).format(day);
}

class _RecentActivityRow extends StatelessWidget {
  const _RecentActivityRow({required this.activity});

  final RecentActivity activity;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      '${_recentDayLabel(activity.day)} · ${activity.minutes} min',
    ];
    if (activity.km != null) {
      details.add('${activity.km!.toStringAsFixed(1)} km');
    }
    if (activity.sets != null) details.add('${activity.sets} sets');
    final hasSets = activity.sets != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _IconBox(
        icon: hasSets
            ? Icons.fitness_center_rounded
            : Icons.directions_run_rounded,
        color: hasSets ? _purple : const Color(0xFF22B879),
      ),
      title: Text(
        activity.name,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(details.join(' · ')),
    );
  }
}

class _LogActivityDialog extends StatefulWidget {
  const _LogActivityDialog();

  @override
  State<_LogActivityDialog> createState() => _LogActivityDialogState();
}

class _LogActivityDialogState extends State<_LogActivityDialog> {
  final _name = TextEditingController();
  final _minutes = TextEditingController();
  final _km = TextEditingController();
  final _sets = TextEditingController();
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _minutes.dispose();
    _km.dispose();
    _sets.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text;
    final kmText = _km.text;
    final setsText = _sets.text;
    final minutes = int.tryParse(_minutes.text);
    final km = kmText.trim().isEmpty ? null : double.tryParse(kmText);
    final sets = setsText.trim().isEmpty ? null : int.tryParse(setsText);
    if (name.trim().isEmpty || minutes == null || minutes <= 0) {
      setState(() => _error = 'Enter a name and valid number of minutes.');
      return;
    }
    if ((kmText.trim().isNotEmpty && km == null) ||
        (setsText.trim().isNotEmpty && sets == null)) {
      setState(() => _error = 'Enter valid numbers for kilometres and sets.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final synced = await RecentActivityService.add(
        name: name,
        minutes: minutes,
        day: _day,
        km: km,
        sets: sets,
      );
      if (!mounted) return;
      if (synced) {
        showToast(context, 'Activity saved.', kind: ToastKind.success);
      } else {
        _showSavedOffline(context, 'Activity');
      }
      Navigator.pop(context, true);
    } catch (error) {
      debugPrint('Could not save activity: $error');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Couldn't save the activity. Try again.";
      });
    }
  }

  Future<void> _pickDay() async {
    final picked = await showVivordoDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) => AppleFormSheet(
    title: 'Log activity',
    doneLabel: 'Add',
    busy: _saving,
    onDone: _save,
    onCancel: () => Navigator.pop(context, false),
    children: [
      AppleFormGroup(
        footer: "Counts toward today's Exercise ring.",
        children: [
          AppleFormTextRow(
            label: 'Activity',
            controller: _name,
            placeholder: 'e.g. Tennis',
            autofocus: true,
            textCapitalization: TextCapitalization.words,
          ),
          AppleFormTextRow(
            label: 'Duration',
            controller: _minutes,
            placeholder: 'Minutes',
            keyboardType: TextInputType.number,
          ),
          AppleFormRow(
            label: 'Date',
            onTap: _pickDay,
            trailing: AppleValuePill(DateFormat('MMM d, y').format(_day)),
          ),
        ],
      ),
      AppleFormGroup(
        header: 'Optional',
        children: [
          AppleFormTextRow(
            label: 'Distance',
            controller: _km,
            placeholder: 'km',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          AppleFormTextRow(
            label: 'Sets',
            controller: _sets,
            placeholder: 'Count',
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            _error!,
            style: const TextStyle(color: appleRed, fontSize: 13),
          ),
        ),
    ],
  );
}

class FitnessGoalsScreen extends StatefulWidget {
  final Map<String, int> strengthGoals;
  const FitnessGoalsScreen({super.key, required this.strengthGoals});
  @override
  State<FitnessGoalsScreen> createState() => _FitnessGoalsScreenState();
}

class _FitnessGoalsScreenState extends State<FitnessGoalsScreen> {
  final Map<String, int> activity = {
    'Steps': 10000,
    'Active Calories': 700,
    'Exercise': 40,
    'Workouts': 4,
  };

  @override
  void initState() {
    super.initState();
    _loadActivityGoals();
    _loadStrengthGoals();
  }

  Future<void> _loadActivityGoals() async {
    final goals = await ActivityGoalsService.load();
    if (!mounted) return;
    setState(() {
      activity['Steps'] = goals.steps;
      activity['Active Calories'] = goals.activeCalories;
      activity['Exercise'] = goals.exerciseMinutes;
      activity['Workouts'] = goals.workoutsPerWeek;
    });
  }

  Future<void> _loadStrengthGoals() async {
    final goals = await ActivityGoalsService.loadStrengthGoals();
    if (!mounted) return;
    setState(() {
      widget.strengthGoals
        ..clear()
        ..addAll(goals);
    });
  }

  Future<void> _saveActivityGoals() => ActivityGoalsService.save(
    ActivityGoals(
      steps: activity['Steps']!,
      activeCalories: activity['Active Calories']!,
      exerciseMinutes: activity['Exercise']!,
      workoutsPerWeek: activity['Workouts']!,
    ),
  );

  Future<void> _edit(Map<String, int> target, String key, String unit) async {
    final editingActivityGoal = identical(target, activity);
    final controller = TextEditingController(text: '${target[key]}');
    final value = await showAppleSheet<int>(
      context,
      builder: (sheetContext) => AppleFormSheet(
        title: '$key goal',
        doneLabel: 'Save',
        onDone: () =>
            Navigator.pop(sheetContext, int.tryParse(controller.text)),
        children: [
          AppleFormGroup(
            children: [
              AppleFormTextRow(
                label: '${unit[0].toUpperCase()}${unit.substring(1)}',
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ],
      ),
    );
    // Not disposed: the sheet's field is still animating out.
    if (value == null || value <= 0) return;
    setState(() => target[key] = value);
    try {
      if (editingActivityGoal) {
        await _saveActivityGoals();
      } else {
        await ActivityGoalsService.saveStrengthGoals(widget.strengthGoals);
      }
    } catch (error) {
      debugPrint('Could not save goal: $error');
      if (!mounted) return;
      showToast(
        context,
        "Couldn't save the goal. Try again.",
        kind: ToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    appBar: AppBar(
      backgroundColor: context.vivordoColors.page,
      elevation: 0,
      title: const Text(
        'Fitness Goals',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      centerTitle: true,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7667F4), Color(0xFF5845DF)],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.track_changes_rounded, color: Colors.white, size: 32),
              SizedBox(height: 12),
              Text(
                'Build consistency',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Set goals that fit your routine. You can adjust them anytime.',
                style: TextStyle(color: Color(0xFFE4DFFF)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (final item in activity.entries) ...[
          _GoalTile(
            label: item.key,
            value: item.value,
            unit: {
              'Steps': 'steps / day',
              'Active Calories': 'calories / day',
              'Exercise': 'minutes / day',
              'Workouts': 'sessions / week',
            }[item.key]!,
            onEdit: () => _edit(
              activity,
              item.key,
              item.key == 'Workouts' ? 'sessions' : 'daily',
            ),
          ),
          const SizedBox(height: 9),
        ],
        const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 9),
          child: Text(
            'WEEKLY STRENGTH GOALS',
            style: TextStyle(
              fontSize: 12,
              color: _muted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ),
        for (final item in widget.strengthGoals.entries) ...[
          _GoalTile(
            label: item.key,
            value: item.value,
            unit: 'sets / week',
            onEdit: () => _edit(widget.strengthGoals, item.key, 'sets'),
          ),
          const SizedBox(height: 9),
        ],
      ],
    ),
  );
}

class ActiveWorkoutScreen extends StatefulWidget {
  const ActiveWorkoutScreen({super.key});
  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

_ActiveWorkoutDraft? _activeWorkoutDraft;

/// Restores the persisted workout before a Live Activity deep link opens the
/// workout route. This prevents [ActiveWorkoutScreen] from creating a blank
/// draft while the app is launching from a terminated state.
Future<bool> prepareActiveWorkoutForLaunch({
  bool createIfMissing = false,
}) async {
  final restored =
      _activeWorkoutDraft ??
      await _ActiveWorkoutDraft.restore() ??
      (createIfMissing ? await _ActiveWorkoutDraft.fresh() : null);
  if (restored == null) return false;
  _activeWorkoutDraft = restored;
  if (createIfMissing) await restored.persist();
  FitnessWorkoutTimerState.start(
    startedAt: restored.startedAt,
    title: restored.liveActivityTitle,
    exerciseCount: restored.exercises.length,
  );
  return true;
}

class _WorkoutButtonLabel extends StatefulWidget {
  const _WorkoutButtonLabel({required this.draft});

  final _ActiveWorkoutDraft? draft;

  @override
  State<_WorkoutButtonLabel> createState() => _WorkoutButtonLabelState();
}

class _WorkoutButtonLabelState extends State<_WorkoutButtonLabel> {
  Timer? timer;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _updateTimer();
  }

  @override
  void didUpdateWidget(covariant _WorkoutButtonLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft) _updateTimer();
  }

  void _updateTimer() {
    timer?.cancel();
    timer = !_visible || widget.draft == null
        ? null
        : Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    const style = TextStyle(fontWeight: FontWeight.w800);
    if (draft == null) return const Text('Start workout', style: style);
    final totalSeconds = DateTime.now().difference(draft.startedAt).inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return Text(
      'Resume · ${hours > 0 ? '$hours:' : ''}$minutes:$seconds',
      style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

class _ActiveWorkoutDraft {
  _ActiveWorkoutDraft({DateTime? startedAt, this.shareToCircle = false})
    : startedAt = startedAt ?? DateTime.now();

  final DateTime startedAt;
  final List<_WorkoutExercise> exercises = [];
  bool shareToCircle;

  String get liveActivityTitle =>
      exercises.isEmpty ? 'Workout' : exercises.first.name;

  Map<String, dynamic> toJson() => {
    'startedAt': startedAt.toUtc().toIso8601String(),
    'shareToCircle': shareToCircle,
    'exercises': exercises.map((exercise) => exercise.toJson()).toList(),
  };

  Future<void> persist() => ActiveWorkoutStorage.write(toJson());

  /// A new workout that starts with the user's last sharing choice.
  static Future<_ActiveWorkoutDraft> fresh() async => _ActiveWorkoutDraft(
    shareToCircle: await ActiveWorkoutStorage.readShareDefault(),
  );

  static Future<_ActiveWorkoutDraft?> restore() async {
    final json = await ActiveWorkoutStorage.read();
    if (json == null) return null;
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    if (startedAt == null) {
      await ActiveWorkoutStorage.clear();
      return null;
    }
    final draft = _ActiveWorkoutDraft(
      startedAt: startedAt.toLocal(),
      shareToCircle: json['shareToCircle'] as bool? ?? false,
    );
    final savedExercises = json['exercises'];
    if (savedExercises is List) {
      draft.exercises.addAll(
        savedExercises.whereType<Map>().map(
          (value) =>
              _WorkoutExercise.fromJson(Map<String, dynamic>.from(value)),
        ),
      );
    }
    return draft;
  }
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  Route<dynamic>? _registeredRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registeredRoute = ModalRoute.of(context);
    ActiveWorkoutNavigation.register(context);
  }

  Timer? timer;
  late final _ActiveWorkoutDraft draft;
  bool saving = false;
  bool savingTemplate = false;
  bool refreshingDistance = false;
  double? trackedDistanceKm;
  final _distanceDisplay = ValueNotifier<({double? km, bool loading})>((
    km: null,
    loading: false,
  ));
  final _setCount = ValueNotifier<int>(0);

  void _updateSetCount() {
    // Cardio and sports exercises keep placeholder sets that are never shown
    // or saved, so only count sets on strength exercises.
    _setCount.value = exercises.fold<int>(
      0,
      (total, exercise) =>
          exercise.isDistanceExercise || exercise.isSportsExercise
          ? total
          : total + exercise.sets.length,
    );
  }

  DateTime? lastDistanceRefresh;

  DateTime get startedAt => draft.startedAt;
  List<_WorkoutExercise> get exercises => draft.exercises;
  int get seconds => DateTime.now().difference(startedAt).inSeconds;

  Future<void> _toggleCircleSharing() async {
    setState(() => draft.shareToCircle = !draft.shareToCircle);
    await Future.wait([
      draft.persist(),
      ActiveWorkoutStorage.writeShareDefault(draft.shareToCircle),
    ]);
  }

  @override
  void initState() {
    super.initState();
    draft = _activeWorkoutDraft ??= _ActiveWorkoutDraft();
    _updateSetCount();
    FitnessWorkoutTimerState.start(
      startedAt: draft.startedAt,
      title: draft.liveActivityTitle,
      exerciseCount: draft.exercises.length,
    );
    // The elapsed clock ticks inside _WorkoutElapsedLabel so this timer only
    // drives the distance refresh, which is already gated to 15s intervals.
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_hasCardioExercise &&
          !refreshingDistance &&
          (lastDistanceRefresh == null ||
              DateTime.now().difference(lastDistanceRefresh!).inSeconds >=
                  15)) {
        unawaited(_refreshTrackedDistance());
      }
    });
    unawaited(draft.persist());
    unawaited(_restorePreviousSets());
    if (_hasCardioExercise) unawaited(_refreshTrackedDistance());
  }

  Future<void> _restorePreviousSets() async {
    final missing = exercises.where((e) => !e.historyLoaded).toList();
    if (missing.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final history = await WorkoutService.loadLatestExerciseSets(
        missing.map((e) => e.name),
      );
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != uid) return;
      setState(() {
        for (final exercise in missing) {
          if (!exercises.contains(exercise) || exercise.historyLoaded) continue;
          exercise.applyHistory(
            history[exercise.name.trim().toLowerCase()] ?? [],
          );
        }
      });
      await draft.persist();
    } catch (error) {
      debugPrint('Could not restore previous exercise sets: $error');
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    ActiveWorkoutNavigation.unregister(_registeredRoute);
    _distanceDisplay.dispose();
    _setCount.dispose();
    super.dispose();
  }

  bool get _hasCardioExercise =>
      exercises.any((exercise) => exercise.isDistanceExercise);

  Future<double?> _refreshTrackedDistance({bool force = false}) async {
    if (!_hasCardioExercise || refreshingDistance) return trackedDistanceKm;
    if (!force &&
        lastDistanceRefresh != null &&
        DateTime.now().difference(lastDistanceRefresh!).inSeconds < 15) {
      return trackedDistanceKm;
    }

    refreshingDistance = true;
    if (mounted) {
      _distanceDisplay.value = (km: trackedDistanceKm, loading: true);
    }
    try {
      final distance = await HealthService().readWalkingRunningDistanceKm(
        start: startedAt,
      );
      if (distance != null) trackedDistanceKm = distance;
    } finally {
      lastDistanceRefresh = DateTime.now();
      refreshingDistance = false;
      if (mounted) {
        _distanceDisplay.value = (km: trackedDistanceKm, loading: false);
      }
    }
    return trackedDistanceKm;
  }

  Future<void> _addExercises() async {
    final selected = await Navigator.of(context)
        .push<List<_ExerciseDefinition>>(
          MaterialPageRoute(
            builder: (_) => _AddExerciseScreen(
              initiallySelected: exercises
                  .map((exercise) => exercise.definition)
                  .toList(),
            ),
          ),
        );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _applyExerciseSelection(selected, replaceCurrent: true);
  }

  Future<void> _applyExerciseSelection(
    List<_ExerciseDefinition> selected, {
    required bool replaceCurrent,
  }) async {
    final newDefinitions = selected
        .where(
          (definition) =>
              !exercises.any((exercise) => exercise.name == definition.name) &&
              definition.category != 'Cardio' &&
              definition.category != 'Sports',
        )
        .toList(growable: false);

    // Reflect the selection immediately. Loading previous sets is a helpful
    // enhancement, but it must never block or prevent adding an exercise.
    setState(() {
      final existing = {
        for (final exercise in exercises) exercise.name: exercise,
      };
      final updated = replaceCurrent
          ? selected
                .map(
                  (definition) =>
                      existing[definition.name] ?? _WorkoutExercise(definition),
                )
                .toList()
          : [
              ...selected
                  .where((definition) => !existing.containsKey(definition.name))
                  .map(_WorkoutExercise.new),
              ...exercises,
            ];
      exercises
        ..clear()
        ..addAll(updated);
      _updateSetCount();
    });
    await draft.persist();
    FitnessWorkoutTimerState.update(
      title: draft.liveActivityTitle,
      exerciseCount: exercises.length,
    );

    if (_hasCardioExercise) unawaited(_refreshTrackedDistance(force: true));

    if (newDefinitions.isEmpty) return;
    try {
      final previousSets = await WorkoutService.loadLatestExerciseSets(
        newDefinitions.map((definition) => definition.name),
      );
      if (!mounted) return;
      setState(() {
        for (final exercise in exercises) {
          final saved = previousSets[exercise.name.trim().toLowerCase()];
          if (!newDefinitions.any((d) => d.name == exercise.name)) continue;
          exercise.applyHistory(saved ?? []);
        }
      });
      await draft.persist();
    } catch (error) {
      debugPrint('Could not load previous exercise sets: $error');
    }
  }

  Future<void> _saveWorkoutTemplate() async {
    if (exercises.isEmpty) {
      showToast(context, 'Add at least one exercise first.');
      return;
    }
    // Not disposed: the alert's field is still animating out.
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        void save() {
          final value = controller.text;
          if (value.trim().isEmpty) return;
          // The old field capped names at 40 characters.
          Navigator.pop(
            dialogContext,
            value.length > 40 ? value.substring(0, 40) : value,
          );
        }

        return AppleAlert(
          title: 'Save workout',
          message: 'Name it so you can start it again later.',
          content: AppleAlertField(
            controller: controller,
            placeholder: 'e.g. Push Day',
          ),
          buttons: [
            AppleAlertButton(
              'Cancel',
              onPressed: () => Navigator.pop(dialogContext),
            ),
            AppleAlertButton('Save', bold: true, onPressed: save),
          ],
        );
      },
    );
    if (name == null || !mounted) return;

    setState(() => savingTemplate = true);
    try {
      await WorkoutService.saveTemplate(
        name: name,
        exercises: exercises
            .map(
              (exercise) => WorkoutTemplateExercise(
                name: exercise.name,
                category: exercise.definition.category,
              ),
            )
            .toList(growable: false),
      );
      if (!mounted) return;
      showToast(context, '$name saved.', kind: ToastKind.success);
    } catch (error) {
      debugPrint('Could not save workout template: $error');
      if (!mounted) return;
      showToast(
        context,
        "Couldn't save the workout. Try again.",
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => savingTemplate = false);
    }
  }

  Future<void> _addSavedWorkout() async {
    final template = await Navigator.of(context).push<WorkoutTemplate>(
      MaterialPageRoute(builder: (_) => const _SavedWorkoutsScreen()),
    );
    if (template == null || !mounted) return;
    await _applyExerciseSelection(
      template.exercises
          .map(
            (exercise) => _ExerciseDefinition(
              name: exercise.name,
              category: exercise.category,
            ),
          )
          .toList(growable: false),
      replaceCurrent: false,
    );
  }

  Future<void> _finishWorkout() async {
    if (exercises.isEmpty) {
      showToast(context, 'Add at least one exercise first.');
      return;
    }

    final finalTrackedDistance = _hasCardioExercise
        ? await _refreshTrackedDistance(force: true)
        : null;
    if (!mounted) return;
    var assignedTrackedDistance = false;
    final records = <WorkoutExerciseRecord>[];
    for (final exercise in exercises) {
      if (exercise.isSportsExercise) {
        records.add(
          WorkoutExerciseRecord(
            name: exercise.definition.name,
            category: exercise.definition.category,
            sets: const [],
          ),
        );
        continue;
      }
      if (exercise.isDistanceExercise) {
        final distance =
            !assignedTrackedDistance &&
                finalTrackedDistance != null &&
                finalTrackedDistance > 0
            ? finalTrackedDistance
            : null;
        assignedTrackedDistance = true;
        records.add(
          WorkoutExerciseRecord(
            name: exercise.definition.name,
            category: exercise.definition.category,
            sets: const [],
            distanceKm: distance,
          ),
        );
        continue;
      }
      final sets = <WorkoutSetRecord>[];
      for (final set in exercise.sets) {
        final weight = double.tryParse(set.lbs);
        final reps = int.tryParse(set.reps);
        if (weight == null || weight < 0 || reps == null || reps <= 0) {
          showToast(
            context,
            'Enter a valid weight and reps for every ${exercise.name} set.',
          );
          return;
        }
        sets.add(WorkoutSetRecord(weightLbs: weight, reps: reps));
      }
      records.add(
        WorkoutExerciseRecord(
          name: exercise.definition.name,
          category: exercise.definition.category,
          sets: sets,
        ),
      );
    }

    setState(() => saving = true);
    try {
      final saved = await WorkoutService.save(
        startedAt: startedAt,
        durationSeconds: seconds,
        exercises: records,
        shareToCircle: draft.shareToCircle,
      );
      timer?.cancel();
      _activeWorkoutDraft = null;
      await ActiveWorkoutStorage.clear();
      FitnessWorkoutTimerState.stop();
      if (!mounted) return;
      if (!saved.synced) _showSavedOffline(context, 'Workout');
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      debugPrint('Could not save workout: $error');
      setState(() => saving = false);
      showToast(
        context,
        "Couldn't save the workout. Try again.",
        kind: ToastKind.error,
      );
    }
  }

  Future<void> _cancelWorkout() async {
    final cancel = await confirmAction(
      context,
      title: 'Cancel workout?',
      message: 'This discards the workout and everything entered in it.',
      cancelLabel: 'Keep workout',
      confirmLabel: 'Cancel workout',
    );
    if (!cancel || !mounted) return;
    timer?.cancel();
    _activeWorkoutDraft = null;
    await ActiveWorkoutStorage.clear();
    if (!mounted) return;
    FitnessWorkoutTimerState.stop();
    Navigator.pop(context, false);
  }

  String get _title {
    for (final exercise in exercises) {
      final category = exercise.definition.category;
      if (category == 'Cardio' || category == 'Sports') {
        return exercise.name;
      }
    }
    return exercises.isEmpty ? 'New workout' : 'Strength workout';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final busy = saving || savingTemplate;
    return Scaffold(
      backgroundColor: colors.page,
      appBar: AppBar(
        backgroundColor: colors.page,
        elevation: 0,
        title: Text(
          _title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          if (busy)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IosPullDownMenu<String>(
              tooltip: 'Workout actions',
              onSelected: (action) => switch (action) {
                'template' => _saveWorkoutTemplate(),
                _ => _cancelWorkout(),
              },
              actions: const [
                IosMenuAction(
                  value: 'template',
                  label: 'Save as template',
                  icon: CupertinoIcons.bookmark,
                ),
                IosMenuAction(
                  value: 'cancel',
                  label: 'Cancel workout',
                  icon: CupertinoIcons.trash,
                  destructive: true,
                ),
              ],
            ),
          const SizedBox(width: 6),
        ],
      ),
      // Counts as part of the set fields, so adjusting rest while typing a
      // weight or reps keeps the keyboard up; any other tap still closes it.
      bottomNavigationBar: TextFieldTapRegion(
        child: WorkoutRestTimer(
          onDeadlineChanged: (deadline) =>
              NotificationService().updateRestTimerNotification(deadline),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFFAA91FF).withValues(alpha: .6),
              ),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF5844ED), Color(0xFF3529AD)],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '●  IN PROGRESS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          color: Color(0xFFE8E0FF),
                        ),
                      ),
                      DefaultTextStyle.merge(
                        style: const TextStyle(color: Colors.white),
                        child: _WorkoutElapsedLabel(startedAt: startedAt),
                      ),
                      ValueListenableBuilder<int>(
                        valueListenable: _setCount,
                        builder: (_, totalSets, _) => Text(
                          '${exercises.length} ${exercises.length == 1 ? 'exercise' : 'exercises'}'
                          '${totalSets == 0 ? '' : ' · $totalSets ${totalSets == 1 ? 'set' : 'sets'}'}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFF1ECFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: busy ? null : _finishWorkout,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF4B3BD9),
                    disabledBackgroundColor: Colors.white.withValues(alpha: .7),
                    minimumSize: const Size(96, 48),
                    shape: const StadiumBorder(),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Finish',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    CupertinoIcons.person_2_fill,
                    color: _purple,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share to Circle',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        draft.shareToCircle
                            ? 'Your Circle can see this workout'
                            : 'Private to you',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: 'Share to Circle',
                  child: CupertinoSwitch(
                    value: draft.shareToCircle,
                    activeTrackColor: _purple,
                    onChanged: busy ? null : (_) => _toggleCircleSharing(),
                  ),
                ),
              ],
            ),
          ),
          if (exercises.isNotEmpty) ...[
            const SizedBox(height: 6),
            const _SectionHeader('EXERCISES'),
            const SizedBox(height: 4),
          ],
          for (final exercise in exercises) ...[
            _WorkoutExerciseCard(
              key: ObjectKey(exercise),
              exercise: exercise,
              distanceDisplay: _distanceDisplay,
              onChanged: () {
                _updateSetCount();
                unawaited(draft.persist());
              },
              onRemove: () {
                setState(() => exercises.remove(exercise));
                _updateSetCount();
                unawaited(draft.persist());
                FitnessWorkoutTimerState.update(
                  title: draft.liveActivityTitle,
                  exerciseCount: exercises.length,
                );
              },
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _addExercises,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add exercise',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _addSavedWorkout,
            style: TextButton.styleFrom(foregroundColor: _purple),
            icon: const Icon(Icons.playlist_add_rounded),
            label: const Text(
              'Add saved workout',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ticks the workout clock in isolation so the surrounding exercise list does
/// not rebuild once per second.
class _WorkoutElapsedLabel extends StatefulWidget {
  const _WorkoutElapsedLabel({required this.startedAt});

  final DateTime startedAt;

  @override
  State<_WorkoutElapsedLabel> createState() => _WorkoutElapsedLabelState();
}

class _WorkoutElapsedLabelState extends State<_WorkoutElapsedLabel> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = DateTime.now().difference(widget.startedAt).inSeconds;
    final elapsed =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Text(
      elapsed,
      style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800),
    );
  }
}

class _SavedWorkoutsScreen extends StatefulWidget {
  const _SavedWorkoutsScreen();

  @override
  State<_SavedWorkoutsScreen> createState() => _SavedWorkoutsScreenState();
}

class _SavedWorkoutsScreenState extends State<_SavedWorkoutsScreen> {
  String _search = '';
  String? _selectedId;
  final Set<String> _deletingIds = {};

  Future<void> _deleteTemplate(WorkoutTemplate template) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete "${template.name}"?',
      message: "Workouts you've already completed stay in your history.",
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    setState(() => _deletingIds.add(template.id));
    try {
      await WorkoutService.deleteTemplate(template.id);
      if (!mounted) return;
      setState(() {
        _deletingIds.remove(template.id);
        if (_selectedId == template.id) _selectedId = null;
      });
      showToast(context, '${template.name} deleted.');
    } catch (error) {
      debugPrint('Could not delete workout template: $error');
      if (!mounted) return;
      setState(() => _deletingIds.remove(template.id));
      showToast(
        context,
        "Couldn't delete the workout. Try again.",
        kind: ToastKind.error,
      );
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => VisibleStreamBuilder<List<WorkoutTemplate>>(
    stream: WorkoutService.watchTemplates(),
    builder: (context, snapshot) {
      final query = _search.trim().toLowerCase();
      final templates = (snapshot.data ?? const <WorkoutTemplate>[])
          .where(
            (template) =>
                query.isEmpty ||
                template.name.toLowerCase().contains(query) ||
                template.exercises.any(
                  (exercise) => exercise.name.toLowerCase().contains(query),
                ),
          )
          .toList(growable: false);
      final selected = snapshot.data
          ?.where((template) => template.id == _selectedId)
          .firstOrNull;

      return Scaffold(
        backgroundColor: context.vivordoColors.page,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    Expanded(
                      child: Text(
                        'Add Workout',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: context.vivordoColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 64),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search saved workouts',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: context.vivordoColors.input,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: context.vivordoColors.border,
                      ),
                    ),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  children: [
                    const _PickerSectionTitle('SAVED WORKOUTS'),
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: CircularProgressIndicator(color: _purple),
                        ),
                      )
                    else if (templates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            query.isEmpty
                                ? 'No saved workouts yet.'
                                : 'No saved workouts found.',
                            style: const TextStyle(color: _muted),
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: context.vivordoColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: context.vivordoColors.border,
                          ),
                        ),
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < templates.length;
                              index++
                            ) ...[
                              _SavedWorkoutPickerRow(
                                template: templates[index],
                                selected: templates[index].id == _selectedId,
                                deleting: _deletingIds.contains(
                                  templates[index].id,
                                ),
                                onTap: () => setState(
                                  () => _selectedId =
                                      templates[index].id == _selectedId
                                      ? null
                                      : templates[index].id,
                                ),
                                onDelete: () =>
                                    _deleteTemplate(templates[index]),
                              ),
                              if (index < templates.length - 1)
                                const Divider(height: 1, indent: 72),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: BoxDecoration(
              color: context.vivordoColors.card,
              border: Border(
                top: BorderSide(color: context.vivordoColors.border),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selected == null
                      ? '0 workouts selected'
                      : '1 workout selected',
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: selected == null
                      ? null
                      : () => Navigator.pop(context, selected),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: _purple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Add to Workout',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SavedWorkoutPickerRow extends StatelessWidget {
  const _SavedWorkoutPickerRow({
    required this.template,
    required this.selected,
    required this.deleting,
    required this.onTap,
    required this.onDelete,
  });

  final WorkoutTemplate template;
  final bool selected;
  final bool deleting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? context.vivordoColors.cardMuted : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _purple.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.fitness_center_rounded, color: _purple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.vivordoColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${template.exercises.length} ${template.exercises.length == 1 ? 'exercise' : 'exercises'} · ${template.exercises.map((exercise) => exercise.name).join(', ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, height: 1.3),
                  ),
                ],
              ),
            ),
            if (deleting)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete saved workout',
                icon: const Icon(Icons.delete_outline_rounded),
                color: Colors.redAccent,
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? _purple : _muted,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ExerciseDefinition {
  const _ExerciseDefinition({required this.name, required this.category});

  final String name;
  final String category;
}

String _exerciseNameKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

String _compactWorkoutNumber(double value) =>
    value.toStringAsFixed(value % 1 == 0 ? 0 : 1);

class _WorkoutSet {
  _WorkoutSet({this.previous});

  WorkoutSetRecord? previous;
  String lbs = '';
  String reps = '';

  Map<String, dynamic> toJson() => {
    'lbs': lbs,
    'reps': reps,
    'previous': previous?.toMap(),
  };
}

WorkoutSetRecord? _previousSetFromJson(dynamic value) {
  if (value is! Map) return null;
  final weight = value['weightLbs'];
  final reps = value['reps'];
  if (weight is! num || reps is! num || !weight.isFinite || !reps.isFinite) {
    return null;
  }
  return WorkoutSetRecord(weightLbs: weight.toDouble(), reps: reps.toInt());
}

class _WorkoutExercise {
  _WorkoutExercise(
    this.definition, {
    List<WorkoutSetRecord> previousSets = const [],
  }) : previousSets = List.of(previousSets),
       sets = [
         _WorkoutSet(previous: previousSets.firstOrNull),
         _WorkoutSet(previous: previousSets.elementAtOrNull(1)),
       ];

  final _ExerciseDefinition definition;
  final List<WorkoutSetRecord> previousSets;
  bool historyLoaded = false;

  void applyHistory(List<WorkoutSetRecord> history) {
    previousSets
      ..clear()
      ..addAll(history);
    historyLoaded = true;
    for (var i = 0; i < sets.length; i++) {
      sets[i].previous ??= history.elementAtOrNull(i);
    }
  }

  final List<_WorkoutSet> sets;
  String distanceKm = '';

  String get name => definition.name;
  bool get isDistanceExercise => definition.category == 'Cardio';
  bool get isSportsExercise => definition.category == 'Sports';

  Map<String, dynamic> toJson() => {
    'name': definition.name,
    'category': definition.category,
    'distanceKm': distanceKm,
    'historyLoaded': historyLoaded,
    'previousSets': previousSets.map((s) => s.toMap()).toList(),
    'sets': sets.map((set) => set.toJson()).toList(),
  };

  factory _WorkoutExercise.fromJson(Map<String, dynamic> json) {
    final exercise = _WorkoutExercise(
      _ExerciseDefinition(
        name: json['name'] as String? ?? 'Exercise',
        category: json['category'] as String? ?? 'Other',
      ),
      previousSets: (json['previousSets'] as List? ?? [])
          .map(_previousSetFromJson)
          .whereType<WorkoutSetRecord>()
          .toList(),
    );
    exercise.historyLoaded = json['historyLoaded'] == true;
    exercise.distanceKm = json['distanceKm'] as String? ?? '';
    final savedSets = json['sets'];
    if (savedSets is List) {
      exercise.sets
        ..clear()
        ..addAll(
          savedSets.whereType<Map>().map((value) {
            final map = Map<String, dynamic>.from(value);
            final set = _WorkoutSet(
              previous: _previousSetFromJson(map['previous']),
            );
            set.lbs = map['lbs'] as String? ?? '';
            set.reps = map['reps'] as String? ?? '';
            return set;
          }),
        );
    }
    return exercise;
  }
}

/// Exercises the same draft codec used when resuming a workout.
@visibleForTesting
Map<String, dynamic> roundTripWorkoutExerciseForTesting(
  Map<String, dynamic> json, {
  List<WorkoutSetRecord>? recoveredHistory,
}) {
  final exercise = _WorkoutExercise.fromJson(json);
  if (recoveredHistory != null) exercise.applyHistory(recoveredHistory);
  return exercise.toJson();
}

/// Builds the production card without starting health/Firebase services.
@visibleForTesting
Widget workoutExerciseCardForTesting({
  required Map<String, dynamic> initialExercise,
  required ValueNotifier<({double? km, bool loading})> distance,
  required ValueChanged<Map<String, dynamic>> onChanged,
}) {
  final exercise = _WorkoutExercise.fromJson(initialExercise);
  return _WorkoutExerciseCard(
    key: ObjectKey(exercise),
    exercise: exercise,
    distanceDisplay: distance,
    onChanged: () => onChanged(exercise.toJson()),
    onRemove: () {},
  );
}

class _WorkoutExerciseCard extends StatefulWidget {
  const _WorkoutExerciseCard({
    super.key,
    required this.exercise,
    required this.distanceDisplay,
    required this.onChanged,
    required this.onRemove,
  });

  final _WorkoutExercise exercise;
  final ValueNotifier<({double? km, bool loading})> distanceDisplay;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_WorkoutExerciseCard> createState() => _WorkoutExerciseCardState();
}

class _WorkoutExerciseCardState extends State<_WorkoutExerciseCard> {
  _WorkoutExercise get exercise => widget.exercise;
  void onRemove() => widget.onRemove();
  void onChanged() {
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      children: [
        Row(
          children: [
            _ExerciseIcon(exercise: exercise.definition),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            IosPullDownMenu<String>(
              tooltip: 'Exercise actions',
              icon: CupertinoIcons.ellipsis,
              onSelected: (_) => onRemove(),
              actions: const [
                IosMenuAction(
                  value: 'remove',
                  label: 'Remove exercise',
                  icon: CupertinoIcons.minus_circle,
                  destructive: true,
                ),
              ],
            ),
          ],
        ),
        const Divider(height: 26),
        if (exercise.isSportsExercise)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: context.vivordoColors.cardMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.timer_outlined, color: _purple, size: 20),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Time is tracked by the workout timer.',
                    style: TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (exercise.isDistanceExercise)
          ValueListenableBuilder<({double? km, bool loading})>(
            valueListenable: widget.distanceDisplay,
            builder: (context, distance, _) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: context.vivordoColors.cardMuted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  if (distance.loading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.route_rounded, color: _purple, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          distance.km == null
                              ? 'Tracking distance automatically'
                              : '${distance.km!.toStringAsFixed(2)} km',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Using walking and running distance from Apple Health',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          const Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  'PREVIOUS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  'SET',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'LBS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'REPS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _muted,
                  ),
                ),
              ),
              SizedBox(width: 44),
            ],
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < exercise.sets.length; index++) ...[
            _WorkoutSetRow(
              key: ObjectKey(exercise.sets[index]),
              number: index + 1,
              set: exercise.sets[index],
              onChanged: onChanged,
              onRemove: () {
                exercise.sets.removeAt(index);
                onChanged();
              },
            ),
            if (index < exercise.sets.length - 1) const Divider(height: 14),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              final index = exercise.sets.length;
              exercise.sets.add(
                _WorkoutSet(
                  previous: exercise.previousSets.elementAtOrNull(index),
                ),
              );
              onChanged();
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Set'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              side: const BorderSide(color: _purple),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _WorkoutSetRow extends StatelessWidget {
  const _WorkoutSetRow({
    super.key,
    required this.number,
    required this.set,
    required this.onChanged,
    required this.onRemove,
  });

  final int number;
  final _WorkoutSet set;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 70,
        child: Text(
          set.previous == null
              ? '—'
              : '${_compactWorkoutNumber(set.previous!.weightLbs)} × ${set.previous!.reps}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ),
      SizedBox(
        width: 38,
        child: Text(
          '$number',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      Expanded(
        child: TextFormField(
          initialValue: set.lbs,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            set.lbs = value;
            onChanged();
          },
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onFieldSubmitted: (_) =>
              FocusManager.instance.primaryFocus?.unfocus(),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextFormField(
          initialValue: set.reps,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            set.reps = value;
            onChanged();
          },
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onFieldSubmitted: (_) =>
              FocusManager.instance.primaryFocus?.unfocus(),
        ),
      ),
      SizedBox(
        width: 44,
        child: IconButton(
          tooltip: 'Remove set',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, color: _muted),
        ),
      ),
    ],
  );
}

final List<_ExerciseDefinition> _exerciseLibrary = List.unmodifiable(
  workoutExerciseCatalog.map(
    (exercise) =>
        _ExerciseDefinition(name: exercise.name, category: exercise.category),
  ),
);

class _AddExerciseScreen extends StatefulWidget {
  const _AddExerciseScreen({this.initiallySelected = const []});

  final List<_ExerciseDefinition> initiallySelected;

  @override
  State<_AddExerciseScreen> createState() => _AddExerciseScreenState();
}

class _AddExerciseScreenState extends State<_AddExerciseScreen> {
  static const _filters = [
    'All',
    'Favourites',
    'Chest',
    'Back',
    'Shoulders',
    'Arms',
    'Legs',
    'Core',
    'Cardio',
    'Sports',
  ];

  late final Set<String> _selected;
  late final List<String> _selectedOrder;
  final List<_ExerciseDefinition> _customExercises = [];
  String _filter = 'All';
  String _search = '';
  final Set<String> _favourites = {};
  final Set<String> _savingFavourites = {};
  bool _favouritesLoaded = false;
  final String? _favouritesUid = FirebaseAuth.instance.currentUser?.uid;

  Future<void> _loadFavourites() async {
    try {
      if (_favouritesUid == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_favouritesUid)
          .get();
      if (!mounted) return;
      setState(() {
        _favourites.addAll(
          (doc.data()?['favouriteExercises'] as List? ?? [])
              .whereType<String>(),
        );
        _favouritesLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        "Couldn't load favourites. Reopen Add exercise to try again.",
        kind: ToastKind.error,
      );
    }
  }

  Future<void> _toggleFavourite(_ExerciseDefinition exercise) async {
    final key = _exerciseNameKey(exercise.name);
    if (!_favouritesLoaded ||
        _savingFavourites.contains(key) ||
        FirebaseAuth.instance.currentUser?.uid != _favouritesUid) {
      return;
    }
    final removing = _favourites.contains(key);
    setState(() {
      _savingFavourites.add(key);
      removing ? _favourites.remove(key) : _favourites.add(key);
    });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_favouritesUid)
          .update({
            'favouriteExercises': removing
                ? FieldValue.arrayRemove([key])
                : FieldValue.arrayUnion([key]),
          });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        removing ? _favourites.add(key) : _favourites.remove(key);
      });
      showToast(
        context,
        "Couldn't save the favourite. Try again.",
        kind: ToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _savingFavourites.remove(key));
    }
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.initiallySelected
        .map((exercise) => exercise.name)
        .toSet();
    _selectedOrder = widget.initiallySelected
        .map((exercise) => exercise.name)
        .toList();
    final libraryNames = _exerciseLibrary
        .map((exercise) => _exerciseNameKey(exercise.name))
        .toSet();
    _customExercises.addAll(
      widget.initiallySelected.where(
        (exercise) => !libraryNames.contains(_exerciseNameKey(exercise.name)),
      ),
    );
    unawaited(_loadCustomExercises());
    unawaited(_loadFavourites());
  }

  Future<void> _loadCustomExercises() async {
    final recovered = <_ExerciseDefinition>[];
    try {
      final saved = await WorkoutService.loadCustomExercises();
      recovered.addAll(
        saved.map(
          (exercise) => _ExerciseDefinition(
            name: exercise.name,
            category: exercise.category,
          ),
        ),
      );
    } catch (_) {
      // Completed workout history below can still recover older exercises.
    }
    try {
      final workouts = await WorkoutService.loadRecent(limit: 100);
      recovered.addAll(
        workouts.expand(
          (workout) => workout.exercises.map(
            (exercise) => _ExerciseDefinition(
              name: exercise.name,
              category: exercise.category,
            ),
          ),
        ),
      );
    } catch (_) {
      // Keep the built-in and already loaded custom exercises available.
    }
    if (!mounted) return;
    final knownNames = {
      for (final exercise in [..._exerciseLibrary, ..._customExercises])
        _exerciseNameKey(exercise.name),
    };
    final additions = <_ExerciseDefinition>[];
    for (final exercise in recovered) {
      final key = _exerciseNameKey(exercise.name);
      if (key.isNotEmpty && knownNames.add(key)) additions.add(exercise);
    }
    if (additions.isEmpty) return;
    setState(() => _customExercises.addAll(additions));
    for (final exercise in additions) {
      unawaited(
        WorkoutService.saveCustomExercise(
          name: exercise.name,
          category: exercise.category,
        ).catchError((_) {}),
      );
    }
  }

  List<_ExerciseDefinition> get _filteredExercises {
    final query = _search.trim().toLowerCase();
    return [..._exerciseLibrary, ..._customExercises].where((exercise) {
        final matchesFilter =
            _filter == 'All' ||
            (_filter == 'Favourites'
                ? _favourites.contains(_exerciseNameKey(exercise.name))
                : exercise.category == _filter);
        final matchesSearch =
            query.isEmpty ||
            exercise.name.toLowerCase().contains(query) ||
            exercise.category.toLowerCase().contains(query);
        return matchesFilter && matchesSearch;
      }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _toggle(_ExerciseDefinition exercise) {
    setState(() {
      if (_selected.add(exercise.name)) {
        // The active workout is ordered newest-first, so the last exercise
        // the user adds becomes both the top card and the Live Activity title.
        _selectedOrder.insert(0, exercise.name);
      } else {
        _selected.remove(exercise.name);
        _selectedOrder.remove(exercise.name);
      }
    });
  }

  void _finish() {
    final definitionsByName = {
      for (final exercise in [..._exerciseLibrary, ..._customExercises])
        exercise.name: exercise,
    };
    final selectedExercises = _selectedOrder
        .map((name) => definitionsByName[name])
        .whereType<_ExerciseDefinition>()
        .toList(growable: false);
    Navigator.pop(context, selectedExercises);
  }

  Future<void> _createExercise() async {
    // Not disposed: the sheet's field is still animating out.
    final name = TextEditingController();
    var category = 'Other';
    final created = await showAppleSheet<_ExerciseDefinition>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => AppleFormSheet(
          title: 'Create exercise',
          doneLabel: 'Create',
          onDone: () {
            if (name.text.trim().isEmpty) return;
            Navigator.pop(
              sheetContext,
              _ExerciseDefinition(name: name.text.trim(), category: category),
            );
          },
          children: [
            AppleFormGroup(
              children: [
                AppleFormTextRow(
                  label: 'Name',
                  controller: name,
                  placeholder: 'e.g. Cable Fly',
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                AppleFormRow(
                  label: 'Muscle group',
                  trailing: IosPullDownMenu<String>(
                    tooltip: 'Muscle group',
                    actions: [
                      for (final value in [..._filters.skip(2), 'Other'])
                        IosMenuAction(
                          value: value,
                          label: value,
                          checked: value == category,
                        ),
                    ],
                    onSelected: (value) =>
                        setSheetState(() => category = value),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          category,
                          style: TextStyle(
                            fontSize: 16,
                            color: context.vivordoColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          CupertinoIcons.chevron_up_chevron_down,
                          size: 14,
                          color: context.vivordoColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (created == null || !mounted) return;
    _ExerciseDefinition? matchingExercise;
    for (final exercise in [..._exerciseLibrary, ..._customExercises]) {
      if (_exerciseNameKey(exercise.name) == _exerciseNameKey(created.name)) {
        matchingExercise = exercise;
        break;
      }
    }
    setState(() {
      if (matchingExercise == null) _customExercises.add(created);
      final selectedName = matchingExercise?.name ?? created.name;
      if (_selected.add(selectedName)) _selectedOrder.insert(0, selectedName);
    });
    try {
      await WorkoutService.saveCustomExercise(
        name: created.name,
        category: created.category,
      );
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        "Exercise added, but it couldn't be saved for later.",
        kind: ToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercises = _filteredExercises;

    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  Expanded(
                    child: Text(
                      'Add Exercise',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: context.vivordoColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _createExercise,
                    child: const Text('Create'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search exercises',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: context.vivordoColors.input,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: context.vivordoColors.border),
                  ),
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final filter = _filters[index];
                  final selected = filter == _filter;
                  return ChoiceChip(
                    label: Text(filter),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = filter),
                    selectedColor: _purple,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : _muted,
                      fontWeight: FontWeight.w700,
                    ),
                    showCheckmark: false,
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _PickerSectionTitle(
                      _filter == 'Favourites' ? 'FAVOURITES' : 'ALL EXERCISES',
                    ),
                  ),
                  if (exercises.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          _filter == 'Favourites' && _search.trim().isEmpty
                              ? 'Star exercises to add them to your favourites.'
                              : 'No exercises found.',
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: context.vivordoColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: context.vivordoColors.border,
                          ),
                        ),
                        child: ListView.separated(
                          itemCount: exercises.length,
                          itemBuilder: (context, index) {
                            final exercise = exercises[index];
                            return _ExercisePickerRow(
                              exercise: exercise,
                              selected: _selected.contains(exercise.name),
                              favourite: _favourites.contains(
                                _exerciseNameKey(exercise.name),
                              ),
                              onFavourite:
                                  !_favouritesLoaded ||
                                      _savingFavourites.contains(
                                        _exerciseNameKey(exercise.name),
                                      )
                                  ? null
                                  : () => _toggleFavourite(exercise),
                              onTap: () => _toggle(exercise),
                            );
                          },
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 72),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: context.vivordoColors.card,
            border: Border(
              top: BorderSide(color: context.vivordoColors.border),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_selected.length} ${_selected.length == 1 ? 'exercise' : 'exercises'} selected',
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _selected.isEmpty ? null : _finish,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: _purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Add to Workout',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickerSectionTitle extends StatelessWidget {
  const _PickerSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 10, 6, 9),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
        color: _muted,
      ),
    ),
  );
}

class _ExercisePickerRow extends StatelessWidget {
  const _ExercisePickerRow({
    required this.exercise,
    required this.selected,
    required this.onTap,
    required this.favourite,
    required this.onFavourite,
  });

  final _ExerciseDefinition exercise;
  final bool selected;
  final VoidCallback onTap;
  final bool favourite;
  final VoidCallback? onFavourite;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? context.vivordoColors.cardMuted : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _ExerciseIcon(exercise: exercise),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.vivordoColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    exercise.category,
                    style: const TextStyle(color: _muted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: favourite
                  ? 'Remove from favourites'
                  : 'Add to favourites',
              onPressed: onFavourite,
              icon: Icon(
                favourite ? Icons.star_rounded : Icons.star_border_rounded,
                color: favourite ? _purple : _muted,
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? _purple : _muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ExerciseIcon extends StatelessWidget {
  const _ExerciseIcon({required this.exercise});

  final _ExerciseDefinition exercise;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (exercise.category) {
      'Back' => (Icons.rowing_rounded, const Color(0xFF1478F2)),
      'Arms' => (Icons.fitness_center_rounded, const Color(0xFF22B879)),
      'Legs' => (Icons.directions_run_rounded, const Color(0xFFFF9500)),
      'Core' => (Icons.self_improvement_rounded, const Color(0xFFE94B9A)),
      'Cardio' => (Icons.directions_run_rounded, const Color(0xFFF43F5E)),
      'Sports' => (Icons.sports_basketball_rounded, const Color(0xFF2563EB)),
      'Shoulders' => (Icons.accessibility_new_rounded, const Color(0xFF9B51E0)),
      _ => (Icons.fitness_center_rounded, _purple),
    };
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class MonthlyRingsDialog extends StatelessWidget {
  const MonthlyRingsDialog({super.key});
  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 700),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ACTIVITY RINGS',
                        style: TextStyle(
                          fontSize: 11,
                          color: _muted,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        'Last 30 Days',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const _ThirtyDayActivityRings(),
          ],
        ),
      ),
    ),
  );
}

class _ThirtyDayActivityRings extends StatefulWidget {
  const _ThirtyDayActivityRings();

  @override
  State<_ThirtyDayActivityRings> createState() =>
      _ThirtyDayActivityRingsState();
}

class _ThirtyDayActivityRingsState extends State<_ThirtyDayActivityRings> {
  /// A day the user tapped; null follows today, past midnight too.
  DateTime? _pickedDay;
  DateTime get _selectedDay => _pickedDay ?? DateUtils.dateOnly(DateTime.now());
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    _scheduleMidnight();
  }

  /// Rebuild at midnight (late, on resume, if the app was asleep) so the
  /// 30-day window and "Today's activity" move to the new day.
  void _scheduleMidnight() {
    _midnight = Timer(durationUntilNextLocalDay(DateTime.now()), () {
      if (!mounted) return;
      setState(() {});
      _scheduleMidnight();
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDay = today.subtract(const Duration(days: 29));
    if (user == null) {
      return _buildContent(today, firstDay, const {}, const ActivityGoals());
    }

    final startKey = DateFormat('yyyy-MM-dd').format(firstDay);
    final endKey = DateFormat('yyyy-MM-dd').format(today);
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('metrics_daily')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
        .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
        .orderBy(FieldPath.documentId)
        .snapshots();

    return VisibleStreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('Could not load activity history.')),
          );
        }
        final days = {
          for (final doc
              in snapshot.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            doc.id: doc.data(),
        };
        return VisibleStreamBuilder<ActivityGoals>(
          stream: ActivityGoalsService.watch(),
          initialData: const ActivityGoals(),
          builder: (context, goalsSnapshot) => _buildContent(
            today,
            firstDay,
            days,
            goalsSnapshot.data ?? const ActivityGoals(),
          ),
        );
      },
    );
  }

  Widget _buildContent(
    DateTime today,
    DateTime firstDay,
    Map<String, Map<String, dynamic>> dataByDay,
    ActivityGoals goals,
  ) {
    final selectedKey = DateFormat('yyyy-MM-dd').format(_selectedDay);
    final selectedData = dataByDay[selectedKey];
    final selectedSteps = _metricSum(selectedData, 'steps');
    final selectedCalories = _metricSum(selectedData, 'active_calories');
    final selectedExercise = _metricSum(selectedData, 'exercise_time');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            mainAxisSpacing: 9,
            crossAxisSpacing: 7,
            childAspectRatio: .72,
          ),
          itemCount: 30,
          itemBuilder: (_, index) {
            final date = firstDay.add(Duration(days: index));
            final dayKey = DateFormat('yyyy-MM-dd').format(date);
            final data = dataByDay[dayKey];
            final steps = _metricSum(data, 'steps');
            final calories = _metricSum(data, 'active_calories');
            final exercise = _metricSum(data, 'exercise_time');
            final isToday = DateUtils.isSameDay(date, today);
            final isSelected = DateUtils.isSameDay(date, _selectedDay);
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(
                () =>
                    _pickedDay = DateUtils.isSameDay(date, today) ? null : date,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _purple.withValues(alpha: .08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? _purple : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        painter: ActivityRingsPainter(
                          move: (steps / goals.steps).clamp(0.0, 1.0),
                          exercise: (calories / goals.activeCalories).clamp(
                            0.0,
                            1.0,
                          ),
                          stand: (exercise / goals.exerciseMinutes).clamp(
                            0.0,
                            1.0,
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Text(
                      isToday ? 'Today' : '${date.day}',
                      style: TextStyle(
                        fontSize: 8,
                        color: isSelected || isToday ? _purple : _muted,
                        fontWeight: isSelected || isToday
                            ? FontWeight.w800
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        _SectionTitle(
          icon: Icons.calendar_today_rounded,
          title: DateUtils.isSameDay(_selectedDay, today)
              ? "TODAY'S ACTIVITY"
              : DateFormat('MMMM d, y').format(_selectedDay).toUpperCase(),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            _RingLegend(
              color: _purple,
              text:
                  'Steps ${NumberFormat.decimalPattern().format(selectedSteps.round())}',
            ),
            _RingLegend(
              color: const Color(0xFFFB923C),
              text: 'Active calories ${_formatMetric(selectedCalories)}',
            ),
            _RingLegend(
              color: const Color(0xFF34D399),
              text: 'Exercise ${_formatMetric(selectedExercise)} min',
            ),
          ],
        ),
      ],
    );
  }

  double _metricSum(Map<String, dynamic>? data, String key) {
    final metric = data?[key] as Map?;
    return (metric?['sum'] as num?)?.toDouble() ?? 0;
  }

  String _formatMetric(double value) =>
      value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
}

class ActivityRingsPainter extends CustomPainter {
  static const ringColors = [_purple, Color(0xFFFB923C), Color(0xFF34D399)];

  final double move, exercise, stand;
  final Color moveColor, trackColor;
  const ActivityRingsPainter({
    required this.move,
    required this.exercise,
    required this.stand,
    this.moveColor = _purple,
    this.trackColor = const Color(0xFFECECF3),
  });
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    final values = [move, exercise, stand];
    final colors = [moveColor, ringColors[1], ringColors[2]];
    for (var i = 0; i < 3; i++) {
      final radius = s.shortestSide / 2 - 5 - i * 9.0;
      final bg = Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;
      final fg = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      c.drawCircle(center, radius, bg);
      c.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * values[i].clamp(0, 1),
        false,
        fg,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ActivityRingsPainter old) =>
      old.move != move ||
      old.exercise != exercise ||
      old.stand != stand ||
      old.moveColor != moveColor ||
      old.trackColor != trackColor;
}

class ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  const ProgressRingPainter({required this.progress, required this.color});
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2),
        r = s.shortestSide / 2 - 5;
    final bg = Paint()
      ..color = color.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    c.drawCircle(center, r, bg);
    c.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant ProgressRingPainter old) =>
      old.progress != progress;
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
      boxShadow: [
        BoxShadow(
          color: context.vivordoColors.shadow,
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _PillButton({
    required this.icon,
    required this.label,
    this.color = _purple,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class _RingLegend extends StatelessWidget {
  final Color color;
  final String text;
  const _RingLegend({required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: _purple),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: _muted,
          ),
        ),
      ),
    ],
  );
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBox({required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, color: color, size: 18.5),
  );
}

class _StrengthRow extends StatelessWidget {
  final String label;
  final int value, goal;
  const _StrengthRow({
    required this.label,
    required this.value,
    required this.goal,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 78,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
      Expanded(
        child: LinearProgressIndicator(
          value: (value / goal).clamp(0, 1),
          minHeight: 7,
          borderRadius: BorderRadius.circular(8),
          color: _purple,
          backgroundColor: context.vivordoColors.input,
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 60,
        child: Text(
          '$value / $goal sets',
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 10, color: _muted),
        ),
      ),
    ],
  );
}

class _ActivityStat extends StatelessWidget {
  final String value, label;
  const _ActivityStat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
    ],
  );
}

class _GoalTile extends StatelessWidget {
  final String label, unit;
  final int value;
  final VoidCallback onEdit;
  const _GoalTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.onEdit,
  });
  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${value.toString()} $unit',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onEdit,
              style: TextButton.styleFrom(
                backgroundColor: context.vivordoColors.cardMuted,
                foregroundColor: _purple,
              ),
              child: const Text(
                'Edit',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        LinearProgressIndicator(
          value: .65,
          minHeight: 7,
          borderRadius: BorderRadius.circular(8),
          color: _purple,
          backgroundColor: context.vivordoColors.input,
        ),
      ],
    ),
  );
}
