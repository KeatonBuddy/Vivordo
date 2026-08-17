import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/activity_goals_service.dart';
import 'package:vivordo_health/src/services/workout_service.dart';
import 'package:vivordo_health/src/utils/smooth_chart_path.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

class ExerciseDetailScreen extends StatefulWidget {
  const ExerciseDetailScreen({super.key});

  @override
  State<ExerciseDetailScreen> createState() => _ExerciseDetailScreenState();
}

class _ExerciseDetailScreenState extends State<ExerciseDetailScreen> {
  static const _purple = Color(0xFF5B28E6);
  int _rangeIndex = 0;
  String? _selectedExercise;

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

  Stream<QuerySnapshot<Map<String, dynamic>>> _metricsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    final today = DateUtils.dateOnly(DateTime.now());
    final oldest = today.subtract(const Duration(days: 59));
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: _dayKey(oldest))
        .where(FieldPath.documentId, isLessThanOrEqualTo: _dayKey(today))
        .orderBy(FieldPath.documentId)
        .snapshots();
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
          'Exercise',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _metricsStream(),
        builder: (context, metricsSnapshot) {
          if (!metricsSnapshot.hasData &&
              metricsSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<List<SavedWorkout>>(
            stream: WorkoutService.watchAll(),
            initialData: const [],
            builder: (context, workoutSnapshot) {
              return StreamBuilder<ActivityGoals>(
                stream: ActivityGoalsService.watch(),
                initialData: const ActivityGoals(),
                builder: (context, goalsSnapshot) => _content(
                  metricsSnapshot.data,
                  workoutSnapshot.data ?? const [],
                  goalsSnapshot.data ?? const ActivityGoals(),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _content(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
    List<SavedWorkout> workouts,
    ActivityGoals goals,
  ) {
    final minutes = <String, int>{};
    for (final doc in snapshot?.docs ?? const []) {
      minutes[doc.id] =
          ((doc.data()['exercise_time'] as Map?)?['sum'] as num?)?.round() ?? 0;
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final days = List.generate(_rangeDays, (index) {
      final date = today.subtract(Duration(days: _rangeDays - index - 1));
      return _ExerciseDay(date, minutes[_dayKey(date)] ?? 0);
    });
    final cutoff = today.subtract(Duration(days: _rangeDays));
    final previous = (snapshot?.docs ?? const [])
        .where((doc) {
          final date = DateTime.tryParse(doc.id);
          return date != null &&
              date.isBefore(cutoff) &&
              !date.isBefore(cutoff.subtract(Duration(days: _rangeDays)));
        })
        .map(
          (doc) =>
              ((doc.data()['exercise_time'] as Map?)?['sum'] as num?)
                  ?.round() ??
              0,
        )
        .toList();
    final rangeStart = today.subtract(Duration(days: _rangeDays - 1));
    final rangeWorkouts = workouts.where((workout) {
      final date = DateUtils.dateOnly(workout.completedAt.toLocal());
      return !date.isBefore(rangeStart) && !date.isAfter(today);
    }).toList();
    final total = days.fold<int>(0, (total, day) => total + day.minutes);
    final average = days.isEmpty ? 0 : (total / days.length).round();
    final previousAverage = previous.isEmpty
        ? null
        : previous.reduce((a, b) => a + b) / previous.length;
    final changeMinutes = previousAverage == null
        ? null
        : average - previousAverage.round();
    final goal = goals.exerciseMinutes * _rangeDays;
    final progress = goal <= 0 ? 0.0 : (total / goal).clamp(0.0, 1.0);
    final activeDates = rangeWorkouts
        .map((workout) => _dayKey(workout.completedAt.toLocal()))
        .toSet();
    final restDays = math.max(0, _rangeDays - activeDates.length);
    final progression = _progressions(workouts);
    final exerciseNames = progression.keys.toList()..sort();
    final selected = exerciseNames.contains(_selectedExercise)
        ? _selectedExercise
        : (exerciseNames.isEmpty ? null : exerciseNames.first);
    final points = selected == null
        ? const <_WeightPoint>[]
        : progression[selected] ?? const <_WeightPoint>[];

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
          _summaryCard(
            total,
            average,
            changeMinutes,
            goal,
            progress,
            rangeWorkouts.length,
            restDays,
          ),
          if (_rangeIndex != 0) ...[
            const SizedBox(height: 24),
            const Text(
              'Exercise time',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            _minutesChart(days, goals.exerciseMinutes.toDouble()),
          ],
          const SizedBox(height: 24),
          const Text(
            'Weight progression',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _exerciseSelector(exerciseNames, selected),
          const SizedBox(height: 10),
          _weightProgression(selected, points),
          const SizedBox(height: 24),
          const Text(
            'Insights',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _insights(changeMinutes, selected, points),
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
    int workouts,
    int restDays,
  ) {
    final hours = total ~/ 60;
    final minutes = total % 60;
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBubble(Icons.fitness_center_rounded, _purple, size: 62),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EXERCISE TIME',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      hours > 0 ? '$hours h  $minutes m' : '$minutes min',
                      style: const TextStyle(
                        fontSize: 38,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$average min daily average',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    if (change != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${change >= 0 ? '↑' : '↓'} ${change.abs()} min vs previous $_rangeName',
                        style: TextStyle(
                          color: change >= 0
                              ? const Color(0xFF20B26B)
                              : Colors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: context.vivordoColors.border),
          Row(
            children: [
              Text('$_rangeName goal ${_duration(goal)}'),
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
              color: _purple,
              backgroundColor: context.vivordoColors.cardMuted,
            ),
          ),
          const SizedBox(height: 18),
          Divider(color: context.vivordoColors.border),
          Row(
            children: [
              Expanded(
                child: _summaryStat(
                  Icons.fitness_center_rounded,
                  '$workouts',
                  workouts == 1 ? 'workout' : 'workouts',
                ),
              ),
              Container(
                width: 1,
                height: 46,
                color: context.vivordoColors.border,
              ),
              Expanded(
                child: _summaryStat(
                  Icons.bed_rounded,
                  '$restDays',
                  restDays == 1 ? 'rest day' : 'rest days',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(IconData icon, String value, String label) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, color: _purple),
      const SizedBox(width: 8),
      Text(
        value,
        style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
      ),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          style: TextStyle(color: context.vivordoColors.textSecondary),
        ),
      ),
    ],
  );

  Widget _minutesChart(List<_ExerciseDay> days, double dailyGoal) => _card(
    padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
    child: SizedBox(
      height: 245,
      child: _ExerciseTimeChart(
        values: days.map((day) => day.minutes.toDouble()).toList(),
        labels: days.map((day) => _chartLabel(day.date)).toList(),
        dates: days.map((day) => day.date).toList(),
        dailyGoal: dailyGoal,
      ),
    ),
  );

  String _chartLabel(DateTime date) => _rangeIndex == 2
      ? DateFormat('M/d').format(date)
      : DateFormat('E').format(date);

  Widget _exerciseSelector(List<String> names, String? selected) => _card(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        isExpanded: true,
        value: selected,
        hint: const Text('No weighted exercises recorded'),
        items: names
            .map(
              (name) => DropdownMenuItem(
                value: name,
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            )
            .toList(),
        onChanged: names.isEmpty
            ? null
            : (value) => setState(() => _selectedExercise = value),
      ),
    ),
  );

  Widget _weightProgression(String? exercise, List<_WeightPoint> points) {
    if (exercise == null || points.isEmpty) {
      return _card(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Complete a weighted exercise to see your progression.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.vivordoColors.textSecondary),
          ),
        ),
      );
    }
    final visible = points.length > 8
        ? points.sublist(points.length - 8)
        : points;
    final change = visible.length < 2
        ? 0.0
        : visible.last.weight - visible.first.weight;
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exercise,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          Text(
            '${change >= 0 ? '↑' : '↓'} ${_number(change.abs())} lb across ${visible.length} sessions',
            style: TextStyle(
              color: change >= 0 ? const Color(0xFF20B26B) : Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 190,
            child: CustomPaint(
              painter: _WeightChartPainter(
                points: visible,
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
              size: const Size(double.infinity, 190),
            ),
          ),
        ],
      ),
    );
  }

  Widget _insights(int? change, String? exercise, List<_WeightPoint> points) {
    final rows = <String>[
      if (change != null)
        'Your daily exercise time ${change >= 0 ? 'increased' : 'decreased'} by ${change.abs()} minutes.',
      if (exercise != null && points.length > 1)
        '$exercise changed by ${_number((points.last.weight - points.first.weight).abs())} lb across your recorded sessions.',
      if (change == null && (exercise == null || points.length < 2))
        'Keep recording exercise to unlock personalized trends.',
    ];
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                children: [
                  _iconBubble(
                    Icons.trending_up_rounded,
                    const Color(0xFF20B26B),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(rows[i])),
                ],
              ),
            ),
            if (i != rows.length - 1)
              Divider(height: 1, color: context.vivordoColors.border),
          ],
        ],
      ),
    );
  }

  Map<String, List<_WeightPoint>> _progressions(List<SavedWorkout> workouts) {
    final pointsByName = <String, List<_WeightPoint>>{};
    final displayNames = <String, String>{};
    for (final workout in workouts.reversed) {
      for (final exercise in workout.exercises) {
        final weights = exercise.sets
            .map((set) => set.weightLbs)
            .where((weight) => weight > 0)
            .toList();
        if (weights.isEmpty) continue;
        final normalizedName = exercise.name.trim().toLowerCase();
        if (normalizedName.isEmpty) continue;
        final currentDisplayName = displayNames[normalizedName];
        if (currentDisplayName == null ||
            _capitalLetterCount(exercise.name) >
                _capitalLetterCount(currentDisplayName)) {
          displayNames[normalizedName] = exercise.name.trim();
        }
        pointsByName
            .putIfAbsent(normalizedName, () => [])
            .add(
              _WeightPoint(
                workout.completedAt.toLocal(),
                weights.reduce(math.max),
              ),
            );
      }
    }
    return {
      for (final entry in pointsByName.entries)
        displayNames[entry.key] ?? entry.key: entry.value,
    };
  }

  int _capitalLetterCount(String value) =>
      RegExp(r'[A-Z]').allMatches(value).length;

  String _duration(int minutes) => minutes >= 60
      ? '${minutes ~/ 60} h${minutes % 60 == 0 ? '' : ' ${minutes % 60} m'}'
      : '$minutes min';
  String _number(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 1);

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

  Widget _iconBubble(IconData icon, Color color, {double size = 48}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: size * .48),
      );
}

