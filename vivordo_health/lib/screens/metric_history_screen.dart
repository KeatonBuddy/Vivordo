import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/achievement_inputs.dart';
import 'package:vivordo_health/src/services/achievement_service.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/utils/metric_history.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import '../src/utils/chart_text.dart';

const _purple = Color(0xFF5B42F3);
final _number = NumberFormat.decimalPattern();

/// The metrics with 6M and Y views, read from the compact daily summaries.
enum HistoryMetric {
  steps('Steps', 'steps', Color(0xFF2878E8)),
  calories('Active Calories', 'kcal', Color(0xFFFF6A00)),
  exercise('Exercise', 'min', Color(0xFF5B28E6)),
  sleep('Sleep', '', Color(0xFF7F77DD)),
  heartRate('Resting heart rate', 'bpm', Color(0xFFE5484D)),
  mood('Mood', '', Color(0xFFF08C2E));

  const HistoryMetric(this.title, this.unit, this.color);
  final String title;
  final String unit;
  final Color color;

  num? of(AchievementMetricDay day) => switch (this) {
    steps => day.steps,
    calories => day.calories,
    exercise => day.minutes,
    sleep => day.sleep,
    heartRate => day.restingHeartRate,
    mood => day.mood,
  };

  /// The activity goal; sleep's need comes from its screen, and heart rate
  /// and mood have none.
  int? goal(ActivityGoals goals) => switch (this) {
    steps => goals.steps,
    calories => goals.activeCalories,
    exercise => goals.exerciseMinutes,
    _ => null,
  };

  bool get isActivity => this == steps || this == calories || this == exercise;

  /// A lower resting heart rate is the better one.
  bool get lowerIsBetter => this == heartRate;

  String get goalName => this == sleep ? 'sleep need' : 'goal';
  String get day => this == sleep ? 'night' : 'day';
  String get bestWord => lowerIsBetter ? 'lowest' : 'best';

  String get bestMonthLabel => switch (this) {
    sleep => 'Most sleep',
    heartRate => 'Lowest month',
    _ => 'Best month',
  };
  String get bestDayLabel => switch (this) {
    sleep => 'Longest night',
    heartRate => 'Lowest day',
    _ => 'Best day',
  };
  String get worstDayLabel => switch (this) {
    sleep => 'Shortest night',
    heartRate => 'Highest day',
    _ => 'Lowest day',
  };

  /// The number alone: "8,912", "7 h 24 m", "58".
  String number(double value) =>
      this == sleep ? hoursMinutes(value) : _number.format(value.round());

  /// "8,912 steps", "7 h 24 m", "58 bpm", "72 · Good".
  String format(double value) => switch (this) {
    sleep => hoursMinutes(value),
    mood => '${value.round()} · ${moodName(value)}',
    _ => '${_number.format(value.round())} $unit',
  };

  /// After the big number: "steps a day", "a night", "bpm", "Good".
  String suffix(double value) => switch (this) {
    sleep => 'a night',
    mood => moodName(value),
    heartRate => 'bpm',
    _ => '$unit a day',
  };

  String total(double value) => this == exercise
      ? '${_number.format((value / 60).round())} h'
      : value >= 1e6
      ? '${(value / 1e6).toStringAsFixed(2)}M $unit'
      : format(value);

  /// Fits a month row or calendar cell: "8.9k" steps, "7:24" sleep, "58".
  String compact(double value) => switch (this) {
    steps => '${(value / 1000).toStringAsFixed(1)}k',
    sleep => () {
      final minutes = (value * 60).round();
      return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
    }(),
    _ => '${value.round()}',
  };

  static String moodName(double score) => switch (score.round()) {
    >= 90 => 'Great',
    >= 65 => 'Good',
    >= 40 => 'Okay',
    >= 20 => 'Low',
    _ => 'Stressed',
  };
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
    this.goal,
  });
  final HistoryMetric metric;

  /// Sleep's need; activity metrics use their goals, the rest have none.
  final double? goal;

  /// 6 (weekly bars) or 12 (monthly bars).
  final int months;
  final Widget header;

  /// Has 6M and Y ready before they are tapped; each metric screen calls it
  /// as it opens. A failure is left for the view to report when it loads.
  static void preload() {
    if (_MetricHistoryViewState._loaded != null) return;
    unawaited(
      _MetricHistoryViewState._load().catchError(
        (_) => const <String, AchievementMetricDay>{},
      ),
    );
  }

  @override
  State<MetricHistoryView> createState() => _MetricHistoryViewState();
}

