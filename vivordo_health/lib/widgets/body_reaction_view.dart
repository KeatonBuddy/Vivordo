import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../src/utils/body_reaction.dart';
import '../src/utils/smooth_chart_path.dart';
import '../theme/vivordo_theme.dart';
import 'apple_ui.dart';

/// Label, icon and colours for the reactions worth showing; null for
/// steady, which isn't shown. [accent] reads on light and dark; [fg]/[bg]
/// are the light-mode chip.
({String label, IconData icon, Color accent, Color fg, Color bg})?
bodyReactionStyle(BodyReactionLevel level) => switch (level) {
  BodyReactionLevel.calm => (
    label: 'Calm',
    icon: Icons.spa_outlined,
    accent: const Color(0xFF1D9E75),
    fg: const Color(0xFF085041),
    bg: const Color(0xFFE1F5EE),
  ),
  BodyReactionLevel.up => (
    label: 'Heart rate up',
    icon: Icons.trending_up_rounded,
    accent: const Color(0xFFEF9F27),
    fg: const Color(0xFF633806),
    bg: const Color(0xFFFAEEDA),
  ),
  BodyReactionLevel.high => (
    label: 'Heart rate high',
    icon: Icons.monitor_heart_outlined,
    accent: const Color(0xFFE0703F),
    fg: const Color(0xFF712B13),
    bg: const Color(0xFFFAECE7),
  ),
  BodyReactionLevel.steady => null,
};

/// The small pill under a past event on My Day's timeline.
class BodyReactionChip extends StatelessWidget {
  const BodyReactionChip({super.key, required this.reaction, this.onTap});

