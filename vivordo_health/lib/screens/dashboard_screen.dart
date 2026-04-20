import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// --- DATA ---

class _WeekPoint {
  final String day;
  final double stress;
  final double hrv;
  const _WeekPoint(this.day, this.stress, this.hrv);
}

const _weekData = [
  _WeekPoint('Mon', 65, 38),
  _WeekPoint('Tue', 72, 34),
  _WeekPoint('Wed', 58, 42),
  _WeekPoint('Thu', 45, 48),
  _WeekPoint('Fri', 52, 45),
  _WeekPoint('Sat', 30, 55),
  _WeekPoint('Sun', 42, 52),
];

// --- SCREEN ---

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const Color accentPurple = Color(0xFF7B6EF6);
  static const Color greenColor = Color(0xFF34C759);
  static const Color bgColor = Color(0xFFF2F2F7);
  static const Color cardWhite = Colors.white;
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color textGrey = Color(0xFF8E8E93);

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
                'Your weekly health trends',
                style: TextStyle(fontSize: 14, color: textGrey),
              ),
              const SizedBox(height: 24),
              _buildSummaryCards(),
              const SizedBox(height: 20),
              _buildChartCard(
                title: 'Stress Levels',
                color: accentPurple,
                values: _weekData.map((d) => d.stress).toList(),
                maxY: 100,
              ),
              const SizedBox(height: 16),
              _buildChartCard(
                title: 'Heart Rate Variability',
                color: greenColor,
                values: _weekData.map((d) => d.hrv).toList(),
                maxY: 70,
              ),
              const SizedBox(height: 28),
              const Text(
                'PATTERNS DETECTED',
                style: TextStyle(
                  color: textGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 12),
              _buildPatternCard(
                emoji: '📈',
                title: 'Stress peaks on Tuesdays',
                body: 'Your Tuesday meetings correlate with 30% higher stress. Consider blocking recovery time after.',
              ),
              const SizedBox(height: 10),
              _buildPatternCard(
                emoji: '😴',
                title: 'Weekend sleep recovery',
                body: 'You average 1.5h more sleep on weekends. Your HRV improves by 18% as a result.',
              ),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            label: 'Avg Stress',
            value: '52',
            change: '-8%',
            trendUp: false,
            flat: false,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            label: 'Avg HRV',
            value: '45ms',
            change: '+12%',
            trendUp: true,
            flat: false,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatCard(
            label: 'Avg Sleep',
            value: '7.1h',
            change: '+0.2h',
            trendUp: true,
            flat: true,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required String change,
    required bool trendUp,
    required bool flat,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                flat
                    ? Icons.remove_rounded
                    : trendUp
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
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

  Widget _buildChartCard({
    required String title,
    required Color color,
    required List<double> values,
    required double maxY,
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
              labels: _weekData.map((d) => d.day).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatternCard({
    required String emoji,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$emoji  $title',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12,
              color: textGrey,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// --- AREA CHART WIDGET ---

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
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
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

    // --- Grid lines ---
    final gridPaint = Paint()
      ..color = const Color(0xFFEEEEF2)
      ..strokeWidth = 1;
    const gridLines = 4;
    for (int i = 0; i <= gridLines; i++) {
      final y = chartH * i / gridLines;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width, y),
        gridPaint,
      );
      // Y-axis label
      final yVal = (maxY * (1 - i / gridLines)).round();
      final tp = TextPainter(
        text: TextSpan(
          text: '$yVal',
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey.shade400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 5));
    }

    if (values.isEmpty) return;

    // Compute pixel positions
    final n = values.length;
    List<Offset> pts = [];
    for (int i = 0; i < n; i++) {
      final x = leftPad + chartW * i / (n - 1);
      final y = chartH * (1 - values[i] / maxY);
      pts.add(Offset(x, y));
    }

    // Build smooth path (catmull-rom → bezier)
    Path linePath = _smoothPath(pts);

    // Animate: clip to progress
    final pathMetrics = linePath.computeMetrics().toList();
    if (pathMetrics.isEmpty) return;
    final totalLen = pathMetrics.first.length;
    final animatedLine = pathMetrics.first.extractPath(0, totalLen * progress);

    // Fill path
    final fillPath = Path.from(animatedLine)
      ..lineTo(pts.last.dx * progress + leftPad * (1 - progress), chartH)
      ..lineTo(leftPad, chartH)
      ..close();

    final gradientPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, chartH),
        [color.withOpacity(0.28), color.withOpacity(0.0)],
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
    final labelStyle = TextStyle(fontSize: 10, color: Colors.grey.shade500);
    for (int i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(pts[i].dx - tp.width / 2, chartH + 6),
      );
    }
  }

  Path _smoothPath(List<Offset> pts) {
    if (pts.length < 2) return Path()..moveTo(pts[0].dx, pts[0].dy);
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final cp1 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i].dy);
      final cp2 = Offset((pts[i].dx + pts[i + 1].dx) / 2, pts[i + 1].dy);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pts[i + 1].dx, pts[i + 1].dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_AreaChartPainter old) => old.progress != progress;
}
