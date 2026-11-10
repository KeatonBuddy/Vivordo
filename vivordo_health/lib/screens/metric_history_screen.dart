import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/achievement_inputs.dart';
import 'package:vivordo_health/src/services/achievement_service.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/utils/metric_history.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import '../src/utils/chart_text.dart';

const _purple = Color(0xFF5B42F3);
final _number = NumberFormat.decimalPattern();

/// The activity metrics with a lifetime history. Sleep, heart rate and mood
/// have no compact daily summary yet, so reading their history would mean
/// every full day record.
enum HistoryMetric {
  steps('Steps', 'steps', Color(0xFF2878E8)),
  calories('Active Calories', 'kcal', Color(0xFFFF6A00)),
  exercise('Exercise', 'min', Color(0xFF5B28E6));

  const HistoryMetric(this.title, this.unit, this.color);
  final String title;
  final String unit;
  final Color color;

  num? of(AchievementMetricDay day) => switch (this) {
    steps => day.steps,
    calories => day.calories,
    exercise => day.minutes,
  };

  int goal(ActivityGoals goals) => switch (this) {
    steps => goals.steps,
    calories => goals.activeCalories,
    exercise => goals.exerciseMinutes,
  };

  String format(double value) => '${_number.format(value.round())} $unit';

  String total(double value) => this == exercise
      ? '${_number.format((value / 60).round())} h'
      : value >= 1e6
      ? '${(value / 1e6).toStringAsFixed(2)}M $unit'
      : format(value);

  /// Fits a calendar cell: "8.9k" steps, "640" kcal, "45" min.
  String compact(double value) => this == steps
      ? '${(value / 1000).toStringAsFixed(1)}k'
      : '${value.round()}';
}

/// A metric screen's 6M and Y views: a bar per week (6M) or month (Y)
/// against the goal, the period's best, total and goal days, and a row per
/// month that opens its calendar. [header] is the screen's range control.
class MetricHistoryView extends StatefulWidget {
  const MetricHistoryView({
    super.key,
    required this.metric,
    required this.months,
    required this.header,
  });
  final HistoryMetric metric;

  /// 6 (weekly bars) or 12 (monthly bars).
  final int months;
  final Widget header;

  @override
  State<MetricHistoryView> createState() => _MetricHistoryViewState();
}

class _MetricHistoryViewState extends State<MetricHistoryView> {
  // Kept across 6M and Y: the same state serves both.
  late final _days = AchievementService.activityHistory();

  HistoryMetric get metric => widget.metric;
  bool get _weekly => widget.months == 6;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<Map<String, AchievementMetricDay>>(
        future: _days,
        builder: (context, days) {
          if (days.hasError) {
            return _list([_message("Couldn't load your history.")]);
          }
          if (!days.hasData) {
            return _list([
              const Padding(
                padding: EdgeInsets.all(40),
                child: CupertinoActivityIndicator(),
              ),
            ]);
          }
          return StreamBuilder<ActivityGoals>(
            stream: ActivityGoalsService.watch(),
            initialData: const ActivityGoals(),
            builder: (context, goals) => _content(
              MetricHistory({
                for (final MapEntry(:key, :value) in days.data!.entries)
                  key: metric.of(value),
              }, goal: metric.goal(goals.data ?? const ActivityGoals())),
            ),
          );
        },
      );

