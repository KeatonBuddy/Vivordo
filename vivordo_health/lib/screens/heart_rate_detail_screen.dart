import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/src/utils/smooth_chart_path.dart';

class HeartRateDetailScreen extends StatefulWidget {
  const HeartRateDetailScreen({super.key});

  @override
  State<HeartRateDetailScreen> createState() => _HeartRateDetailScreenState();
}

class _HeartRateDetailScreenState extends State<HeartRateDetailScreen> {
  static const red = Color(0xFFFF3B4E);
  static const purple = Color(0xFF5B42F3);
  int rangeIndex = 1;

  int get rangeDays => switch (rangeIndex) {
    0 => 1,
    1 => 7,
    _ => 30,
  };
  String get rangeName => switch (rangeIndex) {
    0 => 'Daily',
    1 => 'Weekly',
    _ => 'Monthly',
  };

  String keyFor(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Stream<QuerySnapshot<Map<String, dynamic>>> get stream {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    final now = DateTime.now();
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: keyFor(
            now.subtract(const Duration(days: 59)),
          ),
        )
        .where(FieldPath.documentId, isLessThanOrEqualTo: keyFor(now))
        .orderBy(FieldPath.documentId)
        .snapshots();
  }

  List<_HeartDay> allDays(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    return (snapshot?.docs ?? const []).map((doc) {
      final data = doc.data();
      final scan = data['heart_rate_scan'] as Map?;
      final health = data['heart_rate'] as Map?;
      final date = DateTime.parse(doc.id);
      final readings = <_HeartReading>[];

      void addEntries(Map? metric) {
        if (metric?['entries'] is! List) return;
        for (final entry in metric!['entries'] as List) {
          if (entry is Map && entry['bpm'] is num) {
            readings.add(
              _HeartReading(
                (entry['bpm'] as num).toDouble(),
                _entryTime(entry['timestamp'], date),
              ),
            );
          }
        }
      }

      // Camera scans are mirrored into `heart_rate`, so only merge HealthKit
      // entries when that map actually contains its own timestamped samples.
      addEntries(health);
      addEntries(scan);
      if (readings.isEmpty && scan?['avg'] is num) {
        readings.add(
          _HeartReading(
            (scan!['avg'] as num).toDouble(),
            _entryTime(scan['syncedAt'], date),
          ),
        );
      } else if (readings.isEmpty && health?['avg'] is num) {
        readings.add(
          _HeartReading(
            (health!['avg'] as num).toDouble(),
            _entryTime(health['syncedAt'], date),
          ),
        );
      }
      readings.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final resting = ((data['resting_heart_rate'] as Map?)?['avg'] as num?)
          ?.toDouble();
      return _HeartDay(date, readings, resting);
    }).toList();
  }

