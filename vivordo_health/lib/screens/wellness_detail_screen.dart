import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/utils/activity_score.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/src/utils/smooth_chart_path.dart';

class WellnessDetailScreen extends StatefulWidget {
  const WellnessDetailScreen({super.key});

  @override
  State<WellnessDetailScreen> createState() => _WellnessDetailScreenState();
}

class _WellnessDetailScreenState extends State<WellnessDetailScreen> {
  static const _purple = Color(0xFF5B42F3);
  static const _red = Color(0xFFFF3B4E);
  int _rangeIndex = 0;

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

  String _key(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    final now = DateTime.now();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: _key(now.subtract(const Duration(days: 59))),
        )
        .where(FieldPath.documentId, isLessThanOrEqualTo: _key(now))
        .orderBy(FieldPath.documentId)
        .snapshots();
  }

  _WellnessDay _parse(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    double? avg(String metric) =>
        ((data[metric] as Map?)?['avg'] as num?)?.toDouble();
    return _WellnessDay(
      DateTime.parse(doc.id),
      wellness: avg('wellness'),
      stress: avg('stress'),
      sleep: avg('sleep'),
      steps: ((data['steps'] as Map?)?['sum'] as num?)?.toDouble(),
      exerciseMinutes: ((data['exercise_time'] as Map?)?['sum'] as num?)
          ?.toDouble(),
      activeCalories: ((data['active_calories'] as Map?)?['sum'] as num?)
          ?.toDouble(),
      heartRate: avg('heart_rate_scan'),
    );
  }

  List<_WellnessDay> _range(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    final parsed = {
      for (final doc in snapshot?.docs ?? const []) doc.id: _parse(doc),
    };
    final today = DateUtils.dateOnly(DateTime.now());
    return List.generate(_rangeDays, (index) {
      final date = today.subtract(Duration(days: _rangeDays - index - 1));
      return parsed[_key(date)] ?? _WellnessDay(date);
    });
  }

  List<double> _previous(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    final currentStart = DateUtils.dateOnly(
      DateTime.now(),
    ).subtract(Duration(days: _rangeDays - 1));
    final start = currentStart.subtract(Duration(days: _rangeDays));
    return (snapshot?.docs ?? const [])
        .map(_parse)
        .where(
          (day) =>
              !day.date.isBefore(start) &&
              day.date.isBefore(currentStart) &&
              day.wellness != null,
        )
        .map((day) => day.wellness!)
        .toList();
  }

  double? _average(Iterable<double> values) {
    final list = values.toList();
    return list.isEmpty ? null : list.reduce((a, b) => a + b) / list.length;
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _purple),
        ),
        title: const Text(
          'Wellness Score',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<ActivityGoals>(
        stream: ActivityGoalsService.watch(),
        builder: (context, goalsSnapshot) =>
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _stream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _content(
                  _range(snapshot.data),
                  _previous(snapshot.data),
                  goalsSnapshot.data ?? const ActivityGoals(),
                );
              },
            ),
      ),
    );
  }

  Widget _content(
    List<_WellnessDay> days,
    List<double> previous,
    ActivityGoals activityGoals,
  ) {
    final scoredDays = days.where((day) => day.wellness != null).toList();
    final latest = scoredDays.isEmpty ? days.last : scoredDays.last;
    final currentAverage = _average(scoredDays.map((day) => day.wellness!));
    final score = _rangeIndex == 0 ? latest.wellness : currentAverage;
    final previousAverage = _average(previous);
    final change =
        currentAverage == null ||
            previousAverage == null ||
            previousAverage == 0
        ? null
        : ((currentAverage - previousAverage) / previousAverage * 100).round();
    final usual = _average(previous);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              'Updated ${DateFormat('h:mm a').format(DateTime.now())}',
              style: TextStyle(color: context.vivordoColors.textSecondary),
            ),
          ),
          const SizedBox(height: 18),
          _rangeSelector(),
          const SizedBox(height: 18),
          _scoreCard(score, change, latest, _scoreLabel, activityGoals),
          if (_rangeIndex != 0) ...[
            _section('$_rangeName trend'),
            _chartCard(days, usual),
          ],
          _section('Score breakdown'),
          _breakdown(latest, activityGoals),
          _section('How it works'),
          _howItWorks(),
        ],
      ),
    );
  }

  String get _scoreLabel => switch (_rangeIndex) {
    0 => 'TODAY\'S WELLNESS SCORE',
    1 => 'WEEKLY AVERAGE WELLNESS SCORE',
    _ => 'MONTHLY AVERAGE WELLNESS SCORE',
  };

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

  Widget _scoreCard(
    double? score,
    int? change,
    _WellnessDay latest,
    String scoreLabel,
    ActivityGoals activityGoals,
  ) {
    final status = score == null
        ? 'Not enough data'
        : score >= 75
        ? 'Doing well'
        : score >= 50
        ? 'Fair'
        : 'Needs attention';
    final color = score == null
        ? context.vivordoColors.textSecondary
        : score >= 75
        ? const Color(0xFF20B26B)
        : score >= 50
        ? const Color(0xFFFF9500)
        : _red;
    final explanation = _scoreExplanation(latest, activityGoals);
    return _card(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scoreLabel,
                  style: TextStyle(
                    color: context.vivordoColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  score?.round().toString() ?? '--',
                  style: const TextStyle(
                    fontSize: 48,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                if (change != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${change >= 0 ? '↑' : '↓'} ${change.abs()}% vs previous period',
                    style: TextStyle(
                      color: change >= 0 ? const Color(0xFF20B26B) : _red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(explanation, style: const TextStyle(height: 1.35)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 122,
            height: 122,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: (score ?? 0) / 100,
                    strokeWidth: 12,
                    strokeCap: StrokeCap.round,
                    color: color,
                    backgroundColor: context.vivordoColors.cardMuted,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.spa_outlined, color: _purple, size: 28),
                    Text(
                      score?.round().toString() ?? '--',
                      style: const TextStyle(
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '/100',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ActivityScoreResult? _activityScore(_WellnessDay day, ActivityGoals goals) =>
      calculateActivityScore(
        steps: day.steps,
        exerciseMinutes: day.exerciseMinutes,
        activeCalories: day.activeCalories,
        stepsGoal: goals.steps.toDouble(),
        exerciseMinutesGoal: goals.exerciseMinutes.toDouble(),
        activeCaloriesGoal: goals.activeCalories.toDouble(),
      );

  String _scoreExplanation(_WellnessDay day, ActivityGoals activityGoals) {
    if (day.wellness == null) {
      return 'Sync your health data to calculate your score.';
    }
    final concerns = <String>[];
    if (day.stress != null && day.stress! >= 60) concerns.add('higher stress');
    if (day.heartRate != null && (day.heartRate! < 60 || day.heartRate! > 80)) {
      concerns.add('heart rate outside the optimal range');
    }
    if (day.sleep != null && day.sleep! < 7) concerns.add('lower sleep');
    final activity = _activityScore(day, activityGoals);
    if (activity != null && activity.score < 70) {
      concerns.add('lower activity');
    }
    if (concerns.isEmpty) {
      return 'Your recent health signals support your score.';
    }
    return '${concerns.take(2).join(' and ')} lowered your score.';
  }

  Widget _chartCard(List<_WellnessDay> days, double? usual) => _card(
    padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
    child: SizedBox(
      height: 245,
      child: _WellnessChart(
        values: days.map((day) => day.wellness).toList(),
        dates: days.map((day) => day.date).toList(),
        labels: days
            .map(
              (day) => _rangeIndex == 2
                  ? DateFormat('M/d').format(day.date)
                  : DateFormat('E').format(day.date),
            )
            .toList(),
        usual: usual,
      ),
    ),
  );

  double _heartRateScore(double bpm) {
    if (bpm >= 60 && bpm <= 80) return 100;
    final distance = bpm < 60 ? 60 - bpm : bpm - 80;
    return (100 - distance * 2.5).clamp(0.0, 100.0);
  }

  Widget _breakdown(_WellnessDay day, ActivityGoals activityGoals) {
    final components = <_ScoreComponent>[];
    if (day.stress != null) {
      components.add(
        _ScoreComponent(
          'Stress',
          100 - day.stress!,
          .35,
          Icons.psychology_rounded,
          _red,
        ),
      );
    }
    components.add(
      _ScoreComponent(
        'Sleep',
        day.sleep == null ? null : (day.sleep! / 8 * 100).clamp(0, 100),
        .30,
        Icons.nightlight_round,
        _purple,
      ),
    );
    final activity = _activityScore(day, activityGoals);
    components.add(
      _ScoreComponent(
        'Activity',
        activity?.score,
        .20,
        Icons.directions_run_rounded,
        const Color(0xFF24A83B),
      ),
    );
    if (day.heartRate != null) {
      components.add(
        _ScoreComponent(
          'Avg heart rate',
          _heartRateScore(day.heartRate!),
          .15,
          Icons.favorite_border_rounded,
          const Color(0xFF2878E8),
        ),
      );
    }
    final totalWeight = components.fold<double>(
      0,
      (total, item) => total + (item.score == null ? 0 : item.weight),
    );
    final total = components.fold<double>(
      0,
      (total, item) =>
          total + (item.score ?? 0) * item.weight / math.max(totalWeight, .01),
    );
    return _card(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
      child: Column(
        children: [
          if (components.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No score inputs are available for this day.',
                style: TextStyle(color: context.vivordoColors.textSecondary),
              ),
            )
          else
            for (var index = 0; index < components.length; index++) ...[
              _componentRow(components[index], totalWeight),
              if (index < components.length - 1)
                Divider(height: 1, color: context.vivordoColors.border),
            ],
          Divider(color: context.vivordoColors.border),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total wellness score',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                totalWeight == 0 ? '-- / 100' : '${total.round()} / 100',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _componentRow(_ScoreComponent item, double totalWeight) {
    final points = item.score == null
        ? null
        : item.score! * item.weight / math.max(totalWeight, .01);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: item.color,
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 118,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  item.score == null
                      ? 'No data found'
                      : 'Score ${item.score!.round()}',
                  style: TextStyle(color: context.vivordoColors.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (item.score ?? 0) / 100,
                minHeight: 9,
                color: item.color,
                backgroundColor: context.vivordoColors.cardMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 54,
            child: Text(
              points == null ? '--' : '${points.toStringAsFixed(1)} pts',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _howItWorks() => _card(
    padding: const EdgeInsets.all(18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: _purple, size: 30),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'Your score combines stress, sleep, activity, and average heart '
            'rate. Activity considers steps, exercise time, and active energy '
            'using your goals. Unavailable activity signals are excluded, '
            'while a recorded zero still counts. Stress is inverted, so lower '
            'stress improves your score. Heart rate scores highest within the '
            '60–80 bpm range.',
            style: const TextStyle(height: 1.45),
          ),
        ),
      ],
    ),
  );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
    ),
  );

  Widget _card({required Widget child, required EdgeInsets padding}) =>
      Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: context.vivordoColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.vivordoColors.border),
          boxShadow: [
            BoxShadow(
              color: context.vivordoColors.shadow,
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );
}

class _WellnessDay {
  const _WellnessDay(
    this.date, {
    this.wellness,
    this.stress,
    this.sleep,
    this.steps,
    this.exerciseMinutes,
    this.activeCalories,
    this.heartRate,
  });
  final DateTime date;
  final double? wellness;
  final double? stress;
  final double? sleep;
  final double? steps;
  final double? exerciseMinutes;
  final double? activeCalories;
  final double? heartRate;
}

class _ScoreComponent {
  const _ScoreComponent(
    this.name,
    this.score,
    this.weight,
    this.icon,
    this.color,
  );
  final String name;
  final double? score;
  final double weight;
  final IconData icon;
  final Color color;
}

class _WellnessChart extends StatefulWidget {
  const _WellnessChart({
    required this.values,
    required this.dates,
    required this.labels,
    required this.usual,
  });
  final List<double?> values;
  final List<DateTime> dates;
  final List<String> labels;
  final double? usual;

  @override
  State<_WellnessChart> createState() => _WellnessChartState();
}

class _WellnessChartState extends State<_WellnessChart> {
  int? selected;

  void _select(double x, double width) {
    if (widget.values.isEmpty) return;
    const left = 34.0;
    final index = widget.values.length == 1
        ? 0
        : (((x - left) / (width - left)) * (widget.values.length - 1))
              .round()
              .clamp(0, widget.values.length - 1);
    if (widget.values[index] != null && selected != index) {
      setState(() => selected = index);
    }
  }

  @override
  void didUpdateWidget(covariant _WellnessChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.values, oldWidget.values)) selected = null;
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
        painter: _WellnessChartPainter(
          values: widget.values,
          dates: widget.dates,
          labels: widget.labels,
          usual: widget.usual,
          selected: selected,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    ),
  );
}

class _WellnessChartPainter extends CustomPainter {
  const _WellnessChartPainter({
    required this.values,
    required this.dates,
    required this.labels,
    required this.usual,
    required this.selected,
    required this.dark,
  });
  final List<double?> values;
  final List<DateTime> dates;
  final List<String> labels;
  final double? usual;
  final int? selected;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const bottom = 27.0;
    final height = size.height - bottom;
    final width = size.width - left;
    final grid = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = height * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      _text(canvas, '${100 - i * 25}', Offset(0, y - 6), 9);
    }
    if (usual != null) {
      final y = height * (1 - usual!.clamp(0, 100) / 100);
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width, y),
        Paint()
          ..color = const Color(0xFF5B42F3).withValues(alpha: .7)
          ..strokeWidth = 1.2,
      );
    }
    final available = <int>[];
    for (var i = 0; i < values.length; i++) {
      if (values[i] != null) available.add(i);
    }
    if (available.isEmpty) return;
    Offset point(int index) {
      final x = values.length == 1
          ? left + width / 2
          : left + width * index / (values.length - 1);
      return Offset(x, height * (1 - values[index]!.clamp(0, 100) / 100));
    }

    final points = available.map(point).toList();
    final path = smoothChartPath(points);
    final fill = Path.from(path)
      ..lineTo(points.last.dx, height)
      ..lineTo(points.first.dx, height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, height), [
          const Color(0xFFFF3B4E).withValues(alpha: .22),
          const Color(0xFFFF3B4E).withValues(alpha: 0),
        ]),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF3B4E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final index in available) {
      final p = point(index);
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 3.5, Paint()..color = const Color(0xFFFF3B4E));
      if (values.length <= 10 || index % 5 == 0 || index == values.length - 1) {
        _centerText(canvas, labels[index], Offset(p.dx, height + 7), 9);
      }
    }
    final index = selected;
    if (index == null || values[index] == null) return;
    final p = point(index);
    canvas.drawCircle(
      p,
      9,
      Paint()..color = const Color(0xFF5B42F3).withValues(alpha: .25),
    );
    canvas.drawCircle(p, 5, Paint()..color = const Color(0xFF5B42F3));
    final painter = TextPainter(
      text: TextSpan(
        text:
            '${DateFormat('MMM d').format(dates[index])}\n${values[index]!.round()}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final boxWidth = painter.width + 20;
    final boxHeight = painter.height + 14;
    final x = (p.dx - boxWidth / 2).clamp(left, size.width - boxWidth);
    final y = (p.dy - boxHeight - 12).clamp(0.0, height - boxHeight);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, boxWidth, boxHeight),
        const Radius.circular(9),
      ),
      Paint()..color = const Color(0xFF5B42F3),
    );
    painter.paint(canvas, Offset(x + 10, y + 7));
  }

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
  bool shouldRepaint(covariant _WellnessChartPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values) ||
      !listEquals(labels, oldDelegate.labels) ||
      usual != oldDelegate.usual ||
      selected != oldDelegate.selected ||
      dark != oldDelegate.dark;
}
