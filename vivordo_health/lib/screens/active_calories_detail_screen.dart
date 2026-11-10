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
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'metric_history_screen.dart';

class ActiveCaloriesDetailScreen extends StatefulWidget {
  const ActiveCaloriesDetailScreen({super.key});

  @override
  State<ActiveCaloriesDetailScreen> createState() =>
      _ActiveCaloriesDetailScreenState();
}

class _ActiveCaloriesDetailScreenState
    extends State<ActiveCaloriesDetailScreen> {
  static const _orange = Color(0xFFFF6A00);
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
  late final _calories = _caloriesStream();

  Stream<QuerySnapshot<Map<String, dynamic>>> _caloriesStream() {
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

  List<_CalorieDay> _rangeData(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    final values = <String, int>{};
    for (final doc in snapshot?.docs ?? const []) {
      values[doc.id] =
          ((doc.data()['active_calories'] as Map?)?['sum'] as num?)?.round() ??
          0;
    }
    final today = DateUtils.dateOnly(DateTime.now());
    return List.generate(_rangeDays, (index) {
      final date = today.subtract(Duration(days: _rangeDays - index - 1));
      return _CalorieDay(date, values[localDayKey(date)] ?? 0);
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
        .map(
          (doc) => ((doc.data()['active_calories'] as Map?)?['sum'] as num?)
              ?.round(),
        )
        .whereType<int>()
        .toList();
  }

  /// Each day's active_calories by date, for the insight. Days without data are left
  /// out, never counted as 0.
  DayValues _dayValues(QuerySnapshot<Map<String, dynamic>>? snapshot) => {
    for (final doc in snapshot?.docs ?? const [])
      if (((doc.data()['active_calories'] as Map?)?['sum'] as num?)
          case final v?)
        ?DateTime.tryParse(doc.id): v.toDouble(),
  };

  /// Each day's active_calories per hour, for "usual for this time of day".
  DayHours _dayHours(QuerySnapshot<Map<String, dynamic>>? snapshot) => {
    for (final doc in snapshot?.docs ?? const [])
      if ((doc.data()['active_calories'] as Map?)?['byHour']
          case final List hours when hours.length == 24)
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
          'Active Calories',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _calories,
        builder: (context, snapshot) {
          // 6M and Y read the lifetime history instead; the stream stays
          // subscribed so going back to D/W/M is instant.
          if (_rangeIndex > 2) {
            return MetricHistoryView(
              metric: HistoryMetric.calories,
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
                  goalSnapshot.data?.activeCalories ??
                  const ActivityGoals().activeCalories;
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
    List<_CalorieDay> data,
    List<int> usualValues,
    int dailyGoal,
    DayValues values,
    DayHours hours,
  ) {
    final total = data.fold<int>(0, (total, day) => total + day.activeCalories);
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
    final best = data.isEmpty
        ? null
        : data.reduce((a, b) => a.activeCalories >= b.activeCalories ? a : b);
    final updated = DateFormat('h:mm a').format(DateTime.now());

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'Updated $updated',
              style: TextStyle(color: context.vivordoColors.textSecondary),
            ),
          ),
          const SizedBox(height: 18),
          _rangeSelector(),
          const SizedBox(height: 18),
          _summaryCard(total, average, change, goal, progress),
          if (_rangeIndex != 0) ...[
            const SizedBox(height: 26),
            Text(
              '$_rangeName trend',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            _chartCard(data, dailyGoal),
          ],
          if (_rangeIndex != 0) ...[
            const SizedBox(height: 26),
            const Text(
              'Daily breakdown',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            _breakdownCard(data, best),
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
              unit: 'kcal',
              fewer: 'less',
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeSelector() => AppSegmented<int>(
    segments: const {0: 'D', 1: 'W', 2: 'M', 3: '6M', 4: 'Y'},
    value: _rangeIndex,
    onChanged: (index) => setState(() => _rangeIndex = index),
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
              _iconBubble(CupertinoIcons.flame_fill, _orange),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_rangeName active calories',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            NumberFormat.decimalPattern().format(total),
                            style: const TextStyle(
                              fontSize: 42,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 7, left: 5),
                          child: Text('kcal', style: TextStyle(fontSize: 17)),
                        ),
                      ],
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
                      Text(
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
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Text('Goal ${NumberFormat.decimalPattern().format(goal)} kcal'),
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
              color: _orange,
              backgroundColor: context.vivordoColors.cardMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard(List<_CalorieDay> data, int dailyGoal) {
    final values = [for (final day in data) day.activeCalories.toDouble()];
    final best = bestBar(values);
    final kcal = NumberFormat.decimalPattern();
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 18, 10, 8),
      child: SizedBox(
        height: 220,
        child: MetricBarChart(
          values: values,
          labels: dayBarLabels([for (final day in data) day.date]),
          tooltips: [
            for (final day in data)
              '${DateFormat('EEE, MMM d').format(day.date)}\n'
                  '${kcal.format(day.activeCalories)} kcal',
          ],
          best: best,
          goal: dailyGoal.toDouble(),
          color: _orange,
          summary: best == null
              ? 'Last ${data.length} days: no active calories recorded.'
              : 'Active calories for the last ${data.length} days against '
                    'your goal. Most on '
                    '${DateFormat('EEEE, MMMM d').format(data[best].date)} '
                    'with ${kcal.format(data[best].activeCalories)} kcal.',
        ),
      ),
    );
  }

  Widget _breakdownCard(List<_CalorieDay> data, _CalorieDay? best) {
    final ordered = [...data]..sort((a, b) => b.date.compareTo(a.date));
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          for (var i = 0; i < ordered.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('EEEE, MMM d').format(ordered[i].date),
                    ),
                  ),
                  Text(
                    '${NumberFormat.decimalPattern().format(ordered[i].activeCalories)} kcal',
                    style: const TextStyle(
                      color: _orange,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (best?.date == ordered[i].date &&
                      ordered[i].activeCalories > 0) ...[
                    const SizedBox(width: 10),
                    _badge('Best day'),
                  ],
                ],
              ),
            ),
            if (i != ordered.length - 1)
              Divider(height: 1, color: context.vivordoColors.border),
          ],
        ],
      ),
    );
  }

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
          borderRadius: BorderRadius.circular(22),
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

  Widget _badge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFF20B26B).withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: context.vivordoColors.success,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _CalorieDay {
  const _CalorieDay(this.date, this.activeCalories);
  final DateTime date;
  final int activeCalories;
}
