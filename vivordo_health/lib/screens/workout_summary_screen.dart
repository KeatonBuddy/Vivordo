import 'dart:math' as math;
import '../widgets/apple_ui.dart';
import '../widgets/ios_pull_down_menu.dart';
import '../widgets/workout_ai_insight.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/src/utils/personal_best.dart';
import 'package:vivordo_health/src/utils/workout_activity_visual.dart';
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

class WorkoutSummaryScreen extends StatelessWidget {
  const WorkoutSummaryScreen({super.key, required this.workout});

  final SavedWorkout workout;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : colors.textPrimary;
    final visual = workoutActivityVisual(
      workout.displayName,
      category: workout.displayCategory,
    );
    final overview = _WorkoutOverview.fromWorkout(workout);

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
              onSelected: (action) {
                if (action == _WorkoutSummaryAction.delete) {
                  _deleteWorkout(context);
                }
              },
              actions: const [
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

enum _WorkoutSummaryAction { delete }

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
        (_formatNumber(overview.totalDistance), 'km', 'distance')
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

  static String _set(double? weight, int? reps) => weight == null || weight <= 0
      ? '${reps ?? 0} reps'
      : '${_formatNumber(weight)} × ${reps ?? 0}';

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
      if (weightChange.abs() >= .05) signed(weightChange, 'lb'),
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
  const _ExerciseSummaryCard({required this.number, required this.exercise});

  final int number;
  final WorkoutExerciseRecord exercise;

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
                  '${_formatNumber(exercise.distanceKm!)} km',
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
                    ? '${_formatNumber(exercise.sets[index].weightLbs)} lb'
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

class _ProgressiveOverloadRecommendation extends StatelessWidget {
  const _ProgressiveOverloadRecommendation({required this.exercise});

  final WorkoutExerciseRecord exercise;

  @override
  Widget build(BuildContext context) {
    final repIncrease =
        exercise.currentAttemptReps! - exercise.previousAttemptReps!;
    final weight = _formatNumber(exercise.currentAttemptWeightLbs!);
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
              'You completed $repIncrease more ${repIncrease == 1 ? 'rep' : 'reps'} at $weight lb. Consider increasing the weight by the smallest available increment next session.',
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
    final differenceLabel = _exerciseDifferenceLabel(exercise);
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

  factory _WorkoutOverview.fromWorkout(SavedWorkout workout) {
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
        ? ' You covered ${_formatNumber(totalDistance)} km during the session.'
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
        '${_formatNumber(totalDistance)} km',
      if (workout.personalBestCount > 0)
        '★ ${workout.personalBestCount} personal ${workout.personalBestCount == 1 ? 'best' : 'bests'}',
    ];
    return _WorkoutOverview(
      title: title,
      headline: headline,
      summary: '$base$detail$overload$advice',
      chips: chips,
      totalReps: totalReps,
      totalDistance: totalDistance,
    );
  }
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

String _exerciseDifferenceLabel(WorkoutExerciseRecord exercise) {
  final currentWeight = exercise.currentAttemptWeightLbs;
  final previousWeight = exercise.previousAttemptWeightLbs;
  if (currentWeight != null && previousWeight != null) {
    final difference = currentWeight - previousWeight;
    if (difference.abs() >= .05) {
      final sign = difference > 0 ? '+' : '-';
      return '$sign${_formatNumber(difference.abs())} lb vs last time';
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
