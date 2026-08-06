import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/utils/smooth_chart_path.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

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

  String _dayKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Stream<QuerySnapshot<Map<String, dynamic>>> _caloriesStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    final now = DateTime.now();
    final oldest = now.subtract(const Duration(days: 59));
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: _dayKey(oldest))
        .where(FieldPath.documentId, isLessThanOrEqualTo: _dayKey(now))
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
      return _CalorieDay(date, values[_dayKey(date)] ?? 0);
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
          (doc) =>
              ((doc.data()['active_calories'] as Map?)?['sum'] as num?)
                  ?.round() ??
              0,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      appBar: AppBar(
        backgroundColor: context.vivordoColors.page,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: _purple,
        ),
        title: const Text(
          'Active Calories',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _caloriesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
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
              return _buildContent(data, usualValues, dailyGoal);
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
  ) {
    final total = data.fold<int>(0, (total, day) => total + day.activeCalories);
    final average = data.isEmpty ? 0 : (total / data.length).round();
    final usual = usualValues.isEmpty
        ? null
        : usualValues.reduce((a, b) => a + b) / usualValues.length;
    final change = usual == null || usual == 0
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
          const SizedBox(height: 26),
          Text(
            '$_rangeName trend',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _chartCard(data, usual),
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
          _insightCard(best),
        ],
      ),
    );
  }

  Widget _rangeSelector() {
    const labels = ['Day', 'Week', 'Month'];
    return Container(
      height: 52,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.vivordoColors.cardMuted,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == _rangeIndex;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _rangeIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _purple : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : context.vivordoColors.textSecondary,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

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
              _iconBubble(Icons.local_fire_department_rounded, _orange),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_rangeName.toUpperCase()} ACTIVE CALORIES',
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
                        '${change >= 0 ? '↑' : '↓'} ${change.abs()}% vs your usual',
                        style: TextStyle(
                          color: change >= 0
                              ? const Color(0xFF20B26B)
                              : Colors.red,
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

  Widget _chartCard(List<_CalorieDay> data, double? usual) {
    final maxValue = data.fold<int>(
      0,
      (max, day) => day.activeCalories > max ? day.activeCalories : max,
    );
    final maxY =
        (([
                      maxValue.toDouble(),
                      usual ?? 0,
                      1000,
                    ].reduce((a, b) => a > b ? a : b) *
                    1.2) /
                1000)
            .ceil() *
        1000.0;
    return _card(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
      child: SizedBox(
        height: 245,
        child: _CaloriesChart(
          values: data.map((day) => day.activeCalories.toDouble()).toList(),
          labels: data.map((day) => _chartLabel(day.date)).toList(),
          dates: data.map((day) => day.date).toList(),
          maxY: maxY,
          usual: usual,
        ),
      ),
    );
  }

  String _chartLabel(DateTime date) => _rangeIndex == 2
      ? DateFormat('M/d').format(date)
      : DateFormat('E').format(date);

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

  Widget _insightCard(_CalorieDay? best) {
    final text = best == null || best.activeCalories == 0
        ? 'Keep moving to begin building your active-calorie trend.'
        : 'Your activity was highest on ${DateFormat('EEEE').format(best.date)}.';
    return _card(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          _iconBubble(Icons.trending_up_rounded, const Color(0xFF20B26B)),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
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
      style: const TextStyle(
        color: Color(0xFF20B26B),
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

class _CaloriesChart extends StatefulWidget {
  const _CaloriesChart({
    required this.values,
    required this.labels,
    required this.dates,
    required this.maxY,
    required this.usual,
  });
  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;
  final double maxY;
  final double? usual;

  @override
  State<_CaloriesChart> createState() => _CaloriesChartState();
}

class _CaloriesChartState extends State<_CaloriesChart> {
  int? selected;

  void _select(double x, double width) {
    if (widget.values.isEmpty) return;
    const left = 38.0;
    final chartWidth = width - left;
    final index = widget.values.length == 1
        ? 0
        : (((x - left) / chartWidth) * (widget.values.length - 1))
              .round()
              .clamp(0, widget.values.length - 1);
    if (selected != index) setState(() => selected = index);
  }

  @override
  void didUpdateWidget(covariant _CaloriesChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.values, widget.values)) selected = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (event) =>
          _select(event.localPosition.dx, constraints.maxWidth),
      onHorizontalDragUpdate: (event) =>
          _select(event.localPosition.dx, constraints.maxWidth),
      child: CustomPaint(
        size: Size.infinite,
        painter: _CaloriesChartPainter(
          values: widget.values,
          labels: widget.labels,
          dates: widget.dates,
          maxY: widget.maxY,
          usual: widget.usual,
          selected: selected,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    ),
  );
}

class _CaloriesChartPainter extends CustomPainter {
  const _CaloriesChartPainter({
    required this.values,
    required this.labels,
    required this.dates,
    required this.maxY,
    required this.usual,
    required this.selected,
    required this.dark,
  });
  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;
  final double maxY;
  final double? usual;
  final int? selected;
  final bool dark;
  static const left = 38.0;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 25.0;
    final height = size.height - bottom;
    final width = size.width - left;
    final grid = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = height * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      _text(canvas, _compact(maxY * (1 - i / 4)), Offset(0, y - 6), 10);
    }
    if (values.isEmpty) return;
    final points = List.generate(values.length, (i) {
      final x = values.length == 1
          ? left + width / 2
          : left + width * i / (values.length - 1);
      return Offset(x, height * (1 - (values[i] / maxY).clamp(0.0, 1.0)));
    });
    final usualValue = usual;
    if (usualValue != null) {
      final y = height * (1 - (usualValue / maxY).clamp(0.0, 1.0));
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = 1.2,
      );
    }
    final line = smoothChartPath(points);
    final fill = Path.from(line)
      ..lineTo(points.last.dx, height)
      ..lineTo(points.first.dx, height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, height), [
          const Color(0xFFFF6A00).withValues(alpha: .24),
          const Color(0xFFFF6A00).withValues(alpha: 0),
        ]),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFFFF6A00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        points[i],
        3.5,
        Paint()..color = const Color(0xFFFF6A00),
      );
      if (values.length <= 10 || i % 5 == 0 || i == values.length - 1) {
        _centerText(canvas, labels[i], Offset(points[i].dx, height + 7), 9);
      }
    }
    final index = selected;
    if (index != null && index < points.length) {
      final point = points[index];
      canvas.drawCircle(
        point,
        8,
        Paint()..color = const Color(0xFFFF6A00).withValues(alpha: .2),
      );
      final label =
          '${DateFormat('MMM d').format(dates[index])}\n${NumberFormat.decimalPattern().format(values[index].round())} kcal';
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: dark ? Colors.white : Colors.black,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final boxWidth = painter.width + 18;
      final boxHeight = painter.height + 14;
      final x = (point.dx - boxWidth / 2).clamp(left, size.width - boxWidth);
      final y = (point.dy - boxHeight - 12).clamp(0.0, height - boxHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, boxWidth, boxHeight),
          const Radius.circular(9),
        ),
        Paint()..color = dark ? const Color(0xFF302B48) : Colors.white,
      );
      painter.paint(canvas, Offset(x + 9, y + 7));
    }
  }

  static String _compact(double value) =>
      value >= 1000 ? '${(value / 1000).round()}K' : value.round().toString();

  void _text(Canvas canvas, String value, Offset offset, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: dark ? Colors.white54 : Colors.black45,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  void _centerText(Canvas canvas, String value, Offset offset, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: dark ? Colors.white54 : Colors.black45,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(offset.dx - painter.width / 2, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _CaloriesChartPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values) ||
      selected != oldDelegate.selected ||
      maxY != oldDelegate.maxY ||
      dark != oldDelegate.dark;
}
