import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/vivordo_theme.dart';

/// Rows shared by the My Day and calendar day timelines.

/// Completed priorities and the Now card's free dot.
const timelineDoneGreen = Color(0xFF54C75B);

/// Open slots and resets.
const timelineOpenGreen = Color(0xFF169B62);
const _nowColor = Color(0xFFE8603C);

String formatClock(DateTime time) => DateFormat('h:mm a').format(time);

String formatSpan(Duration duration) {
  final minutes = math.max(duration.inMinutes, 1);
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
}

class TimelinePill extends StatelessWidget {
  const TimelinePill(
    this.label, {
    super.key,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: .12),
    shape: const StadiumBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ),
  );
}

class TimelineNowLine extends StatelessWidget {
  const TimelineNowLine(this.now, {super.key});

  final DateTime now;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    child: Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            'Now',
            semanticsLabel: 'Now, ${formatClock(now)}',
            style: const TextStyle(
              color: _nowColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: _nowColor,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(child: Container(height: 1.5, color: _nowColor)),
      ],
    ),
  );
}

class TimelineRow extends StatelessWidget {
  const TimelineRow({
    super.key,
    required this.start,
    required this.title,
    required this.detail,
    required this.color,
    required this.onTap,
    this.past = false,
    this.completed,
    this.onToggle,
    this.energyColor,
    this.energyNote,
    this.energyAction,
    this.onEnergyAction,
    this.footer,
  });

  final DateTime start;
  final String title;
  final String detail;
  final Color color;
  final VoidCallback onTap;
  final bool past;

  /// The energy forecast's colour at this time (docs/scores.md §8), drawn
  /// as a thin strip beside the row. Null leaves no strip.
  final Color? energyColor;

  /// A clash with the energy forecast, e.g. "Lands in your afternoon dip".
  final String? energyNote;

  /// A move for the clash, e.g. "Move to 10 AM, in your peak", and what
  /// tapping it does.
  final String? energyAction;
  final VoidCallback? onEnergyAction;

  /// Shown under everything else, e.g. how your body reacted to a past event.
  final Widget? footer;

  /// Null when the row is a plain event with no linked priority.
  final bool? completed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final done = completed == true;
    // The toggle's 44 pt target spans the row's height, centred on the
    // icon: row padding 12, time 62, energy strip 10, the card's border 3
    // and padding 10, then half the 21 pt icon.
    final toggleCentre = 12 + 62 + (energyColor != null ? 10 : 0) + 13 + 10.5;
    // The clash with the energy forecast, e.g. "Lands in your afternoon dip".
    final noteRow = energyNote == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.battery_25,
                  size: 13,
                  color: Color(0xFFEF9F27),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    energyNote!,
                    style: TextStyle(
                      color: context.vivordoColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
    return InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  child: Text(
                    formatClock(start),
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                ),
                if (energyColor != null)
                  Container(
                    width: 4,
                    height: 36,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: energyColor!.withValues(alpha: .7),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: past ? .06 : .12),
                      border: Border(left: BorderSide(color: color, width: 3)),
                    ),
                    child: Row(
                      children: [
                        if (completed != null) ...[
                          Icon(
                            done
                                ? CupertinoIcons.checkmark_circle_fill
                                : CupertinoIcons.circle,
                            color: done
                                ? timelineDoneGreen
                                : colors.textSecondary,
                            size: 21,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: past || done
                                      ? colors.textSecondary
                                      : colors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  decoration: done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              if (detail.isNotEmpty)
                                Text(
                                  detail,
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              if (energyAction == null) ?noteRow,
                              // The clash and its fix are one target, the
                              // whole width of the card, so it is easy to hit.
                              if (energyAction != null)
                                Semantics(
                                  container: true,
                                  button: true,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: onEnergyAction,
                                    child: Container(
                                      width: double.infinity,
                                      // 44pt to tap, as iOS asks.
                                      constraints: const BoxConstraints(
                                        minHeight: 44,
                                      ),
                                      alignment: Alignment.centerLeft,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ?noteRow,
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              energyAction!,
                                              style: const TextStyle(
                                                color: VivordoTheme.brand,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ?footer,
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (completed != null)
            Positioned(
              left: toggleCentre - 22,
              top: 0,
              bottom: 0,
              width: 44,
              child: Semantics(
                container: true,
                button: true,
                checked: done,
                label: done ? 'Mark incomplete' : 'Mark completed',
                child: InkResponse(
                  onTap: onToggle,
                  radius: 18,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TimelineOpeningRow extends StatelessWidget {
  const TimelineOpeningRow({
    super.key,
    required this.start,
    required this.label,
    required this.onPlan,
  });

  final DateTime start;
  final String label;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPlan,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              formatClock(start),
              style: TextStyle(
                fontSize: 11,
                color: context.vivordoColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: CustomPaint(
              painter: const _DashedBorder(timelineOpenGreen),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: timelineOpenGreen,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Text(
                      '+ plan',
                      style: TextStyle(
                        color: timelineOpenGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class TimelineBreakRow extends StatelessWidget {
  const TimelineBreakRow(this.minutes, {super.key});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(74, 2, 12, 2),
      child: Row(
        children: [
          Expanded(child: Divider(color: colors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$minutes min break',
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ),
          Expanded(child: Divider(color: colors.border)),
        ],
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(9)),
      );
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 8) {
        canvas.drawPath(metric.extractPath(distance, distance + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => oldDelegate.color != color;
}
