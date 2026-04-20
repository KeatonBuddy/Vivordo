import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vivordo_health/src/services/health_service.dart';
import 'dart:math';
import 'dart:ui';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTimeFilter = 1; // 0=Daily, 1=Weekly, 2=Monthly
  static const Color primaryPurple = Color(0xFF7B6EF6);
  static const Color bgPurple = Color(0xFFFBFAFF);

  // ── Cached streams ────────────────────────────────────────────────
  // Streams are created once (or when the filter changes) rather than on
  // every build() call. Recreating streams on every build causes the
  // Firestore SDK to open and close listeners rapidly, which can push the
  // WatchChangeAggregator into an unexpected state.
  late Stream<QuerySnapshot<Map<String, dynamic>>> _heartRateStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stepsStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _sleepStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _moodStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stressStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _wellnessStream;
  // HealthKit-sourced streams (empty when user hasn't connected Apple Health)
  late Stream<QuerySnapshot<Map<String, dynamic>>> _hrvStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _bloodOxygenStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _activeCaloriesStream;

  @override
  void initState() {
    super.initState();
    _refreshStreams();
  }

  void _refreshStreams() {
    _heartRateStream      = _metricStream('heart_rate');
    _stepsStream          = _metricStream('steps');
    _sleepStream          = _metricStream('sleep');
    _moodStream           = _metricStream('mood');
    _stressStream         = _metricStream('stress');
    _wellnessStream       = _metricStream('wellness');
    _hrvStream            = _metricStream('hrv');
    _bloodOxygenStream    = _metricStream('blood_oxygen');
    _activeCaloriesStream = _metricStream('active_calories');
  }

  // Returns how many days back to query based on filter
  int get _daysBack => _selectedTimeFilter == 0 ? 1 : _selectedTimeFilter == 1 ? 7 : 30;

  // Returns list of period strings (YYYY-MM-DD) for the selected range
  List<String> get _periods {
    final now = DateTime.now();
    return List.generate(_daysBack, (i) {
      final d = now.subtract(Duration(days: i));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });
  }

  // Fetches all docs for a given metricType within the selected time range
  Stream<QuerySnapshot<Map<String, dynamic>>> _metricStream(String metricType) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();

    final periods = _periods;
    final oldest = periods.last;
    final newest = periods.first;

    return FirebaseFirestore.instance
        .collection('metrics_daily')
        .where('userId', isEqualTo: user.uid)
        .where('metricType', isEqualTo: metricType)
        .where('period', isGreaterThanOrEqualTo: oldest)
        .where('period', isLessThanOrEqualTo: newest)
        .orderBy('period', descending: false)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

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

                      // ── Manual metrics (always visible) ──────────────────
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _stressStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) return _buildStreamError('stress', snapshot.error);
                          final docs = snapshot.data?.docs ?? [];
                          return _buildStressCard(docs.isEmpty ? null : docs);
                        },
                      ),
                      const SizedBox(height: 16),

                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _moodStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) return _buildStreamError('mood', snapshot.error);
                          final docs = snapshot.data?.docs ?? [];
                          return _buildMoodCard(docs.isEmpty ? null : docs);
                        },
                      ),
                      const SizedBox(height: 16),

                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _wellnessStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) return _buildStreamError('wellness', snapshot.error);
                          final docs = snapshot.data?.docs ?? [];
                          return _buildWellnessCard(docs.isEmpty ? null : docs);
                        },
                      ),
                      const SizedBox(height: 16),

                      // ── HealthKit metrics — driven by user consent ────────────
                      StreamBuilder<Map<String, bool>>(
                        stream: HealthService().consentStream(),
                        builder: (context, consentSnap) {
                          final consent = consentSnap.data ?? {};
                          return Column(
                            children: [
                              // Steps
                              if (consent['steps'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _stepsStream,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) return _buildStreamError('steps', snapshot.error);
                                    final docs = snapshot.data?.docs;
                                    if (docs == null) return _buildAwaitingSync('Steps');
                                    return _buildStepsCard(docs.isEmpty ? null : docs);
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              // Heart Rate
                              if (consent['heart_rate'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _heartRateStream,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) return _buildStreamError('heart_rate', snapshot.error);
                                    final docs = snapshot.data?.docs;
                                    if (docs == null) return _buildAwaitingSync('Heart Rate');
                                    return _buildHeartRateCard(docs.isEmpty ? null : docs);
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              // Sleep
                              if (consent['sleep'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _sleepStream,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) return _buildStreamError('sleep', snapshot.error);
                                    final docs = snapshot.data?.docs;
                                    if (docs == null) return _buildAwaitingSync('Sleep');
                                    return _buildSleepCard(docs.isEmpty ? null : docs);
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              // HRV
                              if (consent['hrv'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _hrvStream,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) return _buildStreamError('hrv', snapshot.error);
                                    final docs = snapshot.data?.docs;
                                    if (docs == null) return _buildAwaitingSync('HRV');
                                    return _buildHrvCard(docs.isEmpty ? null : docs);
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              // Blood Oxygen
                              if (consent['blood_oxygen'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _bloodOxygenStream,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) return _buildStreamError('blood_oxygen', snapshot.error);
                                    final docs = snapshot.data?.docs;
                                    if (docs == null) return _buildAwaitingSync('Blood Oxygen');
                                    return _buildBloodOxygenCard(docs.isEmpty ? null : docs);
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              // Active Calories
                              if (consent['active_calories'] == true) ...[
                                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                  stream: _activeCaloriesStream,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) return _buildStreamError('active_calories', snapshot.error);
                                    final docs = snapshot.data?.docs;
                                    if (docs == null) return _buildAwaitingSync('Active Calories');
                                    return _buildActiveCaloriesCard(docs.isEmpty ? null : docs);
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              // No HealthKit metrics consented yet
                              if (!consent.values.any((v) => v))
                                _buildConnectHealthPrompt(),
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

  // ── HEADER ────────────────────────────────────────────────────────

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
            "Health Dashboard",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                _filterButton("Daily", 0),
                _filterButton("Weekly", 1),
                _filterButton("Monthly", 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterButton(String text, int index) {
    bool isActive = _selectedTimeFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedTimeFilter = index;
          _refreshStreams(); // rebuild streams with the new date range
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

  // ── VH-58: HEART RATE — animated line chart ───────────────────────

  Widget _buildHeartRateCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = docs != null && docs.isNotEmpty
        ? docs.map((d) => (d.data()['avg'] as num?)?.toDouble() ?? 0.0).toList()
        : <double>[];

    final avg = values.isNotEmpty
        ? (values.reduce((a, b) => a + b) / values.length).round()
        : (_selectedTimeFilter == 0 ? 72 : 68);

    final labels = _buildXLabels(docs?.map((d) => d.data()['period'] as String? ?? '').toList() ?? []);

    return _buildCardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(Icons.favorite_border, "Heart Rate", "$avg bpm", "Avg", Colors.redAccent),
          const SizedBox(height: 8),
          _buildAxisLabels("bpm", labels),
          const SizedBox(height: 4),
          _VisibilityAnimatedWidget(
            duration: const Duration(milliseconds: 1500),
            builder: (context, animValue) {
              return SizedBox(
                height: 120,
                width: double.infinity,
                child: values.isEmpty
                    ? _buildEmptyState()
                    : CustomPaint(
                        painter: LineChartPainter(
                          values: values,
                          color: Colors.redAccent,
                          animationValue: animValue,
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── VH-58: STEPS — bar chart ──────────────────────────────────────

  Widget _buildStepsCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = docs != null && docs.isNotEmpty
        ? docs.map((d) => (d.data()['sum'] as num?)?.toDouble() ?? 0.0).toList()
        : <double>[];

    final total = values.isNotEmpty
        ? values.reduce((a, b) => a + b).round()
        : (_selectedTimeFilter == 0 ? 9540 : 64200);

    final labels = _buildXLabels(docs?.map((d) => d.data()['period'] as String? ?? '').toList() ?? []);

    return _buildCardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(Icons.directions_walk, "Daily Steps", _formatNumber(total), "Total", Colors.blueAccent),
          const SizedBox(height: 8),
          _buildAxisLabels("steps", labels),
          const SizedBox(height: 4),
          SizedBox(
            height: 120,
            child: values.isEmpty
                ? _buildEmptyState()
                : _VisibilityAnimatedWidget(
                    builder: (context, animValue) {
                      final maxVal = values.reduce(max);
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: values.map((v) {
                          final h = maxVal > 0 ? (v / maxVal) * 100 * animValue : 0.0;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                width: _barWidth(values.length),
                                height: h,
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── VH-58: SLEEP — area chart ─────────────────────────────────────

  Widget _buildSleepCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = docs != null && docs.isNotEmpty
        ? docs.map((d) => (d.data()['avg'] as num?)?.toDouble() ?? 0.0).toList()
        : <double>[];

    final avg = values.isNotEmpty
        ? (values.reduce((a, b) => a + b) / values.length)
        : 7.9;

    final labels = _buildXLabels(docs?.map((d) => d.data()['period'] as String? ?? '').toList() ?? []);

    return _buildCardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(Icons.bedtime, "Sleep Duration", "${avg.toStringAsFixed(1)}h", "Avg", primaryPurple),
          const SizedBox(height: 8),
          _buildAxisLabels("hours", labels),
          const SizedBox(height: 4),
          _VisibilityAnimatedWidget(
            duration: const Duration(milliseconds: 1200),
            builder: (context, animValue) {
              return SizedBox(
                height: 120,
                width: double.infinity,
                child: values.isEmpty
                    ? _buildEmptyState()
                    : CustomPaint(
                        painter: AreaChartPainter(
                          values: values,
                          color: primaryPurple,
                          animationValue: animValue,
                        ),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── VH-58: MOOD — dot/score chart ────────────────────────────────

  Widget _buildMoodCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final entries = docs != null && docs.isNotEmpty
        ? docs.map((d) => {
              'score': (d.data()['avg'] as num?)?.toDouble() ?? 50.0,
              'label': d.data()['label'] as String? ?? '',
              'period': d.data()['period'] as String? ?? '',
            }).toList()
        : <Map<String, dynamic>>[];

    final avgScore = entries.isNotEmpty
        ? entries.map((e) => e['score'] as double).reduce((a, b) => a + b) / entries.length
        : 75.0;

    final moodLabel = _scoreToMoodLabel(avgScore);
    final labels = _buildXLabels(entries.map((e) => e['period'] as String).toList());

    return _buildCardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(Icons.psychology_outlined, "Mood", moodLabel, "Avg", const Color(0xFF8B5CF6)),
          const SizedBox(height: 8),
          _buildAxisLabels("score", labels),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: entries.isEmpty
                ? _buildEmptyState()
                : _VisibilityAnimatedWidget(
                    builder: (context, animValue) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: entries.map((e) {
                          final score = e['score'] as double;
                          final emoji = _scoreToEmoji(score);
                          final h = (score / 100) * 80 * animValue;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(emoji, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 4),
                              Container(
                                width: _barWidth(entries.length),
                                height: h,
                                decoration: BoxDecoration(
                                  color: _moodColor(score).withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── VH-58: STRESS — line chart ───────────────────────────────────

  Widget _buildStressCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = docs != null && docs.isNotEmpty
        ? docs.map((d) => (d.data()["avg"] as num?)?.toDouble() ?? 0.0).toList()
        : <double>[];
    final avg = values.isNotEmpty ? (values.reduce((a, b) => a + b) / values.length).round() : 50;
    final labels = _buildXLabels(docs?.map((d) => d.data()["period"] as String? ?? "").toList() ?? []);

    return _buildCardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(Icons.self_improvement, "Stress", "$avg / 100", "Avg", const Color(0xFFF97316)),
          const SizedBox(height: 8),
          _buildAxisLabels("score", labels),
          const SizedBox(height: 4),
          _VisibilityAnimatedWidget(
            duration: const Duration(milliseconds: 1500),
            builder: (context, animValue) {
              return SizedBox(
                height: 120,
                width: double.infinity,
                child: values.isEmpty
                    ? _buildEmptyState()
                    : CustomPaint(painter: LineChartPainter(values: values, color: const Color(0xFFF97316), animationValue: animValue)),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── VH-58: WELLNESS — area chart ─────────────────────────────────

  Widget _buildWellnessCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    final values = docs != null && docs.isNotEmpty
        ? docs.map((d) => (d.data()["avg"] as num?)?.toDouble() ?? 0.0).toList()
        : <double>[];
    final avg = values.isNotEmpty ? (values.reduce((a, b) => a + b) / values.length).round() : 0;
    final labels = _buildXLabels(docs?.map((d) => d.data()["period"] as String? ?? "").toList() ?? []);

    return _buildCardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(Icons.favorite, "Wellness", "$avg / 100", "Score", const Color(0xFF22C55E)),
          const SizedBox(height: 8),
          _buildAxisLabels("score", labels),
          const SizedBox(height: 4),
          _VisibilityAnimatedWidget(
            duration: const Duration(milliseconds: 1200),
            builder: (context, animValue) {
              return SizedBox(
                height: 120,
                width: double.infinity,
                child: values.isEmpty
                    ? _buildEmptyState()
                    : CustomPaint(painter: AreaChartPainter(values: values, color: const Color(0xFF22C55E), animationValue: animValue)),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── SHARED UI ─────────────────────────────────────────────────────

  Widget _buildAxisLabels(String yLabel, List<String> xLabels) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(yLabel, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Row(
          children: xLabels
              .map((l) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(l, style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_outlined, color: Colors.grey, size: 32),
          SizedBox(height: 8),
          Text("No data for this period", style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  // Shows the actual error instead of silently showing an empty chart.
  // Previously snapshot.hasError was never checked, so Firestore assertion
  // ── Awaiting-sync placeholder (consented but no data yet) ─────────────────
  Widget _buildAwaitingSync(String label) {
    return _buildCardBase(
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF7C69EF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Waiting for Apple Health to sync data…',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Prompt shown when no HealthKit metrics consented yet ─────────────────
  Widget _buildConnectHealthPrompt() {
    return _buildCardBase(
      child: Column(
        children: [
          const Icon(Icons.health_and_safety_outlined,
              size: 40, color: Color(0xFF7C69EF)),
          const SizedBox(height: 12),
          const Text(
            'Connect Apple Health',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enable health metrics in Profile → Health Data Permissions '
            'to see your real data here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
          ),
        ],
      ),
    );
  }

  // failures (e.g. after seeding) appeared as "No data" with no indication
  // of what went wrong.
  Widget _buildStreamError(String metric, Object? error) {
    return _buildCardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
            const SizedBox(width: 8),
            Text('$metric — stream error', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Text(
            error?.toString() ?? 'Unknown error',
            style: const TextStyle(fontSize: 11, color: Colors.redAccent),
          ),
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
        boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: child,
    );
  }

  Widget _buildChartHeader(IconData icon, String title, String value, String valueSub, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(valueSub, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildSmallStatCard(IconData icon, String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSyncCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(16)),
      child: const Row(
        children: [
          Icon(Icons.sync, color: Colors.green),
          SizedBox(width: 12),
          Text("Connected", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────

  double _barWidth(int count) {
    if (count <= 7) return 25;
    if (count <= 14) return 16;
    return 10;
  }

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  List<String> _buildXLabels(List<String> periods) {
    if (periods.isEmpty) return [];
    if (periods.length == 1) return [_shortDate(periods.first)];
    if (periods.length <= 7) return periods.map(_shortDate).toList();
    // For monthly show only first, mid, last
    return [_shortDate(periods.first), _shortDate(periods[periods.length ~/ 2]), _shortDate(periods.last)];
  }

  String _shortDate(String period) {
    if (period.length < 10) return period;
    final parts = period.split('-');
    if (parts.length < 3) return period;
    return '${parts[1]}/${parts[2]}';
  }

  String _scoreToMoodLabel(double score) {
    if (score >= 85) return 'Great 🤩';
    if (score >= 65) return 'Good 😊';
    if (score >= 45) return 'Okay 😐';
    if (score >= 25) return 'Down 😔';
    return 'Awful 😫';
  }

  String _scoreToEmoji(double score) {
    if (score >= 85) return '🤩';
    if (score >= 65) return '😊';
    if (score >= 45) return '😐';
    if (score >= 25) return '😔';
    return '😫';
  }

  Color _moodColor(double score) {
    if (score >= 65) return Colors.green;
    if (score >= 45) return Colors.orange;
    return Colors.redAccent;
  }

  // ── HealthKit-sourced card builders ────────────────────────────────────────

  Widget _buildHrvCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    if (docs == null) return _buildAwaitingSync('HRV');
    final values = docs.map<double>((d) => (d['avg'] as num?)?.toDouble() ?? 0.0).toList();
    final latest = values.isNotEmpty ? values.last : 0.0;
    final stressFromHrv = docs.isNotEmpty
        ? (docs.last['stressScore'] as num?)?.toDouble()
        : null;

    return _buildCardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(
            Icons.monitor_heart_outlined,
            'HRV',
            '${latest.toStringAsFixed(0)} ms',
            stressFromHrv != null
                ? 'Stress: ${stressFromHrv.toInt()}'
                : 'Apple Health',
            const Color(0xFF8B5CF6),
          ),
          const SizedBox(height: 16),
          if (values.isNotEmpty)
            SizedBox(
              height: 80,
              child: _VisibilityAnimatedWidget(
                builder: (context, anim) => CustomPaint(
                  size: Size.infinite,
                  painter: AreaChartPainter(
                    values: values,
                    color: const Color(0xFF8B5CF6),
                    animationValue: anim,
                  ),
                ),
              ),
            )
          else
            const Center(child: Text('No HRV data yet', style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildBloodOxygenCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    if (docs == null) return _buildAwaitingSync('Blood Oxygen');
    final values = docs.map<double>((d) => (d['avg'] as num?)?.toDouble() ?? 0.0).toList();
    final latest = values.isNotEmpty ? values.last : 0.0;

    return _buildCardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(
            Icons.water_drop_outlined,
            'Blood Oxygen',
            '${latest.toStringAsFixed(1)}%',
            'SpO₂ · Apple Health',
            const Color(0xFF06B6D4),
          ),
          const SizedBox(height: 16),
          if (values.isNotEmpty)
            SizedBox(
              height: 80,
              child: _VisibilityAnimatedWidget(
                builder: (context, anim) => CustomPaint(
                  size: Size.infinite,
                  painter: AreaChartPainter(
                    values: values,
                    color: const Color(0xFF06B6D4),
                    animationValue: anim,
                  ),
                ),
              ),
            )
          else
            const Center(child: Text('No SpO₂ data yet', style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildActiveCaloriesCard(List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs) {
    if (docs == null) return _buildAwaitingSync('Active Calories');
    final values = docs.map<double>((d) => ((d['sum'] ?? d['avg']) as num? ?? 0).toDouble()).toList();
    final total = values.fold(0.0, (a, b) => a + b);
    final latest = values.isNotEmpty ? values.last : 0.0;

    return _buildCardBase(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(
            Icons.local_fire_department_outlined,
            'Active Calories',
            '${latest.toInt()} kcal',
            'Period: ${total.toInt()} kcal total',
            const Color(0xFFF97316),
          ),
          const SizedBox(height: 16),
          if (values.isNotEmpty)
            SizedBox(
              height: 80,
              child: _VisibilityAnimatedWidget(
                builder: (context, anim) => CustomPaint(
                  size: Size.infinite,
                  painter: AreaChartPainter(
                    values: values,
                    color: const Color(0xFFF97316),
                    animationValue: anim,
                  ),
                ),
              ),
            )
          else
            const Center(
                child: Text('No calorie data yet', style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }
}

// ── VISIBILITY ANIMATION HELPER ───────────────────────────────────

class _VisibilityAnimatedWidget extends StatefulWidget {
  final Widget Function(BuildContext, double) builder;
  final Duration duration;

  const _VisibilityAnimatedWidget({
    required this.builder,
    this.duration = const Duration(milliseconds: 800),
  });

  @override
  State<_VisibilityAnimatedWidget> createState() => _VisibilityAnimatedWidgetState();
}

class _VisibilityAnimatedWidgetState extends State<_VisibilityAnimatedWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _hasBeenVisible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
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
        builder: (context, child) => widget.builder(
          context,
          CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart).value,
        ),
      ),
    );
  }
}

// ── CUSTOM PAINTERS ───────────────────────────────────────────────

// VH-58: Line chart for heart rate
class LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double animationValue;

  LineChartPainter({required this.values, required this.color, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final maxVal = values.reduce(max);
    final minVal = values.reduce(min);
    final range = (maxVal - minVal).clamp(1.0, double.infinity);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1 ? size.width / 2 : (i / (values.length - 1)) * size.width;
      final y = size.height - ((values[i] - minVal) / range) * size.height * 0.85 - size.height * 0.05;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw dots
    final dotPaint = Paint()..color = color..style = PaintingStyle.fill;
    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1 ? size.width / 2 : (i / (values.length - 1)) * size.width;
      final y = size.height - ((values[i] - minVal) / range) * size.height * 0.85 - size.height * 0.05;
      canvas.drawCircle(Offset(x, y), 3, dotPaint);
    }

    for (PathMetric m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * animationValue), paint);
    }
  }

  @override
  bool shouldRepaint(LineChartPainter old) => old.animationValue != animationValue;
}

// VH-58: Area chart for sleep
class AreaChartPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double animationValue;

  AreaChartPainter({required this.values, required this.color, required this.animationValue});

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

    final path = Path();
    final fillPath = Path();

    fillPath.moveTo(0, size.height);

    for (int i = 0; i < values.length; i++) {
      final x = values.length == 1 ? size.width / 2 : (i / (values.length - 1)) * size.width;
      final y = size.height - (values[i] / maxVal) * size.height * 0.85 * animationValue;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(AreaChartPainter old) => old.animationValue != animationValue;
}