class _ExerciseDay {
  const _ExerciseDay(this.date, this.minutes);
  final DateTime date;
  final int minutes;
}

class _WeightPoint {
  const _WeightPoint(this.date, this.weight);
  final DateTime date;
  final double weight;
}

class _ExerciseTimeChart extends StatefulWidget {
  const _ExerciseTimeChart({
    required this.values,
    required this.labels,
    required this.dates,
    required this.dailyGoal,
  });

  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;
  final double dailyGoal;

  @override
  State<_ExerciseTimeChart> createState() => _ExerciseTimeChartState();
}

class _ExerciseTimeChartState extends State<_ExerciseTimeChart> {
  int? selected;

  void _select(double x, double width) {
    if (widget.values.isEmpty) return;
    const left = 34.0;
    final slot = (width - left) / widget.values.length;
    final index = ((x - left) / slot).floor().clamp(
      0,
      widget.values.length - 1,
    );
    if (selected != index) setState(() => selected = index);
  }

  @override
  void didUpdateWidget(covariant _ExerciseTimeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.values, widget.values) ||
        !listEquals(oldWidget.dates, widget.dates)) {
      selected = null;
    }
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
        painter: _ExerciseBarPainter(
          values: widget.values,
          labels: widget.labels,
          dates: widget.dates,
          dailyGoal: widget.dailyGoal,
          selected: selected,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    ),
  );
}

