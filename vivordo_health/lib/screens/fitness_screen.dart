import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:intl/intl.dart';

import '../src/services/activity_goals_service.dart';
import '../src/services/active_workout_storage.dart';
import '../src/services/health_service.dart';
import '../src/services/recent_activity_service.dart';
import '../src/services/workout_service.dart';
import '../src/services/personal_profile_service.dart';
import '../src/services/workout_live_activity_service.dart';
import '../src/utils/workout_activity_visual.dart';
import 'personal_profile_screen.dart';

const _purple = Color(0xFF6B5CE7);
const _ink = Color(0xFF17172B);
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
  const FitnessScreen({super.key});

  @override
  State<FitnessScreen> createState() => _FitnessScreenState();
}

class _FitnessScreenState extends State<FitnessScreen> {
  bool _allActivity = false;
  bool _recommendationsExpanded = true;
  final Map<String, int> _strengthGoals = {
    'Chest': 10,
    'Back': 10,
    'Legs': 12,
    'Shoulders': 8,
    'Arms': 10,
  };

  @override
  void initState() {
    super.initState();
    unawaited(_restoreActiveWorkout());
    unawaited(_backfillLegacyExerciseMinutes());
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
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 150),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fitness',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: context.vivordoColors.textPrimary,
                      ),
                    ),
                  ),
                  _PillButton(
                    icon: Icons.track_changes_rounded,
                    label: 'Goals',
                    onTap: _openGoals,
                  ),
                  const SizedBox(width: 8),
                  const _WorkoutStreakPill(),
                ],
              ),
              const SizedBox(height: 16),
              _TodayActivityRings(onTap: _openMonthlyRings),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: _TodayStepsMetricCard()),
                  const SizedBox(width: 10),
                  const Expanded(child: _LatestHeartScanCard()),
                ],
              ),
              const SizedBox(height: 12),
              const _PersonalProfileCard(),
              const SizedBox(height: 22),
              _SectionTitle(
                icon: Icons.auto_awesome_rounded,
                title: 'DAILY RECOMMENDATIONS',
                expanded: _recommendationsExpanded,
                onTap: () => setState(
                  () => _recommendationsExpanded = !_recommendationsExpanded,
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _recommendationsExpanded
                    ? const Column(
                        children: [
                          SizedBox(height: 10),
                          _DailyStepRecommendation(),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 22),
              Text(
                _allActivity ? 'ACTIVITY' : 'STRENGTH TRAINING',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: context.vivordoColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.vivordoColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _Segment(
                        label: 'Strength',
                        selected: !_allActivity,
                        onTap: () => setState(() => _allActivity = false),
                      ),
                    ),
                    Expanded(
                      child: _Segment(
                        label: 'All Activity',
                        selected: _allActivity,
                        onTap: () => setState(() => _allActivity = true),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_allActivity) _buildAllActivity() else _buildStrength(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStrength() => Column(
    children: [
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'START A WORKOUT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: _muted,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _IconBox(
                  icon: _activeWorkoutDraft == null
                      ? Icons.fitness_center_rounded
                      : Icons.timer_outlined,
                  color: _purple,
                  size: 68,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _WorkoutStatusMessage(draft: _activeWorkoutDraft),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _startWorkout,
                icon: const Icon(Icons.add),
                label: Text(
                  _activeWorkoutDraft == null
                      ? 'Start New Workout'
                      : 'Resume Workout',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _WeeklyStrengthProgress(goals: _strengthGoals),
      const SizedBox(height: 18),
      Row(
        children: [
          const Expanded(
            child: Text(
              'RECENT SESSIONS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: _muted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _AllWorkoutsScreen()),
            ),
            child: const Text('View All'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const _RecentWorkoutSessions(),
    ],
  );

  Widget _buildAllActivity() => Column(
    children: [
      const _ThisWeekActivityCard(),
      const SizedBox(height: 18),
      const Row(
        children: [
          Expanded(
            child: Text(
              'RECENT ACTIVITY',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: _muted,
              ),
            ),
          ),
          Text(
            'See all',
            style: TextStyle(fontWeight: FontWeight.w800, color: _purple),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const _RecentActivitiesCard(),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: _logActivity,
          icon: const Icon(Icons.add),
          label: const Text('Log Activity'),
          style: FilledButton.styleFrom(
            backgroundColor: _purple,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ],
  );

  Future<void> _logActivity() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _LogActivityDialog(),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Activity saved.')));
    }
  }

  Future<void> _startWorkout() async {
    _activeWorkoutDraft ??= await _ActiveWorkoutDraft.restore();
    _activeWorkoutDraft ??= _ActiveWorkoutDraft();
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

class _TodayActivityRings extends StatelessWidget {
  const _TodayActivityRings({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final now = DateTime.now();
    final dayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final stream = user == null
        ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('metrics_daily')
              .doc(dayKey)
              .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final steps = ((data?['steps'] as Map?)?['sum'] as num?)?.round() ?? 0;
        final calories =
            ((data?['active_calories'] as Map?)?['sum'] as num?)?.round() ?? 0;
        final exercise =
            ((data?['exercise_time'] as Map?)?['sum'] as num?)?.round() ?? 0;

        return StreamBuilder<ActivityGoals>(
          stream: ActivityGoalsService.watch(),
          initialData: const ActivityGoals(),
          builder: (context, goalsSnapshot) {
            final goals = goalsSnapshot.data ?? const ActivityGoals();
            return InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onTap,
              child: _Card(
                child: Row(
                  children: [
                    SizedBox(
                      width: 82,
                      height: 82,
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
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RingLegend(
                            color: _purple,
                            text:
                                'Steps  ${NumberFormat.decimalPattern().format(steps)} / ${NumberFormat.decimalPattern().format(goals.steps)} steps',
                          ),
                          const SizedBox(height: 7),
                          _RingLegend(
                            color: const Color(0xFFFB923C),
                            text:
                                'Active calories  ${NumberFormat.decimalPattern().format(calories)} / ${goals.activeCalories} calories burnt',
                          ),
                          const SizedBox(height: 7),
                          _RingLegend(
                            color: const Color(0xFF34D399),
                            text:
                                'Exercise  $exercise / ${goals.exerciseMinutes} minutes',
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: _muted),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DailyStepRecommendation extends StatelessWidget {
  const _DailyStepRecommendation();

  static const optimalSteps = 10000;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _Recommendation(
        icon: Icons.directions_walk_rounded,
        color: _muted,
        title: 'Sign in to see your daily step feedback.',
        detail: 'Your step recommendation is based on today’s synced activity.',
      );
    }

    final dayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('metrics_daily')
        .doc(dayKey)
        .snapshots();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _Card(
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }

        final data = snapshot.data?.data();
        final steps = ((data?['steps'] as Map?)?['sum'] as num?)?.round() ?? 0;
        final remaining = math.max(0, optimalSteps - steps);
        final formattedSteps = NumberFormat.decimalPattern().format(steps);
        final formattedRemaining = NumberFormat.decimalPattern().format(
          remaining,
        );

        late final String title;
        late final String detail;
        late final Color color;
        if (steps >= optimalSteps) {
          title = 'Your step count is optimal for today.';
          detail =
              '$formattedSteps steps recorded — you reached the 10,000-step target.';
          color = const Color(0xFF22B879);
        } else if (steps >= 7500) {
          title = 'Your step count is in a healthy range.';
          detail =
              '$formattedSteps steps recorded. Add $formattedRemaining more to reach the optimal 10,000-step target.';
          color = const Color(0xFF22B879);
        } else if (steps >= 5000) {
          title = 'You’re making progress toward a healthy step count.';
          detail =
              '$formattedSteps steps recorded. You’re $formattedRemaining steps from the optimal daily target.';
          color = const Color(0xFFFFA726);
        } else if (steps > 0) {
          title = 'Your step count is low so far today.';
          detail =
              '$formattedSteps steps recorded. Gradually add movement toward the 10,000-step optimal target.';
          color = const Color(0xFFFF7043);
        } else {
          title = 'No steps have been recorded today.';
          detail =
              'Sync your activity data or start moving toward the 10,000-step optimal target.';
          color = _muted;
        }

        return _Recommendation(
          icon: Icons.directions_walk_rounded,
          color: color,
          title: title,
          detail: detail,
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
  Widget build(BuildContext context) => StreamBuilder<List<SavedWorkout>>(
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

class _LatestHeartScanCard extends StatefulWidget {
  const _LatestHeartScanCard();

  @override
  State<_LatestHeartScanCard> createState() => _LatestHeartScanCardState();
}

class _LatestHeartScanCardState extends State<_LatestHeartScanCard> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _scanStream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _scanStream = user == null
        ? const Stream.empty()
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('metrics_daily')
              .snapshots();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _scanStream,
        builder: (context, snapshot) {
          final bpm = _latestBpmFrom(snapshot.data?.docs ?? const []);
          return _MetricCard(
            icon: Icons.favorite_rounded,
            iconColor: const Color(0xFFFF4D67),
            label: 'HEART RATE',
            value: bpm?.toString() ?? '--',
            detail: bpm == null ? 'No scan yet' : 'bpm · Latest scan',
          );
        },
      );

  int? _latestBpmFrom(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final sortedDocs = [...docs]..sort((a, b) => b.id.compareTo(a.id));
    for (final doc in sortedDocs) {
      final data = doc.data();
      final savedScan = data['heart_rate_scan'] as Map?;
      if (savedScan != null) {
        final rawEntries = savedScan['entries'];
        if (rawEntries is List && rawEntries.isNotEmpty) {
          Map? latestEntry;
          DateTime? latestTime;
          for (final entry in rawEntries) {
            if (entry is! Map || entry['bpm'] is! num) continue;
            final timestamp = entry['timestamp'];
            final entryTime = timestamp is Timestamp
                ? timestamp.toDate()
                : null;
            if (latestEntry == null ||
                (entryTime != null &&
                    (latestTime == null || entryTime.isAfter(latestTime)))) {
              latestEntry = entry;
              latestTime = entryTime;
            }
          }
          final bpm = latestEntry?['bpm'];
          if (bpm is num) return bpm.round();
        }

        final legacyBpm = savedScan['avg'];
        if (legacyBpm is num) return legacyBpm.round();
      }

      final heartRate = data['heart_rate'] as Map?;
      if (heartRate?['source'] == 'camera_ppg' && heartRate?['avg'] is num) {
        return (heartRate!['avg'] as num).round();
      }
    }
    return null;
  }
}

class _PersonalProfileCard extends StatefulWidget {
  const _PersonalProfileCard();

  @override
  State<_PersonalProfileCard> createState() => _PersonalProfileCardState();
}

class _PersonalProfileCardState extends State<_PersonalProfileCard> {
  late final Stream<PersonalProfile> profileStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> metricsStream;

  @override
  void initState() {
    super.initState();
    profileStream = PersonalProfileService.watch();
    final user = FirebaseAuth.instance.currentUser;
    metricsStream = user == null
        ? const Stream.empty()
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('metrics_daily')
              .orderBy(FieldPath.documentId, descending: true)
              .limit(30)
              .snapshots();
  }

  double? _latestMetric(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String key,
  ) {
    for (final doc in docs) {
      final value = ((doc.data()[key] as Map?)?['avg'] as num?)?.toDouble();
      if (value != null) return value;
    }
    return null;
  }

  String _number(double? value, {int decimals = 1}) {
    if (value == null) return '--';
    return value.toStringAsFixed(value % 1 == 0 ? 0 : decimals);
  }

  String _imperialHeight(double centimeters) {
    final totalInches = centimeters / 2.54;
    var feet = totalInches ~/ 12;
    var inches = (totalInches - feet * 12).round();
    if (inches == 12) {
      feet++;
      inches = 0;
    }
    return '$feet\u2032 $inches\u2033';
  }

  String _updatedLabel(DateTime? updatedAt) {
    if (updatedAt == null) return 'Tap to add your measurements';
    final local = updatedAt.toLocal();
    final now = DateTime.now();
    if (DateUtils.isSameDay(local, now)) return 'Updated today';
    return 'Updated ${DateFormat('MMM d').format(local)}';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<PersonalProfile>(
    stream: profileStream,
    initialData: const PersonalProfile(),
    builder: (context, profileSnapshot) =>
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: metricsStream,
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
            DateTime? metricDate;
            if (docs.isNotEmpty) {
              metricDate = DateTime.tryParse(docs.first.id);
            }
            final updatedAt = profile.updatedAt ?? metricDate;

            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .035),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _IconBox(
                              icon: Icons.person_outline_rounded,
                              color: _purple,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Personal Profile',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: context.vivordoColors.textPrimary,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: _muted),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: _ProfileMetric(
                                label: 'HEIGHT',
                                value: height == null
                                    ? '--'
                                    : _imperialHeight(height),
                              ),
                            ),
                            const _ProfileDivider(),
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
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _updatedLabel(updatedAt),
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
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
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 46,
    color: Colors.black.withValues(alpha: .08),
  );
}

class _ThisWeekActivityCard extends StatelessWidget {
  const _ThisWeekActivityCard();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final today = DateUtils.dateOnly(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    if (user == null) return _buildCard(monday, today, const {});

    final startKey = DateFormat('yyyy-MM-dd').format(monday);
    final endKey = DateFormat('yyyy-MM-dd').format(sunday);
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('metrics_daily')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
        .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
        .orderBy(FieldPath.documentId)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final dataByDay = {
          for (final doc
              in snapshot.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            doc.id: doc.data(),
        };
        return _buildCard(monday, today, dataByDay);
      },
    );
  }

  Widget _buildCard(
    DateTime monday,
    DateTime today,
    Map<String, Map<String, dynamic>> dataByDay,
  ) {
    final days = List.generate(7, (index) {
      final date = monday.add(Duration(days: index));
      final data = dataByDay[DateFormat('yyyy-MM-dd').format(date)];
      return _WeeklyActivityDay(
        date: date,
        activeMinutes: _metricSum(data, 'exercise_time'),
        distanceKm: _metricSum(data, 'distance'),
        calories: _metricSum(data, 'active_calories'),
      );
    });
    final activeMinutes = days.fold<double>(
      0,
      (total, day) => total + day.activeMinutes,
    );
    final distance = days.fold<double>(
      0,
      (total, day) => total + day.distanceKm,
    );
    final calories = days.fold<double>(0, (total, day) => total + day.calories);
    final activeDays = days
        .where(
          (day) =>
              day.activeMinutes > 0 || day.distanceKm > 0 || day.calories > 0,
        )
        .length;
    final maxCalories = days.fold<double>(
      0,
      (largest, day) => math.max(largest, day.calories),
    );

    return _Card(
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'THIS WEEK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    color: _muted,
                  ),
                ),
              ),
              Text(
                '$activeDays active ${activeDays == 1 ? 'day' : 'days'}',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ActivityStat(
                  value: '${activeMinutes.round()} min',
                  label: 'Active',
                ),
              ),
              Expanded(
                child: _ActivityStat(
                  value: '${distance.toStringAsFixed(1)} km',
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
          const SizedBox(height: 20),
          SizedBox(
            height: 88,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (index) {
                final day = days[index];
                final hasActivity = day.calories > 0;
                final height = maxCalories == 0
                    ? 4.0
                    : math.max(4.0, day.calories / maxCalories * 64);
                final isToday = DateUtils.isSameDay(day.date, today);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 14,
                      height: height,
                      decoration: BoxDecoration(
                        color: hasActivity
                            ? _purple.withValues(alpha: isToday ? 1 : .55)
                            : Colors.black12,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'MTWTFSS'[index],
                      style: TextStyle(
                        fontSize: 10,
                        color: isToday ? _purple : _muted,
                        fontWeight: isToday ? FontWeight.w800 : null,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  double _metricSum(Map<String, dynamic>? data, String key) {
    final metric = data?[key] as Map?;
    return (metric?['sum'] as num?)?.toDouble() ?? 0;
  }
}

class _WeeklyActivityDay {
  const _WeeklyActivityDay({
    required this.date,
    required this.activeMinutes,
    required this.distanceKm,
    required this.calories,
  });

  final DateTime date;
  final double activeMinutes;
  final double distanceKm;
  final double calories;
}

class _RecentWorkoutSessions extends StatelessWidget {
  const _RecentWorkoutSessions();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<SavedWorkout>>(
    stream: WorkoutService.watchRecent(limit: 3),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return const _Card(child: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) {
        return const _Card(
          child: Center(child: Text('Could not load recent workouts.')),
        );
      }
      final workouts = snapshot.data ?? const <SavedWorkout>[];
      if (workouts.isEmpty) {
        return const _Card(
          child: Center(
            child: Text(
              'No workouts completed yet.',
              style: TextStyle(color: _muted),
            ),
          ),
        );
      }
      return _Card(
        child: Column(
          children: [
            for (var index = 0; index < workouts.length; index++) ...[
              _RecentWorkoutRow(workout: workouts[index]),
              if (index < workouts.length - 1) const Divider(),
            ],
          ],
        ),
      );
    },
  );
}

class _AllWorkoutsScreen extends StatelessWidget {
  const _AllWorkoutsScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    appBar: AppBar(
      backgroundColor: context.vivordoColors.page,
      elevation: 0,
      title: const Text(
        'All Workouts',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      centerTitle: true,
    ),
    body: StreamBuilder<List<SavedWorkout>>(
      stream: WorkoutService.watchAll(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load workouts.'));
        }
        final workouts = snapshot.data ?? const <SavedWorkout>[];
        if (workouts.isEmpty) {
          return const Center(
            child: Text(
              'No workouts completed yet.',
              style: TextStyle(color: _muted),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          itemCount: workouts.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, index) =>
              _Card(child: _RecentWorkoutRow(workout: workouts[index])),
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
    final dateLabel = DateFormat('EEEE, MMMM d, y').format(workout.completedAt);
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
            '$dateLabel · $durationLabel · ${workout.exerciseCount} exercises · ${workout.setCount} sets',
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: .82,
        child: Container(
          decoration: BoxDecoration(
            color: context.vivordoColors.page,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'WORKOUT SUMMARY',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                                color: _muted,
                              ),
                            ),
                            Text(
                              DateFormat(
                                'EEEE, MMMM d, y',
                              ).format(workout.completedAt),
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    children: [
                      _Card(
                        child: Row(
                          children: [
                            Expanded(
                              child: _ActivityStat(
                                value: _durationLabel(workout.durationSeconds),
                                label: 'Time',
                              ),
                            ),
                            Expanded(
                              child: _ActivityStat(
                                value: '${workout.exerciseCount}',
                                label: 'Exercises',
                              ),
                            ),
                            Expanded(
                              child: _ActivityStat(
                                value: '${workout.setCount}',
                                label: 'Sets',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'EXERCISES',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final exercise in workout.exercises) ...[
                        _Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exercise.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                exercise.category,
                                style: const TextStyle(color: _muted),
                              ),
                              const Divider(height: 24),
                              if (exercise.distanceKm != null)
                                Text(
                                  '${exercise.distanceKm!.toStringAsFixed(exercise.distanceKm! % 1 == 0 ? 0 : 2)} km',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              else
                                for (
                                  var index = 0;
                                  index < exercise.sets.length;
                                  index++
                                ) ...[
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 52,
                                        child: Text(
                                          'Set ${index + 1}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${exercise.sets[index].weightLbs.toStringAsFixed(exercise.sets[index].weightLbs % 1 == 0 ? 0 : 1)} lbs',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          '${exercise.sets[index].reps} reps',
                                          textAlign: TextAlign.end,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (index < exercise.sets.length - 1)
                                    const Divider(height: 18),
                                ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _deleteWorkout(context),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete Workout'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteWorkout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete workout?'),
        content: const Text(
          'This workout and all of its exercise data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Workout'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await WorkoutService.delete(workout.id);
      if (context.mounted) Navigator.pop(context);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete workout: $error')),
      );
    }
  }
}

class _RecentActivitiesCard extends StatelessWidget {
  const _RecentActivitiesCard();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<RecentActivity>>(
    stream: RecentActivityService.watch(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return const _Card(child: Center(child: CircularProgressIndicator()));
      }
      final activities = snapshot.data ?? const <RecentActivity>[];
      if (activities.isEmpty) {
        return const _Card(
          child: Center(
            child: Text(
              'No activities logged yet.',
              style: TextStyle(color: _muted),
            ),
          ),
        );
      }
      return _Card(
        child: Column(
          children: [
            for (var index = 0; index < activities.length; index++) ...[
              _RecentActivityRow(activity: activities[index]),
              if (index < activities.length - 1) const Divider(),
            ],
          ],
        ),
      );
    },
  );
}

class _RecentActivityRow extends StatelessWidget {
  const _RecentActivityRow({required this.activity});

  final RecentActivity activity;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final activityDay = DateUtils.dateOnly(activity.day);
    final dayLabel = DateUtils.isSameDay(today, activityDay)
        ? 'Today'
        : DateUtils.isSameDay(
            today.subtract(const Duration(days: 1)),
            activityDay,
          )
        ? 'Yesterday'
        : DateFormat('MMM d').format(activityDay);
    final details = <String>['$dayLabel · ${activity.minutes} min'];
    if (activity.km != null) {
      details.add('${activity.km!.toStringAsFixed(1)} km');
    }
    if (activity.sets != null) details.add('${activity.sets} sets');
    final hasSets = activity.sets != null;
    return _ActivityRow(
      icon: hasSets
          ? Icons.fitness_center_rounded
          : Icons.directions_run_rounded,
      color: hasSets ? _purple : const Color(0xFF22B879),
      title: activity.name,
      detail: details.join(' · '),
      result: '',
    );
  }
}

class _LogActivityDialog extends StatefulWidget {
  const _LogActivityDialog();

  @override
  State<_LogActivityDialog> createState() => _LogActivityDialogState();
}

class _LogActivityDialogState extends State<_LogActivityDialog> {
  String _name = '';
  String _minutes = '';
  String _km = '';
  String _sets = '';
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final minutes = int.tryParse(_minutes);
    final km = _km.trim().isEmpty ? null : double.tryParse(_km);
    final sets = _sets.trim().isEmpty ? null : int.tryParse(_sets);
    if (_name.trim().isEmpty || minutes == null || minutes <= 0) {
      setState(() => _error = 'Enter a name and valid number of minutes.');
      return;
    }
    if ((_km.trim().isNotEmpty && km == null) ||
        (_sets.trim().isNotEmpty && sets == null)) {
      setState(() => _error = 'Enter valid numbers for kilometres and sets.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await RecentActivityService.add(
        name: _name,
        minutes: minutes,
        day: _day,
        km: km,
        sets: sets,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save activity: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    title: const Text('Log Activity'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Activity name'),
            onChanged: (value) => _name = value,
          ),
          TextFormField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Time (minutes)'),
            onChanged: (value) => _minutes = value,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Day'),
            subtitle: Text(DateFormat('MMMM d, y').format(_day)),
            trailing: const Icon(Icons.calendar_today_rounded),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _day = picked);
            },
          ),
          TextFormField(
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Kilometres (optional)',
            ),
            onChanged: (value) => _km = value,
          ),
          TextFormField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Sets (optional)'),
            onChanged: (value) => _sets = value,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
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

  Future<void> _saveActivityGoals() => ActivityGoalsService.save(
    ActivityGoals(
      steps: activity['Steps']!,
      activeCalories: activity['Active Calories']!,
      exerciseMinutes: activity['Exercise']!,
      workoutsPerWeek: activity['Workouts']!,
    ),
  );

  Future<void> _edit(Map<String, int> target, String key, String unit) async {
    var enteredValue = '${target[key]}';
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Edit $key Goal'),
        content: TextFormField(
          initialValue: enteredValue,
          autofocus: true,
          keyboardType: TextInputType.number,
          onChanged: (value) => enteredValue = value,
          decoration: InputDecoration(
            suffixText: unit,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(enteredValue)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || value <= 0) return;
    setState(() => target[key] = value);
    try {
      await _saveActivityGoals();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save goal: $error')));
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
Future<bool> prepareActiveWorkoutForLaunch() async {
  final restored = await _ActiveWorkoutDraft.restore();
  if (restored == null) return false;
  _activeWorkoutDraft = restored;
  FitnessWorkoutTimerState.start(
    startedAt: restored.startedAt,
    title: restored.liveActivityTitle,
    exerciseCount: restored.exercises.length,
  );
  return true;
}

class _WorkoutStatusMessage extends StatefulWidget {
  const _WorkoutStatusMessage({required this.draft});

  final _ActiveWorkoutDraft? draft;

  @override
  State<_WorkoutStatusMessage> createState() => _WorkoutStatusMessageState();
}

class _WorkoutStatusMessageState extends State<_WorkoutStatusMessage> {
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _updateTimer();
  }

  @override
  void didUpdateWidget(covariant _WorkoutStatusMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft) _updateTimer();
  }

  void _updateTimer() {
    timer?.cancel();
    timer = widget.draft == null
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
    if (draft == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to train?',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: context.vivordoColors.textPrimary,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Build your workout as you go.',
            style: TextStyle(color: _muted, height: 1.3),
          ),
        ],
      );
    }

    final totalSeconds = DateTime.now().difference(draft.startedAt).inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final elapsed = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          elapsed,
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            color: context.vivordoColors.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Workout in progress',
          style: TextStyle(color: _muted, height: 1.3),
        ),
      ],
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
  Timer? timer;
  late final _ActiveWorkoutDraft draft;
  bool saving = false;
  bool savingTemplate = false;
  bool refreshingDistance = false;
  double? trackedDistanceKm;
  DateTime? lastDistanceRefresh;

  DateTime get startedAt => draft.startedAt;
  List<_WorkoutExercise> get exercises => draft.exercises;
  int get seconds => DateTime.now().difference(startedAt).inSeconds;

  Future<void> _toggleCircleSharing() async {
    setState(() => draft.shareToCircle = !draft.shareToCircle);
    await draft.persist();
  }

  @override
  void initState() {
    super.initState();
    draft = _activeWorkoutDraft ??= _ActiveWorkoutDraft();
    FitnessWorkoutTimerState.start(
      startedAt: draft.startedAt,
      title: draft.liveActivityTitle,
      exerciseCount: draft.exercises.length,
    );
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      if (_hasCardioExercise &&
          !refreshingDistance &&
          (lastDistanceRefresh == null ||
              DateTime.now().difference(lastDistanceRefresh!).inSeconds >=
                  15)) {
        unawaited(_refreshTrackedDistance());
      }
    });
    unawaited(draft.persist());
    if (_hasCardioExercise) unawaited(_refreshTrackedDistance());
  }

  @override
  void dispose() {
    timer?.cancel();
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
    if (mounted) setState(() {});
    final distance = await HealthService().readWalkingRunningDistanceKm(
      start: startedAt,
    );
    lastDistanceRefresh = DateTime.now();
    refreshingDistance = false;
    if (distance != null) trackedDistanceKm = distance;
    if (mounted) setState(() {});
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
              ...exercises,
              ...selected
                  .where((definition) => !existing.containsKey(definition.name))
                  .map(_WorkoutExercise.new),
            ];
      exercises
        ..clear()
        ..addAll(updated);
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
          if (saved == null) continue;
          for (
            var index = 0;
            index < exercise.sets.length && index < saved.length;
            index++
          ) {
            exercise.sets[index].previous = saved[index];
          }
        }
      });
      await draft.persist();
    } catch (error) {
      debugPrint('Could not load previous exercise sets: $error');
    }
  }

  Future<void> _saveWorkoutTemplate() async {
    if (exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise first.')),
      );
      return;
    }
    var workoutName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save Workout'),
        content: TextField(
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Workout name',
            hintText: 'e.g. Push Day',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => workoutName = value,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(dialogContext, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (workoutName.trim().isNotEmpty) {
                Navigator.pop(dialogContext, workoutName);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$name saved.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save workout: $error')));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise first.')),
      );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Enter a valid weight and reps for every ${exercise.name} set.',
              ),
            ),
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
      await WorkoutService.save(
        startedAt: startedAt,
        durationSeconds: seconds,
        exercises: records,
        shareToCircle: draft.shareToCircle,
      );
      timer?.cancel();
      _activeWorkoutDraft = null;
      await ActiveWorkoutStorage.clear();
      FitnessWorkoutTimerState.stop();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save workout: $error')));
    }
  }

  Future<void> _cancelWorkout() async {
    final cancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel workout?'),
        content: const Text(
          'This will discard the workout and everything entered in it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Workout'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Workout'),
          ),
        ],
      ),
    );
    if (cancel != true || !mounted) return;
    timer?.cancel();
    _activeWorkoutDraft = null;
    await ActiveWorkoutStorage.clear();
    if (!mounted) return;
    FitnessWorkoutTimerState.stop();
    Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final elapsed =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final setCount = exercises.fold<int>(
      0,
      (total, exercise) => total + exercise.sets.length,
    );
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      appBar: AppBar(
        backgroundColor: context.vivordoColors.page,
        elevation: 0,
        title: const Text(
          'New Workout',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: saving ? null : _cancelWorkout,
            child: const Text('Cancel'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '●  Workout in progress',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      elapsed,
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: saving || savingTemplate
                        ? null
                        : _saveWorkoutTemplate,
                    style: TextButton.styleFrom(
                      foregroundColor: _purple,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: savingTemplate
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Save Workout',
                            style: TextStyle(fontSize: 12),
                          ),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: saving || savingTemplate ? null : _finishWorkout,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEDE8FF),
                      foregroundColor: _purple,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Finish'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Card(
            child: Row(
              children: [
                Expanded(
                  child: _ActivityStat(
                    value: '${exercises.length}',
                    label: 'Exercises',
                  ),
                ),
                Expanded(
                  child: _ActivityStat(value: '$setCount', label: 'Sets'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: saving || savingTemplate ? null : _toggleCircleSharing,
            style: OutlinedButton.styleFrom(
              foregroundColor: _purple,
              side: BorderSide(
                color: draft.shareToCircle
                    ? _purple
                    : _purple.withValues(alpha: .45),
              ),
              backgroundColor: draft.shareToCircle
                  ? _purple.withValues(alpha: .07)
                  : Colors.transparent,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: Icon(
              draft.shareToCircle
                  ? Icons.check_circle_rounded
                  : Icons.groups_rounded,
            ),
            label: Text(
              draft.shareToCircle ? 'Sharing to Circle' : 'Share to Circle',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                draft.shareToCircle ? Icons.groups_rounded : Icons.lock_rounded,
                color: _muted,
                size: 14,
              ),
              const SizedBox(width: 5),
              Text(
                draft.shareToCircle
                    ? 'Your Circle can see this workout'
                    : 'Private to you',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final exercise in exercises) ...[
            _WorkoutExerciseCard(
              exercise: exercise,
              trackedDistanceKm: trackedDistanceKm,
              refreshingDistance: refreshingDistance,
              onChanged: () {
                setState(() {});
                unawaited(draft.persist());
              },
              onRemove: () {
                setState(() => exercises.remove(exercise));
                unawaited(draft.persist());
              },
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: _addExercises,
            icon: const Icon(Icons.add),
            label: const Text('Add Exercise'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              side: const BorderSide(color: _purple),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _addSavedWorkout,
            icon: const Icon(Icons.playlist_add_rounded),
            label: const Text('Add Workout'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              foregroundColor: _purple,
              side: BorderSide(color: _purple.withValues(alpha: .45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Saved Workout?'),
        content: Text(
          'Delete "${template.name}"? This will not delete workouts you already completed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingIds.add(template.id));
    try {
      await WorkoutService.deleteTemplate(template.id);
      if (!mounted) return;
      setState(() {
        _deletingIds.remove(template.id);
        if (_selectedId == template.id) _selectedId = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${template.name} deleted.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _deletingIds.remove(template.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete workout: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<WorkoutTemplate>>(
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

String _compactWorkoutNumber(double value) =>
    value.toStringAsFixed(value % 1 == 0 ? 0 : 1);

class _WorkoutSet {
  _WorkoutSet({this.previous});

  WorkoutSetRecord? previous;
  String lbs = '';
  String reps = '';

  Map<String, dynamic> toJson() => {'lbs': lbs, 'reps': reps};
}

class _WorkoutExercise {
  _WorkoutExercise(
    this.definition, {
    List<WorkoutSetRecord> previousSets = const [],
  }) : previousSets = previousSets,
       sets = [
         _WorkoutSet(previous: previousSets.firstOrNull),
         _WorkoutSet(previous: previousSets.elementAtOrNull(1)),
       ];

  final _ExerciseDefinition definition;
  final List<WorkoutSetRecord> previousSets;
  final List<_WorkoutSet> sets;
  String distanceKm = '';

  String get name => definition.name;
  bool get isDistanceExercise => definition.category == 'Cardio';
  bool get isSportsExercise => definition.category == 'Sports';

  Map<String, dynamic> toJson() => {
    'name': definition.name,
    'category': definition.category,
    'distanceKm': distanceKm,
    'sets': sets.map((set) => set.toJson()).toList(),
  };

  factory _WorkoutExercise.fromJson(Map<String, dynamic> json) {
    final exercise = _WorkoutExercise(
      _ExerciseDefinition(
        name: json['name'] as String? ?? 'Exercise',
        category: json['category'] as String? ?? 'Other',
      ),
    );
    exercise.distanceKm = json['distanceKm'] as String? ?? '';
    final savedSets = json['sets'];
    if (savedSets is List) {
      exercise.sets
        ..clear()
        ..addAll(
          savedSets.whereType<Map>().map((value) {
            final map = Map<String, dynamic>.from(value);
            final set = _WorkoutSet();
            set.lbs = map['lbs'] as String? ?? '';
            set.reps = map['reps'] as String? ?? '';
            return set;
          }),
        );
    }
    return exercise;
  }
}

class _WorkoutExerciseCard extends StatelessWidget {
  const _WorkoutExerciseCard({
    required this.exercise,
    required this.trackedDistanceKm,
    required this.refreshingDistance,
    required this.onChanged,
    required this.onRemove,
  });

  final _WorkoutExercise exercise;
  final double? trackedDistanceKm;
  final bool refreshingDistance;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

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
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'remove') onRemove();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'remove', child: Text('Remove exercise')),
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: context.vivordoColors.cardMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                if (refreshingDistance)
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
                        trackedDistanceKm == null
                            ? 'Tracking distance automatically'
                            : '${trackedDistanceKm!.toStringAsFixed(2)} km',
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

const _exerciseLibrary = <_ExerciseDefinition>[
  _ExerciseDefinition(name: 'Barbell Bench Press', category: 'Chest'),
  _ExerciseDefinition(name: 'Incline Barbell Bench Press', category: 'Chest'),
  _ExerciseDefinition(name: 'Decline Barbell Bench Press', category: 'Chest'),
  _ExerciseDefinition(name: 'Dumbbell Bench Press', category: 'Chest'),
  _ExerciseDefinition(name: 'Incline Dumbbell Press', category: 'Chest'),
  _ExerciseDefinition(name: 'Decline Dumbbell Press', category: 'Chest'),
  _ExerciseDefinition(name: 'Dumbbell Chest Fly', category: 'Chest'),
  _ExerciseDefinition(name: 'Cable Chest Fly', category: 'Chest'),
  _ExerciseDefinition(name: 'Cable Crossover', category: 'Chest'),
  _ExerciseDefinition(name: 'Chest Press Machine', category: 'Chest'),
  _ExerciseDefinition(name: 'Pec Deck', category: 'Chest'),
  _ExerciseDefinition(name: 'Push-Up', category: 'Chest'),
  _ExerciseDefinition(name: 'Incline Push-Up', category: 'Chest'),
  _ExerciseDefinition(name: 'Decline Push-Up', category: 'Chest'),
  _ExerciseDefinition(name: 'Chest Dip', category: 'Chest'),
  _ExerciseDefinition(name: 'Dumbbell Pullover', category: 'Chest'),
  _ExerciseDefinition(name: 'Barbell Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'EZ-Bar Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'Dumbbell Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'Hammer Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'Preacher Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'Incline Dumbbell Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'Concentration Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'Cable Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'Machine Biceps Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'Triceps Pushdown', category: 'Arms'),
  _ExerciseDefinition(name: 'Rope Pushdown', category: 'Arms'),
  _ExerciseDefinition(name: 'Skull Crusher', category: 'Arms'),
  _ExerciseDefinition(name: 'Overhead Triceps Extension', category: 'Arms'),
  _ExerciseDefinition(name: 'Triceps Kickback', category: 'Arms'),
  _ExerciseDefinition(name: 'Close-Grip Bench Press', category: 'Arms'),
  _ExerciseDefinition(name: 'Triceps Dip', category: 'Arms'),
  _ExerciseDefinition(name: 'Bench Dip', category: 'Arms'),
  _ExerciseDefinition(name: 'Diamond Push-Up', category: 'Arms'),
  _ExerciseDefinition(name: 'Wrist Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'Reverse Wrist Curl', category: 'Arms'),
  _ExerciseDefinition(name: 'Deadlift', category: 'Back'),
  _ExerciseDefinition(name: 'Barbell Row', category: 'Back'),
  _ExerciseDefinition(name: 'T-Bar Row', category: 'Back'),
  _ExerciseDefinition(name: 'Landmine Row', category: 'Back'),
  _ExerciseDefinition(name: 'One-Arm Dumbbell Row', category: 'Back'),
  _ExerciseDefinition(name: 'Chest-Supported Dumbbell Row', category: 'Back'),
  _ExerciseDefinition(name: 'Seated Cable Row', category: 'Back'),
  _ExerciseDefinition(name: 'Machine Row', category: 'Back'),
  _ExerciseDefinition(name: 'Lat Pulldown', category: 'Back'),
  _ExerciseDefinition(name: 'Single-Arm Lat Pulldown', category: 'Back'),
  _ExerciseDefinition(name: 'Straight-Arm Pulldown', category: 'Back'),
  _ExerciseDefinition(name: 'Pull-Up', category: 'Back'),
  _ExerciseDefinition(name: 'Chin-Up', category: 'Back'),
  _ExerciseDefinition(name: 'Assisted Pull-Up', category: 'Back'),
  _ExerciseDefinition(name: 'Inverted Row', category: 'Back'),
  _ExerciseDefinition(name: 'Back Extension', category: 'Back'),
  _ExerciseDefinition(name: 'Reverse Hyperextension', category: 'Back'),
  _ExerciseDefinition(name: 'Barbell Overhead Press', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Dumbbell Shoulder Press', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Machine Shoulder Press', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Arnold Press', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Push Press', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Landmine Press', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Dumbbell Lateral Raise', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Cable Lateral Raise', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Machine Lateral Raise', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Dumbbell Front Raise', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Cable Front Raise', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Rear-Delt Dumbbell Fly', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Cable Rear-Delt Fly', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Reverse Pec Deck', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Face Pull', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Upright Row', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Dumbbell Shrug', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Pike Push-Up', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Handstand Push-Up', category: 'Shoulders'),
  _ExerciseDefinition(name: 'Back Squat', category: 'Legs'),
  _ExerciseDefinition(name: 'Front Squat', category: 'Legs'),
  _ExerciseDefinition(name: 'Goblet Squat', category: 'Legs'),
  _ExerciseDefinition(name: 'Hack Squat', category: 'Legs'),
  _ExerciseDefinition(name: 'Leg Press', category: 'Legs'),
  _ExerciseDefinition(name: 'Leg Extension', category: 'Legs'),
  _ExerciseDefinition(name: 'Romanian Deadlift', category: 'Legs'),
  _ExerciseDefinition(name: 'Stiff-Leg Deadlift', category: 'Legs'),
  _ExerciseDefinition(name: 'Seated Leg Curl', category: 'Legs'),
  _ExerciseDefinition(name: 'Lying Leg Curl', category: 'Legs'),
  _ExerciseDefinition(name: 'Bulgarian Split Squat', category: 'Legs'),
  _ExerciseDefinition(name: 'Walking Lunge', category: 'Legs'),
  _ExerciseDefinition(name: 'Reverse Lunge', category: 'Legs'),
  _ExerciseDefinition(name: 'Step-Up', category: 'Legs'),
  _ExerciseDefinition(name: 'Hip Thrust', category: 'Legs'),
  _ExerciseDefinition(name: 'Glute Bridge', category: 'Legs'),
  _ExerciseDefinition(name: 'Cable Kickback', category: 'Legs'),
  _ExerciseDefinition(name: 'Hip Abduction', category: 'Legs'),
  _ExerciseDefinition(name: 'Hip Adduction', category: 'Legs'),
  _ExerciseDefinition(name: 'Standing Calf Raise', category: 'Legs'),
  _ExerciseDefinition(name: 'Seated Calf Raise', category: 'Legs'),
  _ExerciseDefinition(name: 'Single-Leg Calf Raise', category: 'Legs'),
  _ExerciseDefinition(name: 'Sled Push', category: 'Legs'),
  _ExerciseDefinition(name: 'Box Jump', category: 'Legs'),
  _ExerciseDefinition(name: 'Plank', category: 'Core'),
  _ExerciseDefinition(name: 'Cable Crunch', category: 'Core'),
  _ExerciseDefinition(name: 'Run', category: 'Cardio'),
  _ExerciseDefinition(name: 'Walk', category: 'Cardio'),
  _ExerciseDefinition(name: 'Hike', category: 'Cardio'),
  _ExerciseDefinition(name: 'Stairmaster', category: 'Cardio'),
  _ExerciseDefinition(name: 'Soccer', category: 'Sports'),
  _ExerciseDefinition(name: 'Basketball', category: 'Sports'),
  _ExerciseDefinition(name: 'Football', category: 'Sports'),
  _ExerciseDefinition(name: 'Pickleball', category: 'Sports'),
  _ExerciseDefinition(name: 'Tennis', category: 'Sports'),
  _ExerciseDefinition(name: 'Hockey', category: 'Sports'),
  _ExerciseDefinition(name: 'Volleyball', category: 'Sports'),
  _ExerciseDefinition(name: 'Baseball', category: 'Sports'),
  _ExerciseDefinition(name: 'Golf', category: 'Sports'),
  _ExerciseDefinition(name: 'Dance', category: 'Sports'),
  _ExerciseDefinition(name: 'Squash', category: 'Sports'),
  _ExerciseDefinition(name: 'Rugby', category: 'Sports'),
  _ExerciseDefinition(name: 'Swimming', category: 'Sports'),
  _ExerciseDefinition(name: 'Boxing', category: 'Sports'),
  _ExerciseDefinition(name: 'Badminton', category: 'Sports'),
  _ExerciseDefinition(name: 'Cycling', category: 'Sports'),
  _ExerciseDefinition(name: 'Skiing', category: 'Sports'),
  _ExerciseDefinition(name: 'Lacrosse', category: 'Sports'),
];

class _AddExerciseScreen extends StatefulWidget {
  const _AddExerciseScreen({this.initiallySelected = const []});

  final List<_ExerciseDefinition> initiallySelected;

  @override
  State<_AddExerciseScreen> createState() => _AddExerciseScreenState();
}

class _AddExerciseScreenState extends State<_AddExerciseScreen> {
  static const _filters = [
    'All',
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
  final List<_ExerciseDefinition> _customExercises = [];
  String _filter = 'All';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.initiallySelected
        .map((exercise) => exercise.name)
        .toSet();
    final libraryNames = _exerciseLibrary
        .map((exercise) => exercise.name)
        .toSet();
    _customExercises.addAll(
      widget.initiallySelected.where(
        (exercise) => !libraryNames.contains(exercise.name),
      ),
    );
  }

  List<_ExerciseDefinition> get _filteredExercises {
    final query = _search.trim().toLowerCase();
    return [..._exerciseLibrary, ..._customExercises].where((exercise) {
      final matchesFilter = _filter == 'All' || exercise.category == _filter;
      final matchesSearch =
          query.isEmpty ||
          exercise.name.toLowerCase().contains(query) ||
          exercise.category.toLowerCase().contains(query);
      return matchesFilter && matchesSearch;
    }).toList();
  }

  void _toggle(_ExerciseDefinition exercise) {
    setState(() {
      if (!_selected.add(exercise.name)) _selected.remove(exercise.name);
    });
  }

  void _finish() {
    final selectedExercises = [
      ..._exerciseLibrary,
      ..._customExercises,
    ].where((exercise) => _selected.contains(exercise.name)).toList();
    Navigator.pop(context, selectedExercises);
  }

  Future<void> _createExercise() async {
    var name = '';
    var category = 'Other';
    final created = await showDialog<_ExerciseDefinition>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Create Exercise'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Exercise name'),
                onChanged: (value) => name = value,
              ),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Muscle group'),
                items: [..._filters.skip(1), 'Other']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => category = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (name.trim().isEmpty) return;
                Navigator.pop(
                  dialogContext,
                  _ExerciseDefinition(name: name.trim(), category: category),
                );
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (created == null || !mounted) return;
    setState(() {
      _customExercises.add(created);
      _selected.add(created.name);
    });
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                children: [
                  const _PickerSectionTitle('ALL EXERCISES'),
                  if (exercises.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('No exercises found.')),
                    )
                  else
                    _ExercisePickerCard(
                      exercises: exercises,
                      selected: _selected,
                      onTap: _toggle,
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

class _ExercisePickerCard extends StatelessWidget {
  const _ExercisePickerCard({
    required this.exercises,
    required this.selected,
    required this.onTap,
  });

  final List<_ExerciseDefinition> exercises;
  final Set<String> selected;
  final ValueChanged<_ExerciseDefinition> onTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Column(
      children: [
        for (var index = 0; index < exercises.length; index++) ...[
          _ExercisePickerRow(
            exercise: exercises[index],
            selected: selected.contains(exercises[index].name),
            onTap: () => onTap(exercises[index]),
          ),
          if (index < exercises.length - 1)
            const Divider(height: 1, indent: 72),
        ],
      ],
    ),
  );
}

class _ExercisePickerRow extends StatelessWidget {
  const _ExercisePickerRow({
    required this.exercise,
    required this.selected,
    required this.onTap,
  });

  final _ExerciseDefinition exercise;
  final bool selected;
  final VoidCallback onTap;

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
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateUtils.dateOnly(DateTime.now());
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

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
        return StreamBuilder<ActivityGoals>(
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
              onTap: () => setState(() => _selectedDay = date),
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
  final double move, exercise, stand;
  const ActivityRingsPainter({
    required this.move,
    required this.exercise,
    required this.stand,
  });
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    final values = [move, exercise, stand];
    final colors = [_purple, const Color(0xFFFB923C), const Color(0xFF34D399)];
    for (var i = 0; i < 3; i++) {
      final radius = s.shortestSide / 2 - 5 - i * 9.0;
      final bg = Paint()
        ..color = const Color(0xFFECECF3)
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
      old.move != move || old.exercise != exercise || old.stand != stand;
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
  final VoidCallback? onTap;
  const _PillButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.color = _purple,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(30),
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

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label, value, detail;
  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.detail,
  });
  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: _muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          value,
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
        ),
        Text(detail, style: const TextStyle(fontSize: 11, color: _muted)),
      ],
    ),
  );
}

class _TodayStepsMetricCard extends StatelessWidget {
  const _TodayStepsMetricCard();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _MetricCard(
        icon: Icons.directions_walk_rounded,
        iconColor: Color(0xFF22B879),
        label: 'STEPS',
        value: '--',
        detail: 'Goal: --',
      );
    }
    final dayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final stepsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('metrics_daily')
        .doc(dayKey)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stepsStream,
      builder: (context, stepsSnapshot) {
        final data = stepsSnapshot.data?.data();
        final steps = ((data?['steps'] as Map?)?['sum'] as num?)?.round();
        return StreamBuilder<ActivityGoals>(
          stream: ActivityGoalsService.watch(),
          initialData: const ActivityGoals(),
          builder: (context, goalsSnapshot) {
            final goal =
                goalsSnapshot.data?.steps ?? const ActivityGoals().steps;
            return _MetricCard(
              icon: Icons.directions_walk_rounded,
              iconColor: const Color(0xFF22B879),
              label: 'STEPS',
              value: steps == null
                  ? '--'
                  : NumberFormat.decimalPattern().format(steps),
              detail: 'Goal: ${NumberFormat.decimalPattern().format(goal)}',
            );
          },
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool? expanded;
  final VoidCallback? onTap;
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.expanded,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
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
        if (expanded != null)
          AnimatedRotation(
            turns: expanded! ? .5 : 0,
            duration: const Duration(milliseconds: 220),
            child: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: _purple,
            ),
          ),
      ],
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: content,
        ),
      ),
    );
  }
}

class _Recommendation extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, detail;
  const _Recommendation({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });
  @override
  Widget build(BuildContext context) => _Card(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconBox(icon: icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(
                  fontSize: 11,
                  color: _muted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _IconBox({required this.icon, required this.color, this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(icon, color: color, size: size * .42),
  );
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? _purple : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: selected ? Colors.white : _muted,
        ),
      ),
    ),
  );
}

class _WeeklyStrengthProgress extends StatelessWidget {
  const _WeeklyStrengthProgress({required this.goals});

  final Map<String, int> goals;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    return StreamBuilder<List<SavedWorkout>>(
      stream: WorkoutService.watchBetween(start: monday, end: nextMonday),
      builder: (context, snapshot) {
        final workouts = snapshot.data ?? const <SavedWorkout>[];
        final setsByCategory = {for (final category in goals.keys) category: 0};
        for (final workout in workouts) {
          for (final exercise in workout.exercises) {
            final category = setsByCategory.keys.cast<String?>().firstWhere(
              (candidate) =>
                  candidate!.toLowerCase() ==
                  exercise.category.trim().toLowerCase(),
              orElse: () => null,
            );
            if (category != null) {
              setsByCategory[category] =
                  setsByCategory[category]! + exercise.sets.length;
            }
          }
        }
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'THIS WEEK',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: _muted,
                      ),
                    ),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      '${workouts.length} ${workouts.length == 1 ? 'workout' : 'workouts'}',
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                ],
              ),
              if (snapshot.hasError) ...[
                const SizedBox(height: 10),
                const Text(
                  'Could not load this week’s workouts.',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 16),
              for (final entry in setsByCategory.entries) ...[
                _StrengthRow(
                  label: entry.key,
                  value: entry.value,
                  goal: goals[entry.key]!,
                ),
                if (entry.key != setsByCategory.keys.last)
                  const SizedBox(height: 13),
              ],
            ],
          ),
        );
      },
    );
  }
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

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, detail, result;
  const _ActivityRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.result,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      _IconBox(icon: icon, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(detail, style: const TextStyle(fontSize: 11, color: _muted)),
          ],
        ),
      ),
      Text(
        result,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
      const Icon(Icons.chevron_right, size: 19),
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