  DateTime _entryTime(Object? raw, DateTime fallbackDate) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? fallbackDate;
    return fallbackDate;
  }

  List<_HeartDay> currentDays(List<_HeartDay> all) {
    final byKey = {for (final day in all) keyFor(day.date): day};
    final today = DateUtils.dateOnly(DateTime.now());
    return List.generate(rangeDays, (index) {
      final date = today.subtract(Duration(days: rangeDays - index - 1));
      return byKey[keyFor(date)] ?? _HeartDay(date, const [], null);
    });
  }

  List<_HeartDay> previousDays(List<_HeartDay> all) {
    final end = DateUtils.dateOnly(
      DateTime.now(),
    ).subtract(Duration(days: rangeDays));
    final start = end.subtract(Duration(days: rangeDays));
    return all
        .where((day) => !day.date.isBefore(start) && day.date.isBefore(end))
        .toList();
  }

  double? average(Iterable<double> values) {
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: purple),
        ),
        title: const Text(
          'Heart Rate',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = allDays(snapshot.data);
          return content(currentDays(all), previousDays(all));
        },
      ),
    );
  }

  Widget content(List<_HeartDay> days, List<_HeartDay> previous) {
    final entries = days.expand((day) => day.readings).toList();
    final readings = entries.map((entry) => entry.bpm).toList();
    final resting = days.map((day) => day.resting).whereType<double>().toList();
    final prior = previous
        .map((day) => day.resting)
        .whereType<double>()
        .toList();
    final avg = average(readings);
    final restingAvg = average(resting);
    final priorAvg = average(prior);
    final change = restingAvg == null || priorAvg == null
        ? null
        : (restingAvg - priorAvg).round();
    final low = readings.isEmpty ? null : readings.reduce(math.min).round();
    final high = readings.isEmpty ? null : readings.reduce(math.max).round();
    final dailyValues = days
        .map(
          (day) =>
              average(day.readings.map((entry) => entry.bpm)) ??
              day.resting ??
              0,
        )
        .toList();

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
          rangeSelector(),
          const SizedBox(height: 18),
          summary(avg, restingAvg, change, low, high),
          section('$rangeName trend'),
          chart(days, entries, dailyValues, restingAvg),
          section('Heart rate zones'),
          zones(readings),
          section('Insight'),
          insight(change, restingAvg),
        ],
      ),
    );
  }

  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Text(
      title,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
    ),
  );

  Widget rangeSelector() {
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
          final selected = index == rangeIndex;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => rangeIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? purple : Colors.transparent,
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

  Widget summary(
    double? avg,
    double? resting,
    int? change,
    int? low,
    int? high,
  ) {
    final avgText = avg?.round().toString() ?? '--';
    return card(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bubble(Icons.favorite_border_rounded, red),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AVERAGE HEART RATE',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: avgText,
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const TextSpan(
                              text: ' bpm',
                              style: TextStyle(fontSize: 21),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        style: TextStyle(
                          color: context.vivordoColors.textPrimary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    Text(
                      resting == null
                          ? 'No resting average available'
                          : 'Resting average ${resting.round()} bpm',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    if (change != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${change <= 0 ? '↓' : '↑'} ${change.abs()} bpm vs previous period',
                        style: TextStyle(
                          color: change <= 0 ? const Color(0xFF20B26B) : red,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              stat('Low', low?.toString() ?? '--'),
              divider(),
              stat('Average', avgText),
              divider(),
              stat('High', high?.toString() ?? '--'),
            ],
          ),
        ],
      ),
    );
  }

  Widget stat(String label, String value) => Expanded(
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(color: context.vivordoColors.textSecondary),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: red,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget divider() =>
      Container(width: 1, height: 44, color: context.vivordoColors.border);

  Widget chart(
    List<_HeartDay> days,
    List<_HeartReading> entries,
    List<double> dailyValues,
    double? resting,
  ) {
    final isDay = rangeIndex == 0;
    final values = isDay
        ? entries.map((entry) => entry.bpm).toList()
        : dailyValues;
    final dates = isDay
        ? entries.map((entry) => entry.timestamp).toList()
        : days.map((day) => day.date).toList();
    final labels = isDay
        ? dates.map((date) => DateFormat('h:mm a').format(date)).toList()
        : days
              .map(
                (day) => rangeIndex == 2
                    ? DateFormat('M/d').format(day.date)
                    : DateFormat('E').format(day.date),
              )
              .toList();
    return card(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
      child: SizedBox(
        height: 245,
        child: _HeartChart(
          values: values,
          labels: labels,
          dates: dates,
          resting: resting,
          showTime: isDay,
        ),
      ),
    );
  }

  Widget zones(List<double> readings) {
    final counts = [
      readings.where((value) => value < 70).length,
      readings.where((value) => value >= 70 && value < 100).length,
      readings.where((value) => value >= 100).length,
    ];
    final total = math.max(1, readings.length);
    return card(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        children: [
          zone('Resting', 'Below 70 bpm', counts[0], total),
          Divider(height: 1, color: context.vivordoColors.border),
          zone('Elevated', '70–99 bpm', counts[1], total),
          Divider(height: 1, color: context.vivordoColors.border),
          zone('Active', '100+ bpm', counts[2], total),
        ],
      ),
    );
  }

  Widget zone(String title, String range, int count, int total) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        SizedBox(
          width: 105,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16)),
              Text(
                range,
                style: TextStyle(color: context.vivordoColors.textSecondary),
              ),
            ],
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: count / total,
              minHeight: 9,
              color: red.withValues(alpha: .7),
              backgroundColor: context.vivordoColors.cardMuted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 62,
          child: Text(
            '$count reading${count == 1 ? '' : 's'}',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Widget insight(int? change, double? resting) {
    final text = resting == null
        ? 'Complete a heart scan to begin building your heart rate trend.'
        : change == null
        ? 'Your resting heart rate averaged ${resting.round()} bpm.'
        : change <= 0
        ? 'Your resting heart rate improved by ${change.abs()} bpm.'
        : 'Your resting heart rate increased by $change bpm.';
    return card(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          bubble(Icons.monitor_heart_outlined, const Color(0xFF20B26B)),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Widget card({required Widget child, required EdgeInsets padding}) =>
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

  Widget bubble(IconData icon, Color color) => Container(
    width: 54,
    height: 54,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color, size: 29),
  );
}

class _HeartDay {
  const _HeartDay(this.date, this.readings, this.resting);
  final DateTime date;
  final List<_HeartReading> readings;
  final double? resting;
}

class _HeartReading {
  const _HeartReading(this.bpm, this.timestamp);
  final double bpm;
  final DateTime timestamp;
}

class _HeartChart extends StatefulWidget {
  const _HeartChart({
    required this.values,
    required this.labels,
    required this.dates,
    required this.resting,
    required this.showTime,
  });
  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;
  final double? resting;
  final bool showTime;

  @override
  State<_HeartChart> createState() => _HeartChartState();
}

class _HeartChartState extends State<_HeartChart> {
  int? selected;

  void select(double x, double width) {
    if (widget.values.isEmpty) return;
    const left = 38.0;
    final index = widget.values.length == 1
        ? 0
        : (((x - left) / (width - left)) * (widget.values.length - 1))
              .round()
              .clamp(0, widget.values.length - 1);
    if (selected != index) setState(() => selected = index);
  }

  @override
  void didUpdateWidget(covariant _HeartChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.values, oldWidget.values)) selected = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (event) =>
          select(event.localPosition.dx, constraints.maxWidth),
      onHorizontalDragUpdate: (event) =>
          select(event.localPosition.dx, constraints.maxWidth),
      child: CustomPaint(
        size: Size.infinite,
        painter: _HeartChartPainter(
          values: widget.values,
          labels: widget.labels,
          dates: widget.dates,
          resting: widget.resting,
          showTime: widget.showTime,
          selected: selected,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    ),
  );
}