class _ExerciseBarPainter extends CustomPainter {
  const _ExerciseBarPainter({
    required this.values,
    required this.labels,
    required this.dates,
    required this.dailyGoal,
    required this.selected,
    required this.dark,
  });
  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;
  final double dailyGoal;
  final int? selected;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const bottom = 28.0;
    const top = 12.0;
    final height = size.height - bottom - top;
    final maxValue = math.max(
      dailyGoal * 1.25,
      values.isEmpty ? 60.0 : values.reduce(math.max) * 1.2,
    );
    final axis = Paint()..color = dark ? Colors.white24 : Colors.black12;
    canvas.drawLine(
      Offset(left, top + height),
      Offset(size.width, top + height),
      axis,
    );
    if (dailyGoal > 0) {
      final y = top + height - (dailyGoal / maxValue * height);
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width, y),
        Paint()
          ..color = _ExerciseDetailScreenState._purple.withValues(alpha: .65)
          ..strokeWidth = 1,
      );
      _rightText(
        canvas,
        'Goal ${dailyGoal.round()} min',
        Offset(size.width - 8, top),
        10,
      );
    }
    if (values.isEmpty) return;
    final slot = (size.width - left) / values.length;
    final barWidth = math.min(28.0, slot * .55);
    for (var i = 0; i < values.length; i++) {
      final x = left + slot * i + slot / 2;
      final barHeight = values[i] / maxValue * height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - barWidth / 2,
            top + height - barHeight,
            barWidth,
            barHeight,
          ),
          const Radius.circular(10),
        ),
        Paint()..color = _ExerciseDetailScreenState._purple,
      );
      if (selected == i) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x - barWidth / 2 - 4,
              top + height - barHeight - 4,
              barWidth + 8,
              barHeight + 8,
            ),
            const Radius.circular(12),
          ),
          Paint()
            ..color = _ExerciseDetailScreenState._purple.withValues(alpha: .2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      if (values.length <= 10 || i % 5 == 0 || i == values.length - 1) {
        _center(canvas, labels[i], Offset(x, top + height + 8), 9);
      }
    }

    final index = selected;
    if (index != null && index < values.length && index < dates.length) {
      final x = left + slot * index + slot / 2;
      final barHeight = values[index] / maxValue * height;
      final barTop = top + height - barHeight;
      final label =
          '${DateFormat('MMM d').format(dates[index])}\n${values[index].round()} min';
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
      final boxX = (x - boxWidth / 2).clamp(0.0, size.width - boxWidth);
      final boxY = (barTop - boxHeight - 10).clamp(0.0, height - boxHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(boxX, boxY, boxWidth, boxHeight),
          const Radius.circular(9),
        ),
        Paint()..color = dark ? const Color(0xFF302B48) : Colors.white,
      );
      painter.paint(canvas, Offset(boxX + 9, boxY + 7));
    }
  }

  void _rightText(Canvas canvas, String text, Offset offset, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: dark ? Colors.white60 : Colors.black54,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(offset.dx - painter.width, offset.dy));
  }

  void _center(Canvas canvas, String text, Offset offset, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: dark ? Colors.white60 : Colors.black54,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(offset.dx - painter.width / 2, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _ExerciseBarPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.dates != dates ||
      oldDelegate.dailyGoal != dailyGoal ||
      oldDelegate.selected != selected ||
      oldDelegate.dark != dark;
}

class _WeightChartPainter extends CustomPainter {
  const _WeightChartPainter({required this.points, required this.dark});
  final List<_WeightPoint> points;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const right = 10.0;
    const top = 14.0;
    const bottom = 30.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;
    final weights = points.map((point) => point.weight).toList();
    final low = weights.reduce(math.min);
    final high = weights.reduce(math.max);
    final padding = math.max(5.0, (high - low) * .25);
    final minY = math.max(0.0, low - padding);
    final maxY = high + padding;
    final offsets = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? left + width / 2
          : left + width * i / (points.length - 1);
      final y =
          top + height - ((points[i].weight - minY) / (maxY - minY) * height);
      offsets.add(Offset(x, y));
    }
    final line = Paint()
      ..color = _ExerciseDetailScreenState._purple
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawPath(smoothChartPath(offsets), line);
    for (var i = 0; i < offsets.length; i++) {
      canvas.drawCircle(
        offsets[i],
        5,
        Paint()..color = _ExerciseDetailScreenState._purple,
      );
      _center(
        canvas,
        '${points[i].weight.round()} lb',
        Offset(offsets[i].dx, offsets[i].dy - 20),
        9,
      );
      _center(
        canvas,
        DateFormat('MMM d').format(points[i].date),
        Offset(offsets[i].dx, top + height + 9),
        8,
      );
    }
  }

  void _center(Canvas canvas, String text, Offset offset, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: dark ? Colors.white60 : Colors.black54,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(offset.dx - painter.width / 2, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.dark != dark;
}
