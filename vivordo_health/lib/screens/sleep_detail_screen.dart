import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/utils/heart_rate_history.dart';
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
    final sleepingHeartRate = _rangeIndex == 0 && latest != null
        ? _heartRateDuringSleep(snapshot, latest)
        : const <HeartRateHistoryReading>[];

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
            _rangeIndex == 0 ? 'Heart rate during sleep' : '$_rangeName sleep',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          _rangeIndex == 0
              ? _sleepHeartRateChart(sleepingHeartRate, latest)
              : _sleepChart(days),
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
      child: _SleepBarChart(
        values: days.map((day) => day.value?.hours ?? 0).toList(),
        labels: days.map((day) => _chartLabel(day.date)).toList(),
        dates: days.map((day) => day.date).toList(),
      ),
    ),
  );

  String _chartLabel(DateTime date) => _rangeIndex == 2
      ? DateFormat('M/d').format(date)
      : DateFormat('E').format(date);

  List<HeartRateHistoryReading> _heartRateDuringSleep(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
    _SleepValue sleep,
  ) {
    final bedtime = sleep.bedtime;
    final wakeTime = sleep.wakeTime;
    if (bedtime == null || wakeTime == null || !wakeTime.isAfter(bedtime)) {
      return const [];
    }

    final readings = <HeartRateHistoryReading>[];
    final firstDay = DateUtils.dateOnly(bedtime);
    final lastDay = DateUtils.dateOnly(wakeTime);
    for (final doc in snapshot?.docs ?? const []) {
      final fallbackDate = DateTime.tryParse(doc.id);
      if (fallbackDate == null) continue;
      final documentDay = DateUtils.dateOnly(fallbackDate);
      if (documentDay.isBefore(firstDay) || documentDay.isAfter(lastDay)) {
        continue;
      }
      readings.addAll(
        mergedHeartRateHistory(
          doc.data(),
          fallbackDate: fallbackDate,
          includeDailyFallback: false,
        ).where(
          (reading) =>
              !reading.timestamp.isBefore(bedtime) &&
              !reading.timestamp.isAfter(wakeTime) &&
              reading.bpm >= 30 &&
              reading.bpm <= 220,
        ),
      );
    }
    readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return readings;
  }

  Widget _sleepHeartRateChart(
    List<HeartRateHistoryReading> readings,
    _SleepValue? sleep,
  ) {
    final bedtime = sleep?.bedtime;
    final wakeTime = sleep?.wakeTime;
    if (bedtime == null || wakeTime == null || !wakeTime.isAfter(bedtime)) {
      return _sleepHeartRateEmptyState(
        'Sleep times not synced',
        'Bedtime and wake time are needed to identify heart-rate readings captured during sleep.',
      );
    }
    if (readings.isEmpty) {
      return _sleepHeartRateEmptyState(
        'No sleeping heart-rate data',
        'Your sleep was recorded, but no timestamped heart-rate readings were found between bedtime and wake time.',
      );
    }

    final values = readings.map((reading) => reading.bpm).toList();
    final average = values.reduce((a, b) => a + b) / values.length;
    final low = values.reduce(math.min).round();
    final high = values.reduce(math.max).round();
    final duration = wakeTime.difference(bedtime);

    return _card(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AVERAGE SLEEPING HEART RATE',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: average.round().toString(),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const TextSpan(
                            text: ' bpm',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_duration(duration.inMinutes / 60)} window',
                style: TextStyle(
                  color: context.vivordoColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: _SleepingHeartRateChart(
              readings: readings,
              bedtime: bedtime,
              wakeTime: wakeTime,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Low $low bpm',
                style: TextStyle(
                  color: context.vivordoColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                'High $high bpm',
                style: TextStyle(
                  color: context.vivordoColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sleepHeartRateEmptyState(String title, String message) => _card(
    padding: const EdgeInsets.all(22),
    child: Row(
      children: [
        _iconBubble(Icons.favorite_outline_rounded, _purple),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(
                message,
                style: TextStyle(color: context.vivordoColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    ),
  );

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

class _SleepingHeartRateChart extends StatefulWidget {
  const _SleepingHeartRateChart({
    required this.readings,
    required this.bedtime,
    required this.wakeTime,
  });

  final List<HeartRateHistoryReading> readings;
  final DateTime bedtime;
  final DateTime wakeTime;

  @override
  State<_SleepingHeartRateChart> createState() =>
      _SleepingHeartRateChartState();
}

class _SleepingHeartRateChartState extends State<_SleepingHeartRateChart> {
  int? _selectedIndex;

  void _select(double x, double width) {
    if (widget.readings.isEmpty) return;
    const left = 38.0;
    const right = 6.0;
    final plotWidth = width - left - right;
    final totalMilliseconds = widget.wakeTime
        .difference(widget.bedtime)
        .inMilliseconds;
    if (plotWidth <= 0 || totalMilliseconds <= 0) return;

    final fraction = ((x - left) / plotWidth).clamp(0.0, 1.0);
    final targetMilliseconds = (fraction * totalMilliseconds).round();
    var nearestIndex = 0;
    var nearestDistance =
        (widget.readings.first.timestamp
                    .difference(widget.bedtime)
                    .inMilliseconds -
                targetMilliseconds)
            .abs();
    for (var index = 0; index < widget.readings.length; index++) {
      final elapsed = widget.readings[index].timestamp
          .difference(widget.bedtime)
          .inMilliseconds;
      final distance = (elapsed - targetMilliseconds).abs();
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }
    if (_selectedIndex != nearestIndex) {
      setState(() => _selectedIndex = nearestIndex);
    }
  }

  @override
  void didUpdateWidget(covariant _SleepingHeartRateChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.readings, widget.readings) ||
        oldWidget.bedtime != widget.bedtime ||
        oldWidget.wakeTime != widget.wakeTime) {
      _selectedIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (event) =>
          _select(event.localPosition.dx, constraints.maxWidth),
      onHorizontalDragStart: (event) =>
          _select(event.localPosition.dx, constraints.maxWidth),
      onHorizontalDragUpdate: (event) =>
          _select(event.localPosition.dx, constraints.maxWidth),
      child: CustomPaint(
        size: Size.infinite,
        painter: _SleepingHeartRatePainter(
          readings: widget.readings,
          bedtime: widget.bedtime,
          wakeTime: widget.wakeTime,
          selectedIndex: _selectedIndex,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    ),
  );
}

class _SleepingHeartRatePainter extends CustomPainter {
  const _SleepingHeartRatePainter({
    required this.readings,
    required this.bedtime,
    required this.wakeTime,
    required this.selectedIndex,
    required this.dark,
  });

  final List<HeartRateHistoryReading> readings;
  final DateTime bedtime;
  final DateTime wakeTime;
  final int? selectedIndex;
  final bool dark;

  static const _lineColor = Color(0xFF7B67F6);

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    const right = 6.0;
    const top = 12.0;
    const bottom = 35.0;
    final plotWidth = size.width - left - right;
    final plotHeight = size.height - top - bottom;
    if (plotWidth <= 0 || plotHeight <= 0 || readings.isEmpty) return;

    final values = readings.map((reading) => reading.bpm).toList();
    var minY = ((values.reduce(math.min) - 5) / 5).floor() * 5.0;
    var maxY = ((values.reduce(math.max) + 5) / 5).ceil() * 5.0;
    minY = math.max(30, minY);
    maxY = math.min(220, maxY);
    if (maxY - minY < 10) {
      minY = math.max(30, minY - 5);
      maxY = math.min(220, maxY + 5);
    }

    final gridColor = dark ? Colors.white12 : Colors.black12;
    final labelColor = dark ? Colors.white60 : Colors.black54;
    for (var index = 0; index < 3; index++) {
      final fraction = index / 2;
      final y = top + plotHeight * fraction;
      canvas.drawLine(
        Offset(left, y),
        Offset(left + plotWidth, y),
        Paint()..color = gridColor,
      );
      final value = maxY - (maxY - minY) * fraction;
      _paintText(
        canvas,
        value.round().toString(),
        Offset(0, y - 7),
        11,
        labelColor,
      );
    }

    final totalMilliseconds = wakeTime.difference(bedtime).inMilliseconds;
    if (totalMilliseconds <= 0) return;
    Offset pointFor(HeartRateHistoryReading reading) {
      final elapsed = reading.timestamp.difference(bedtime).inMilliseconds;
      final x =
          left + (elapsed / totalMilliseconds).clamp(0.0, 1.0) * plotWidth;
      final y =
          top +
          (1 - ((reading.bpm - minY) / (maxY - minY)).clamp(0.0, 1.0)) *
              plotHeight;
      return Offset(x, y);
    }

    final linePaint = Paint()
      ..color = _lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, top),
        Offset(0, top + plotHeight),
        [
          _lineColor.withValues(alpha: dark ? .22 : .16),
          _lineColor.withValues(alpha: 0),
        ],
      );

    var segment = <Offset>[];
    DateTime? previousTime;
    void drawSegment() {
      if (segment.isEmpty) return;
      if (segment.length == 1) {
        final point = segment.single;
        canvas.drawLine(
          Offset(point.dx - 3, point.dy),
          Offset(point.dx + 3, point.dy),
          linePaint,
        );
        segment = <Offset>[];
        return;
      }
      final line = Path()..moveTo(segment.first.dx, segment.first.dy);
      for (final point in segment.skip(1)) {
        line.lineTo(point.dx, point.dy);
      }
      final fill = Path.from(line)
        ..lineTo(segment.last.dx, top + plotHeight)
        ..lineTo(segment.first.dx, top + plotHeight)
        ..close();
      canvas.drawPath(fill, fillPaint);
      canvas.drawPath(line, linePaint);
      segment = <Offset>[];
    }

    for (final reading in readings) {
      if (previousTime != null &&
          reading.timestamp.difference(previousTime) >
              const Duration(minutes: 45)) {
        drawSegment();
      }
      segment.add(pointFor(reading));
      previousTime = reading.timestamp;
    }
    drawSegment();

    final boundaryPaint = Paint()
      ..color = dark ? Colors.white54 : Colors.black38
      ..strokeWidth = 1.2;
    _drawDashedLine(
      canvas,
      Offset(left, top),
      Offset(left, top + plotHeight),
      boundaryPaint,
    );
    _drawDashedLine(
      canvas,
      Offset(left + plotWidth, top),
      Offset(left + plotWidth, top + plotHeight),
      boundaryPaint,
    );
    _paintText(
      canvas,
      DateFormat('h:mm a').format(bedtime),
      Offset(left, top + plotHeight + 10),
      11,
      labelColor,
    );
    final wakeLabel = DateFormat('h:mm a').format(wakeTime);
    final wakePainter = _textPainter(wakeLabel, 11, labelColor)..layout();
    wakePainter.paint(
      canvas,
      Offset(left + plotWidth - wakePainter.width, top + plotHeight + 10),
    );

    final index = selectedIndex;
    if (index != null && index >= 0 && index < readings.length) {
      final reading = readings[index];
      final point = pointFor(reading);
      final selectionColor = dark ? Colors.white70 : Colors.black54;
      canvas.drawLine(
        Offset(point.dx, top),
        Offset(point.dx, top + plotHeight),
        Paint()
          ..color = selectionColor.withValues(alpha: .55)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        point,
        6,
        Paint()..color = dark ? Colors.black : Colors.white,
      );
      canvas.drawCircle(point, 4, Paint()..color = _lineColor);

      final tooltip = TextPainter(
        text: TextSpan(
          text:
              '${DateFormat('h:mm a').format(reading.timestamp)}\n${reading.bpm.round()} bpm',
          style: TextStyle(
            color: dark ? Colors.white : Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final tooltipWidth = tooltip.width + 18;
      final tooltipHeight = tooltip.height + 12;
      final tooltipX = (point.dx - tooltipWidth / 2).clamp(
        left,
        left + plotWidth - tooltipWidth,
      );
      final preferredY = point.dy - tooltipHeight - 12;
      final tooltipY = preferredY >= top
          ? preferredY
          : math.min(point.dy + 12, top + plotHeight - tooltipHeight);
      final tooltipRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight),
        const Radius.circular(9),
      );
      canvas.drawRRect(
        tooltipRect,
        Paint()..color = dark ? const Color(0xFF302B48) : Colors.white,
      );
      canvas.drawRRect(
        tooltipRect,
        Paint()
          ..color = _lineColor.withValues(alpha: .35)
          ..style = PaintingStyle.stroke,
      );
      tooltip.paint(canvas, Offset(tooltipX + 9, tooltipY + 6));
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 5.0;
    const gap = 5.0;
    var y = start.dy;
    while (y < end.dy) {
      canvas.drawLine(
        Offset(start.dx, y),
        Offset(start.dx, math.min(y + dash, end.dy)),
        paint,
      );
      y += dash + gap;
    }
  }

  TextPainter _textPainter(String text, double size, Color color) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: size, color: color),
        ),
        textDirection: ui.TextDirection.ltr,
      );

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    double size,
    Color color,
  ) {
    final painter = _textPainter(text, size, color)..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _SleepingHeartRatePainter oldDelegate) =>
      oldDelegate.readings != readings ||
      oldDelegate.bedtime != bedtime ||
      oldDelegate.wakeTime != wakeTime ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.dark != dark;
}

class _SleepBarChart extends StatefulWidget {
  const _SleepBarChart({
    required this.values,
    required this.labels,
    required this.dates,
  });

  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;

  @override
  State<_SleepBarChart> createState() => _SleepBarChartState();
}

class _SleepBarChartState extends State<_SleepBarChart> {
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
  void didUpdateWidget(covariant _SleepBarChart oldWidget) {
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
        painter: _SleepBarPainter(
          values: widget.values,
          labels: widget.labels,
          dates: widget.dates,
          selected: selected,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    ),
  );
}

class _SleepBarPainter extends CustomPainter {
  const _SleepBarPainter({
    required this.values,
    required this.labels,
    required this.dates,
    required this.selected,
    required this.dark,
  });
  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;
  final int? selected;
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
            ..color = _SleepDetailScreenState._purple.withValues(alpha: .2)
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
      final barHeight = values[index] / maxY * height;
      final barTop = top + height - barHeight;
      final label =
          '${DateFormat('MMM d').format(dates[index])}\n${_durationLabel(values[index])}';
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

  String _durationLabel(double hours) {
    final totalMinutes = (hours * 60).round();
    if (totalMinutes <= 0) return 'No sleep recorded';
    final wholeHours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (wholeHours == 0) return '$minutes min';
    if (minutes == 0) return '$wholeHours h';
    return '$wholeHours h $minutes min';
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
      !listEquals(oldDelegate.values, values) ||
      !listEquals(oldDelegate.labels, labels) ||
      !listEquals(oldDelegate.dates, dates) ||
      oldDelegate.selected != selected ||
      oldDelegate.dark != dark;
}