  /// Laid out like the Day/Week/Month views, so the range control stays put.
  Widget _list(List<Widget> children) => ListView(
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
    children: [
      Center(
        child: Text(
          'Daily average by ${_weekly ? 'week' : 'month'}',
          style: TextStyle(color: context.vivordoColors.textSecondary),
        ),
      ),
      const SizedBox(height: 18),
      widget.header,
      const SizedBox(height: 18),
      ...children,
    ],
  );

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.all(32),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: context.vivordoColors.textSecondary),
    ),
  );

  Widget _content(MetricHistory history) {
    final first = history.first;
    if (first == null) {
      return _list([_message('No ${metric.title.toLowerCase()} synced yet.')]);
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = DateTime(now.year, now.month - widget.months + 1);
    final bars = _weekly
        ? history.weeks(from, today)
        : history.months(from, today);
    final firstMonth = DateTime(first.year, first.month);
    final months = history
        .months(from, today)
        .where((m) => !m.start.isBefore(firstMonth))
        .toList();
    final values = history.between(from, today.add(const Duration(days: 1)));
    final days = values.length;
    final total = values.sum;
    final average = days == 0 ? 0.0 : total / days;
    final goalDays = values.where((v) => v >= history.goal).length;
    MetricPeriod? best(Iterable<MetricPeriod> periods) => periods
        .where((p) => p.days > 0)
        .fold<MetricPeriod?>(
          null,
          (best, p) => best == null || p.average > best.average ? p : best,
        );
    final bestMonth = best(months);
    final bestBar = best(bars);
    final bestDay = history.bestSince(from);
    final period = _weekly ? 'week' : 'month';

    return _list([
      _card(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily average',
              style: TextStyle(
                color: context.vivordoColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text.rich(
              TextSpan(
                text: _number.format(average.round()),
                children: [
                  TextSpan(
                    text: ' ${metric.unit}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: context.vivordoColors.textSecondary,
                    ),
                  ),
                ],
              ),
              style: const TextStyle(
                fontSize: 40,
                height: 1.15,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              '${DateFormat('MMM d, y').format(from)} – today',
              style: TextStyle(color: context.vivordoColors.textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 170,
              child: _PeriodBars(
                periods: bars,
                weekly: _weekly,
                best: bestBar,
                goal: history.goal.toDouble(),
                metric: metric,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Each bar is a $period's daily average. The dashed line is "
              'your goal${bestBar == null ? '' : ', and the solid bar your best $period'}.',
              style: TextStyle(
                fontSize: 12,
                color: context.vivordoColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          _tile(
            'Best month',
            bestMonth == null
                ? '–'
                : DateFormat('MMM y').format(bestMonth.start),
            bestMonth == null
                ? ''
                : '${metric.format(bestMonth.average)} a day',
          ),
          const SizedBox(width: 10),
          _tile(
            'Best day',
            bestDay == null ? '–' : metric.format(bestDay.value),
            bestDay == null
                ? ''
                : DateFormat('EEE, MMM d, y').format(bestDay.key),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          _tile('Goal days', _number.format(goalDays), 'of $days days'),
          const SizedBox(width: 10),
          _tile('Total', metric.total(total), 'over $days days'),
        ],
      ),
      if (months.isNotEmpty) ...[
        const SizedBox(height: 26),
        const Text(
          'By month',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        _card(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, month) in months.reversed.indexed) ...[
                if (i > 0)
                  Divider(height: 1, color: context.vivordoColors.border),
                _monthRow(
                  month,
                  history,
                  firstMonth,
                  bestMonth,
                  months.map((m) => m.average).max,
                ),
              ],
            ],
          ),
        ),
      ],
    ]);
  }

  Widget _monthRow(
    MetricPeriod month,
    MetricHistory history,
    DateTime firstMonth,
    MetricPeriod? best,
    double maxAverage,
  ) {
    final now = DateTime.now();
    final current =
        month.start.year == now.year && month.start.month == now.month;
    final name = DateFormat(
      month.start.year == now.year ? 'MMMM' : 'MMM y',
    ).format(month.start);
    final note = month.days == 0
        ? 'No data'
        : current
        ? 'So far · ${month.days} ${month.days == 1 ? 'day' : 'days'}'
        : '${month.goalDays} goal ${month.goalDays == 1 ? 'day' : 'days'}';
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MetricMonthScreen(
            metric: metric,
            history: history,
            month: month.start,
            firstMonth: firstMonth,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.vivordoColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: maxAverage == 0 ? 0 : month.average / maxAverage,
                  minHeight: 8,
                  color: metric.color.withValues(
                    alpha: month.start == best?.start ? 1 : .55,
                  ),
                  backgroundColor: context.vivordoColors.cardMuted,
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                month.days == 0 ? '–' : _number.format(month.average.round()),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: context.vivordoColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(String label, String value, String note) => Expanded(
    child: _card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.vivordoColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: context.vivordoColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _card({required Widget child, required EdgeInsets padding}) =>
      _historyCard(context, padding, child);
}

PreferredSizeWidget _appBar(BuildContext context, String title) => AppBar(
  backgroundColor: context.vivordoColors.page,
  elevation: 0,
  centerTitle: true,
  leading: IconButton(
    tooltip: 'Back',
    onPressed: () => Navigator.pop(context),
    icon: const Icon(CupertinoIcons.back),
    color: _purple,
  ),
  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
);

Widget _historyCard(BuildContext context, EdgeInsets padding, Widget child) =>
    Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: child,
    );

/// A bar per week or month's daily average, the best one solid, the goal
/// dashed.
class _PeriodBars extends StatelessWidget {
  const _PeriodBars({
    required this.periods,
    required this.weekly,
    required this.best,
    required this.goal,
    required this.metric,
  });
  final List<MetricPeriod> periods;
  final bool weekly;
  final MetricPeriod? best;
  final double goal;
  final HistoryMetric metric;

  @override
  Widget build(BuildContext context) {
    final best = this.best;
    return Semantics(
      label: best == null
          ? 'No data in this range.'
          : 'Average a day by ${weekly ? 'week' : 'month'}. Best was '
                '${weekly ? 'the week of ${DateFormat('MMMM d').format(best.start)}' : DateFormat('MMMM y').format(best.start)}'
                ' with ${metric.format(best.average)}.',
      child: ExcludeSemantics(
        child: CustomPaint(
          size: Size.infinite,
          painter: _PeriodBarsPainter(
            averages: [for (final p in periods) p.average],
            // A week is labelled with the month whose 1st it holds; months
            // every other one, counted back from this month.
            labels: [
              for (final (i, p) in periods.indexed)
                weekly
                    ? _holdsFirst(p.start)
                          ? DateFormat(
                              'MMM',
                            ).format(p.start.add(const Duration(days: 6)))
                          : ''
                    : (periods.length - 1 - i).isEven
                    ? DateFormat('MMM').format(p.start)
                    : '',
            ],
            best: best == null ? null : periods.indexOf(best),
            goal: goal,
            color: metric.color,
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
        ),
      ),
    );
  }
}

bool _holdsFirst(DateTime weekStart) =>
    weekStart.day == 1 ||
    DateTime(weekStart.year, weekStart.month, weekStart.day + 6).month !=
        weekStart.month;

class _PeriodBarsPainter extends CustomPainter {
  const _PeriodBarsPainter({
    required this.averages,
    required this.labels,
    required this.best,
    required this.goal,
    required this.color,
    required this.dark,
  });
  final List<double> averages;
  final List<String> labels;
  final int? best;
  final double goal;
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 20.0, goalLabel = 30.0;
    final height = size.height - bottom;
    final width = size.width - goalLabel;
    final maxY = [goal, ...averages].max * 1.15;
    double y(double v) => height * (1 - (v / maxY).clamp(0.0, 1.0));
    final muted = dark ? Colors.white54 : Colors.black54;

    canvas.drawLine(
      Offset(0, height),
      Offset(width, height),
      Paint()
        ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .12),
    );
    final slot = width / averages.length;
    final barWidth = math.min(18.0, slot * .62);
    for (var i = 0; i < averages.length; i++) {
      final x = i * slot + (slot - barWidth) / 2;
      if (averages[i] > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(x, y(averages[i]), x + barWidth, height),
            topLeft: Radius.circular(math.min(4, barWidth / 2)),
            topRight: Radius.circular(math.min(4, barWidth / 2)),
          ),
          Paint()..color = color.withValues(alpha: i == best ? 1 : .45),
        );
      }
      if (labels[i].isNotEmpty) {
        _text(
          canvas,
          labels[i],
          Offset(i * slot + slot / 2, height + 5),
          muted,
          center: true,
        );
      }
    }
    final goalY = y(goal);
    final dash = Paint()
      ..color = muted
      ..strokeWidth = 1;
    for (var x = 0.0; x < width; x += 8) {
      canvas.drawLine(
        Offset(x, goalY),
        Offset(math.min(x + 4, width), goalY),
        dash,
      );
    }
    _text(canvas, 'Goal', Offset(width + 4, goalY - 7), muted);
  }

  void _text(
    Canvas canvas,
    String value,
    Offset offset,
    Color color, {
    bool center = false,
  }) {
    final painter = TextPainter(
      textScaler: chartTextScaler,
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: 10, color: color),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center ? Offset(offset.dx - painter.width / 2, offset.dy) : offset,
    );
  }

  @override
  bool shouldRepaint(covariant _PeriodBarsPainter old) =>
      !const ListEquality<double>().equals(averages, old.averages) ||
      !const ListEquality<String>().equals(labels, old.labels) ||
      best != old.best ||
      goal != old.goal ||
      dark != old.dark;
}