  final BodyReaction reaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = bodyReactionStyle(reaction.level);
    if (style == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? style.accent : style.fg;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: dark ? style.accent.withValues(alpha: .18) : style.bg,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(
              style.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _bpmChange(BodyReaction r) {
  final d = r.delta.round();
  return d == 0
      ? 'Same as usual'
      : '${d > 0 ? '+' : '−'}${d.abs()} bpm vs usual';
}

/// What your heart did during an event: a line against your usual range,
/// the numbers behind it, and the wellness-estimate note.
Future<void> showBodyReactionSheet(
  BuildContext context, {
  required String title,
  required DateTime start,
  required DateTime end,
  required BodyReaction reaction,
}) {
  final style = bodyReactionStyle(reaction.level);
  final time =
      '${DateFormat.jm().format(start)} – ${DateFormat.jm().format(end)}';
  final colors = context.vivordoColors;
  return showInfoSheet(
    context,
    icon: style?.icon ?? Icons.monitor_heart_outlined,
    title: title,
    summary: '$time · ${style?.label ?? 'Steady'}',
    body: Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 170,
            child: CustomPaint(
              painter: _ReactionChart(
                reaction: reaction,
                start: start,
                end: end,
                line: style?.accent ?? VivordoTheme.brand,
                band: _usualColor.withValues(alpha: .14),
                grid: colors.border,
                label: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _LegendSwatch(
                color: _usualColor.withValues(alpha: .3),
                label: 'Your usual at this time',
              ),
              const SizedBox(width: 16),
              _LegendSwatch(
                color: style?.accent ?? VivordoTheme.brand,
                label: 'This event',
                line: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppleFormGroup(
            children: [
              AppleFormRow(
                label: 'Heart rate',
                value:
                    '${reaction.median.round()} avg · ${reaction.peak.round()} peak',
              ),
              AppleFormRow(label: 'Change', value: _bpmChange(reaction)),
              AppleFormRow(
                label: 'Your usual then',
                value:
                    '${reaction.usualLow.round()}–${reaction.usualHigh.round()} bpm',
              ),
              AppleFormRow(label: 'Readings', value: '${reaction.readings}'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'A wellness estimate from your heart rate, not a diagnosis.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    ),
  );
}

const _usualColor = Color(0xFF1D9E75);

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({
    required this.color,
    required this.label,
    this.line = false,
  });

  final Color color;
  final String label;
  final bool line;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: line ? 3 : 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: context.vivordoColors.textSecondary,
        ),
      ),
    ],
  );
}

/// Heart rate through the event: a smoothed curve over your usual band,
/// bpm gridlines on the right and times along the bottom.
class _ReactionChart extends CustomPainter {
  _ReactionChart({
    required this.reaction,
    required this.start,
    required this.end,
    required this.line,
    required this.band,
    required this.grid,
    required this.label,
  });

  final BodyReaction reaction;
  final DateTime start, end;
  final Color line, band, grid, label;

  /// Readings averaged into short steps (about eight across the event), so
  /// sensor noise doesn't read as a jagged line.
  List<(DateTime, double)> get _points {
    final minutes = math.max(1, end.difference(start).inMinutes);
    final step = math.max(5, (minutes / 8).ceil());
    final buckets = <int, List<double>>{};
    for (final s in reaction.samples) {
      buckets
          .putIfAbsent(
            s.timestamp.difference(start).inMinutes ~/ step,
            () => [],
          )
          .add(s.bpm);
    }
    final keys = buckets.keys.toList()..sort();
    final points = [
      for (final k in keys)
        (
          start.add(Duration(minutes: math.min(minutes, k * step + step ~/ 2))),
          buckets[k]!.reduce((a, b) => a + b) / buckets[k]!.length,
        ),
    ];
    // Run the line from the first reading to the last, not mid-step.
    if (points.length > 1) {
      points.first = (reaction.samples.first.timestamp, points.first.$2);
      points.last = (reaction.samples.last.timestamp, points.last.$2);
    }
    return points;
  }

  void _text(Canvas canvas, String text, Offset at, {TextAlign? align}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: label, fontFamily: 'DMSans'),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.center => at.dx - painter.width / 2,
      TextAlign.right => at.dx - painter.width,
      _ => at.dx,
    };
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final points = _points;
    if (points.isEmpty) return;
    const right = 30.0, bottom = 22.0, top = 6.0;
    final width = size.width - right;
    final height = size.height - bottom;
    final bpms = [for (final p in points) p.$2];
    var lo =
        ((math.min(reaction.usualLow, bpms.reduce(math.min)) - 5) / 10)
            .floorToDouble() *
        10;
    var hi =
        ((math.max(reaction.usualHigh, bpms.reduce(math.max)) + 5) / 10)
            .ceilToDouble() *
        10;
    if (hi - lo < 30) {
      lo -= 10;
      hi = lo + 40;
    }
    final span = math.max(1, end.difference(start).inSeconds);
    double y(double bpm) => top + (height - top) * (1 - (bpm - lo) / (hi - lo));
    double x(DateTime t) =>
        width * (t.difference(start).inSeconds / span).clamp(0.0, 1.0);

    // Gridlines and bpm labels.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final gridStep = (hi - lo) <= 40 ? 10.0 : 20.0;
    for (var v = lo; v <= hi; v += gridStep) {
      canvas.drawLine(Offset(0, y(v)), Offset(width, y(v)), gridPaint);
      _text(canvas, '${v.round()}', Offset(width + 6, y(v)));
    }

    // Your usual.
    canvas.drawRRect(
      RRect.fromLTRBR(
        0,
        y(reaction.usualHigh),
        width,
        y(reaction.usualLow),
        const Radius.circular(4),
      ),
      Paint()..color = band,
    );

    // Times: start, end, and the round quarter-hours between when there's room.
    final minutes = end.difference(start).inMinutes;
    final tickStep = minutes <= 45 ? 15 : (minutes <= 120 ? 30 : 60);
    _text(canvas, DateFormat.jm().format(start), Offset(0, size.height - 7));
    _text(
      canvas,
      DateFormat.jm().format(end),
      Offset(width, size.height - 7),
      align: TextAlign.right,
    );
    var tick = DateTime(start.year, start.month, start.day, start.hour);
    while (!tick.isAfter(start)) {
      tick = tick.add(Duration(minutes: tickStep));
    }
    for (; tick.isBefore(end); tick = tick.add(Duration(minutes: tickStep))) {
      final tx = x(tick);
      if (tx < 60 || tx > width - 60) continue;
      canvas.drawLine(Offset(tx, height), Offset(tx, height + 4), gridPaint);
      _text(
        canvas,
        DateFormat('h:mm').format(tick),
        Offset(tx, size.height - 7),
        align: TextAlign.center,
      );
    }

    // The event's heart rate.
    final offsets = [for (final p in points) Offset(x(p.$1), y(p.$2))];
    if (offsets.length == 1) {
      canvas.drawCircle(offsets.first, 4, Paint()..color = line);
      return;
    }
    final path = smoothChartPath(offsets);
    canvas.drawPath(
      Path.from(path)
        ..lineTo(offsets.last.dx, height)
        ..lineTo(offsets.first.dx, height)
        ..close(),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, height), [
          line.withValues(alpha: .22),
          line.withValues(alpha: 0),
        ]),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // Mark the highest point.
    final highest = offsets.reduce((a, b) => b.dy < a.dy ? b : a);
    canvas.drawCircle(highest, 4.5, Paint()..color = line);
    canvas.drawCircle(highest, 2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ReactionChart old) => old.reaction != reaction;
}
