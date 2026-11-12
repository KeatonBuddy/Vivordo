import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

/// One day of a metric screen's W or M breakdown: its [value] for the line
/// and the calendar's depth, [text] for the value as written, a [note]
/// under it ("Goal met", "472 short", "Above usual"), whether it [met] the
/// goal, and the value by hour when the metric records one.
typedef BreakdownDay = ({
  DateTime date,
  double value,
  String text,
  String note,
  bool met,
  List<double>? hours,
});

/// "By day" under a metric screen's W or M chart, showing what the chart
/// can't. Week is a row per day: when in the day it happened and how close
/// it came to [mark]. Month is a calendar (weeks start on Monday, like the
/// month screens), deeper for bigger days and outlined where the goal was
/// met, with the picked day spelled out underneath. [selected] is shared
/// with the chart, so picking a day in either shows it in both.
class MetricDayBreakdown extends StatelessWidget {
  const MetricDayBreakdown({
    super.key,
    required this.days,
    required this.month,
    required this.color,
    required this.mark,
    required this.compact,
    required this.selected,
    required this.onSelected,
    this.scaleMax,
  });

  /// Oldest first, like the chart's bars.
  final List<BreakdownDay> days;
  final bool month;
  final Color color;

  /// Where the tick sits on each day's line: the goal, or the usual for a
  /// metric without one. Null draws no tick.
  final double? mark;

  /// The top of each day's line; null fits it to the day and the mark.
  final double? scaleMax;

  /// A value short enough for a calendar cell.
  final String Function(double value) compact;
  final int? selected;
  final ValueChanged<int?> onSelected;

  static const _purple = Color(0xFF5B42F3);

  bool get _hourly => days.any((d) => d.hours != null);

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: month ? _calendar(context) : _rows(context),
  );

  Widget _note(BuildContext context, BreakdownDay day, double fontSize) => Text(
    day.note,
    maxLines: 1,
    style: TextStyle(
      fontSize: fontSize,
      fontWeight: day.met ? FontWeight.w700 : FontWeight.w400,
      color: day.met
          ? context.vivordoColors.success
          : context.vivordoColors.textSecondary,
    ),
  );

  Widget _hourAxis(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      for (final label in const ['6 AM', '2 PM', '10 PM'])
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: context.vivordoColors.textSecondary,
          ),
        ),
    ],
  );

  Widget _rows(BuildContext context) {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = days.length - 1; i >= 0; i--) ...[
            if (i != days.length - 1)
              Divider(
                height: 1,
                indent: 18,
                endIndent: 18,
                color: colors.border,
              ),
            InkWell(
              onTap: () => onSelected(selected == i ? null : i),
              child: Container(
                color: selected == i ? color.withValues(alpha: .08) : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 50,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEE').format(days[i].date),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            DateFormat('MMM d').format(days[i].date),
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        children: [
                          if (_hourly) ...[
                            _HourShape(hours: days[i].hours, color: color),
                            const SizedBox(height: 7),
                          ],
                          _MarkLine(
                            value: days[i].value,
                            mark: mark,
                            scaleMax: scaleMax,
                            color: color,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 84,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              days[i].text,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (days[i].note.isNotEmpty)
                            _note(context, days[i], 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_hourly)
            Padding(
              padding: const EdgeInsets.fromLTRB(78, 0, 114, 8),
              child: _hourAxis(context),
            ),
        ],
      ),
    );
  }

  Widget _calendar(BuildContext context) {
    final colors = context.vivordoColors;
    final most = days.fold<double>(1, (m, d) => d.value > m ? d.value : m);
    final shown = selected ?? days.length - 1;
    final picked = days[shown];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.count(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (var i = 1; i < days.first.date.weekday; i++)
                const SizedBox.shrink(),
              for (final (i, day) in days.indexed)
                Semantics(
                  button: true,
                  selected: i == shown,
                  label:
                      '${DateFormat('MMMM d').format(day.date)}, ${day.text}'
                      '${day.note.isEmpty ? '' : ', ${day.note}'}',
                  child: ExcludeSemantics(
                    child: Material(
                      color: color.withValues(
                        alpha: day.value <= 0
                            ? .04
                            : .08 + .34 * day.value / most,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: i == shown
                            ? const BorderSide(color: _purple, width: 2.5)
                            : day.met
                            ? BorderSide(color: color, width: 1.5)
                            : BorderSide.none,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onSelected(i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${day.date.day}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              day.value <= 0 ? '–' : compact(day.value),
                              style: const TextStyle(fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: colors.border),
          ),
          Text(
            DateFormat('EEEE, MMM d').format(picked.date),
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                picked.text,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              _note(context, picked, 13),
            ],
          ),
          if (picked.hours != null) ...[
            const SizedBox(height: 10),
            _HourShape(hours: picked.hours, color: color, height: 30),
            const SizedBox(height: 3),
            _hourAxis(context),
          ],
        ],
      ),
    );
  }
}

/// When in the day it happened: a bar per hour from 6 AM to 10 PM, scaled
/// to the day's own busiest hour. Empty space when the hours weren't
/// recorded, so rows keep their height.
class _HourShape extends StatelessWidget {
  const _HourShape({
    required this.hours,
    required this.color,
    this.height = 20,
  });
  final List<double>? hours;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final shown = hours?.sublist(6, 22) ?? const <double>[];
    final most = shown.fold<double>(0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, v) in shown.indexed) ...[
            if (i > 0) const SizedBox(width: 1.5),
            Expanded(
              child: Container(
                height: most == 0 ? 1 : (height * v / most).clamp(1.0, height),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: v > 0 ? .55 : .15),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A day against its mark: the fill is the day, the tick is the goal or the
/// usual (which sits inside the line, so a day past it shows by how much).
class _MarkLine extends StatelessWidget {
  const _MarkLine({
    required this.value,
    required this.mark,
    required this.scaleMax,
    required this.color,
  });
  final double value;
  final double? mark, scaleMax;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tick = mark ?? 0;
    final full = scaleMax ?? (value > tick ? value : tick) * 1.15;
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: 10,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: context.vivordoColors.cardMuted,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Container(
              height: 4,
              width: full <= 0
                  ? 0
                  : constraints.maxWidth * (value / full).clamp(0.0, 1.0),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            if (tick > 0 && full > 0)
              Positioned(
                left: constraints.maxWidth * (tick / full).clamp(0.0, 1.0),
                top: 0,
                bottom: 0,
                child: Container(
                  width: 1.5,
                  color: context.vivordoColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
