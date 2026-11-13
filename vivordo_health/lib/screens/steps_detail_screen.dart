import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:vivordo_health/widgets/apple_ui.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/utils/day_key.dart';
import 'package:vivordo_health/src/utils/detail_insights.dart';
import 'package:provider/provider.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/metric_day_breakdown.dart';

import 'metric_history_screen.dart';

class StepsDetailScreen extends StatefulWidget {
  const StepsDetailScreen({super.key});

  @override
  State<StepsDetailScreen> createState() => _StepsDetailScreenState();
}

class _StepsDetailScreenState extends State<StepsDetailScreen> {
  @override
  void initState() {
    super.initState();
    MetricHistoryView.preload();
  }

  static const _blue = Color(0xFF2878E8);
  static const _purple = Color(0xFF5B42F3);
  // Opens on Week; Day is a tap away.
  int _rangeIndex = 1;

  int get _rangeDays => switch (_rangeIndex) {
    0 => 1,
    1 => 7,
    _ => 30,
  };
  String get _rangeName => switch (_rangeIndex) {
    0 => 'Daily',
    1 => 'Weekly',
    _ => 'Monthly',
  };

  // Made once: a new stream on each rebuild re-sent the whole range.
  late final _steps = _stepsStream();

  Stream<QuerySnapshot<Map<String, dynamic>>> _stepsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    final now = DateTime.now();
    final oldest = now.subtract(const Duration(days: 59));
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: localDayKey(oldest),
        )
        .where(FieldPath.documentId, isLessThanOrEqualTo: localDayKey(now))
        .orderBy(FieldPath.documentId)
        .snapshots();
  }

  List<_StepDay> _rangeData(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    final stepsByDay = <String, int>{};
    final distanceByDay = <String, double>{};
    for (final doc in snapshot?.docs ?? const []) {
      stepsByDay[doc.id] =
          ((doc.data()['steps'] as Map?)?['sum'] as num?)?.round() ?? 0;
      distanceByDay[doc.id] =
          ((doc.data()['distance'] as Map?)?['sum'] as num?)?.toDouble() ?? 0;
    }
    final today = DateUtils.dateOnly(DateTime.now());
    return List.generate(_rangeDays, (index) {
      final date = today.subtract(Duration(days: _rangeDays - index - 1));
      final key = localDayKey(date);
      return _StepDay(date, stepsByDay[key] ?? 0, distanceByDay[key] ?? 0);
    });
  }

  List<int> _usualValues(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    final cutoff = DateUtils.dateOnly(
      DateTime.now(),
    ).subtract(Duration(days: _rangeDays));
    return (snapshot?.docs ?? const [])
        .where((doc) {
          final date = DateTime.tryParse(doc.id);
          return date != null && date.isBefore(cutoff);
        })
        .map((doc) => ((doc.data()['steps'] as Map?)?['sum'] as num?)?.round())
        .whereType<int>()
        .toList();
  }

  /// Each day's steps by date, for the insight. Days without data are left
  /// out, never counted as 0.
  DayValues _dayValues(QuerySnapshot<Map<String, dynamic>>? snapshot) => {
    for (final doc in snapshot?.docs ?? const [])
      if (((doc.data()['steps'] as Map?)?['sum'] as num?) case final v?)
        ?DateTime.tryParse(doc.id): v.toDouble(),
  };

  /// Each day's steps per hour, for "usual for this time of day".
  DayHours _dayHours(QuerySnapshot<Map<String, dynamic>>? snapshot) => {
    for (final doc in snapshot?.docs ?? const [])
      if ((doc.data()['steps'] as Map?)?['byHour'] case final List hours
          when hours.length == 24)
        ?DateTime.tryParse(doc.id): [
          for (final h in hours) h is num ? h.toDouble() : 0.0,
        ],
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      appBar: AppBar(
        backgroundColor: context.vivordoColors.page,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(CupertinoIcons.back),
          color: _purple,
        ),
        title: const Text(
          'Steps',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _steps,
        builder: (context, snapshot) {
          // 6M and Y read the lifetime history instead; the stream stays
          // subscribed so going back to D/W/M is instant.
          if (_rangeIndex > 2) {
            return MetricHistoryView(
              metric: HistoryMetric.steps,
              months: _rangeIndex == 3 ? 6 : 12,
              header: _rangeSelector(),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CupertinoActivityIndicator());
          }
          final data = _rangeData(snapshot.data);
          final usualValues = _usualValues(snapshot.data);
          return StreamBuilder<ActivityGoals>(
            stream: ActivityGoalsService.watch(),
            initialData: const ActivityGoals(),
            builder: (context, goalSnapshot) {
              final dailyGoal =
                  goalSnapshot.data?.steps ?? const ActivityGoals().steps;
              return _buildContent(
                data,
                usualValues,
                dailyGoal,
                _dayValues(snapshot.data),
                _dayHours(snapshot.data),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(
    List<_StepDay> data,
    List<int> usualValues,
    int dailyGoal,
    DayValues values,
    DayHours hours,
  ) {
    final total = data.fold<int>(0, (total, day) => total + day.steps);
    final totalDistance = data.fold<double>(
      0,
      (total, day) => total + day.distanceKm,
    );
    final average = data.isEmpty ? 0 : (total / data.length).round();
    final usual = usualValues.isEmpty
        ? null
        : usualValues.reduce((a, b) => a + b) / usualValues.length;
    // Day compares with the usual by this time of day (like the insight),
    // not with whole earlier days; hidden until a week of hours exists.
    final byNow = _rangeIndex == 0 ? usualByNow(hours, DateTime.now()) : null;
    final change = _rangeIndex == 0
        ? (byNow == null || byNow == 0
              ? null
              : ((average - byNow) / byNow * 100).round())
        : usual == null || usual == 0
        ? null
        : ((average - usual) / usual * 100).round();
    final goal = dailyGoal * _rangeDays;
    final progress = goal == 0 ? 0.0 : (total / goal).clamp(0.0, 1.0);
    final updated = DateFormat('h:mm a').format(DateTime.now());

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              total == 0 ? 'No steps synced yet' : 'Updated $updated',
              style: TextStyle(color: context.vivordoColors.textSecondary),
            ),
          ),
          const SizedBox(height: 18),
          _rangeSelector(),
          const SizedBox(height: 18),
          // W and M use the same card as 6M and Y, so the bars morph.
          if (_rangeIndex == 0)
            _summaryCard(total, average, change, goal, progress)
          else
            MetricChartCard(
              label: 'Daily average',
              number: NumberFormat.decimalPattern().format(average),
              unit: 'steps',
              range:
                  '${dayRangeText(data.first.date)} · '
                  '${NumberFormat.decimalPattern().format(total)} total',
              note: change == null ? null : _changeText(change),
              chart: _chartCard(data, dailyGoal),
              caption:
                  'Each bar is a day. The dashed line is your goal. The '
                  'solid bar is your best day.',
              footer: _goalProgress(goal, progress),
            ),
          const SizedBox(height: 16),
          _distanceCard(totalDistance),
          if (_rangeIndex != 0) ...[
            const SizedBox(height: 26),
            const Text(
              'By day',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            MetricDayBreakdown(
              month: _rangeIndex == 2,
              color: _blue,
              mark: dailyGoal.toDouble(),
              compact: HistoryMetric.steps.compact,
              selected: _day,
              onSelected: _pick,
              days: [
                for (final day in data)
                  (
                    date: day.date,
                    value: day.steps.toDouble(),
                    text: NumberFormat.decimalPattern().format(day.steps),
                    note: _goalNote(day.steps, dailyGoal),
                    met: day.steps >= dailyGoal,
                    hours: hours[day.date],
                  ),
              ],
            ),
          ],
          const SizedBox(height: 26),
          const Text(
            'Insight',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _insightCard(
            countInsight(
              values: values,
              today: DateTime.now(),
              rangeDays: _rangeDays,
              goal: dailyGoal.toDouble(),
              hours: hours,
              unit: 'steps',
              fewer: 'fewer',
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeSelector() => AppSegmented<int>(
    segments: const {0: 'D', 1: 'W', 2: 'M', 3: '6M', 4: 'Y'},
    value: _rangeIndex,
    onChanged: (index) => setState(() {
      _rangeIndex = index;
      _day = null;
    }),
  );

  Widget _summaryCard(
    int total,
    int average,
    int? change,
    int goal,
    double progress,
  ) {
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBubble(Icons.directions_walk_rounded, _blue),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_rangeName steps',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      NumberFormat.decimalPattern().format(total),
                      style: const TextStyle(
                        fontSize: 40,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${NumberFormat.decimalPattern().format(average)} daily average',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    if (change != null) ...[
                      const SizedBox(height: 10),
                      _changeText(change),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _goalProgress(goal, progress),
        ],
      ),
    );
  }

  Widget _changeText(int change) => Text(
    _rangeIndex == 0 && change.abs() < 10
        ? 'About usual for this time'
        : '${change >= 0 ? '↑' : '↓'} ${change.abs()}% vs '
              '${_rangeIndex == 0 ? 'usual for this time' : 'your usual'}',
    style: TextStyle(
      // Below usual by now isn't flagged on Day.
      color: _rangeIndex == 0 && change < 10
          ? context.vivordoColors.textSecondary
          : change >= 0
          ? context.vivordoColors.success
          : context.vivordoColors.danger,
      fontSize: 16,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _goalProgress(int goal, double progress) => Column(
    children: [
      Row(
        children: [
          Text('Goal ${NumberFormat.decimalPattern().format(goal)}'),
          const Spacer(),
          Text('${(progress * 100).round()}%'),
        ],
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 9,
          color: _blue,
          backgroundColor: context.vivordoColors.cardMuted,
        ),
      ),
    ],
  );

  Widget _chartCard(List<_StepDay> data, int dailyGoal) {
    final values = [for (final day in data) day.steps.toDouble()];
    final best = bestBar(values);
    final steps = NumberFormat.decimalPattern();
    return MetricBarChart(
      selected: _day,
      onSelected: _pick,
      values: values,
      labels: dayBarLabels([for (final day in data) day.date]),
      tooltips: [
        for (final day in data)
          '${DateFormat('EEE, MMM d').format(day.date)}\n'
              '${steps.format(day.steps)} steps',
      ],
      best: best,
      goal: dailyGoal.toDouble(),
      color: _blue,
      summary: best == null
          ? 'Last ${data.length} days: no steps recorded.'
          : 'Steps for the last ${data.length} days against your goal. '
                'Most on ${DateFormat('EEEE, MMMM d').format(data[best].date)} '
                'with ${steps.format(data[best].steps)}.',
    );
  }

  Widget _distanceCard(double distanceKm) {
    final decimals = distanceKm == 0 || distanceKm >= 10 ? 1 : 2;
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          _iconBubble(CupertinoIcons.map, const Color(0xFF20B26B)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total distance',
                  style: TextStyle(
                    color: context.vivordoColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.watch<ThemeController>().units.formatDistance(
                    distanceKm,
                    decimals: decimals,
                  ),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _rangeIndex == 0
                ? 'Today'
                : _rangeIndex == 1
                ? 'Past 7 days'
                : 'Past 30 days',
            style: TextStyle(
              color: context.vivordoColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// The day picked in the chart or in "By day" (an index into the range's
  /// days); both show the same one.
  int? _day;

  void _pick(int? day) => setState(() => _day = day);

  String _goalNote(int value, int goal) => value >= goal
      ? 'Goal met'
      : '${NumberFormat.decimalPattern().format(goal - value)} short';

  Widget _insightCard(DetailInsight insight) {
    final (icon, color) = insightStyle(insight.tone);
    return _card(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          _iconBubble(icon, color),
          const SizedBox(width: 14),
          Expanded(
            child: Text(insight.text, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child, required EdgeInsets padding}) =>
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

  Widget _iconBubble(IconData icon, Color color) => Container(
    width: 54,
    height: 54,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color, size: 29),
  );
}

class _StepDay {
  const _StepDay(this.date, this.steps, this.distanceKm);
  final DateTime date;
  final int steps;
  final double distanceKm;
}
