import 'dart:math' as math;
import '../widgets/apple_ui.dart';
import '../widgets/ios_pull_down_menu.dart';
import '../widgets/workout_ai_insight.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:vivordo_health/src/services/personal_profile_service.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'package:vivordo_health/src/utils/heart_rate_history.dart';
import 'package:vivordo_health/src/utils/workout_heart_rate.dart';
import 'package:vivordo_health/src/utils/personal_best.dart';
import 'package:vivordo_health/src/utils/workout_activity_visual.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

const _summaryPurple = Color(0xFF6B5CE7);

/// Status text colours: the bright shade reads on dark cards, the deep one
/// keeps readable contrast on light cards.
Color _statusColor(BuildContext context, Color dark, Color light) =>
    Theme.of(context).brightness == Brightness.dark ? dark : light;

Color _personalBestColor(BuildContext context) =>
    _statusColor(context, const Color(0xFFF59E0B), const Color(0xFFB45309));

Color _improvedColor(BuildContext context) =>
    _statusColor(context, const Color(0xFF32C878), const Color(0xFF15803D));

Color _declinedColor(BuildContext context) =>
    _statusColor(context, const Color(0xFFF08A5D), const Color(0xFFC2410C));

/// A heart rate zone's colour, deeper on light cards; null is under zone 1.
Color _zoneColor(BuildContext context, WorkoutZone? zone) => switch (zone) {
  null => context.vivordoColors.textSecondary,
  WorkoutZone.z1 => _statusColor(
    context,
    const Color(0xFF94A3B8),
    const Color(0xFF64748B),
  ),
  WorkoutZone.z2 => _statusColor(
    context,
    const Color(0xFF60A5FA),
    const Color(0xFF2563EB),
  ),
  WorkoutZone.z3 => _statusColor(
    context,
    const Color(0xFF34D399),
    const Color(0xFF059669),
  ),
  WorkoutZone.z4 => _statusColor(
    context,
    const Color(0xFFFB923C),
    const Color(0xFFEA580C),
  ),
  WorkoutZone.z5 => _statusColor(
    context,
    const Color(0xFFF87171),
    const Color(0xFFDC2626),
  ),
};

class WorkoutSummaryScreen extends StatefulWidget {
  const WorkoutSummaryScreen({super.key, required this.workout});

  final SavedWorkout workout;

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  // Renaming updates the title here without reopening the screen.
  late SavedWorkout workout = widget.workout;

  /// Null until loaded, and when there isn't enough heart rate data.
  WorkoutHeartRate? heartRate;
  List<WorkoutExerciseSpan>? exerciseSpans;

  DateTime get _end => workout.completedAt;
  DateTime get _start =>
      workout.startedAt ??
      _end.subtract(Duration(seconds: workout.durationSeconds));

  @override
  void initState() {
    super.initState();
    _loadHeartRate();
  }