/// One month as a calendar, each day shaded by its value, a ring on goal
/// days. Tapping a day shows it below.
class MetricMonthScreen extends StatefulWidget {
  const MetricMonthScreen({
    super.key,
    required this.metric,
    required this.history,
    required this.month,
    required this.firstMonth,
  });
  final HistoryMetric metric;
  final MetricHistory history;
  final DateTime month;
  final DateTime firstMonth;

  @override
  State<MetricMonthScreen> createState() => _MetricMonthScreenState();
}

class _MetricMonthScreenState extends State<MetricMonthScreen> {
  late DateTime _month = widget.month;
  late int? _day = _bestDay;

  HistoryMetric get metric => widget.metric;
  Map<int, double> get _values => widget.history.daysIn(_month);
  int? get _bestDay => _values.entries
      .fold<MapEntry<int, double>?>(
        null,
        (best, day) => best == null || day.value > best.value ? day : best,
      )
      ?.key;

  void _move(int months) => setState(() {
    _month = DateTime(_month.year, _month.month + months);
    _day = _bestDay;
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final values = _values;
    final goal = widget.history.goal;
    final average = values.isEmpty ? 0.0 : values.values.sum / values.length;
    final goalDays = values.values.where((v) => v >= goal).length;
    final canBack = _month.isAfter(widget.firstMonth);
    final canForward = _month.isBefore(DateTime(now.year, now.month));
    final lead = DateTime(_month.year, _month.month).weekday - 1;
    final length = DateTime(_month.year, _month.month + 1, 0).day;
    final best = _bestDay;
    final day = _day;
    final selected = day == null ? null : values[day];

    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      appBar: _appBar(context, metric.title),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Row(
            children: [
              _arrow(
                CupertinoIcons.chevron_left,
                'Previous month',
                canBack,
                -1,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      DateFormat('MMMM y').format(_month),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      values.isEmpty
                          ? 'No data this month'
                          : '${metric.format(average)} a day · '
                                '$goalDays goal ${goalDays == 1 ? 'day' : 'days'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.vivordoColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _arrow(CupertinoIcons.chevron_right, 'Next month', canForward, 1),
            ],
          ),
          const SizedBox(height: 16),
          _historyCard(
            context,
            const EdgeInsets.fromLTRB(12, 16, 12, 14),
            Column(
              children: [
                Row(
                  children: [
                    for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(
                            d,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.vivordoColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 5,
                  crossAxisSpacing: 5,
                  childAspectRatio: .95,
                  children: [
                    for (var i = 0; i < lead; i++) const SizedBox.shrink(),
                    for (var d = 1; d <= length; d++)
                      _cell(d, values[d], goal, d == day),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Darker days had more. A ring means you met your goal.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.vivordoColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (day != null && selected != null) ...[
            const SizedBox(height: 12),
            _historyCard(
              context,
              const EdgeInsets.all(18),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat(
                            'EEEE, MMMM d',
                          ).format(DateTime(_month.year, _month.month, day)),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (day == best && values.length > 1)
                        Text(
                          'Best day this month',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.vivordoColors.success,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metric.format(selected),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Divider(height: 24, color: context.vivordoColors.border),
                  Row(
                    children: [
                      _stat(
                        '${selected >= average ? '+' : '−'}'
                            '${((selected - average).abs() / average * 100).round()}%',
                        'vs month average',
                      ),
                      _stat(
                        '${(selected / goal * 100).round()}%',
                        'of your goal',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, String label, bool enabled, int months) =>
      IconButton(
        tooltip: label,
        onPressed: enabled ? () => _move(months) : null,
        icon: Icon(icon, size: 20),
        color: _purple,
      );

  Widget _cell(int day, double? value, num goal, bool selected) {
    if (value == null) {
      return Center(
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 12,
            color: context.vivordoColors.textSecondary,
          ),
        ),
      );
    }
    final strength = math.min(1.0, value / (goal * 1.3));
    // Capped so the day's text stays readable on the darkest cells.
    final alpha = .1 + .55 * strength;
    final met = value >= goal;
    final date = DateTime(_month.year, _month.month, day);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${DateFormat('MMMM d').format(date)}, ${metric.format(value)}'
          '${met ? ', goal met' : ''}',
      child: ExcludeSemantics(
        child: Material(
          color: metric.color.withValues(alpha: alpha),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: selected
                ? const BorderSide(color: _purple, width: 2.5)
                : met
                ? BorderSide(color: metric.color, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _day = day),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  metric.compact(value),
                  style: const TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: context.vivordoColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
