import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/utils/smooth_chart_path.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

class StressDetailScreen extends StatefulWidget {
  const StressDetailScreen({super.key});

  @override
  State<StressDetailScreen> createState() => _StressDetailScreenState();
}

class _StressDetailScreenState extends State<StressDetailScreen> {
  static const _purple = Color(0xFF6B55F5);
  static const _green = Color(0xFF69D6A4);
  static const _yellow = Color(0xFFFFC53D);
  static const _red = Color(0xFFFF6B62);

  int _rangeIndex = 0;

  int get _rangeDays => switch (_rangeIndex) {
    0 => 7,
    _ => 30,
  };

  String get _rangeName => switch (_rangeIndex) {
    0 => 'Weekly stress',
    _ => 'Monthly stress',
  };

  String _key(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Stream<QuerySnapshot<Map<String, dynamic>>> _stream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    final today = DateUtils.dateOnly(DateTime.now());
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: _key(
            today.subtract(const Duration(days: 60)),
          ),
        )
        .where(FieldPath.documentId, isLessThanOrEqualTo: _key(today))
        .orderBy(FieldPath.documentId)
        .snapshots();
  }

  _StressDay _parse(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final stress = doc.data()['stress'] as Map?;
    final date = DateTime.tryParse(doc.id) ?? DateTime.now();
    final entries = <_StressReading>[];
    if (stress?['entries'] is List) {
      for (final raw in stress!['entries'] as List) {
        if (raw is! Map) continue;
        final score = (raw['score'] as num?)?.toDouble();
        if (score == null) continue;
        entries.add(_StressReading(score, _date(raw['timestamp']) ?? date));
      }
    }
    entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return _StressDay(
      date: date,
      current: (stress?['current'] as num?)?.toDouble(),
      average: (stress?['avg'] as num?)?.toDouble(),
      minimum: (stress?['min'] as num?)?.toDouble(),
      maximum: (stress?['max'] as num?)?.toDouble(),
      anchor: (stress?['anchor'] as num?)?.toDouble(),
      readingCount: (stress?['readings'] as num?)?.toInt() ?? entries.length,
      label: stress?['label']?.toString(),
      confidence: stress?['confidence']?.toString(),
      coverage: (stress?['coverage_pct'] as num?)?.toDouble(),
      justification: stress?['justification']?.toString(),
      computedAt: _date(stress?['computedAt']),
      drivers: _drivers(stress?['top_drivers']),
      entries: entries,
    );
  }

  DateTime? _date(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  List<_StressDriver> _drivers(Object? raw) {
    if (raw is! List) return const [];
    final result = <_StressDriver>[];
    for (final item in raw) {
      if (item is String) {
        result.add(_StressDriver(item, null, null));
        continue;
      }
      if (item is! Map) continue;
      String? firstString(List<String> keys) {
        for (final key in keys) {
          final value = item[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            return value.toString();
          }
        }
        return null;
      }

      double? firstNumber(List<String> keys) {
        for (final key in keys) {
          final value = item[key];
          if (value is num) return value.toDouble();
        }
        return null;
      }

      final name = firstString([
        'label',
        'name',
        'signal',
        'metric',
        'driver',
        'feature',
      ]);
      if (name == null) continue;
      result.add(
        _StressDriver(
          _title(name),
          firstNumber(['percentage', 'percent', 'weight', 'contribution']),
          firstString(['status', 'direction', 'effect', 'detail', 'reason']),
        ),
      );
    }
    return result;
  }

  String _title(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  List<_StressDay> _allDays(QuerySnapshot<Map<String, dynamic>>? snapshot) =>
      (snapshot?.docs ?? const []).map(_parse).toList();

  List<_StressDay> _currentDays(List<_StressDay> all) {
    final byDate = {for (final day in all) _key(day.date): day};
    final today = DateUtils.dateOnly(DateTime.now());
    return List.generate(_rangeDays, (index) {
      final date = today.subtract(Duration(days: _rangeDays - index - 1));
      return byDate[_key(date)] ?? _StressDay(date: date);
    });
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
          'Stress Score',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'How stress score works',
            onPressed: _showHowItWorks,
            icon: const Icon(Icons.info_outline_rounded, color: _purple),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = _allDays(snapshot.data);
          final byDate = {for (final day in all) _key(day.date): day};
          final todayDate = DateUtils.dateOnly(DateTime.now());
          final today = byDate[_key(todayDate)] ?? _StressDay(date: todayDate);
          final yesterday =
              byDate[_key(todayDate.subtract(const Duration(days: 1)))];
          return _content(today, yesterday, _currentDays(all));
        },
      ),
    );
  }

  Widget _content(
    _StressDay today,
    _StressDay? yesterday,
    List<_StressDay> periodDays,
  ) {
    final score = today.current ?? today.average;
    final previousScore = yesterday?.current ?? yesterday?.average;
    final change = score == null || previousScore == null
        ? null
        : score - previousScore;
    final chart = _chartData(periodDays);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _summary(today, score, change),
          const SizedBox(height: 16),
          _rangeSelector(),
          _section(_rangeName),
          _chartCard(chart),
          _section('Personalized to you'),
          _personalizationCard(),
        ],
      ),
    );
  }

  Widget _summary(_StressDay latest, double? score, double? change) {
    final band = _band(score);
    final color = _bandColor(score);
    final updated = latest.computedAt;
    final coverage = latest.coverage;

    return _card(
      padding: const EdgeInsets.all(20),
      borderColor: _purple.withValues(alpha: .45),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 330;
              final scoreSummary = _scoreSummary(score, band, color);
              final metadata = _scoreMetadata(
                updated,
                coverage,
                compact: compact,
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    scoreSummary,
                    const SizedBox(height: 16),
                    metadata,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: scoreSummary),
                  const SizedBox(width: 12),
                  Flexible(child: metadata),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _stressScale(score),
          if (change != null) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(
                  change <= 0 ? Icons.south_rounded : Icons.north_rounded,
                  color: change <= 0 ? _green : _red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${change.abs().round()} points ${change <= 0 ? 'lower' : 'higher'} than yesterday',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _scoreSummary(double? score, String band, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: score?.round().toString() ?? '--',
                style: const TextStyle(
                  fontSize: 54,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const TextSpan(
                text: ' /100',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _purple,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .18),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          band,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Lower means calmer',
        style: TextStyle(color: context.vivordoColors.textSecondary),
      ),
    ],
  );

  Widget _scoreMetadata(
    DateTime? updated,
    double? coverage, {
    required bool compact,
  }) => Column(
    crossAxisAlignment: compact
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end,
    children: [
      Text(
        updated == null
            ? 'Not updated yet'
            : 'Updated ${DateFormat('h:mm a').format(updated)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.vivordoColors.textSecondary),
      ),
      if (coverage != null) const SizedBox(height: 10),
      Wrap(
        alignment: compact ? WrapAlignment.start : WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (coverage != null)
            _pill(
              Icons.pie_chart_outline_rounded,
              '${coverage.round()}% coverage',
              _green,
              onTap: () => _showCoverageExplanation(coverage),
            ),
        ],
      ),
    ],
  );

  Widget _stressScale(double? score) => Column(
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final position = ((score ?? 0) / 100).clamp(0.0, 1.0);
          return SizedBox(
            height: 24,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Row(
                  children: [
                    Expanded(child: _scaleSegment(_green, left: true)),
                    const SizedBox(width: 2),
                    Expanded(child: _scaleSegment(_yellow)),
                    const SizedBox(width: 2),
                    Expanded(child: _scaleSegment(_red, right: true)),
                  ],
                ),
                Positioned(
                  left: (constraints.maxWidth - 22) * position,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _purple,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 5),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 4),
      const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Calm', style: TextStyle(color: _green)),
          Text('Moderate', style: TextStyle(color: _yellow)),
          Text('High', style: TextStyle(color: _red)),
        ],
      ),
    ],
  );

  Widget _scaleSegment(Color color, {bool left = false, bool right = false}) =>
      Container(
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.horizontal(
            left: left ? const Radius.circular(8) : Radius.zero,
            right: right ? const Radius.circular(8) : Radius.zero,
          ),
        ),
      );

  Widget _pill(
    IconData icon,
    String label,
    Color color, {
    VoidCallback? onTap,
  }) => Material(
    color: context.vivordoColors.cardMuted,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _rangeSelector() {
    const labels = ['Week', 'Month'];
    return Container(
      height: 52,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.vivordoColors.cardMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == _rangeIndex;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: () => setState(() => _rangeIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? _purple : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
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

  _StressChartData _chartData(List<_StressDay> days) {
    final present = days.where((day) => day.average != null).toList();
    return _StressChartData(
      values: present.map((day) => day.average!).toList(),
      dates: present.map((day) => day.date).toList(),
      labels: present
          .map(
            (day) => _rangeIndex == 0
                ? DateFormat('E').format(day.date)
                : DateFormat('M/d').format(day.date),
          )
          .toList(),
      isTime: false,
    );
  }

  Widget _chartCard(_StressChartData data) {
    final values = data.values;
    final average = _average(values);
    final low = values.isEmpty ? null : values.reduce(math.min);
    final high = values.isEmpty ? null : values.reduce(math.max);
    final count = values.length;
    return _card(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: Column(
        children: [
          SizedBox(
            height: 220,
            child: _StressChart(
              values: values,
              dates: data.dates,
              labels: data.labels,
              isTime: data.isTime,
              showDataPoints: _rangeIndex == 0,
            ),
          ),
          Divider(color: context.vivordoColors.border),
          Row(
            children: [
              _stat('Average', average),
              _divider(),
              _stat('Low', low),
              _divider(),
              _stat('High', high),
              _divider(),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$count',
                      style: const TextStyle(
                        color: _purple,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Days',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.vivordoColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (values.length <= 1) ...[
            const SizedBox(height: 14),
            Text(
              'More daily scores will build your trend over this period.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.vivordoColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, double? value) => Expanded(
    child: Column(
      children: [
        Text(
          value?.round().toString() ?? '--',
          style: const TextStyle(
            color: _purple,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: context.vivordoColors.textSecondary,
          ),
        ),
      ],
    ),
  );

  Widget _divider() =>
      Container(width: 1, height: 42, color: context.vivordoColors.border);

  Widget _personalizationCard() => _card(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconBubble(Icons.auto_awesome_rounded, _purple, size: 58),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                'Vivordo compares new readings with about 14 days of your own history. Mood feedback helps tune which signals predict your stress best.',
                style: TextStyle(
                  color: context.vivordoColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.sync_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Updates about every 10 minutes, or after new health data or a mood check-in.',
                style: TextStyle(
                  color: context.vivordoColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _showHowItWorks,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Learn about personalization',
                style: TextStyle(color: _purple, fontWeight: FontWeight.w800),
              ),
              Icon(Icons.chevron_right_rounded, color: _purple),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _iconBubble(IconData icon, Color color, {double size = 48}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: size * .52),
      );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 10),
    child: Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: _purple,
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    ),
  );

  Widget _card({
    required Widget child,
    required EdgeInsets padding,
    Color? borderColor,
  }) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: borderColor ?? context.vivordoColors.border),
      boxShadow: [
        BoxShadow(
          color: context.vivordoColors.shadow,
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );

  String _band(double? score) {
    if (score == null) return 'No data';
    if (score < 35) return 'Calm';
    if (score < 67) return 'Moderate';
    return 'High';
  }

  Color _bandColor(double? score) {
    if (score == null) return context.vivordoColors.textSecondary;
    if (score < 35) return _green;
    if (score < 67) return _yellow;
    return _red;
  }

  void _showCoverageExplanation(double coverage) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'What coverage means',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.pie_chart_outline_rounded,
                    color: _green,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${coverage.round()}% of relevant signals available',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Coverage indicates how much of the relevant signal set—such as mood, sleep, heart and recovery readings, activity, and breathing data—was available when Vivordo calculated today’s score.',
                style: TextStyle(
                  color: context.vivordoColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'It measures data completeness, not accuracy. A lower percentage usually means some signals have not been recorded or synced yet. Your score can still be calculated from the information that is available, and coverage may improve as more data arrives throughout the day.',
                style: TextStyle(
                  color: context.vivordoColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHowItWorks() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How your stress score works',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Text(
                'Vivordo combines available signals such as mood, sleep, heart and recovery readings, activity, and breathing data. It compares those signals with your own recent baseline—not another person’s.',
                style: TextStyle(
                  color: context.vivordoColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Lower scores indicate a calmer state. Coverage explains how much relevant data was available. The score is a wellness insight and is not a medical diagnosis.',
                style: TextStyle(
                  color: context.vivordoColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StressDay {
  const _StressDay({
    required this.date,
    this.current,
    this.average,
    this.minimum,
    this.maximum,
    this.anchor,
    this.readingCount = 0,
    this.label,
    this.confidence,
    this.coverage,
    this.justification,
    this.computedAt,
    this.drivers = const [],
    this.entries = const [],
  });

  final DateTime date;
  final double? current;
  final double? average;
  final double? minimum;
  final double? maximum;
  final double? anchor;
  final int readingCount;
  final String? label;
  final String? confidence;
  final double? coverage;
  final String? justification;
  final DateTime? computedAt;
  final List<_StressDriver> drivers;
  final List<_StressReading> entries;
}

class _StressDriver {
  const _StressDriver(this.name, this.influence, this.detail);
  final String name;
  final double? influence;
  final String? detail;
}

class _StressReading {
  const _StressReading(this.score, this.timestamp);
  final double score;
  final DateTime timestamp;
}

class _StressChartData {
  const _StressChartData({
    required this.values,
    required this.dates,
    required this.labels,
    required this.isTime,
  });
  final List<double> values;
  final List<DateTime> dates;
  final List<String> labels;
  final bool isTime;
}

class _StressChart extends StatefulWidget {
  const _StressChart({
    required this.values,
    required this.dates,
    required this.labels,
    required this.isTime,
    required this.showDataPoints,
  });
  final List<double> values;
  final List<DateTime> dates;
  final List<String> labels;
  final bool isTime;
  final bool showDataPoints;

  @override
  State<_StressChart> createState() => _StressChartState();
}

class _StressChartState extends State<_StressChart> {
  int? selected;

  @override
  void didUpdateWidget(covariant _StressChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.values, oldWidget.values)) selected = null;
  }

  void _select(double x, double width) {
    if (widget.values.isEmpty) return;
    const left = 34.0;
    final index = widget.values.length == 1
        ? 0
        : (((x - left) / math.max(1, width - left)) *
                  (widget.values.length - 1))
              .round()
              .clamp(0, widget.values.length - 1);
    if (selected != index) setState(() => selected = index);
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
        painter: _StressChartPainter(
          values: widget.values,
          dates: widget.dates,
          labels: widget.labels,
          isTime: widget.isTime,
          showDataPoints: widget.showDataPoints,
          selected: selected,
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    ),
  );
}

class _StressChartPainter extends CustomPainter {
  const _StressChartPainter({
    required this.values,
    required this.dates,
    required this.labels,
    required this.isTime,
    required this.showDataPoints,
    required this.selected,
    required this.dark,
  });
  final List<double> values;
  final List<DateTime> dates;
  final List<String> labels;
  final bool isTime;
  final bool showDataPoints;
  final int? selected;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const bottom = 28.0;
    final chartHeight = size.height - bottom;
    final chartWidth = size.width - left;
    final grid = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: .08)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = chartHeight * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
      _text(canvas, '${100 - i * 25}', Offset(0, y - 6), 9);
    }
    if (values.isEmpty) {
      _centerMessage(canvas, size, 'No stress readings for this period');
      return;
    }
    final points = List.generate(values.length, (index) {
      final x = values.length == 1
          ? left + chartWidth / 2
          : left + chartWidth * index / (values.length - 1);
      final y = chartHeight * (1 - (values[index] / 100).clamp(0.0, 1.0));
      return Offset(x, y);
    });
    final path = smoothChartPath(points);
    if (points.length > 1) {
      final fill = Path.from(path)
        ..lineTo(points.last.dx, chartHeight)
        ..lineTo(points.first.dx, chartHeight)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, chartHeight), [
            const Color(0xFF6B55F5).withValues(alpha: .35),
            const Color(0xFF6B55F5).withValues(alpha: 0),
          ]),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF6B55F5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    for (var index = 0; index < points.length; index++) {
      if (showDataPoints) {
        canvas.drawCircle(points[index], 6, Paint()..color = Colors.white);
        canvas.drawCircle(
          points[index],
          4,
          Paint()..color = const Color(0xFF6B55F5),
        );
      }
      if (values.length <= 8 || index % 4 == 0 || index == values.length - 1) {
        _centerText(
          canvas,
          labels[index],
          Offset(points[index].dx, chartHeight + 8),
          9,
        );
      }
    }
    final index = selected;
    if (index == null || index >= points.length) return;
    final point = points[index];
    canvas.drawLine(
      Offset(point.dx, 0),
      Offset(point.dx, chartHeight),
      Paint()
        ..color = const Color(0xFF6B55F5).withValues(alpha: .35)
        ..strokeWidth = 1,
    );
    final label = isTime
        ? '${DateFormat('h:mm a').format(dates[index])}\n${values[index].round()}'
        : '${DateFormat('MMM d').format(dates[index])}\n${values[index].round()}';
    _tooltip(canvas, size, point, label, chartHeight);
  }

  void _tooltip(
    Canvas canvas,
    Size size,
    Offset point,
    String label,
    double chartHeight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final width = painter.width + 18;
    final height = painter.height + 12;
    final x = (point.dx - width / 2).clamp(34.0, size.width - width);
    final y = (point.dy - height - 12).clamp(0.0, chartHeight - height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0xFF6B55F5),
    );
    painter.paint(canvas, Offset(x + 9, y + 6));
  }

  void _centerMessage(Canvas canvas, Size size, String value) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: dark ? Colors.white54 : Colors.black45,
          fontSize: 13,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: size.width - 50);
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  void _text(Canvas canvas, String value, Offset offset, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: dark ? Colors.white54 : Colors.black45,
          fontSize: fontSize,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  void _centerText(
    Canvas canvas,
    String value,
    Offset offset,
    double fontSize,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: dark ? Colors.white54 : Colors.black45,
          fontSize: fontSize,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(offset.dx - painter.width / 2, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _StressChartPainter oldDelegate) =>
      !listEquals(values, oldDelegate.values) ||
      selected != oldDelegate.selected ||
      showDataPoints != oldDelegate.showDataPoints ||
      dark != oldDelegate.dark;
}
