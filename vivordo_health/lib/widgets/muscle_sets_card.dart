import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/workout_service.dart';
import '../src/utils/muscle_sets.dart';

const _purple = Color(0xFF5B28E6);
const _low = Color(0xFFE08600);

/// The Exercise screen's "Sets by muscle group": today's sets (Day), this
/// week since Monday against the usual week (Week), or the last 4 weeks a
/// week at a time (Month). Nothing without strength workouts.
class MuscleSetsSection extends StatelessWidget {
  const MuscleSetsSection({
    super.key,
    required this.workouts,
    required this.rangeIndex,
  });

  final List<SavedWorkout> workouts;

  /// 0 Day, 1 Week, 2 Month.
  final int rangeIndex;

  @override
  Widget build(BuildContext context) {
    if (setsByGroup(workouts).isEmpty) return const SizedBox.shrink();
    final today = DateTime.now();
    final card = switch (rangeIndex) {
      0 => _day(context, today),
      1 => switch (muscleSetsWeek(workouts, today)) {
        final view? => _week(context, view),
        null => _empty(context, 'No strength sets this week yet.'),
      },
      _ => switch (muscleSetsMonth(workouts, today)) {
        final view? => _month(context, view),
        null => _empty(context, 'No strength sets in the last 4 weeks.'),
      },
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Sets by muscle group',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        card,
      ],
    );
  }

  Widget _card(BuildContext context, List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _headline(BuildContext context, String value, String unit) =>
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            TextSpan(
              text: '  $unit',
              style: TextStyle(color: context.vivordoColors.textSecondary),
            ),
          ],
        ),
      );

  Widget _note(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _low.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: const Icon(CupertinoIcons.info, color: _low),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
      ],
    ),
  );

  Widget _empty(BuildContext context, String text) => _card(context, [
    Text(text, style: TextStyle(color: context.vivordoColors.textSecondary)),
  ]);

  Widget _week(BuildContext context, MuscleSetsView view) {
    final colors = context.vivordoColors;
    final scale = math.max(
      20.0,
      view.groups.fold<double>(
        0,
        (m, g) => math.max(m, math.max(g.value, g.usual ?? 0)),
      ),
    );
    final hasUsual = view.groups.any((g) => g.usual != null);
    return _card(context, [
      Row(
        children: [
          Expanded(child: _headline(context, '${view.total}', 'sets')),
          if (hasUsual) ...[
            Container(width: 2, height: 14, color: colors.textPrimary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'your usual week',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ),
          ],
        ],
      ),
      Text(
        DateTime.now().weekday == DateTime.sunday
            ? 'This week, Monday to Sunday'
            : 'This week so far, since Monday',
        style: TextStyle(fontSize: 13, color: colors.textSecondary),
      ),
      const SizedBox(height: 6),
      for (final g in view.groups)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            label:
                '${g.group}: ${g.value.round()} sets'
                '${g.usual == null ? '' : ', usual ${g.usual!.round()}'}',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  SizedBox(width: 84, child: _groupName(g.group)),
                  Expanded(
                    child: _Bar(
                      fraction: g.value / scale,
                      // No tick for a group that isn't usually trained.
                      marker: (g.usual ?? 0) < 1 ? null : g.usual! / scale,
                      color: g.low ? _low : _purple,
                    ),
                  ),
                  SizedBox(width: 34, child: _count('${g.value.round()}')),
                ],
              ),
            ),
          ),
        ),
      if (view.note case final note?) _note(context, note),
    ]);
  }

  Widget _month(BuildContext context, MuscleSetsView view) {
    final colors = context.vivordoColors;
    final scale = math.max(
      16.0,
      view.groups.fold<double>(
        0,
        (m, g) => math.max(
          m,
          math.max(g.usual ?? 0, g.weeks!.reduce(math.max).toDouble()),
        ),
      ),
    );
    final small = TextStyle(fontSize: 11, color: colors.textSecondary);
    return _card(context, [
      _headline(context, '${view.total}', 'sets a week'),
      Text(
        'Average of the last 4 weeks, Monday to Sunday',
        style: TextStyle(fontSize: 13, color: colors.textSecondary),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          SizedBox(width: 84, child: Text('Week of', style: small)),
          Expanded(
            child: Row(
              children: [
                for (final week in view.weeks)
                  Expanded(
                    child: Text(
                      DateFormat('MMM d').format(week),
                      textAlign: TextAlign.center,
                      style: small,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
      for (final g in view.groups)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Semantics(
            label:
                '${g.group}: ${g.weeks!.join(', ')} sets in the last 4 weeks'
                '${g.usual == null ? '' : ', usual ${g.usual!.round()} a week'}',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  SizedBox(width: 84, child: _groupName(g.group)),
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: CustomPaint(
                        painter: _WeeksPainter(
                          weeks: g.weeks!,
                          usual: g.usual,
                          scale: scale,
                          color: g.low ? _low : _purple,
                          empty: colors.border,
                          line: colors.textPrimary.withValues(alpha: .7),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${g.value.round()}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          TextSpan(text: '/wk', style: small),
                        ],
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (view.note case final note?) _note(context, note),
    ]);
  }

  Widget _day(BuildContext context, DateTime now) {
    final colors = context.vivordoColors;
    bool sameDay(DateTime t) => DateUtils.isSameDay(t.toLocal(), now);
    final today = [
      for (final w in workouts)
        if (sameDay(w.completedAt) && setsByGroup([w]).isNotEmpty) w,
    ];
    if (today.isEmpty) {
      final last = workouts
          .where(
            (w) =>
                w.completedAt.toLocal().isBefore(DateUtils.dateOnly(now)) &&
                setsByGroup([w]).isNotEmpty,
          )
          .fold<SavedWorkout?>(
            null,
            (a, w) => a == null || w.completedAt.isAfter(a.completedAt) ? w : a,
          );
      final sets = last == null ? null : setsByGroup([last]);
      return _card(context, [
        const Text(
          'No sets today',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (last != null && sets != null) ...[
          const SizedBox(height: 4),
          Text(
            'Last workout was ${_when(last.completedAt.toLocal(), now)}: '
            '${[for (final g in muscleGroups)
              if (sets[g] case final n?) '$g $n'].join(', ')}.',
            style: TextStyle(height: 1.45, color: colors.textSecondary),
          ),
        ],
      ]);
    }
    final sets = setsByGroup(today);
    final rows = sets.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final scale = math.max(8, rows.first.value).toDouble();
    return _card(context, [
      _headline(
        context,
        '${sets.values.fold(0, (a, b) => a + b)}',
        'sets today',
      ),
      Text(
        [
          for (final w in today)
            '${w.displayName} · ${DateFormat('h:mm a').format(w.completedAt.toLocal())}',
        ].join(', '),
        style: TextStyle(fontSize: 13, color: colors.textSecondary),
      ),
      const SizedBox(height: 6),
      for (final MapEntry(key: group, value: n) in rows)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            label: '$group: $n sets',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  SizedBox(width: 84, child: _groupName(group)),
                  Expanded(
                    child: _Bar(fraction: n / scale, color: _purple),
                  ),
                  SizedBox(width: 34, child: _count('$n')),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 14),
      Text(
        exerciseSets(today),
        style: TextStyle(
          fontSize: 13,
          height: 1.45,
          color: colors.textSecondary,
        ),
      ),
    ]);
  }

  String _when(DateTime day, DateTime now) {
    final days = DateUtils.dateOnly(
      now,
    ).difference(DateUtils.dateOnly(day)).inDays;
    return days == 1
        ? 'yesterday'
        : days < 7
        ? DateFormat('EEEE').format(day)
        : DateFormat('MMM d').format(day);
  }

  Widget _groupName(String group) => Text(
    group,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );

  Widget _count(String text) => Text(
    text,
    textAlign: TextAlign.right,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
  );
}

/// A rounded bar filled to [fraction], with a tick at [marker].
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color, this.marker});

  final double fraction;
  final double? marker;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 17,
    child: LayoutBuilder(
      builder: (context, box) => Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: 9,
            decoration: BoxDecoration(
              color: context.vivordoColors.cardMuted,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          Container(
            height: 9,
            width: box.maxWidth * fraction.clamp(0, 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          if (marker case final m?)
            Positioned(
              left: (box.maxWidth * m.clamp(0, 1) - 1).clamp(
                0,
                box.maxWidth - 2,
              ),
              top: 0,
              bottom: 0,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: context.vivordoColors.textPrimary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Month's four weekly bars, with a dashed line at the usual week.
class _WeeksPainter extends CustomPainter {
  _WeeksPainter({
    required this.weeks,
    required this.usual,
    required this.scale,
    required this.color,
    required this.empty,
    required this.line,
  });

  final List<int> weeks;
  final double? usual, scale;
  final Color color, empty, line;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0, gap = 8.0;
    final width = (size.width - inset * 2 - gap * 3) / 4;
    for (final (i, n) in weeks.indexed) {
      final height = n == 0 ? 2.0 : size.height * n / scale!;
      final x = inset + i * (width + gap);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, size.height - height, width, height),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()..color = n == 0 ? empty : color,
      );
    }
    canvas.drawLine(
      Offset(0, size.height - .5),
      Offset(size.width, size.height - .5),
      Paint()..color = empty,
    );
    if (usual case final u? when u >= 1) {
      final y = size.height - size.height * u / scale!;
      final paint = Paint()
        ..color = line
        ..strokeWidth = 2;
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width), y),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WeeksPainter old) =>
      old.weeks != weeks || old.usual != usual || old.color != color;
}
