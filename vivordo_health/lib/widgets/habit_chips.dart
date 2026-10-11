import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/services/daily_priority_service.dart';
import '../src/utils/priority_schedule.dart';
import '../theme/vivordo_theme.dart';

const habitDoneGreen = Color(0xFF54C75B);
const _streakOrange = Color(0xFFF5A524);

/// Today's habits as chips. A tap adds one (or ticks it off); a long press
/// takes one away.
class HabitChips extends StatelessWidget {
  const HabitChips({
    super.key,
    required this.habits,
    required this.templates,
    required this.today,
    required this.onChanged,
  });

  final List<DailyPriority> habits;
  final Map<String, PriorityTemplate> templates;
  final DateTime today;

  /// Called with the habit and its new count.
  final void Function(DailyPriority habit, int count) onChanged;

  @override
  Widget build(BuildContext context) {
    final sorted = [...habits]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final habit in sorted)
          _HabitChip(
            key: ValueKey(habit.reference.path),
            habit: habit,
            streak: templates[habit.templateId]?.streak(today) ?? 0,
            onTap: () {
              if (habit.target == 1) {
                HapticFeedback.selectionClick();
                onChanged(habit, habit.completed ? 0 : 1);
              } else if (!habit.completed) {
                HapticFeedback.selectionClick();
                onChanged(habit, habit.count + 1);
              }
            },
            onLongPress: habit.count == 0
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onChanged(habit, habit.count - 1);
                  },
          ),
      ],
    );
  }
}

class _HabitChip extends StatelessWidget {
  const _HabitChip({
    super.key,
    required this.habit,
    required this.streak,
    required this.onTap,
    required this.onLongPress,
  });

  final DailyPriority habit;
  final int streak;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final done = habit.completed;
    final icon = habitIcon(habit.title);
    final progress = habit.target > 1 && !done
        ? '${habit.count}/${habit.target}'
        : null;
    return Semantics(
      button: true,
      label: [
        habit.title,
        if (done)
          'done'
        else if (progress != null)
          '${habit.count} of ${habit.target}',
        if (streak >= 2) '$streak day streak',
      ].join(', '),
      excludeSemantics: true,
      child: Material(
        color: done ? habitDoneGreen.withValues(alpha: .16) : colors.card,
        shape: StadiumBorder(
          side: BorderSide(
            color: done ? habitDoneGreen.withValues(alpha: .55) : colors.border,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? habitDoneGreen
                        : icon == null
                        ? null
                        : VivordoTheme.brand.withValues(alpha: .16),
                    border: done || icon != null
                        ? null
                        : Border.all(color: colors.textSecondary, width: 1.5),
                  ),
                  child: done
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        )
                      : icon == null
                      ? null
                      : Icon(icon, color: VivordoTheme.brand, size: 16),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    habit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    progress,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (streak >= 2) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.local_fire_department_rounded,
                    color: _streakOrange,
                    size: 15,
                  ),
                  Text(
                    '$streak',
                    style: const TextStyle(
                      color: _streakOrange,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