class _HeartChartPainter extends CustomPainter {
  const _HeartChartPainter({
    required this.values,
    required this.labels,
    required this.dates,
    required this.resting,
    required this.showTime,
    required this.selected,
    required this.dark,
  });
  final List<double> values;
  final List<String> labels;
  final List<DateTime> dates;
  final double? resting;
  final bool showTime;
  final int? selected;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 38.0;
    const bottom = 25.0;
    final height = size.height - bottom;
    final width = size.width - left;
    final maximum = math.max(
      120.0,
      values.isEmpty ? 0 : values.reduce(math.max) * 1.15,
    );
    final grid = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = height * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      text(canvas, '${(maximum * (1 - i / 4)).round()}', Offset(0, y - 6), 10);
    }
    if (values.isEmpty) return;
    final points = List.generate(values.length, (i) {
      final x = values.length == 1
          ? left + width / 2
          : left + width * i / (values.length - 1);
      return Offset(x, height * (1 - (values[i] / maximum).clamp(0.0, 1.0)));
    });
    if (resting != null) {
      final y = height * (1 - resting! / maximum);
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.grey
          ..strokeWidth = 1.2,
      );
    }
    final path = smoothChartPath(points);
    final fill = Path.from(path)
      ..lineTo(points.last.dx, height)
      ..lineTo(points.first.dx, height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, height), [
          const Color(0xFFFF3B4E).withValues(alpha: .2),
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
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        points[i],
        3.5,
        Paint()..color = const Color(0xFFFF3B4E),
      );
      if (values.length <= 10 || i % 5 == 0 || i == values.length - 1) {
        centerText(canvas, labels[i], Offset(points[i].dx, height + 7), 9);
      }
    }
    final index = selected;
    if (index != null && index < points.length) {
      final point = points[index];
      canvas.drawCircle(
        point,
        9,
        Paint()..color = const Color(0xFFFF3B4E).withValues(alpha: .2),
      );
      final label = showTime
          ? '${DateFormat('h:mm a').format(dates[index])}\n${values[index].round()} bpm'
          : '${DateFormat('MMM d').format(dates[index])}\n${values[index].round()} bpm';
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

  void text(Canvas canvas, String value, Offset offset, double size) {
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

  void centerText(Canvas canvas, String value, Offset offset, double size) {
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
  bool shouldRepaint(covariant _HeartChartPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values) ||
      selected != oldDelegate.selected ||
      resting != oldDelegate.resting ||
      dark != oldDelegate.dark;
}
