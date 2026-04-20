import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vivordo_health/src/services/health_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen
//
// UI structure: taken verbatim from dev branch.
// Data: hardcoded values replaced with real Firestore streams (metrics_daily).
// HealthKit metrics (steps, heart_rate, sleep, hrv, blood_oxygen,
// active_calories) are gated behind the user's per-metric consent stored in
// Firestore via HealthService. Manual metrics (stress, mood, wellness) are
// always visible.
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTimeFilter = 1; // 0 = Daily, 1 = Weekly, 2 = Monthly
  static const Color primaryPurple = Color(0xFF7B6EF6);
  static const Color bgPurple = Color(0xFFFBFAFF);

  // ── Cached streams — rebuilt when filter changes ───────────────────────────
  late Stream<QuerySnapshot<Map<String, dynamic>>> _heartRateStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stepsStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _sleepStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stressStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _moodStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _wellnessStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _hrvStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _bloodOxygenStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _activeCaloriesStream;

  @override
  void initState() {
    super.initState();
    _refreshStreams();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  int get _daysBack =>
      _selectedTimeFilter == 0 ? 1 : _selectedTimeFilter == 1 ? 7 : 30;

  List<String> get _periods {
    final now = DateTime.now();
    return List.generate(_daysBack, (i) {
      final d = now.subtract(Duration(days: i));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });
  }

  void _refreshStreams() {
    _heartRateStream = _metricStream('heart_rate');
    _stepsStream = _metricStream('steps');
    _sleepStream = _metricStream('sleep');
    _stressStream = _metricStream('stress');
    _moodStream = _metricStream('mood');
    _wellnessStream = _metricStream('wellness');
    _hrvStream = _metricStream('hrv');
    _bloodOxygenStream = _metricStream('blood_oxygen');
    _activeCaloriesStream = _metricStream('active_calories');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _metricStream(String metricType) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    final periods = _periods;
    return FirebaseFirestore.instance
        .collection('metrics_daily')
        .where('userId', isEqualTo: user.uid)
        .where('metricType', isEqualTo: metricType)
        .where('period', isGreaterThanOrEqualTo: periods.last)
        .where('period', isLessThanOrEqualTo: periods.first)
        .orderBy('period', descending: false)
        .snapshots();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgPurple,
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildSyncCard(),
                      const SizedBox(height: 20),

                      // ── Manual metrics (always shown) ─────────────────────
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _stressStream,
                        builder: (ctx, snap) => _buildStressCard(snap.data?.docs),
                      ),
                      const SizedBox(height: 16),

                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _moodStream,
                        builder: (ctx, snap) => _buildMoodCard(snap.data?.docs),
                      ),
                      const SizedBox(height: 16),

                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _wellnessStream,
                        builder: (ctx, snap) => _buildWellnessCard(snap.data?.docs),
                      ),
                      const SizedBox(height: 16),

                      // ── HealthKit metrics — gated by consent ──────────────
                      StreamBuilder<Map<String, bool>>(
                        stream: HealthService().consentStream(),
                        builder: (ctx, consentSnap) {
                          final consent = consentSnap.data ?? {};
                          final anyConsented = consent.values.any((v) => v);

                          return Column(
                            children: [
                              if (consent['heart_rate'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _heartRateStream,
                                  builder: (ctx, snap) =>
                                      _buildHeartRateCard(snap.data?.docs),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (consent['steps'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _stepsStream,
                                  builder: (ctx, snap) =>
                                      _buildStepsCard(snap.data?.docs),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (consent['sleep'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _sleepStream,
                                  builder: (ctx, snap) =>
                                      _buildSleepCard(snap.data?.docs),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (consent['hrv'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _hrvStream,
                                  builder: (ctx, snap) =>
                                      _buildHrvCard(snap.data?.docs),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (consent['blood_oxygen'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _bloodOxygenStream,
                                  builder: (ctx, snap) =>
                                      _buildBloodOxygenCard(snap.data?.docs),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (consent['active_calories'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _activeCaloriesStream,
                                  builder: (ctx, snap) =>
                                      _buildActiveCaloriesCard(snap.data?.docs),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (!anyConsented) _buildConnectHealthPrompt(),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header (from dev — unchanged) ─────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
      decoration: const BoxDecoration(
        color: primaryPurple,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Health Dashboard',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                _filterButton('Daily', 0),
                _filterButton('Weekly', 1),
                _filterButton('Monthly', 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton(String text, int index) {
    final isActive = _selectedTimeFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedTimeFilter = index;
          _refreshStreams();
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? primaryPurple : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Sync card (from dev — shows HealthKit connection state) ───────────────

  Widget _buildSyncCard() {
    return StreamBuilder<Map<String, bool>>(
      stream: HealthService().consentStream(),
      builder: (ctx, snap) {
        final anyConnected = snap.data?.values.any((v) => v) ?? false;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: anyConnected ? Colors.green[50] : Colors.orange[50],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                anyConnected ? Icons.sync : Icons.sync_disabled,
                color: anyConnected ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 12),
              Text(
                anyConnected ? 'Apple Health Connected' : 'Apple Health Not Connected',
                style: TextStyle(
                  color: anyConnected ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── HealthKit card — prompt when nothing consented ────────────────────────

  Widget _buildConnectHealthPrompt() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primaryPurple.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primaryPurple.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.health_and_safety_outlined, color: primaryPurple),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connect Apple Health',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                SizedBox(height: 4),
                Text('Enable metrics in Profile → Health Data Permissions',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Manual metric cards ────────────────────────────────────────────────────

  Widget _buildStressCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = _extractValues(docs, 'avg');
    final latest = values.isNotEmpty ? values.last : 0.0;
    final label = latest < 30 ? 'Low' : latest < 60 ? 'Moderate' : 'High';

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.psychology_outlined,
            'Stress',
            '${latest.toInt()}',
            label,
            const Color(0xFF7B6EF6),
          ),
          const SizedBox(height: 20),
          if (values.isNotEmpty)
            _VisibilityAnimatedWidget(
              duration: const Duration(milliseconds: 1200),
              builder: (ctx, anim) => SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: AreaChartPainter(
                    values: values,
                    color: const Color(0xFF7B6EF6),
                    animationValue: anim,
                  ),
                ),
              ),
            )
          else
            _buildEmptyHint('No stress data — check in via mood'),
        ],
      ),
    );
  }

  Widget _buildMoodCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = _extractValues(docs, 'avg');
    final latest = values.isNotEmpty ? values.last : 0.0;
    final emoji = latest >= 80 ? '🤩' : latest >= 60 ? '😊' : latest >= 40 ? '😐' : latest >= 20 ? '😔' : '--';

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.mood,
            'Mood',
            emoji,
            '${latest.toInt()} / 100',
            Colors.orange,
          ),
          const SizedBox(height: 20),
          if (values.isNotEmpty)
            SizedBox(
              height: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _normalizedBars(values, Colors.orange),
              ),
            )
          else
            _buildEmptyHint('No mood data — check in via home'),
        ],
      ),
    );
  }

  Widget _buildWellnessCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = _extractValues(docs, 'avg');
    final latest = values.isNotEmpty ? values.last : 0.0;

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.spa_outlined,
            'Wellness',
            '${latest.toInt()}',
            '/ 100',
            Colors.teal,
          ),
          const SizedBox(height: 20),
          if (values.isNotEmpty)
            SizedBox(
              height: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _normalizedBars(values, Colors.teal),
              ),
            )
          else
            _buildEmptyHint('No wellness data yet'),
        ],
      ),
    );
  }

  // ── HealthKit card builders ────────────────────────────────────────────────

  Widget _buildHeartRateCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = _extractValues(docs, 'avg');
    final avg = values.isNotEmpty
        ? (values.reduce((a, b) => a + b) / values.length).round()
        : 0;

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.favorite_border,
            'Heart Rate',
            avg > 0 ? '$avg bpm' : '--',
            'Avg · Apple Health',
            Colors.redAccent,
          ),
          const SizedBox(height: 20),
          _VisibilityAnimatedWidget(
            duration: const Duration(milliseconds: 1500),
            builder: (ctx, anim) => SizedBox(
              height: 150,
              width: double.infinity,
              child: values.isNotEmpty
                  ? CustomPaint(
                      painter: LineChartPainter(
                        values: values,
                        color: Colors.redAccent,
                        animationValue: anim,
                      ),
                    )
                  : CustomPaint(painter: HeartRateLinePainter(anim)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepsCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = _extractValues(docs, 'sum');
    final total = values.fold(0.0, (a, b) => a + b).toInt();
    final latest = values.isNotEmpty ? values.last.toInt() : 0;
    final display = _selectedTimeFilter == 0
        ? (latest >= 1000 ? '${(latest / 1000).toStringAsFixed(1)}k' : '$latest')
        : (total >= 1000 ? '${(total / 1000).toStringAsFixed(1)}k' : '$total');

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.directions_walk,
            'Daily Steps',
            values.isNotEmpty ? display : '--',
            _selectedTimeFilter == 0 ? 'Today' : 'Total',
            Colors.blueAccent,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: values.isNotEmpty
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: _normalizedBars(values, Colors.blueAccent),
                  )
                : _buildEmptyHint('Awaiting Apple Health sync…'),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = _extractValues(docs, 'avg');
    final latest = values.isNotEmpty ? values.last : 0.0;
    final labels = _buildPeriodLabels(docs);

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.bedtime,
            'Sleep Duration',
            values.isNotEmpty ? '${latest.toStringAsFixed(1)}h' : '--',
            'Last Night · Apple Health',
            primaryPurple,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: values.isNotEmpty
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      values.length,
                      (i) => _buildBar(
                        values[i] / (values.reduce(max).clamp(0.1, double.infinity)),
                        primaryPurple,
                        label: labels.length > i ? labels[i] : '',
                      ),
                    ),
                  )
                : _buildEmptyHint('Awaiting Apple Health sync…'),
          ),
        ],
      ),
    );
  }

  Widget _buildHrvCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = _extractValues(docs, 'avg');
    final latest = values.isNotEmpty ? values.last : 0.0;
    final stressScore = docs != null && docs.isNotEmpty
        ? (docs.last['stressScore'] as num?)?.toInt()
        : null;

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.monitor_heart_outlined,
            'HRV',
            values.isNotEmpty ? '${latest.toStringAsFixed(0)} ms' : '--',
            stressScore != null ? 'Stress: $stressScore' : 'Apple Health',
            const Color(0xFF8B5CF6),
          ),
          const SizedBox(height: 20),
          if (values.isNotEmpty)
            _VisibilityAnimatedWidget(
              duration: const Duration(milliseconds: 1200),
              builder: (ctx, anim) => SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: AreaChartPainter(
                    values: values,
                    color: const Color(0xFF8B5CF6),
                    animationValue: anim,
                  ),
                ),
              ),
            )
          else
            _buildEmptyHint('Awaiting Apple Health sync…'),
        ],
      ),
    );
  }

  Widget _buildBloodOxygenCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = _extractValues(docs, 'avg');
    final latest = values.isNotEmpty ? values.last : 0.0;

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.water_drop_outlined,
            'Blood Oxygen',
            values.isNotEmpty ? '${latest.toStringAsFixed(1)}%' : '--',
            'SpO₂ · Apple Health',
            const Color(0xFF06B6D4),
          ),
          const SizedBox(height: 20),
          if (values.isNotEmpty)
            _VisibilityAnimatedWidget(
              duration: const Duration(milliseconds: 1200),
              builder: (ctx, anim) => SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: AreaChartPainter(
                    values: values,
                    color: const Color(0xFF06B6D4),
                    animationValue: anim,
                  ),
                ),
              ),
            )
          else
            _buildEmptyHint('Awaiting Apple Health sync…'),
        ],
      ),
    );
  }

  Widget _buildActiveCaloriesCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = _extractValues(docs, 'sum');
    final total = values.fold(0.0, (a, b) => a + b);
    final latest = values.isNotEmpty ? values.last : 0.0;

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.local_fire_department_outlined,
            'Active Calories',
            values.isNotEmpty ? '${latest.toInt()} kcal' : '--',
            _selectedTimeFilter == 0 ? 'Today' : '${total.toInt()} kcal total',
            const Color(0xFFF97316),
          ),
          const SizedBox(height: 20),
          if (values.isNotEmpty)
            _VisibilityAnimatedWidget(
              duration: const Duration(milliseconds: 1200),
              builder: (ctx, anim) => SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: AreaChartPainter(
                    values: values,
                    color: const Color(0xFFF97316),
                    animationValue: anim,
                  ),
                ),
              ),
            )
          else
            _buildEmptyHint('Awaiting Apple Health sync…'),
        ],
      ),
    );
  }

  // ── Shared UI helpers (from dev — kept exactly) ───────────────────────────

  Widget _buildBar(double normalizedHeight, Color color, {String? label}) {
    return _VisibilityAnimatedWidget(
      builder: (ctx, anim) => Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 25,
            height: 100 * normalizedHeight * anim,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ],
      ),
    );
  }

  Widget _buildCardBase({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: child,
    );
  }

  Widget _buildChartHeader(
    IconData icon,
    String title,
    String value,
    String valueSub,
    Color color,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(valueSub,
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyHint(String message) {
    return SizedBox(
      height: 60,
      child: Center(
        child: Text(message,
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ),
    );
  }

  // ── Data helpers ──────────────────────────────────────────────────────────

  List<double> _extractValues(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
    String field,
  ) {
    if (docs == null || docs.isEmpty) return [];
    return docs
        .map((d) => (d.data()[field] as num?)?.toDouble() ?? 0.0)
        .toList();
  }

  List<Widget> _normalizedBars(List<double> values, Color color) {
    final maxVal = values.reduce(max).clamp(0.001, double.infinity);
    return values
        .map((v) => _buildBar(v / maxVal, color))
        .toList();
  }

  List<String> _buildPeriodLabels(
      List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    if (docs == null) return [];
    return docs.map((d) {
      final period = d.data()['period'] as String? ?? '';
      if (period.length >= 10) {
        final month = period.substring(5, 7);
        final day = period.substring(8, 10);
        return '$month/$day';
      }
      return '';
    }).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers from dev branch — kept verbatim
// ─────────────────────────────────────────────────────────────────────────────

class _VisibilityAnimatedWidget extends StatefulWidget {
  final Widget Function(BuildContext, double) builder;
  final Duration duration;

  const _VisibilityAnimatedWidget({
    required this.builder,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<_VisibilityAnimatedWidget> createState() =>
      _VisibilityAnimatedWidgetState();
}

class _VisibilityAnimatedWidgetState extends State<_VisibilityAnimatedWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _hasBeenVisible = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: widget.duration);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: UniqueKey(),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.3 && !_hasBeenVisible) {
          if (mounted) {
            setState(() => _hasBeenVisible = true);
            _controller.forward();
          }
        }
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (ctx, _) => widget.builder(
          ctx,
          CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart).value,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────────────────────

/// ECG-style heartbeat line — from dev, shown as fallback when no real data
class HeartRateLinePainter extends CustomPainter {
  final double animationValue;
  HeartRateLinePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, size.height * 0.7);
    path.lineTo(size.width * 0.20, size.height * 0.7);
    path.lineTo(size.width * 0.25, size.height * 0.3);
    path.lineTo(size.width * 0.35, size.height * 0.9);
    path.lineTo(size.width * 0.45, size.height * 0.1);
    path.lineTo(size.width * 0.55, size.height * 0.8);
    path.lineTo(size.width * 0.60, size.height * 0.7);
    path.lineTo(size.width, size.height * 0.7);

    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * animationValue), paint);
    }
  }

  @override
  bool shouldRepaint(HeartRateLinePainter old) =>
      old.animationValue != animationValue;
}

/// Real data line chart — used when Firestore data is available
class LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double animationValue;

  LineChartPainter({
    required this.values,
    required this.color,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxVal = values.reduce(max);
    final minVal = values.reduce(min);
    final range = (maxVal - minVal).clamp(1.0, double.infinity);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : (i / (values.length - 1)) * size.width;
      final y = size.height -
          ((values[i] - minVal) / range) * size.height * 0.85 -
          size.height * 0.05;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }

    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * animationValue), linePaint);
    }
  }

  @override
  bool shouldRepaint(LineChartPainter old) =>
      old.animationValue != animationValue;
}

/// Filled area chart — for sleep, HRV, SpO₂, calories, stress
class AreaChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double animationValue;

  AreaChartPainter({
    required this.values,
    required this.color,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxVal = values.reduce(max).clamp(1.0, double.infinity);

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final linePath = Path();
    final fillPath = Path()..moveTo(0, size.height);

    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : (i / (values.length - 1)) * size.width;
      final y = size.height -
          (values[i] / maxVal) * size.height * 0.85 * animationValue;
      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(AreaChartPainter old) =>
      old.animationValue != animationValue;
}