  Future<void> _loadHeartRate() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final metrics = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('metrics_daily');
      final (days, age) = await (
        // Two days when the workout crossed midnight.
        Future.wait(
          {
            localDayKey(_start),
            localDayKey(_end),
          }.map((day) => metrics.doc(day).get()),
        ),
        PersonalProfileService.watch().first
            .then<int?>((profile) => profile.age)
            .timeout(const Duration(seconds: 5), onTimeout: () => null),
      ).wait;
      final loaded = workoutHeartRate(
        [
          for (final day in days)
            ...mergedHeartRateHistory(
              day.data() ?? const {},
              fallbackDate: _start,
              includeDailyFallback: false,
            ),
        ],
        start: _start,
        end: _end,
        age: age,
      );
      if (loaded == null || !mounted) return;
      setState(() {
        heartRate = loaded;
        exerciseSpans = workoutExerciseSpans(
          workout.exercises,
          start: _start,
          end: _end,
        );
      });
    } catch (error) {
      debugPrint('Workout heart rate unavailable: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : colors.textPrimary;
    final visual = workoutActivityVisual(
      workout.displayName,
      category: workout.displayCategory,
    );
    final overview = _WorkoutOverview.fromWorkout(
      workout,
      _units(context),
      heartRate: heartRate,
    );
    final peaks = _exercisePeaks(heartRate, exerciseSpans);

    return WorkoutAiInsight(
      key: ValueKey(workout),
      workout: workout,
      child: Scaffold(
        backgroundColor: colors.page,
        appBar: AppBar(
          backgroundColor: colors.page,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(
            'Workout Summary',
            style: TextStyle(color: primaryText, fontWeight: FontWeight.w800),
          ),
          actions: [
            IosPullDownMenu<_WorkoutSummaryAction>(
              tooltip: 'Workout actions',
              onSelected: (action) => switch (action) {
                _WorkoutSummaryAction.rename => _renameWorkout(),
                _WorkoutSummaryAction.delete => _deleteWorkout(context),
              },
              actions: const [
                IosMenuAction(
                  value: _WorkoutSummaryAction.rename,
                  label: 'Rename workout',
                  icon: CupertinoIcons.pencil,
                ),
                IosMenuAction(
                  value: _WorkoutSummaryAction.delete,
                  label: 'Delete workout',
                  icon: CupertinoIcons.trash,
                  destructive: true,
                ),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Stack(
          children: [
            Positioned(
              top: -90,
              right: -80,
              child: IgnorePointer(
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _summaryPurple.withValues(alpha: isDark ? .16 : .10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ListView(
              // Leaves room to scroll the last set clear of the assistant
              // bubble in the bottom-right corner.
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
              children: [
                _WorkoutHeader(
                  title: overview.title,
                  subtitle: _workoutDateLabel(workout.completedAt),
                  visual: visual,
                ),
                const SizedBox(height: 20),
                _HeroStats(workout: workout, overview: overview),
                const SizedBox(height: 14),
                _SummaryCard(overview: overview, workout: workout),
                if (heartRate case final heartRate?) ...[
                  const SizedBox(height: 14),
                  _HeartRateCard(
                    heartRate: heartRate,
                    start: _start,
                    end: _end,
                    spans: exerciseSpans,
                    exercises: workout.exercises,
                  ),
                ],
                const SizedBox(height: 28),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        'EXERCISES',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ),
                    Text(
                      '${workout.exerciseCount} ${workout.exerciseCount == 1 ? 'exercise' : 'exercises'}',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (
                  var index = 0;
                  index < workout.exercises.length;
                  index++
                ) ...[
                  _ExerciseSummaryCard(
                    number: index + 1,
                    exercise: workout.exercises[index],
                    peakBpm: peaks[index],
                    peakZone: peaks[index] == null
                        ? null
                        : heartRate!.zoneOf(peaks[index]!.toDouble()),
                  ),
                  if (index < workout.exercises.length - 1)
                    const SizedBox(height: 12),
                ],
                if (workout.exercises.isEmpty)
                  _SurfaceCard(
                    child: Text(
                      'No exercise details were saved for this workout.',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameWorkout() async {
    final generated = workout.withCustomName(null).displayName;
    // Not disposed: the alert's field is still animating out.
    final controller = TextEditingController(text: workout.customName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AppleAlert(
        title: 'Rename workout',
        message: 'Leave it empty to call it $generated.',
        content: AppleAlertField(
          controller: controller,
          placeholder: generated,
        ),
        buttons: [
          AppleAlertButton(
            'Cancel',
            onPressed: () => Navigator.pop(dialogContext),
          ),
          AppleAlertButton(
            'Save',
            bold: true,
            onPressed: () => Navigator.pop(dialogContext, controller.text),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    // Template names are capped at 40 characters too.
    final clean = name.trim().length > 40
        ? name.trim().substring(0, 40)
        : name.trim();
    final previous = workout;
    setState(
      () => workout = workout.withCustomName(clean.isEmpty ? null : clean),
    );
    try {
      final synced = await WorkoutService.rename(workout.id, clean);
      if (!synced && mounted) {
        showToast(
          context,
          "Workout renamed. It'll sync when you're online.",
          kind: ToastKind.offline,
        );
      }
    } catch (error) {
      debugPrint('Could not rename workout: $error');
      if (!mounted) return;
      setState(() => workout = previous);
      showToast(
        context,
        "Couldn't rename the workout. Try again.",
        kind: ToastKind.error,
      );
    }
  }

  Future<void> _deleteWorkout(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete workout?',
      message:
          'This workout and all of its exercise data will be permanently deleted.',
      cancelLabel: 'Keep workout',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;

    try {
      final synced = await WorkoutService.delete(workout.id);
      if (!context.mounted) return;
      if (!synced) {
        showToast(
          context,
          "Workout deleted. It'll sync when you're online.",
          kind: ToastKind.offline,
        );
      }
      Navigator.pop(context, true);
    } catch (error) {
      debugPrint('Could not delete workout: $error');
      if (!context.mounted) return;
      showToast(
        context,
        "Couldn't delete the workout. Try again.",
        kind: ToastKind.error,
      );
    }
  }
}

enum _WorkoutSummaryAction { rename, delete }

class _WorkoutHeader extends StatelessWidget {
  const _WorkoutHeader({
    required this.title,
    required this.subtitle,
    required this.visual,
  });

  final String title;
  final String subtitle;
  final WorkoutActivityVisual visual;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: visual.color.withValues(alpha: .14),
          ),
          child: Icon(visual.icon, color: visual.color, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: colors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroStats extends StatelessWidget {
  const _HeroStats({required this.workout, required this.overview});

  final SavedWorkout workout;
  final _WorkoutOverview overview;

  @override
  Widget build(BuildContext context) {
    // The exercise count is already in the Exercises header, so the third
    // stat shows reps, then distance, and only falls back to exercises.
    final stats = [
      (_durationMinutes(workout.durationSeconds), 'min', 'duration'),
      if (_hasStrengthExercise(workout))
        ('${workout.setCount}', null, 'working sets'),
      if (overview.totalReps > 0)
        ('${overview.totalReps}', null, 'reps')
      else if (overview.totalDistance > 0)
        (
          _formatNumber(_units(context).distanceValue(overview.totalDistance)),
          _units(context).distanceLabel,
          'distance',
        )
      else
        ('${workout.exerciseCount}', null, 'exercises'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
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
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  color: Colors.white.withValues(alpha: .15),
                ),
              Expanded(
                child: _HeroStat(
                  value: stats[i].$1,
                  suffix: stats[i].$2,
                  label: stats[i].$3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label, this.suffix});

  final String value;
  final String label;
  final String? suffix;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: value),
              if (suffix != null)
                TextSpan(
                  text: ' $suffix',
                  style: const TextStyle(fontSize: 15),
                ),
            ],
          ),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Color(0xFFE8E0FF))),
    ],
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.overview, required this.workout});

  final _WorkoutOverview overview;
  final SavedWorkout workout;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: _summaryPurple, size: 21),
              SizedBox(width: 8),
              Text(
                'VIVORDO SUMMARY',
                style: TextStyle(
                  color: _summaryPurple,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            overview.headline,
            style: TextStyle(
              color: isDark ? Colors.white : colors.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            overview.summary,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 16,
              height: 1.45,
            ),
          ),
          _TrendBreakdown(workout: workout),
          if (overview.chips.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: overview.chips
                  .map((chip) {
                    final color = chip.startsWith('★')
                        ? _personalBestColor(context)
                        : _summaryPurple;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: color.withValues(alpha: .25)),
                      ),
                      child: Text(
                        chip,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

/// Each strength exercise against its last attempt: a split bar of how
/// many went up, held or dropped, then rows grouped that way with the best
/// set last time → today. Hidden when nothing has a previous attempt.
class _TrendBreakdown extends StatelessWidget {
  const _TrendBreakdown({required this.workout});

  final SavedWorkout workout;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    List<WorkoutExerciseRecord> where(ExerciseAttemptTrend? trend) => [
      for (final exercise in workout.exercises)
        if (exercise.attemptTrend == trend &&
            (trend != null ||
                (exercise.sets.isNotEmpty &&
                    exercise.category != 'Cardio' &&
                    exercise.category != 'Sports')))
          exercise,
    ];
    final up = where(ExerciseAttemptTrend.improved);
    final same = where(ExerciseAttemptTrend.maintained);
    final down = where(ExerciseAttemptTrend.declined);
    if (up.isEmpty && same.isEmpty && down.isEmpty) {
      return const SizedBox.shrink();
    }
    final fresh = where(null);
    final groups = [
      ('UP', 'up', up, _improvedColor(context)),
      ('SAME', 'same', same, _summaryPurple),
      ('LOWER', 'lower', down, _declinedColor(context)),
      ('NEW', 'new', fresh, colors.textSecondary),
    ].where((group) => group.$3.isNotEmpty).toList(growable: false);
    final compared = groups.where((group) => group.$2 != 'new').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Semantics(
          label: compared
              .map((group) => '${group.$3.length} ${group.$2}')
              .join(', '),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 9,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < compared.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: compared[i].$3.length,
                      child: ColoredBox(color: compared[i].$4),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final group in compared)
                Text(
                  '${group.$3.length} ${group.$2}',
                  style: TextStyle(
                    color: group.$4,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        for (final group in groups) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: group.$4,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                group.$1,
                style: TextStyle(
                  color: group.$4,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          for (var i = 0; i < group.$3.length; i++)
            _TrendRow(
              exercise: group.$3[i],
              color: group.$4,
              divider: i < group.$3.length - 1,
            ),
        ],
      ],
    );
  }
}

class _TrendRow extends StatelessWidget {
  const _TrendRow({
    required this.exercise,
    required this.color,
    required this.divider,
  });

  final WorkoutExerciseRecord exercise;
  final Color color;
  final bool divider;

  static String _set(Units units, double? weightLbs, int? reps) =>
      weightLbs == null || weightLbs <= 0
      ? '${reps ?? 0} reps'
      : '${units.liftNumber(weightLbs)} × ${reps ?? 0}';

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final best = exercise.sets.fold<WorkoutSetRecord?>(
      null,
      (best, set) =>
          best == null ||
              set.weightLbs > best.weightLbs ||
              (set.weightLbs == best.weightLbs && set.reps > best.reps)
          ? set
          : best,
    );
    final today = _set(
      _units(context),
      exercise.currentAttemptWeightLbs ?? best?.weightLbs,
      exercise.currentAttemptReps ?? best?.reps,
    );
    final isNew = exercise.attemptTrend == null;
    final weightChange =
        (exercise.currentAttemptWeightLbs ?? 0) -
        (exercise.previousAttemptWeightLbs ?? 0);
    final repChange =
        (exercise.currentAttemptReps ?? 0) -
        (exercise.previousAttemptReps ?? 0);
    String signed(num value, String unit) =>
        '${value > 0 ? '+' : '−'}${value is double ? _formatNumber(value.abs()) : value.abs()} $unit';
    final changes = [
      if (weightChange.abs() >= .05)
        signed(
          _units(context).liftValue(weightChange),
          _units(context).liftLabel,
        ),
      if (repChange != 0)
        signed(repChange, repChange.abs() == 1 ? 'rep' : 'reps'),
    ];
    final chip = isNew
        ? 'First time'
        : changes.isEmpty
        ? 'Matched'
        : changes.join(' · ');
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: colors.border))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: exercise.name),
                      if (exercise.personalBest)
                        TextSpan(
                          text: '  ★ PB',
                          style: TextStyle(
                            color: _personalBestColor(context),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      if (!isNew) ...[
                        TextSpan(
                          text: _set(
                            _units(context),
                            exercise.previousAttemptWeightLbs,
                            exercise.previousAttemptReps,
                          ),
                        ),
                        TextSpan(
                          text: '  →  ',
                          style: TextStyle(color: color),
                        ),
                      ],
                      TextSpan(
                        text: today,
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ],
                  ),
                  style: muted,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              chip,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseSummaryCard extends StatelessWidget {
  const _ExerciseSummaryCard({
    required this.number,
    required this.exercise,
    this.peakBpm,
    this.peakZone,
  });

  final int number;
  final WorkoutExerciseRecord exercise;

  /// The highest heart rate during this exercise, when it's on the graph.
  final int? peakBpm;
  final WorkoutZone? peakZone;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final recommendWeightIncrease = _readyForMoreWeight(exercise);
    return _SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 38,
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: _summaryPurple,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: TextStyle(
                        color: isDark ? Colors.white : colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (exercise.category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        exercise.category,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (peakBpm != null) ...[
                const SizedBox(width: 8),
                _PeakHeartRateChip(
                  bpm: peakBpm!,
                  color: _zoneColor(context, peakZone),
                ),
              ],
            ],
          ),
          if (exercise.personalBest || exercise.attemptTrend != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if (exercise.personalBest) const _PersonalBestBadge(),
                if (exercise.attemptTrend != null)
                  _ExerciseComparisonBadge(exercise: exercise),
              ],
            ),
          ],
          if (recommendWeightIncrease) ...[
            const SizedBox(height: 10),
            _ProgressiveOverloadRecommendation(exercise: exercise),
          ],
          const SizedBox(height: 12),
          Divider(color: colors.border, height: 1),
          if (exercise.distanceKm != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.route_rounded, color: colors.textSecondary),
                const SizedBox(width: 10),
                Text(
                  _units(context).formatDistance(exercise.distanceKm!),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ] else if (exercise.sets.isEmpty) ...[
            const SizedBox(height: 14),
            Text(switch (exercise.category) {
              'Cardio' => 'No distance recorded',
              'Sports' => 'Time tracked by the workout timer',
              _ => 'No set details saved',
            }, style: TextStyle(color: colors.textSecondary)),
          ] else ...[
            const SizedBox(height: 12),
            _SetRow(set: 'SET', weight: 'WEIGHT', reps: 'REPS', header: true),
            const SizedBox(height: 6),
            for (var index = 0; index < exercise.sets.length; index++) ...[
              Divider(color: colors.border, height: 1),
              const SizedBox(height: 8),
              _SetRow(
                highlight: index == _personalBestSetIndex(exercise),
                set: '${index + 1}',
                weight: exercise.sets[index].weightLbs > 0
                    ? _units(context).formatLift(exercise.sets[index].weightLbs)
                    : '—',
                reps: exercise.sets[index].reps > 0
                    ? '${exercise.sets[index].reps}'
                    : '—',
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

/// The heart rate during the workout, coloured by zone, with each exercise
/// on a track under it when its set times place it. Dragging across shows
/// the reading and exercise at that moment; the zone bar opens the minutes
/// in each zone.
class _HeartRateCard extends StatefulWidget {
  const _HeartRateCard({
    required this.heartRate,
    required this.start,
    required this.end,
    required this.spans,
    required this.exercises,
  });

  final WorkoutHeartRate heartRate;
  final DateTime start;
  final DateTime end;
  final List<WorkoutExerciseSpan>? spans;
  final List<WorkoutExerciseRecord> exercises;

  @override
  State<_HeartRateCard> createState() => _HeartRateCardState();
}

class _HeartRateCardState extends State<_HeartRateCard> {
  HeartRateHistoryReading? scrubbed;

  void _scrub(double dx, double width) {
    final share = (dx / (width - _HeartRatePainter.axisWidth)).clamp(0.0, 1.0);
    final time = widget.start.add(widget.end.difference(widget.start) * share);
    Duration away(HeartRateHistoryReading r) =>
        r.timestamp.difference(time).abs();
    final nearest = widget.heartRate.readings.reduce(
      (a, b) => away(a) <= away(b) ? a : b,
    );
    if (nearest != scrubbed) setState(() => scrubbed = nearest);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final heartRate = widget.heartRate;
    final spans = widget.spans;
    final reading = scrubbed;
    final zones = [
      for (final zone in WorkoutZone.values)
        if (heartRate.zoneTime[zone]! > Duration.zero) zone,
    ];
    final hard = _hardMinutes(heartRate);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 22,
            child: reading == null
                ? Row(
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        color: _zoneColor(context, WorkoutZone.z5),
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'HEART RATE',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${heartRate.average} avg · ${heartRate.peak} max',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ],
                  )
                : _scrubHeader(context, reading),
          ),
          const SizedBox(height: 12),
          Semantics(
            label:
                'Heart rate graph. Average ${heartRate.average}, '
                'max ${heartRate.peak} beats per minute.',
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) =>
                    _scrub(details.localPosition.dx, constraints.maxWidth),
                onHorizontalDragUpdate: (details) =>
                    _scrub(details.localPosition.dx, constraints.maxWidth),
                onHorizontalDragEnd: (_) => setState(() => scrubbed = null),
                onHorizontalDragCancel: () => setState(() => scrubbed = null),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, spans == null ? 150 : 184),
                  painter: _HeartRatePainter(
                    heartRate: heartRate,
                    start: widget.start,
                    end: widget.end,
                    spans: spans,
                    names: [for (final e in widget.exercises) e.name],
                    zoneColors: {
                      for (final zone in WorkoutZone.values)
                        zone: _zoneColor(context, zone),
                    },
                    belowColor: colors.textSecondary,
                    gridColor: colors.border,
                    textColor: colors.textSecondary,
                    scrubbed: reading,
                  ),
                ),
              ),
            ),
          ),
          if (zones.isNotEmpty) ...[
            const SizedBox(height: 14),
            Semantics(
              button: true,
              label:
                  '${hard > 0 ? '$hard minutes in Zones 4 to 5' : 'Mostly ${_mainZone(heartRate).label}'}. '
                  'Shows time in each heart rate zone.',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showZones(context),
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: SizedBox(
                          height: 10,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < zones.length; i++) ...[
                                if (i > 0) const SizedBox(width: 2),
                                Expanded(
                                  flex: heartRate.zoneTime[zones[i]]!.inSeconds,
                                  child: ColoredBox(
                                    color: _zoneColor(context, zones[i]),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  // An easy session says where it was
                                  // instead of "0 min hard".
                                  TextSpan(
                                    text: hard > 0
                                        ? '$hard min hard'
                                        : 'Mostly ${_mainZone(heartRate).label}',
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: hard > 0
                                        ? ' (Zones 4–5)'
                                        : ' (${_mainZone(heartRate).feel.toLowerCase()})',
                                  ),
                                ],
                              ),
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Text(
                            'Zones',
                            style: TextStyle(
                              color: _summaryPurple,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: _summaryPurple,
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// While dragging: the exercise and time on the left, the reading and its
  /// zone on the right.
  Widget _scrubHeader(BuildContext context, HeartRateHistoryReading reading) {
    final colors = context.vivordoColors;
    final span = widget.spans
        ?.where((span) => span.contains(reading.timestamp))
        .firstOrNull;
    final elapsed = reading.timestamp.difference(widget.start);
    final clock =
        '${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    final zone = widget.heartRate.zoneOf(reading.bpm);
    // The name gives way before the time does.
    return Row(
      children: [
        if (span != null)
          Flexible(
            child: Text(
              widget.exercises[span.index].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        Text(
          span == null ? clock : ' · $clock',
          style: TextStyle(color: colors.textSecondary),
        ),
        const Spacer(),
        const SizedBox(width: 8),
        Text(
          '${reading.bpm.round()} bpm${zone == null ? '' : ' · ${zone.label}'}',
          style: TextStyle(
            color: _zoneColor(context, zone),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  void _showZones(BuildContext context) {
    final heartRate = widget.heartRate;
    final total = heartRate.totalInZones.inSeconds;
    showAppleSheet<void>(
      context,
      builder: (sheetContext) {
        final colors = sheetContext.vivordoColors;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Time in zones',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      'Max ${heartRate.maxHr} bpm',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final zone in WorkoutZone.values.reversed)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 86,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                zone.label,
                                style: TextStyle(
                                  color: _zoneColor(sheetContext, zone),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                zone.feel,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: total == 0
                                  ? 0
                                  : heartRate.zoneTime[zone]!.inSeconds / total,
                              minHeight: 8,
                              color: _zoneColor(sheetContext, zone),
                              backgroundColor: colors.border,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 58,
                          child: Text(
                            '${_minutes(heartRate.zoneTime[zone]!)} min',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text(
                            total == 0
                                ? '0%'
                                : '${(heartRate.zoneTime[zone]!.inSeconds / total * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                Text(
                  'Zones are shares of your maximum heart rate, estimated '
                  'from your age and the highest reading in this workout.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeartRatePainter extends CustomPainter {
  _HeartRatePainter({
    required this.heartRate,
    required this.start,
    required this.end,
    required this.spans,
    required this.names,
    required this.zoneColors,
    required this.belowColor,
    required this.gridColor,
    required this.textColor,
    required this.scrubbed,
  });

  /// Room on the right for the bpm labels.
  static const axisWidth = 30.0;
  static const _trackHeight = 22.0;
  static const _trackGap = 8.0;
  static const _footer = 18.0;

  final WorkoutHeartRate heartRate;
  final DateTime start;
  final DateTime end;
  final List<WorkoutExerciseSpan>? spans;
  final List<String> names;
  final Map<WorkoutZone, Color> zoneColors;
  final Color belowColor;
  final Color gridColor;
  final Color textColor;
  final HeartRateHistoryReading? scrubbed;

  Color _colorOf(double bpm) => zoneColors[heartRate.zoneOf(bpm)] ?? belowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final readings = heartRate.readings;
    final width = size.width - axisWidth;
    final trackTop = size.height - _footer - (spans == null ? 0 : _trackHeight);
    final plotBottom = spans == null ? trackTop : trackTop - _trackGap;
    const plotTop = 6.0;
    final bpms = readings.map((r) => r.bpm);
    final low = ((bpms.reduce(math.min) - 10) / 20).floor() * 20;
    final high = ((bpms.reduce(math.max) + 10) / 20).ceil() * 20;
    final length = end.difference(start).inMilliseconds;
    double x(DateTime time) =>
        (time.difference(start).inMilliseconds / length).clamp(0.0, 1.0) *
        width;
    double y(double bpm) =>
        plotBottom - (bpm - low) / (high - low) * (plotBottom - plotTop);
    final active = scrubbed == null
        ? null
        : spans?.where((s) => s.contains(scrubbed!.timestamp)).firstOrNull;

    // Shade every other exercise's stretch so the line lines up with the
    // track.
    for (final (i, span) in (spans ?? const <WorkoutExerciseSpan>[]).indexed) {
      canvas.drawRect(
        Rect.fromLTRB(x(span.start), plotTop, x(span.end), plotBottom),
        Paint()
          ..color = _summaryPurple.withValues(
            alpha: span == active
                ? .18
                : i.isEven
                ? .07
                : 0,
          ),
      );
    }

    final step = (high - low) / 20 > 4 ? 40 : 20;
    for (var value = (low / step).ceil() * step; value <= high; value += step) {
      canvas.drawLine(
        Offset(0, y(value.toDouble())),
        Offset(width, y(value.toDouble())),
        Paint()..color = gridColor,
      );
      _text(canvas, '$value', Offset(width + 6, y(value.toDouble()) - 7));
    }

    final line = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i + 1 < readings.length; i++) {
      final a = readings[i];
      final b = readings[i + 1];
      // A gap in the readings stays a gap.
      if (b.timestamp.difference(a.timestamp) > const Duration(minutes: 3)) {
        continue;
      }
      final color = _colorOf(a.bpm);
      line.color = active != null && !active.contains(a.timestamp)
          ? color.withValues(alpha: .35)
          : color;
      canvas.drawLine(
        Offset(x(a.timestamp), y(a.bpm)),
        Offset(x(b.timestamp), y(b.bpm)),
        line,
      );
    }

    for (final span in spans ?? const <WorkoutExerciseSpan>[]) {
      final block = RRect.fromLTRBR(
        x(span.start) + 1.5,
        trackTop,
        x(span.end) - 1.5,
        trackTop + _trackHeight,
        const Radius.circular(7),
      );
      final on = span == active;
      canvas.drawRRect(
        block,
        Paint()
          ..color = on ? _summaryPurple : _summaryPurple.withValues(alpha: .14),
      );
      // The name if it fits, else its first word ("Incline"), else the
      // exercise's number.
      final name = names[span.index];
      late TextPainter label;
      for (final text in [name, name.split(' ').first, '${span.index + 1}']) {
        label = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: on ? Colors.white : _summaryPurple,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        if (label.width <= block.width - 8) break;
      }
      label.paint(
        canvas,
        block.center - Offset(label.width / 2, label.height / 2),
      );
    }

    _text(canvas, '0', Offset(0, size.height - 14));
    _text(
      canvas,
      '${_minutes(end.difference(start))} min',
      Offset(width, size.height - 14),
      alignRight: true,
    );

    final marked = scrubbed ?? readings.reduce((a, b) => b.bpm > a.bpm ? b : a);
    if (scrubbed != null) {
      canvas.drawLine(
        Offset(x(marked.timestamp), plotTop),
        Offset(
          x(marked.timestamp),
          spans == null ? plotBottom : trackTop + _trackHeight,
        ),
        Paint()
          ..color = textColor
          ..strokeWidth = 1.2,
      );
    }
    final dot = Offset(x(marked.timestamp), y(marked.bpm));
    canvas.drawCircle(dot, 5.5, Paint()..color = Colors.white);
    canvas.drawCircle(dot, 4, Paint()..color = _colorOf(marked.bpm));
  }

  void _text(Canvas canvas, String text, Offset at, {bool alignRight = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, alignRight ? at - Offset(painter.width, 0) : at);
  }

  @override
  bool shouldRepaint(_HeartRatePainter old) =>
      old.scrubbed != scrubbed ||
      old.heartRate != heartRate ||
      old.spans != spans ||
      old.gridColor != gridColor;
}

class _PeakHeartRateChip extends StatelessWidget {
  const _PeakHeartRateChip({required this.bpm, required this.color});

  final int bpm;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Peak heart rate $bpm',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_rounded, color: color, size: 13),
            const SizedBox(width: 4),
            Text(
              'Peak $bpm',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProgressiveOverloadRecommendation extends StatelessWidget {
  const _ProgressiveOverloadRecommendation({required this.exercise});

  final WorkoutExerciseRecord exercise;

  @override
  Widget build(BuildContext context) {
    final repIncrease =
        exercise.currentAttemptReps! - exercise.previousAttemptReps!;
    final weight = _units(
      context,
    ).formatLift(exercise.currentAttemptWeightLbs!);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _summaryPurple.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _summaryPurple.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.trending_up_rounded,
            color: _summaryPurple,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'You completed $repIncrease more ${repIncrease == 1 ? 'rep' : 'reps'} at $weight. Consider increasing the weight by the smallest available increment next session.',
              style: const TextStyle(
                color: _summaryPurple,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalBestBadge extends StatelessWidget {
  const _PersonalBestBadge();

  @override
  Widget build(BuildContext context) {
    final color = _personalBestColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            'Personal best',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseComparisonBadge extends StatelessWidget {
  const _ExerciseComparisonBadge({required this.exercise});

  final WorkoutExerciseRecord exercise;

  @override
  Widget build(BuildContext context) {
    final trend = exercise.attemptTrend!;
    final differenceLabel = _exerciseDifferenceLabel(exercise, _units(context));
    final (icon, label, color) = switch (trend) {
      ExerciseAttemptTrend.improved => (
        Icons.trending_up_rounded,
        differenceLabel,
        _improvedColor(context),
      ),
      ExerciseAttemptTrend.declined => (
        Icons.trending_down_rounded,
        differenceLabel,
        _declinedColor(context),
      ),
      ExerciseAttemptTrend.maintained => (
        Icons.drag_handle_rounded,
        'Matched last time',
        _summaryPurple,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.set,
    required this.weight,
    required this.reps,
    this.header = false,
    this.highlight = false,
  });

  final String set;
  final String weight;
  final String reps;
  final bool header;

  /// Marks the set that produced this exercise's personal best.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: header
          ? context.vivordoColors.textSecondary
          : highlight
          ? _personalBestColor(context)
          : Theme.of(context).colorScheme.onSurface,
      fontSize: header ? 12 : 15,
      fontWeight: header || highlight ? FontWeight.w800 : FontWeight.w600,
      letterSpacing: header ? .7 : 0,
    );
    return Row(
      children: [
        SizedBox(width: 54, child: Text(set, style: style)),
        Expanded(
          child: Text(weight, textAlign: TextAlign.center, style: style),
        ),
        SizedBox(
          width: 62,
          child: Text(reps, textAlign: TextAlign.center, style: style),
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
      boxShadow: [
        BoxShadow(
          color: context.vivordoColors.shadow,
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

class _WorkoutOverview {
  const _WorkoutOverview({
    required this.title,
    required this.headline,
    required this.summary,
    required this.chips,
    required this.totalReps,
    required this.totalDistance,
  });

  final String title;
  final String headline;
  final String summary;
  final List<String> chips;
  final int totalReps;
  final double totalDistance;

  factory _WorkoutOverview.fromWorkout(
    SavedWorkout workout,
    Units units, {
    WorkoutHeartRate? heartRate,
  }) {
    final categories = workout.exercises
        .map((exercise) => exercise.category)
        .toSet();
    final isCardio = categories.contains('Cardio');
    final isSport = categories.contains('Sports');
    final isStrength = _hasStrengthExercise(workout);
    final title = workout.displayName == 'Workout'
        ? isStrength && !isCardio && !isSport
              ? 'Strength Workout'
              : 'Workout'
        : workout.displayName;
    final totalReps = workout.exercises.fold<int>(
      0,
      (total, exercise) =>
          total + exercise.sets.fold<int>(0, (sum, set) => sum + set.reps),
    );
    final totalDistance = workout.exercises.fold<double>(
      0,
      (total, exercise) => total + math.max(0, exercise.distanceKm ?? 0),
    );
    final improved = workout.exercises
        .where(
          (exercise) => exercise.attemptTrend == ExerciseAttemptTrend.improved,
        )
        .toList(growable: false);
    final declined = workout.exercises
        .where(
          (exercise) => exercise.attemptTrend == ExerciseAttemptTrend.declined,
        )
        .toList(growable: false);
    final maintained = workout.exercises
        .where(
          (exercise) =>
              exercise.attemptTrend == ExerciseAttemptTrend.maintained,
        )
        .toList(growable: false);
    final headline = improved.isNotEmpty && declined.isEmpty
        ? 'Progress moved forward'
        : declined.isNotEmpty && improved.isEmpty
        ? 'A lighter session than last time'
        : improved.length > declined.length
        ? 'A stronger overall session'
        : improved.isNotEmpty || maintained.isNotEmpty
        ? 'Consistent overall performance'
        : switch ((isStrength, isCardio, isSport)) {
            (true, false, false) => 'Focused strength session',
            (false, true, false) => 'Steady cardio session',
            (false, false, true) => 'Completed sports session',
            _ => 'Balanced training session',
          };
    final duration = _durationSentence(workout.durationSeconds);
    final base = isStrength
        ? 'You completed ${workout.setCount} working sets across ${workout.exerciseCount} ${workout.exerciseCount == 1 ? 'exercise' : 'exercises'} in $duration.'
        : 'You completed this session in $duration.';
    final detail = totalDistance > 0
        ? ' You covered ${units.formatDistance(totalDistance)} during the session.'
        : '';
    // The trend rows under this text show each exercise's change; the text
    // keeps the advice.
    final ready = [
      for (final exercise in workout.exercises)
        if (_readyForMoreWeight(exercise)) exercise.name,
    ];
    final overload = ready.isEmpty
        ? ''
        : ' ${_nameList(ready)} ${ready.length == 1 ? 'is' : 'are'} ready '
              'for a small weight increase next session.';
    final advice = isStrength
        ? ' Give the trained areas time to recover before your next hard session.'
        : isCardio || isSport
        ? ' Rehydrate and keep your next recovery period easy.'
        : ' Balance your next session with comfortable recovery.';
    final chips = <String>[
      // Reps, or distance when there are no reps, lead the hero card.
      if (totalReps > 0 && totalDistance > 0)
        units.formatDistance(totalDistance),
      if (workout.personalBestCount > 0)
        '★ ${workout.personalBestCount} personal ${workout.personalBestCount == 1 ? 'best' : 'bests'}',
    ];
    return _WorkoutOverview(
      title: title,
      headline: headline,
      summary:
          '$base$detail${heartRate == null ? '' : ' ${_heartRateSentence(heartRate)}'}$overload$advice',
      chips: chips,
      totalReps: totalReps,
      totalDistance: totalDistance,
    );
  }
}

/// "Your heart rate averaged 128 bpm and peaked at 171, mostly in Zone 3
/// (aerobic), with 11 minutes in Zones 4–5."
String _heartRateSentence(WorkoutHeartRate heartRate) {
  final opening =
      'Your heart rate averaged ${heartRate.average} bpm and peaked at '
      '${heartRate.peak}';
  if (heartRate.totalInZones == Duration.zero) {
    return '$opening, staying below the training zones.';
  }
  final main = _mainZone(heartRate);
  final hard = _hardMinutes(heartRate);
  final hardText = hard == 0
      ? ''
      : ', with $hard ${hard == 1 ? 'minute' : 'minutes'} in Zones 4–5';
  return '$opening, mostly in ${main.label} (${main.feel.toLowerCase()})'
      '$hardText.';
}

/// The zone with the most time.
WorkoutZone _mainZone(WorkoutHeartRate heartRate) => WorkoutZone.values.reduce(
  (a, b) => heartRate.zoneTime[b]! > heartRate.zoneTime[a]! ? b : a,
);

int _minutes(Duration time) => (time.inSeconds / 60).round();

int _hardMinutes(WorkoutHeartRate heartRate) => _minutes(
  heartRate.zoneTime[WorkoutZone.z4]! + heartRate.zoneTime[WorkoutZone.z5]!,
);

/// Each placed exercise's highest reading, by its index in the workout.
Map<int, int> _exercisePeaks(
  WorkoutHeartRate? heartRate,
  List<WorkoutExerciseSpan>? spans,
) {
  final peaks = <int, int>{};
  if (heartRate == null) return peaks;
  for (final span in spans ?? const <WorkoutExerciseSpan>[]) {
    for (final reading in heartRate.readings) {
      if (span.contains(reading.timestamp) &&
          reading.bpm.round() > (peaks[span.index] ?? 0)) {
        peaks[span.index] = reading.bpm.round();
      }
    }
  }
  return peaks;
}

/// Progressive overload: more reps than last time at the same weight.
bool _readyForMoreWeight(WorkoutExerciseRecord exercise) =>
    exercise.category != 'Cardio' &&
    exercise.category != 'Sports' &&
    exercise.currentAttemptWeightLbs != null &&
    exercise.previousAttemptWeightLbs != null &&
    exercise.currentAttemptReps != null &&
    exercise.previousAttemptReps != null &&
    shouldRecommendWeightIncrease(
      currentWeightLbs: exercise.currentAttemptWeightLbs!,
      previousWeightLbs: exercise.previousAttemptWeightLbs!,
      currentReps: exercise.currentAttemptReps!,
      previousReps: exercise.previousAttemptReps!,
    );

/// "A", "A and B", "A, B and C".
String _nameList(List<String> names) => names.length < 3
    ? names.join(' and ')
    : '${names.take(names.length - 1).join(', ')} and ${names.last}';

int? _personalBestSetIndex(WorkoutExerciseRecord exercise) {
  final weight = exercise.personalBestWeightLbs;
  final reps = exercise.personalBestReps;
  if (!exercise.personalBest || weight == null || reps == null) return null;
  final index = exercise.sets.indexWhere(
    (set) => set.weightLbs == weight && set.reps == reps,
  );
  return index < 0 ? null : index;
}

bool _hasStrengthExercise(SavedWorkout workout) => workout.exercises.any(
  (exercise) =>
      exercise.sets.isNotEmpty &&
      exercise.category != 'Cardio' &&
      exercise.category != 'Sports',
);

String _workoutDateLabel(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final day = date == today
      ? 'Today'
      : date == today.subtract(const Duration(days: 1))
      ? 'Yesterday'
      : DateFormat('MMM d, y').format(local);
  return '$day · ${DateFormat.jm().format(local)}';
}

String _durationMinutes(int seconds) =>
    math.max(0, (seconds / 60).round()).toString();

String _durationSentence(int seconds) {
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  if (minutes <= 0) return '${math.max(0, remaining)} seconds';
  if (remaining == 0) return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  return '$minutes min $remaining sec';
}

String _formatNumber(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

String _exerciseDifferenceLabel(WorkoutExerciseRecord exercise, Units units) {
  final currentWeight = exercise.currentAttemptWeightLbs;
  final previousWeight = exercise.previousAttemptWeightLbs;
  if (currentWeight != null && previousWeight != null) {
    final difference = currentWeight - previousWeight;
    if (difference.abs() >= .05) {
      final sign = difference > 0 ? '+' : '-';
      return '$sign${units.liftNumber(difference.abs())} ${units.liftLabel} vs last time';
    }
  }
  final currentReps = exercise.currentAttemptReps;
  final previousReps = exercise.previousAttemptReps;
  if (currentReps != null && previousReps != null) {
    final difference = currentReps - previousReps;
    if (difference != 0) {
      final sign = difference > 0 ? '+' : '-';
      return '$sign${difference.abs()} ${difference.abs() == 1 ? 'rep' : 'reps'} at same weight';
    }
  }
  return 'Matched last time';
}

/// The user's Settings → Units, rebuilding when they change.
Units _units(BuildContext context) => context.watch<ThemeController>().units;
