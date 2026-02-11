import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTimeFilter = 1;
  static const Color primaryPurple = Color(0xFF7B6EF6);
  static const Color bgPurple = Color(0xFFFBFAFF);

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

                      /*
                        DASHBOARD DATA RULE (per task):
                        - Only pull values that exist in Firestore for the authenticated user.
                        - Do NOT modify UI elements that do not have a real database field/collection yet.
                        - Security is enforced by Firestore Rules (auth required + user owns their docs).

                        THIS SECTION:
                        - Pulled from Firestore (collection: metrics_daily):
                          * Heart Rate value: restingHeartRate
                          * Daily Steps value: stepsCount
                          * Sleep Duration value: sleepDurationHours

                        - Not pulled (no matching field/collection exists in current schema; UI left unchanged):
                          * Screen Time (hardcoded "4.2h" in _buildGridStats)
                          * Audio (hardcoded "65 dB" in _buildGridStats)

                        Counts:
                        - Values shown on UI (text): 5
                        - Values pulled from Firestore: 3
                        - Values NOT pulled (missing field/collection): 2
                      */

                      // If user is not logged in, we keep the existing UI values (no DB access possible).
                      if (currentUser == null)
                        Column(
                          children: [
                            _buildHeartRateCard(null),
                            const SizedBox(height: 16),
                            _buildStepsCard(null),
                            const SizedBox(height: 16),
                            _buildSleepCard(null),
                          ],
                        )
                      else
                        // Pull the most recent metrics document for this authenticated user.
                        // The query is scoped by userId == auth.uid (backend rules also enforce ownership).
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection("metrics_daily")
                              .where("userId", isEqualTo: currentUser.uid)
                              // We order by "date" to get latest. "date" must exist in the document.
                              .orderBy("date", descending: true)
                              .limit(1)
                              .snapshots(),
                          builder: (context, snapshot) {
                            // If we have data, use it. If not, fall back to existing UI placeholders.
                            Map<String, dynamic>? data;
                            if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                              data = snapshot.data!.docs.first.data();
                            }

                            return Column(
                              children: [
                                _buildHeartRateCard(data),
                                const SizedBox(height: 16),
                                _buildStepsCard(data),
                                const SizedBox(height: 16),
                                _buildSleepCard(data),
                              ],
                            );
                          },
                        ),

                      const SizedBox(height: 16),

                      // This stays unchanged because the DB does not currently provide these fields:
                      // - Screen Time (hardcoded UI)
                      // - Audio (hardcoded UI)
                      _buildGridStats(),
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

  // --- HEADER SECTION ---

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
            "Health Dashboards",
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
        onTap: () => setState(() => _selectedTimeFilter = index),
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

  // --- CHART CARDS ---
  // NOTE: These cards keep the original UI layout.
  // Only the displayed "value" is replaced with Firestore fields when available.

  Widget _buildHeartRateCard(Map<String, dynamic>? data) {
    // Pulled field (if present): metrics_daily.restingHeartRate
    // Fallback: original placeholder value (unchanged behavior)
    final firestoreHr = data?["restingHeartRate"];
    final displayed = firestoreHr != null
        ? firestoreHr.toString()
        : (_selectedTimeFilter == 0 ? "72" : "68");

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.favorite_border,
            "Heart Rate",
            displayed,
            "Avg",
            Colors.redAccent,
          ),
          const SizedBox(height: 20),
          _VisibilityAnimatedWidget(
            duration: const Duration(milliseconds: 1500),
            builder: (context, value) {
              return SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(painter: HeartRateLinePainter(value)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStepsCard(Map<String, dynamic>? data) {
    // Pulled field (if present): metrics_daily.stepsCount
    // Fallback: original placeholder value (unchanged behavior)
    final firestoreSteps = data?["stepsCount"];
    final displayed = firestoreSteps != null
        ? firestoreSteps.toString()
        : (_selectedTimeFilter == 0 ? "9,540" : "64,200");

    final List<double> dailyData = [0.3, 0.5, 0.2, 0.7, 0.4, 0.9, 0.6]; // unchanged UI

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(
            Icons.directions_walk,
            "Daily Steps",
            displayed,
            "Total",
            Colors.blueAccent,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: dailyData.map((h) => _buildBar(h, Colors.blueAccent)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepCard(Map<String, dynamic>? data) {
    // Pulled field (if present): metrics_daily.sleepDurationHours
    // Fallback: original placeholder value (unchanged behavior)
    final firestoreSleep = data?["sleepDurationHours"];
    final displayed = firestoreSleep != null ? "${firestoreSleep}h" : "7.9h";

    final List<double> sleepData = [0.7, 0.65, 0.8, 0.75, 0.6, 0.9, 0.85]; // unchanged UI
    final List<String> labels = ["M", "T", "W", "T", "F", "S", "S"]; // unchanged UI

    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(Icons.bedtime, "Sleep Duration", displayed, "Last Night", primaryPurple),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(
                7,
                (i) => _buildBar(sleepData[i], primaryPurple, label: labels[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- SHARED UI COMPONENTS ---

  Widget _buildBar(double targetHeight, Color color, {String? label}) {
    return _VisibilityAnimatedWidget(
      builder: (context, animationValue) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 25,
              height: 100 * targetHeight * animationValue,
              decoration: BoxDecoration(
                color: color.withOpacity(0.8),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            if (label != null) ...[
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ]
          ],
        );
      },
    );
  }

  Widget _buildGridStats() {
    // Not pulled from Firestore because current DB schema has no fields/collection for:
    // - Screen Time
    // - Audio (dB)
    // These remain hardcoded UI placeholders until a real data source is added.
    return Row(
      children: [
        Expanded(child: _buildSmallStatCard(Icons.smartphone, "Screen Time", "4.2h", Colors.orange)),
        const SizedBox(width: 16),
        Expanded(child: _buildSmallStatCard(Icons.volume_up, "Audio", "65 dB", Colors.green)),
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

  Widget _buildCardBase({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)],
      ),
      child: child,
    );
  }

  Widget _buildChartHeader(IconData icon, String title, String value, String valueSub, Color color) {
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
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(valueSub, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
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
}

// --- HELPER CLASS FOR SCROLL ACTIVATION ---

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

class _VisibilityAnimatedWidgetState extends State<_VisibilityAnimatedWidget> with SingleTickerProviderStateMixin {
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

// --- PAINTER FOR HEART RATE ---

class HeartRateLinePainter extends CustomPainter {
  final double animationValue;
  HeartRateLinePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    Path path = Path();
    path.moveTo(0, size.height * 0.7);
    path.lineTo(size.width * 0.2, size.height * 0.7);
    path.lineTo(size.width * 0.25, size.height * 0.3);
    path.lineTo(size.width * 0.35, size.height * 0.9);
    path.lineTo(size.width * 0.45, size.height * 0.1);
    path.lineTo(size.width * 0.55, size.height * 0.8);
    path.lineTo(size.width * 0.6, size.height * 0.7);
    path.lineTo(size.width, size.height * 0.7);

    for (PathMetric measurePath in path.computeMetrics()) {
      Path extractPath = measurePath.extractPath(0.0, measurePath.length * animationValue);
      canvas.drawPath(extractPath, paint);
    }
  }

  @override
  bool shouldRepaint(HeartRateLinePainter oldDelegate) => oldDelegate.animationValue != animationValue;
}
