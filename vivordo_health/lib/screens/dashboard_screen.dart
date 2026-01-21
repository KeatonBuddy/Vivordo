import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:visibility_detector/visibility_detector.dart'; // Add this package
import 'home_screen.dart';
import 'goals_screen.dart';
import 'panda_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedTimeFilter = 1;
  final Color primaryPurple = const Color(0xFF7B6EF6);
  final Color bgPurple = const Color(0xFFFBFaff);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgPurple,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              children: [
                _buildHeader(primaryPurple),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      _buildSyncCard(),
                      const SizedBox(height: 20),
                      _buildHeartRateCard(primaryPurple),
                      const SizedBox(height: 16),
                      _buildStepsCard(primaryPurple),
                      const SizedBox(height: 16),
                      _buildSleepCard(primaryPurple),
                      const SizedBox(height: 16),
                      _buildGridStats(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(bottom: 30, left: 24, right: 24, child: _buildFloatingNavBar(context, primaryPurple)),
        ],
      ),
    );
  }

  Widget _buildScrollAnimatedBar(double targetHeight, Color color, {String? label}) {
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

  // --- HEART RATE WITH SCROLL TRIGGER ---
  Widget _buildHeartRateCard(Color primaryColor) {
    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(Icons.favorite_border, "Heart Rate", "Resting: 68 bpm",
              _selectedTimeFilter == 0 ? "72" : "68", "Avg", Colors.redAccent),
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

  // --- STEPS CHART ---
  Widget _buildStepsCard(Color primaryColor) {
    List<double> dailyData = [0.3, 0.5, 0.2, 0.7, 0.4, 0.9, 0.6];
    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(Icons.directions_walk, "Daily Steps", "Goal: 10k",
              _selectedTimeFilter == 0 ? "9,540" : "64,200", "Total", Colors.blueAccent),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: dailyData.map((h) => _buildScrollAnimatedBar(h, Colors.blueAccent)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // --- SLEEP CHART ---
  Widget _buildSleepCard(Color primaryColor) {
    List<double> sleepData = [0.7, 0.65, 0.8, 0.75, 0.6, 0.9, 0.85];
    List<String> labels = ["M", "T", "W", "T", "F", "S", "S"];
    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(Icons.bedtime, "Sleep Duration", "Avg: 7.4h", "7.9h", "Last Night", primaryColor),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) => _buildScrollAnimatedBar(sleepData[i], primaryColor, label: labels[i])),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color color) {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
      decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Health Dashboards", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [_filterButton("Daily", 0, color), _filterButton("Weekly", 1, color), _filterButton("Monthly", 2, color)]),
          ),
        ],
      ),
    );
  }

  Widget _filterButton(String text, int index, Color activeColor) {
    bool isActive = _selectedTimeFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTimeFilter = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: isActive ? activeColor : Colors.transparent, borderRadius: BorderRadius.circular(16)),
          child: Center(child: Text(text, style: TextStyle(color: isActive ? Colors.white : Colors.grey, fontSize: 12))),
        ),
      ),
    );
  }

  Widget _buildGridStats() {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _buildSmallStatCard(Icons.smartphone, "Screen Time", "4.2h", "-30m", Colors.orange)),
          const SizedBox(width: 16),
          Expanded(child: _buildSmallStatCard(Icons.volume_up, "Audio", "65 dB", "Safe", Colors.green)),
        ]),
      ],
    );
  }

  Widget _buildSmallStatCard(IconData icon, String title, String value, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 16),
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildCardBase({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)]),
      child: child,
    );
  }

  Widget _buildChartHeader(IconData icon, String title, String subtitle, String value, String valueSub, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [Icon(icon, color: color), const SizedBox(width: 10), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))]),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), Text(valueSub, style: TextStyle(fontSize: 10, color: color))]),
    ]);
  }

  Widget _buildSyncCard() => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(16)), child: const Row(children: [Icon(Icons.sync, color: Colors.green), SizedBox(width: 12), Text("Connected", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]));

  Widget _buildFloatingNavBar(BuildContext context, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)]),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _navItem(context, Icons.home, "Home", 0, primaryColor),
        _navItem(context, Icons.track_changes, "Goals", 1, primaryColor),
        _navItem(context, Icons.bar_chart, "Dashboard", 2, primaryColor),
        _navItem(context, Icons.pets_rounded, "Panda", 3, primaryColor),
      ]),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String label, int index, Color color) {
    bool isActive = index == 2;
    
    return GestureDetector(
      onTap: () {
        if (label == "Home") Navigator.pop(context); 
        if (label == "Goals") Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GoalsScreen()));
        if (label == "Panda") Navigator.push(context, MaterialPageRoute(builder: (_) => const PandaScreen()));
      },
      child: isActive
          ? Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 20), Text(label, style: const TextStyle(color: Colors.white, fontSize: 10))]))
          : Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.grey, size: 24), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10))]),
    );
  }
}

// --- HELPER CLASS FOR SCROLL ACTIVATION ---
class _VisibilityAnimatedWidget extends StatefulWidget {
  final Widget Function(BuildContext, double) builder;
  final Duration duration;

  const _VisibilityAnimatedWidget({required this.builder, this.duration = const Duration(milliseconds: 800)});

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
          setState(() => _hasBeenVisible = true);
          _controller.forward();
        }
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => widget.builder(context, CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart).value),
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
    Paint paint = Paint()..color = Colors.redAccent..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round;
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