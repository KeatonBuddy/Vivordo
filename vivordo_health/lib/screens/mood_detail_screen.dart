import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/src/utils/smooth_chart_path.dart';

class MoodDetailScreen extends StatefulWidget {
  const MoodDetailScreen({super.key});

  @override
  State<MoodDetailScreen> createState() => _MoodDetailScreenState();
}

class _MoodDetailScreenState extends State<MoodDetailScreen> {
  static const _moodColor = Color(0xFFF59E0B);
  static const _purple = Color(0xFF5B42F3);
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

  Stream<QuerySnapshot<Map<String, dynamic>>> _moodStream() {
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

  List<_MoodDay> _rangeData(QuerySnapshot<Map<String, dynamic>>? snapshot) {
    final today = DateUtils.dateOnly(DateTime.now());
    if (_rangeIndex == 0) {
      final todayDoc = (snapshot?.docs ?? const [])
          .where((doc) => doc.id == _dayKey(today))
          .firstOrNull;
      final mood = todayDoc?.data()['mood'] as Map?;
      final entries = <_MoodDay>[];
      for (final raw in mood?['entries'] as List? ?? const []) {
        if (raw is! Map || raw['score'] is! num) continue;
        final timestamp = raw['timestamp'];
        final occurredAt = timestamp is Timestamp
            ? timestamp.toDate()
            : DateTime.tryParse(timestamp?.toString() ?? '') ?? today;
        entries.add(_MoodDay(occurredAt, (raw['score'] as num).round()));
      }
      entries.sort((a, b) => a.date.compareTo(b.date));
      if (entries.isNotEmpty) return entries;
      final average = (mood?['avg'] as num?)?.round();
      return average == null ? const [] : [_MoodDay(today, average)];
    }

    final values = <String, int>{};
    for (final doc in snapshot?.docs ?? const []) {
      values[doc.id] =
          ((doc.data()['mood'] as Map?)?['avg'] as num?)?.round() ?? 0;
    }
    return List.generate(_rangeDays, (index) {
      final date = today.subtract(Duration(days: _rangeDays - index - 1));
      return _MoodDay(date, values[_dayKey(date)] ?? 0);
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
          (doc) => ((doc.data()['mood'] as Map?)?['avg'] as num?)?.round() ?? 0,
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
          'Mood',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _moodStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = _rangeData(snapshot.data);
          final usualValues = _usualValues(snapshot.data);
          return _buildContent(data, usualValues);
        },
      ),
    );
  }

  Widget _buildContent(List<_MoodDay> data, List<int> usualValues) {
    final recorded = data.where((day) => day.moodScore > 0).toList();
    final total = recorded.fold<int>(0, (total, day) => total + day.moodScore);
    final average = recorded.isEmpty ? 0 : (total / recorded.length).round();
    final usual = usualValues.isEmpty
        ? null
        : usualValues.reduce((a, b) => a + b) / usualValues.length;
    final change = usual == null || usual == 0
        ? null
        : ((average - usual) / usual * 100).round();
    final best = recorded.isEmpty
        ? null
        : recorded.reduce((a, b) => a.moodScore >= b.moodScore ? a : b);
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
          _summaryCard(average, change, recorded.length),
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

  Widget _summaryCard(int average, int? change, int checkIns) {
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBubble(Icons.mood_rounded, _moodColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_rangeName.toUpperCase()} MOOD',
                      style: TextStyle(
                        color: context.vivordoColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      average == 0 ? 'No data' : _moodLabel(average),
                      style: TextStyle(
                        fontSize: average == 0 ? 30 : 42,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      average == 0
                          ? 'Log a mood to begin your trend'
                          : '$average/100 average · $checkIns ${checkIns == 1 ? 'check-in' : 'check-ins'}',
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
        ],
      ),
    );
  }

  Widget _chartCard(List<_MoodDay> data, double? usual) {
    const maxY = 100.0;
    return _card(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
      child: SizedBox(
        height: 245,
        child: _MoodChart(
          values: data.map((day) => day.moodScore.toDouble()).toList(),
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
      : _rangeIndex == 0
      ? DateFormat('h a').format(date)
      : DateFormat('E').format(date);

  Widget _breakdownCard(List<_MoodDay> data, _MoodDay? best) {
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
                      _rangeIndex == 0
                          ? DateFormat('h:mm a').format(ordered[i].date)
                          : DateFormat('EEEE, MMM d').format(ordered[i].date),
                    ),
                  ),
                  Text(
                    ordered[i].moodScore == 0
                        ? 'No entry'
                        : '${_moodEmoji(ordered[i].moodScore)}  ${_moodLabel(ordered[i].moodScore)}',
                    style: const TextStyle(
                      color: _moodColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (best?.date == ordered[i].date &&
                      ordered[i].moodScore > 0) ...[
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

  Widget _insightCard(_MoodDay? best) {
    final text = best == null || best.moodScore == 0
        ? 'Log how you feel to begin building your mood trend.'
        : 'You felt your best on ${DateFormat('EEEE').format(best.date)}.';
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

  String _moodLabel(int score) => switch (score) {
    >= 90 => 'Great',
    >= 65 => 'Good',
    >= 40 => 'Okay',
    >= 20 => 'Low',
    _ => 'Stressed',
  };

  String _moodEmoji(int score) => switch (score) {
    >= 90 => '😄',
    >= 65 => '🙂',
    >= 40 => '😐',
    >= 20 => '☹️',
    _ => '😣',
  };
}

class _MoodDay {
  const _MoodDay(this.date, this.moodScore);
  final DateTime date;
  final int moodScore;
}

class _MoodChart extends StatefulWidget {
  const _MoodChart({
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
  State<_MoodChart> createState() => _MoodChartState();
}

class _MoodChartState extends State<_MoodChart> {
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
  void didUpdateWidget(covariant _MoodChart oldWidget) {
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
        painter: _MoodChartPainter(
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

class _MoodChartPainter extends CustomPainter {
  const _MoodChartPainter({
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
          const Color(0xFFF59E0B).withValues(alpha: .24),
          const Color(0xFFF59E0B).withValues(alpha: 0),
        ]),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = const Color(0xFFF59E0B)
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
        Paint()..color = const Color(0xFFF59E0B),
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
        Paint()..color = const Color(0xFFF59E0B).withValues(alpha: .2),
      );
      final label =
          '${DateFormat('MMM d').format(dates[index])}\n${_moodName(values[index])} · ${values[index].round()}/100';
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

  static String _moodName(double score) => switch (score.round()) {
    >= 90 => 'Great',
    >= 65 => 'Good',
    >= 40 => 'Okay',
    >= 20 => 'Low',
    _ => 'Stressed',
  };

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
  bool shouldRepaint(covariant _MoodChartPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values) ||
      selected != oldDelegate.selected ||
      maxY != oldDelegate.maxY ||
      dark != oldDelegate.dark;
}
