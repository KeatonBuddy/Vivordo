import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

class SleepDetailScreen extends StatefulWidget {
  const SleepDetailScreen({super.key});

  @override
  State<SleepDetailScreen> createState() => _SleepDetailScreenState();
}

class _SleepDetailScreenState extends State<SleepDetailScreen> {
  static const _purple = Color(0xFF5420DE);
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

  String _dayKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Stream<QuerySnapshot<Map<String, dynamic>>> _sleepStream() {
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
          'Sleep',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _sleepStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return _content(snapshot.data);
        },
      ),
    );
  }

  Widget _content(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    final byDay = <String, _SleepValue>{};
    for (final doc in snapshot?.docs ?? const []) {
      final raw = doc.data()['sleep'] as Map?;
      if (raw == null) continue;
      final hours = (raw['avg'] as num?)?.toDouble();
      if (hours == null || hours <= 0) continue;
      byDay[doc.id] = _SleepValue(
        hours: hours,
        bedtime: (raw['bedtime'] as Timestamp?)?.toDate().toLocal(),
        wakeTime: (raw['wakeTime'] as Timestamp?)?.toDate().toLocal(),
        stages: _stageValues(raw['stages'] as Map?),
      );
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final days = List.generate(_rangeDays, (index) {
      final date = today.subtract(Duration(days: _rangeDays - index - 1));
      return _SleepDay(date, byDay[_dayKey(date)]);
    });
    final previousCutoff = today.subtract(Duration(days: _rangeDays));
    final previous = (snapshot?.docs ?? const [])
        .where((doc) {
          final date = DateTime.tryParse(doc.id);
          return date != null &&
              date.isBefore(previousCutoff) &&
              !date.isBefore(
                previousCutoff.subtract(Duration(days: _rangeDays)),
              );
        })
        .map(
          (doc) => ((doc.data()['sleep'] as Map?)?['avg'] as num?)?.toDouble(),
        )
        .whereType<double>()
        .where((hours) => hours > 0)
        .toList();
    final recorded = days.where((day) => day.value != null).toList();
    final total = recorded.fold<double>(
      0,
      (total, day) => total + day.value!.hours,
    );
    final average = recorded.isEmpty ? 0.0 : total / recorded.length;
    final previousAverage = previous.isEmpty
        ? null
        : previous.reduce((a, b) => a + b) / previous.length;
    final changeMinutes = previousAverage == null
        ? null
        : ((average - previousAverage) * 60).round();
    final latest = recorded.isEmpty ? null : recorded.last.value;
    final averageStages = _averageStages(recorded);

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
          _summaryCard(average, total, changeMinutes, latest),
          const SizedBox(height: 24),
          Text(
            '$_rangeName sleep',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _sleepChart(days),
          const SizedBox(height: 24),
          Text(
            _rangeIndex == 0
                ? "Last night's sleep stages"
                : 'Average sleep stages',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _stagesCard(averageStages, average),
          const SizedBox(height: 24),
          const Text(
            'Insight',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _insightCard(recorded, average),
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
    double average,
    double total,
    int? changeMinutes,
    _SleepValue? latest,
  ) {
    final progress = (average / 8).clamp(0.0, 1.0);
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBubble(Icons.nightlight_round, _purple, size: 62),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rangeIndex == 0 ? "LAST NIGHT'S SLEEP" : 'AVERAGE SLEEP',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _duration(average),
                      style: const TextStyle(
                        fontSize: 38,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${_duration(total)} this ${_rangeIndex == 0
                          ? 'day'
                          : _rangeIndex == 1
                          ? 'week'
                          : 'month'}',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    if (changeMinutes != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${changeMinutes >= 0 ? '↑' : '↓'} ${changeMinutes.abs()} min vs previous $_rangeName',
                        style: TextStyle(
                          color: changeMinutes >= 0
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
              const Text('Sleep goal 8 h'),
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
                child: _timeStat(Icons.bed_rounded, 'Bedtime', latest?.bedtime),
              ),
              Container(
                width: 1,
                height: 52,
                color: context.vivordoColors.border,
              ),
              Expanded(
                child: _timeStat(
                  Icons.wb_sunny_rounded,
                  'Wake time',
                  latest?.wakeTime,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeStat(IconData icon, String label, DateTime? time) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, color: _purple),
      const SizedBox(width: 9),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: context.vivordoColors.textSecondary),
            ),
            Text(
              time == null ? 'Not synced' : DateFormat('h:mm a').format(time),
              maxLines: 1,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _sleepChart(List<_SleepDay> days) => _card(
    padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
    child: SizedBox(
      height: 245,
      child: CustomPaint(
        painter: _SleepBarPainter(
          values: days.map((day) => day.value?.hours ?? 0).toList(),
          labels: days.map((day) => _chartLabel(day.date)).toList(),
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
        size: const Size(double.infinity, 245),
      ),
    ),
  );

  String _chartLabel(DateTime date) => _rangeIndex == 2
      ? DateFormat('M/d').format(date)
      : DateFormat('E').format(date);

  Widget _stagesCard(Map<String, double> stages, double average) {
    if (stages.isEmpty) {
      return _card(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            _iconBubble(Icons.bedtime_outlined, _purple),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sleep-stage data not synced',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Total sleep is available, but stage details were not provided by your health source.',
                    style: TextStyle(
                      color: context.vivordoColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    const colors = {
      'Awake': Color(0xFFFF6900),
      'REM': Color(0xFF9D20E6),
      'Core': Color(0xFF356DEC),
      'Deep': Color(0xFF2B2497),
    };
    final totalMinutes = stages.values.fold<double>(
      0,
      (total, value) => total + value,
    );
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Column(
        children: [
          for (final entry in stages.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: colors[entry.key] ?? _purple,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    // "Awake" was clipped by the old 55 px slot on compact
                    // screens and when iOS text scaling was enabled.
                    width: 68,
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: totalMinutes == 0 ? 0 : entry.value / totalMinutes,
                      color: colors[entry.key] ?? _purple,
                      backgroundColor: context.vivordoColors.cardMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _duration(entry.value / 60),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
          Divider(color: context.vivordoColors.border),
          Row(
            children: [
              Text(
                _rangeIndex == 0
                    ? "Last night's total sleep"
                    : 'Average total sleep',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                _duration(average),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _insightCard(List<_SleepDay> recorded, double average) {
    String text;
    if (recorded.isEmpty) {
      text = 'Sync sleep from your health source to reveal sleep trends.';
    } else if (average >= 8) {
      text = 'You averaged at least eight hours of sleep in this period.';
    } else if (average >= 7) {
      text =
          'Your average sleep is within the recommended range for many adults.';
    } else {
      text = 'Your average sleep was below seven hours in this period.';
    }
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

  Map<String, double> _stageValues(Map? raw) {
    if (raw == null) return const {};
    final result = <String, double>{};
    for (final name in const ['Awake', 'REM', 'Core', 'Deep']) {
      final value = raw[name.toLowerCase()] as num?;
      if (value != null && value > 0) result[name] = value.toDouble();
    }
    return result;
  }

  Map<String, double> _averageStages(List<_SleepDay> days) {
    final sums = <String, double>{};
    var count = 0;
    for (final day in days) {
      final stages = day.value?.stages ?? const {};
      if (stages.isEmpty) continue;
      count++;
      for (final entry in stages.entries) {
        sums.update(
          entry.key,
          (value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }
    if (count == 0) return const {};
    return sums.map((key, value) => MapEntry(key, value / count));
  }

  String _duration(double hours) {
    final totalMinutes = (hours * 60).round();
    if (totalMinutes <= 0) return 'No data';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return h == 0 ? '$m m' : '$h h ${m.toString().padLeft(2, '0')} m';
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

class _SleepValue {
  const _SleepValue({
    required this.hours,
    this.bedtime,
    this.wakeTime,
    required this.stages,
  });
  final double hours;
  final DateTime? bedtime;
  final DateTime? wakeTime;
  final Map<String, double> stages;
}

class _SleepDay {
  const _SleepDay(this.date, this.value);
  final DateTime date;
  final _SleepValue? value;
}

class _SleepBarPainter extends CustomPainter {
  const _SleepBarPainter({
    required this.values,
    required this.labels,
    required this.dark,
  });
  final List<double> values;
  final List<String> labels;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const top = 12.0;
    const bottom = 28.0;
    final height = size.height - top - bottom;
    final maxY = math.max(
      10.0,
      values.isEmpty ? 10.0 : values.reduce(math.max) * 1.18,
    );
    final axis = Paint()..color = dark ? Colors.white24 : Colors.black12;
    canvas.drawLine(
      Offset(left, top + height),
      Offset(size.width, top + height),
      axis,
    );
    final goalY = top + height - 8 / maxY * height;
    canvas.drawLine(
      Offset(left, goalY),
      Offset(size.width, goalY),
      Paint()..color = _SleepDetailScreenState._purple.withValues(alpha: .65),
    );
    _text(canvas, 'Goal 8 h', Offset(size.width - 58, goalY - 16), 10);
    if (values.isEmpty) return;
    final slot = (size.width - left) / values.length;
    final barWidth = math.min(28.0, slot * .55);
    for (var i = 0; i < values.length; i++) {
      final x = left + slot * i + slot / 2;
      final barHeight = values[i] / maxY * height;
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
        Paint()..color = _SleepDetailScreenState._purple,
      );
      if (values.length <= 10 || i % 5 == 0 || i == values.length - 1) {
        _center(canvas, labels[i], Offset(x, top + height + 8), 9);
      }
    }
  }

  void _text(Canvas canvas, String text, Offset offset, double size) {
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
    painter.paint(canvas, offset);
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
  bool shouldRepaint(covariant _SleepBarPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.dark != dark;
}