class _MetricHistoryViewState extends State<MetricHistoryView> {
  // Kept across 6M and Y: the same state serves both.
  late final _days = _load();

  /// The history last loaded, with whose it is. The view is rebuilt on each
  /// switch to 6M or Y, and without this it blinks empty for a frame while
  /// the same history loads again.
  static (String, Map<String, AchievementMetricDay>)? _loaded;

  static Future<Map<String, AchievementMetricDay>> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final days = await AchievementService.activityHistory();
    if (uid != null) _loaded = (uid, days);
    return days;
  }

  HistoryMetric get metric => widget.metric;
  bool get _weekly => widget.months == 6;

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<Map<String, AchievementMetricDay>>(
        future: _days,
        initialData: _loaded?.$1 == FirebaseAuth.instance.currentUser?.uid
            ? _loaded?.$2
            : null,
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
              MetricHistory(
                {
                  for (final MapEntry(:key, :value) in days.data!.entries)
                    key: metric.of(value),
                },
                goal:
                    widget.goal ??
                    metric.goal(goals.data ?? const ActivityGoals()),
              ),
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
          '${switch (metric) {
            HistoryMetric.sleep => 'Average night',
            HistoryMetric.heartRate => 'Resting average',
            _ => 'Daily average',
          }} by ${_weekly ? 'week' : 'month'}',
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
    final goal = history.goal;
    final goalDays = history.goalDays(values);
    final lowest = metric.lowerIsBetter;
    MetricPeriod? best(Iterable<MetricPeriod> periods) => periods
        .where((p) => p.days > 0)
        .fold<MetricPeriod?>(
          null,
          (best, p) =>
              best == null ||
                  (lowest ? p.average < best.average : p.average > best.average)
              ? p
              : best,
        );
    final bestMonth = best(months);
    final bestBar = best(bars);
    final bestDay = history.extremeSince(from, lowest: lowest);
    final worstDay = history.extremeSince(from, lowest: !lowest);
    final period = _weekly ? 'week' : 'month';
    // The same 28-day band as W and M, so it holds still across ranges.
    final usual = goal != null
        ? null
        : usualRange(
            history.between(
              today.subtract(const Duration(days: 28)),
              today.add(const Duration(days: 1)),
            ),
          );
    final perDay = metric == HistoryMetric.sleep
        ? 'a night'
        : metric.isActivity
        ? 'a day'
        : 'on average';
    final daysText = '$days ${metric.day}${days == 1 ? '' : 's'}';

    return _list([
      MetricChartCard(
        label: switch (metric) {
          HistoryMetric.sleep => 'Average night',
          HistoryMetric.heartRate => 'Average resting',
          _ => 'Daily average',
        },
        number: metric.number(average),
        unit: switch (metric) {
          HistoryMetric.sleep => '',
          HistoryMetric.mood => HistoryMetric.moodName(average),
          _ => metric.unit,
        },
        range: '${DateFormat('MMM d, y').format(from)} – today',
        chart: _PeriodBars(
          periods: bars,
          weekly: _weekly,
          best: bestBar,
          goal: goal?.toDouble(),
          usual: usual,
          metric: metric,
        ),
        caption:
            "Each bar is a $period's average."
            '${usual == null ? '' : ' The band is your usual range over the last 28 days.'}'
            '${goal == null ? '' : ' The dashed line is your ${metric.goalName}.'}'
            '${bestBar == null ? '' : ' The solid bar is your ${metric.bestWord} $period.'}',
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          _tile(
            metric.bestMonthLabel,
            bestMonth == null
                ? '–'
                : DateFormat('MMM y').format(bestMonth.start),
            bestMonth == null
                ? ''
                : '${metric.format(bestMonth.average)} $perDay',
          ),
          const SizedBox(width: 10),
          _dayTile(metric.bestDayLabel, bestDay),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          goal != null
              ? _tile(
                  metric == HistoryMetric.sleep ? 'Enough sleep' : 'Goal days',
                  _number.format(goalDays),
                  'of $daysText',
                )
              : _tile(
                  metric == HistoryMetric.mood ? 'Check-ins' : 'Days',
                  _number.format(days),
                  metric == HistoryMetric.mood
                      ? 'days logged'
                      : 'with a reading',
                ),
          const SizedBox(width: 10),
          metric.isActivity
              ? _tile('Total', metric.total(total), 'over $daysText')
              : _dayTile(metric.worstDayLabel, worstDay),
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
        : history.goal != null && metric.isActivity
        ? '${month.goalDays} goal ${month.goalDays == 1 ? 'day' : 'days'}'
        : '${month.days} ${metric.day}${month.days == 1 ? '' : 's'}';
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
                month.days == 0
                    ? '–'
                    : metric == HistoryMetric.sleep
                    ? metric.compact(month.average)
                    : metric.number(month.average),
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

  Widget _dayTile(String label, MapEntry<DateTime, double>? day) => _tile(
    label,
    day == null ? '–' : metric.format(day.value),
    day == null ? '' : DateFormat('EEE, MMM d, y').format(day.key),
  );

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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: child,
    );

/// The card every bar-chart range shares (W and M on the metric screens, 6M
/// and Y here): the average, the dates it covers, any [note] such as a
/// change against usual, then the [chart] and what its marks mean.
class MetricChartCard extends StatelessWidget {
  const MetricChartCard({
    super.key,
    required this.label,
    required this.number,
    required this.unit,
    required this.range,
    required this.chart,
    required this.caption,
    this.note,
    this.insight,
    this.footer,
  });

  /// The screen's insight, between the number and the chart.
  final Widget? insight;
  final String label;
  final String number;
  final String unit;
  final String range;
  final Widget chart;
  final String caption;
  final Widget? note;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final secondary = context.vivordoColors.textSecondary;
    return _historyCard(
      context,
      const EdgeInsets.fromLTRB(18, 20, 18, 14),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: secondary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text.rich(
            TextSpan(
              text: number,
              children: [
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: secondary,
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
          Text(range, style: TextStyle(color: secondary)),
          if (note != null) ...[const SizedBox(height: 8), note!],
          if (insight != null) ...[const SizedBox(height: 12), insight!],
          const SizedBox(height: 16),
          SizedBox(height: 170, child: chart),
          const SizedBox(height: 10),
          Text(caption, style: TextStyle(fontSize: 12, color: secondary)),
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    );
  }
}

/// "Nov 6 – today", for a W or M chart ending today.
String dayRangeText(DateTime first) =>
    '${DateFormat('MMM d').format(first)} – today';

/// A bar per week or month's average, the best one solid, any goal dashed.
class _PeriodBars extends StatelessWidget {
  const _PeriodBars({
    required this.periods,
    required this.weekly,
    required this.best,
    required this.goal,
    required this.usual,
    required this.metric,
  });
  final (double, double)? usual;
  final List<MetricPeriod> periods;
  final bool weekly;
  final MetricPeriod? best;
  final double? goal;
  final HistoryMetric metric;

  @override
  Widget build(BuildContext context) {
    final best = this.best;
    String name(DateTime start) => weekly
        ? 'Week of ${DateFormat('MMM d').format(start)}'
        : DateFormat('MMMM y').format(start);
    return MetricBarChart(
      values: [for (final p in periods) p.average],
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
      tooltips: [
        for (final p in periods)
          '${name(p.start)}\n${metric.format(p.average)}',
      ],
      best: best == null ? null : periods.indexOf(best),
      goal: goal,
      goalLabel: metric == HistoryMetric.sleep ? 'Need' : 'Goal',
      usual: usual,
      daysPerBar: weekly ? 7 : 30.4,
      // Resting heart rate moves a few bpm; bars from 0 would hide it.
      fromLowest: metric == HistoryMetric.heartRate,
      color: metric.color,
      summary: best == null
          ? 'No data in this range.'
          : 'Average by ${weekly ? 'week' : 'month'}. '
                '${metric.lowerIsBetter ? 'Lowest' : 'Best'} was '
                '${name(best.start)} with ${metric.format(best.average)}.',
    );
  }
}

bool _holdsFirst(DateTime weekStart) =>
    weekStart.day == 1 ||
    DateTime(weekStart.year, weekStart.month, weekStart.day + 6).month !=
        weekStart.month;

/// The metric bar chart: a bar per value, the [best] one solid, any [goal]
/// dashed. Tapping or dragging across shows a bar's [tooltips] line. Shared
/// by the metric screens' D/W/M views and their 6M and Y views. Values of 0
/// draw no bar.
class MetricBarChart extends StatefulWidget {
  const MetricBarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.tooltips,
    required this.color,
    required this.summary,
    this.best,
    this.goal,
    this.goalLabel = 'Goal',
    this.usual,
    this.daysPerBar = 1,
    this.fromLowest = false,
    this.selected,
    this.onSelected,
  });

  /// The bar a list or calendar beside the chart has picked, and word back
  /// when the chart picks one, so the two stay in step. Both optional.
  final int? selected;
  final ValueChanged<int?>? onSelected;
  final List<double> values;

  /// How long each bar covers (7 for weeks), so a change of range zooms
  /// through time: today stays at the right edge.
  final double daysPerBar;

  /// The person's usual range (see [usualRange]), drawn as a band behind
  /// the bars so any one bar reads as usual or not.
  final (double, double)? usual;

  /// Under each bar; empty for none.
  final List<String> labels;
  final List<String> tooltips;
  final Color color;

  /// What the chart shows, for VoiceOver.
  final String summary;
  final int? best;
  final double? goal;
  final String goalLabel;

  /// Starts the axis just under the lowest bar, labelled, instead of at 0.
  final bool fromLowest;

  @override
  State<MetricBarChart> createState() => _MetricBarChartState();
}

class _MetricBarChartState extends State<MetricBarChart> {
  late int? _selected = widget.selected;

  /// The bars before the last change and the days they covered: the chart
  /// zooms from that range to the new one.
  List<double> _from = const [];
  double _fromSpan = 0;

  // W/M and 6M/Y are different charts on the same screen: each leaves its
  // bars in the route's storage so the next zooms from them.
  static const _storageId = 'metric-bars';

  double get _span => widget.values.length * widget.daysPerBar;

  @override
  void initState() {
    super.initState();
    MetricHistoryView.preload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_from.isEmpty) {
      final last = PageStorage.maybeOf(
        context,
      )?.readState(context, identifier: _storageId);
      if (last is (List<double>, double)) {
        _from = last.$1;
        _fromSpan = last.$2;
      }
    }
  }

  @override
  void didUpdateWidget(covariant MetricBarChart old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) _selected = widget.selected;
    if (!const ListEquality<double>().equals(old.values, widget.values)) {
      _selected = widget.selected;
      _from = old.values;
      _fromSpan = old.values.length * old.daysPerBar;
    }
  }

  void _select(double x, double width) {
    final count = widget.values.length;
    if (count == 0) return;
    final index = (x / ((width - _labelWidth) / count)).floor();
    final pick = index >= 0 && index < count && widget.values[index] > 0
        ? index
        : null;
    if (pick == _selected) return;
    if (pick != null) unawaited(HapticFeedback.selectionClick());
    setState(() => _selected = pick);
    widget.onSelected?.call(pick);
  }

  @override
  Widget build(BuildContext context) {
    PageStorage.maybeOf(
      context,
    )?.writeState(context, (widget.values, _span), identifier: _storageId);
    return _chart(context);
  }

  Widget _chart(BuildContext context) => Semantics(
    label: widget.summary,
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (e) => _select(e.localPosition.dx, constraints.maxWidth),
          onHorizontalDragUpdate: (e) =>
              _select(e.localPosition.dx, constraints.maxWidth),
          // Another range zooms in or out from the old one; the first bars
          // rise from the axis.
          child: TweenAnimationBuilder<double>(
            key: ValueKey(Object.hashAll(widget.values)),
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            builder: (context, grow, _) => CustomPaint(
              size: Size.infinite,
              painter: _BarsPainter(
                averages: widget.values,
                from: _from,
                fromSpan: _fromSpan,
                span: _span,
                labels: widget.labels,
                best: widget.best,
                selected: _selected,
                tooltip: _selected == null ? null : widget.tooltips[_selected!],
                goal: widget.goal,
                goalLabel: widget.goalLabel,
                usual: widget.usual,
                grow: grow,
                fromLowest: widget.fromLowest,
                color: widget.color,
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _labelWidth = 30.0;

/// Labels under a W or M chart's day bars: each weekday for a week, every
/// 7th date counted back from today for a month.
List<String> dayBarLabels(List<DateTime> dates) => [
  for (final (i, date) in dates.indexed)
    dates.length <= 7
        ? DateFormat('E').format(date)
        : (dates.length - 1 - i) % 7 == 0
        ? DateFormat('M/d').format(date)
        : '',
];

/// The middle half of [values] (0s are days without one), as Stress draws
/// its usual: null under 7 values, too few to call usual. The day charts
/// pass the last 28 days, whatever range is showing.
(double, double)? usualRange(List<double> values) {
  final sorted = values.where((v) => v > 0).toList()..sort();
  if (sorted.length < 7) return null;
  double at(double q) => sorted[((sorted.length - 1) * q).round()];
  return (at(.25), at(.75));
}

/// The highest bar with a value (the lowest with [lowest]), or null.
int? bestBar(List<double> values, {bool lowest = false}) {
  int? best;
  for (var i = 0; i < values.length; i++) {
    if (values[i] <= 0) continue;
    final b = best;
    if (b == null || (lowest ? values[i] < values[b] : values[i] > values[b])) {
      best = i;
    }
  }
  return best;
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({
    required this.averages,
    required this.from,
    required this.fromSpan,
    required this.span,
    required this.labels,
    required this.best,
    required this.selected,
    required this.tooltip,
    required this.goal,
    required this.goalLabel,
    required this.usual,
    required this.grow,
    required this.fromLowest,
    required this.color,
    required this.dark,
  });
  final (double, double)? usual;

  /// 0 → 1 as the chart zooms from [from] (covering [fromSpan] days) to
  /// its own bars (covering [span] days).
  final double grow;
  final List<double> from;
  final double fromSpan;
  final double span;
  final List<double> averages;
  final List<String> labels;
  final int? best;
  final int? selected;
  final String? tooltip;
  final double? goal;
  final String goalLabel;
  final bool fromLowest;
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 20.0;
    final height = size.height - bottom;
    final width = size.width - _labelWidth;
    // The axis for a set of bars: where it starts and what fills it.
    (double, double) axis(List<double> values) {
      final shown = values.where((v) => v > 0);
      final floor = fromLowest && shown.isNotEmpty
          ? ((shown.min - 5) / 5).floorToDouble() * 5
          : 0.0;
      return (
        floor,
        math.max(
          floor + 1,
          fromLowest && shown.isNotEmpty
              ? shown.max + 2
              : <double>[goal ?? 0, ...values].max * 1.15,
        ),
      );
    }

    double rise(double v, (double, double) a) =>
        height * ((v - a.$1) / (a.$2 - a.$1)).clamp(0.0, 1.0);
    // Mid-zoom the axis sits between the old range's and the new one's.
    final zooming = from.isNotEmpty && fromSpan > 0 && grow < 1;
    final toAxis = axis(averages);
    final fromAxis = zooming ? axis(from) : toAxis;
    final floor = ui.lerpDouble(fromAxis.$1, toAxis.$1, grow)!;
    final maxY = ui.lerpDouble(fromAxis.$2, toAxis.$2, grow)!;
    double y(double v) => height - rise(v, (floor, maxY));
    final muted = dark ? Colors.white54 : Colors.black54;

    canvas.drawLine(
      Offset(0, height),
      Offset(width, height),
      Paint()
        ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .12),
    );
    if (averages.isEmpty) return;
    final slot = width / averages.length;
    // The days in view, from the old range to the new. Today is the right
    // edge throughout, so W → M and M → 6M both read as zooming out.
    final window = zooming ? fromSpan * math.pow(span / fromSpan, grow) : span;
    void bars(List<double> values, double days, double fade, bool marks) {
      final each = width * (days / values.length) / window;
      final barWidth = math.min(18.0, each * .62);
      final left = width * (1 - days / window);
      for (var i = 0; i < values.length; i++) {
        final x = left + i * each + (each - barWidth) / 2;
        final tall = values[i] > 0
            ? rise(values[i], (floor, maxY)) * (from.isEmpty ? grow : 1)
            : 0.0;
        if (tall > .5 && x < width && x + barWidth > 0) {
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTRB(x, height - tall, x + barWidth, height),
              topLeft: Radius.circular(math.min(4, barWidth / 2)),
              topRight: Radius.circular(math.min(4, barWidth / 2)),
            ),
            Paint()
              ..color = color.withValues(
                alpha: (marks && (i == best || i == selected) ? 1 : .45) * fade,
              ),
          );
        }
        if (marks && labels[i].isNotEmpty) {
          final center = left + i * each + each / 2;
          if (center >= 0 && center <= width) {
            _text(
              canvas,
              labels[i],
              Offset(center, height + 5),
              muted.withValues(alpha: muted.a * fade),
              center: true,
            );
          }
        }
      }
    }

    final band = usual;
    if (band != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          // At least a sliver: mood's usual is often a single score.
          Rect.fromLTRB(
            0,
            math.min(y(band.$2), y(band.$1) - 4),
            width,
            y(band.$1),
          ),
          const Radius.circular(4),
        ),
        Paint()
          ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .07),
      );
      _text(canvas, 'Usual', Offset(width + 4, y(band.$2) - 5), muted);
    }
    final picked = selected;
    if (picked != null && picked < averages.length) {
      final x = picked * slot + slot / 2;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, height),
        Paint()
          ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .25),
      );
    }
    // Bars stay inside the plot; labels are drawn by the same pass.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, size.height));
    if (zooming) bars(from, fromSpan, 1 - grow, false);
    bars(averages, span, zooming ? grow : 1, true);
    canvas.restore();
    if (floor > 0) {
      _text(
        canvas,
        floor.round().toString(),
        Offset(width + 4, height - 7),
        muted,
      );
    }
    final line = goal;
    if (line != null) {
      final goalY = y(line);
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
      _text(canvas, goalLabel, Offset(width + 4, goalY - 7), muted);
    }
    final index = selected, text = tooltip;
    if (index != null && text != null && index < averages.length) {
      final painter = TextPainter(
        textScaler: chartTextScaler,
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: dark ? Colors.white : Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final boxWidth = painter.width + 18, boxHeight = painter.height + 14;
      final center = index * slot + slot / 2;
      final left = (center - boxWidth / 2).clamp(0.0, size.width - boxWidth);
      final top = (y(averages[index]) - boxHeight - 8).clamp(
        0.0,
        math.max(0.0, height - boxHeight),
      );
      final box = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top.toDouble(), boxWidth, boxHeight),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        box,
        Paint()..color = dark ? const Color(0xFF302B48) : Colors.white,
      );
      canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .1),
      );
      painter.paint(canvas, Offset(left + 9, top + 7.0));
    }
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
  bool shouldRepaint(covariant _BarsPainter old) =>
      !const ListEquality<double>().equals(averages, old.averages) ||
      !const ListEquality<double>().equals(from, old.from) ||
      fromSpan != old.fromSpan ||
      span != old.span ||
      !const ListEquality<String>().equals(labels, old.labels) ||
      best != old.best ||
      selected != old.selected ||
      goal != old.goal ||
      usual != old.usual ||
      grow != old.grow ||
      fromLowest != old.fromLowest ||
      color != old.color ||
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
        (best, day) =>
            best == null ||
                (metric.lowerIsBetter
                    ? day.value < best.value
                    : day.value > best.value)
            ? day
            : best,
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
    final goalDays = widget.history.goalDays(values.values);
    final perDay = switch (metric) {
      HistoryMetric.sleep => 'a night',
      HistoryMetric.heartRate || HistoryMetric.mood => 'on average',
      _ => 'a day',
    };
    // Without a goal, shading spans the month's own lowest to highest.
    final low = values.values.minOrNull ?? 0;
    final high = values.values.maxOrNull ?? 0;
    double strength(double v) => goal != null
        ? math.min(1.0, v / (goal * 1.3))
        : high == low
        ? .5
        : (v - low) / (high - low);
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
                          : '${metric.format(average)} $perDay'
                                '${goal == null
                                    ? ''
                                    : metric == HistoryMetric.sleep
                                    ? ' · $goalDays with enough sleep'
                                    : ' · $goalDays goal ${goalDays == 1 ? 'day' : 'days'}'}',
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
                      _cell(d, values[d], goal, strength, d == day),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  goal == null
                      ? 'Darker days were higher.'
                      : 'Darker ${metric.day}s had more. A ring means you '
                            '${metric == HistoryMetric.sleep ? 'got your sleep need' : 'met your goal'}.',
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
                          '${metric.bestDayLabel} this month',
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
                      fontSize: 34,
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
                      if (goal != null)
                        _stat(
                          '${(selected / goal * 100).round()}%',
                          'of your ${metric.goalName}',
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

  Widget _cell(
    int day,
    double? value,
    num? goal,
    double Function(double) strengthOf,
    bool selected,
  ) {
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
    final strength = strengthOf(value);
    // Capped so the day's text stays readable on the darkest cells.
    final alpha = .1 + .55 * strength;
    final met = goal != null && value >= goal;
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
            borderRadius: BorderRadius.circular(12),
            side: selected
                ? const BorderSide(color: _purple, width: 2.5)
                : met
                ? BorderSide(color: metric.color, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
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
                  // The one place 9 stays: 10 overflows the day cell.
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
