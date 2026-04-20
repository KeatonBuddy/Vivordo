import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vivordo_health/src/services/health_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen
//
// UI: dev branch verbatim — "Metrics" title, summary row, _buildChartCard,
//     _buildPatternCard, _AreaChart painter with smooth bezier + gradient.
//
// Data: hardcoded _weekData removed. Every chart is driven by a Firestore
//       stream on metrics_daily. HealthKit metrics are gated by the user's
//       per-metric consent (HealthService.consentStream).
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Color accentPurple = Color(0xFF7B6EF6);
  static const Color greenColor = Color(0xFF34C759);
  static const Color bgColor = Color(0xFFF2F2F7);
  static const Color cardWhite = Colors.white;
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color textGrey = Color(0xFF8E8E93);

  // 0 = last 1 day, 1 = last 7 days (default), 2 = last 30 days
  int _filterIndex = 1;
  static const _filterLabels = ['Day', 'Week', 'Month'];

  int get _daysBack => _filterIndex == 0 ? 1 : _filterIndex == 1 ? 7 : 30;

  // Cached streams — rebuilt when filter changes
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stressStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _moodStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _wellnessStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _heartRateStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stepsStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _sleepStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _hrvStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _bloodOxygenStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _calsStream;

  @override
  void initState() {
    super.initState();
    _rebuildStreams();
  }

  void _rebuildStreams() {
    _stressStream      = _metricStream('stress');
    _moodStream        = _metricStream('mood');
    _wellnessStream    = _metricStream('wellness');
    _heartRateStream   = _metricStream('heart_rate');
    _stepsStream       = _metricStream('steps');
    _sleepStream       = _metricStream('sleep');
    _hrvStream         = _metricStream('hrv');
    _bloodOxygenStream = _metricStream('blood_oxygen');
    _calsStream        = _metricStream('active_calories');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _metricStream(String type) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    final now = DateTime.now();
    final oldest = now.subtract(Duration(days: _daysBack - 1));
    final fmt = (DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return FirebaseFirestore.instance
        .collection('metrics_daily')
        .where('userId', isEqualTo: user.uid)
        .where('metricType', isEqualTo: type)
        .where('period', isGreaterThanOrEqualTo: fmt(oldest))
        .where('period', isLessThanOrEqualTo: fmt(now))
        .orderBy('period')
        .snapshots();
  }

  // ── Helpers to extract chart data from Firestore docs ──────────────────────

  List<double> _vals(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String field) =>
      docs.map((d) => (d[field] as num?)?.toDouble() ?? 0.0).toList();

  List<String> _dayLabels(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      docs.map((d) {
        final p = d['period'] as String? ?? '';
        if (p.length < 10) return '';
        final dt = DateTime.tryParse(p);
        if (dt == null) return '';
        const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return names[dt.weekday - 1];
      }).toList();

  double _avg(List<double> vals) =>
      vals.isEmpty ? 0 : vals.reduce((a, b) => a + b) / vals.length;

  String _trend(List<double> vals) {
    if (vals.length < 2) return '';
    final half = vals.length ~/ 2;
    final old = _avg(vals.sublist(0, half));
    final recent = _avg(vals.sublist(half));
    if (old == 0) return '';
    final pct = ((recent - old) / old * 100).round();
    return pct >= 0 ? '+$pct%' : '$pct%';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              // ── Title (from dev — unchanged)
              const Text(
                'Metrics',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your health trends',
                style: TextStyle(fontSize: 14, color: textGrey),
              ),
              const SizedBox(height: 16),

              // ── Time filter
              _buildFilter(),
              const SizedBox(height: 20),

              // ── Summary row: Avg Stress · Avg HRV · Avg Sleep ─────────────
              _buildLiveSummaryRow(),
              const SizedBox(height: 20),

              // ── Manual metrics (always visible) ───────────────────────────
              _liveChart(stream: _stressStream, title: 'Stress Levels',
                  color: accentPurple, field: 'avg', maxY: 100),
              const SizedBox(height: 16),
              _liveChart(stream: _moodStream, title: 'Mood',
                  color: const Color(0xFFF97316), field: 'avg', maxY: 100),
              const SizedBox(height: 16),
              _liveChart(stream: _wellnessStream, title: 'Wellness',
                  color: Colors.teal, field: 'avg', maxY: 100),
              const SizedBox(height: 16),

              // ── HealthKit metrics — consent-gated ─────────────────────────
              StreamBuilder<Map<String, bool>>(
                stream: HealthService().consentStream(),
                builder: (ctx, consentSnap) {
                  final consent = consentSnap.data ?? {};
                  final anyConsented = consent.values.any((v) => v);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (consent['heart_rate'] == true) ...[
                        _liveChart(stream: _heartRateStream,
                            title: 'Heart Rate (bpm)',
                            color: Colors.redAccent, field: 'avg', maxY: 200),
                        const SizedBox(height: 16),
                      ],
                      if (consent['steps'] == true) ...[
                        _liveChart(stream: _stepsStream,
                            title: 'Daily Steps',
                            color: Colors.blueAccent, field: 'sum', maxY: 20000),
                        const SizedBox(height: 16),
                      ],
                      if (consent['sleep'] == true) ...[
                        _liveChart(stream: _sleepStream,
                            title: 'Sleep (hours)',
                            color: const Color(0xFF8B5CF6), field: 'avg', maxY: 12),
                        const SizedBox(height: 16),
                      ],
                      if (consent['hrv'] == true) ...[
                        _liveChart(stream: _hrvStream,
                            title: 'HRV (ms)',
                            color: greenColor, field: 'avg', maxY: 120),
                        const SizedBox(height: 16),
                      ],
                      if (consent['blood_oxygen'] == true) ...[
                        _liveChart(stream: _bloodOxygenStream,
                            title: 'Blood Oxygen SpO₂ (%)',
                            color: const Color(0xFF06B6D4), field: 'avg', maxY: 100),
                        const SizedBox(height: 16),
                      ],
                      if (consent['active_calories'] == true) ...[
                        _liveChart(stream: _calsStream,
                            title: 'Active Calories (kcal)',
                            color: const Color(0xFFF97316), field: 'sum', maxY: 1000),
                        const SizedBox(height: 16),
                      ],
                      if (!anyConsented) _buildConnectCard(),
                    ],
                  );
                },
              ),

              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }

  // ── Time filter chips ──────────────────────────────────────────────────────

  Widget _buildFilter() {
    return Row(
      children: List.generate(_filterLabels.length, (i) {
        final active = _filterIndex == i;
        return Padding(
          padding: EdgeInsets.only(right: i < _filterLabels.length - 1 ? 8 : 0),
          child: GestureDetector(
            onTap: () => setState(() {
              _filterIndex = i;
              _rebuildStreams();
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: active ? accentPurple : cardWhite,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? accentPurple : const Color(0xFFE5E5EA),
                ),
              ),
              child: Text(
                _filterLabels[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : textGrey,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Live summary row (Avg Stress · Avg HRV · Avg Sleep) ───────────────────

  Widget _buildLiveSummaryRow() {
    return Row(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stressStream,
            builder: (_, s) {
              final vals = _vals(s.data?.docs ?? [], 'avg');
              return _buildStatCard(
                label: 'Avg Stress',
                value: vals.isEmpty ? '--' : _avg(vals).toInt().toString(),
                change: _trend(vals),
                trendUp: false,
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _hrvStream,
            builder: (_, s) {
              final vals = _vals(s.data?.docs ?? [], 'avg');
              return _buildStatCard(
                label: 'Avg HRV',
                value: vals.isEmpty ? '--' : '${_avg(vals).toInt()}ms',
                change: _trend(vals),
                trendUp: true,
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _sleepStream,
            builder: (_, s) {
              final vals = _vals(s.data?.docs ?? [], 'avg');
              return _buildStatCard(
                label: 'Avg Sleep',
                value: vals.isEmpty ? '--' : '${_avg(vals).toStringAsFixed(1)}h',
                change: _trend(vals),
                trendUp: true,
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Live chart — wraps _buildChartCard with a StreamBuilder ───────────────

  Widget _liveChart({
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    required String title,
    required Color color,
    required String field,
    required double maxY,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        final values = _vals(docs, field);
        final labels = _dayLabels(docs);

        if (values.isEmpty) {
          return _buildEmptyChartCard(title: title, color: color);
        }

        return _buildChartCard(
          title: title,
          color: color,
          values: values,
          maxY: maxY > 0 ? maxY : (values.reduce((a, b) => a > b ? a : b) * 1.2).clamp(1, double.infinity),
          labels: labels,
        );
      },
    );
  }

  // ── "Connect Apple Health" placeholder ────────────────────────────────────

  Widget _buildConnectCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: const Column(
        children: [
          Icon(Icons.health_and_safety_outlined, size: 36, color: Color(0xFF7B6EF6)),
          SizedBox(height: 12),
          Text(
            'Apple Health not connected',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textDark),
          ),
          SizedBox(height: 6),
          Text(
            'Go to Profile → Health Data Permissions to enable metrics.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: textGrey, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── Empty state for a chart with no data yet ──────────────────────────────

  Widget _buildEmptyChartCard({required String title, required Color color}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: textDark)),
              const SizedBox(height: 4),
              const Text('Awaiting sync from Apple Health…',
                  style: TextStyle(fontSize: 12, color: textGrey)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Shared UI widgets (from dev — unchanged) ──────────────────────────────

  Widget _buildStatCard({
    required String label,
    required String value,
    required String change,
    required bool trendUp,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              color: textGrey,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textDark,
            ),
          ),
          const SizedBox(height: 4),
          if (change.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  trendUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  size: 13,
                  color: greenColor,
                ),
                const SizedBox(width: 3),
                Text(
                  change,
                  style: const TextStyle(
                    fontSize: 10,
                    color: greenColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // _buildChartCard from dev — unchanged except labels param added
  Widget _buildChartCard({
    required String title,
    required Color color,
    required List<double> values,
    required double maxY,
    required List<String> labels,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textDark,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: _AreaChart(
              values: values,
              maxY: maxY,
              color: color,
              labels: labels,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AreaChart — from dev, unchanged
// ─────────────────────────────────────────────────────────────────────────────

class _AreaChart extends StatefulWidget {
  final List<double> values;
  final double maxY;
  final Color color;
  final List<String> labels;

  const _AreaChart({
    required this.values,
    required this.maxY,
    required this.color,
    required this.labels,
  });

  @override
  State<_AreaChart> createState() => _AreaChartState();
}

class _AreaChartState extends State<_AreaChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _animation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void didUpdateWidget(_AreaChart old) {
    super.didUpdateWidget(old);
    if (old.values != widget.values) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => CustomPaint(
        painter: _AreaChartPainter(
          values: widget.values,
          maxY: widget.maxY,
          color: widget.color,
          labels: widget.labels,
          progress: _animation.value,
        ),
        size: Size.infinite,
      ),
    );
  }
}

// _AreaChartPainter — from dev, unchanged
class _AreaChartPainter extends CustomPainter {
  final List<double> values;
  final double maxY;
  final Color color;
  final List<String> labels;
  final double progress;

  static const double labelHeight = 22;
  static const double leftPad = 36;

  _AreaChartPainter({
    required this.values,
    required this.maxY,
    required this.color,
    required this.labels,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chartH = size.height - labelHeight;
    final chartW = size.width - leftPad;

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFFEEEEF2)
      ..strokeWidth = 1;
    const gridLines = 4;
    for (int i = 0; i <= gridLines; i++) {
      final y = chartH * i / gridLines;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      final yVal = (maxY * (1 - i / gridLines)).round();
      final tp = TextPainter(
        text: TextSpan(
          text: '$yVal',
          style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 5));
    }

    if (values.isEmpty) return;

    final n = values.length;
    final List<Offset> pts = List.generate(n, (i) {
      final x = n == 1 ? leftPad + chartW / 2 : leftPad + chartW * i / (n - 1);
      final y = chartH * (1 - (values[i] / maxY).clamp(0, 1));
      return Offset(x, y);
    });

    final linePath = _smoothPath(pts);
    final pathMetrics = linePath.computeMetrics().toList();
    if (pathMetrics.isEmpty) return;
    final animatedLine =
        pathMetrics.first.extractPath(0, pathMetrics.first.length * progress);

    // Gradient fill
    final fillPath = Path.from(animatedLine)
      ..lineTo(pts.last.dx, chartH)
      ..lineTo(leftPad, chartH)
      ..close();
    final gradientPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, chartH),
        [color.withValues(alpha: 0.28), color.withValues(alpha: 0.0)],
      )
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, gradientPaint);

    // Stroke
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(animatedLine, linePaint);

    // X-axis labels
    if (labels.length == n) {
      final labelStyle = TextStyle(fontSize: 10, color: Colors.grey.shade500);
      for (int i = 0; i < n; i++) {
        final tp = TextPainter(
          text: TextSpan(text: labels[i], style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(pts[i].dx - tp.width / 2, chartH + 6));
      }
    }
  }

  Path _smoothPath(List<Offset> pts) {
    if (pts.length == 1) return Path()..moveTo(pts[0].dx, pts[0].dy);
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final cp1 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i].dy);
      final cp2 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i + 1].dy);
      path.cubicTo(
          cp1.dx, cp1.dy, cp2.dx, cp2.dy, pts[i + 1].dx, pts[i + 1].dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_AreaChartPainter old) => old.progress != progress;
}
