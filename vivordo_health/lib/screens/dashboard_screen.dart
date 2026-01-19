import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'goals_screen.dart';
import 'panda_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryPurple = const Color(0xFF7B6EF6);
    final Color bgPurple = const Color(0xFFFBFaff);

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
                      // Apple Health Sync
                      _buildSyncCard(),
                      const SizedBox(height: 20),
                      
                      // Heart Rate Chart
                      _buildHeartRateCard(primaryPurple),
                      const SizedBox(height: 16),
                      
                      // Steps Chart
                      _buildStepsCard(primaryPurple),
                      const SizedBox(height: 16),
                      
                      // Sleep Chart
                      _buildSleepCard(primaryPurple),
                      const SizedBox(height: 16),

                      // Grid Stats (2 Rows)
                      Row(
                        children: [
                          Expanded(child: _buildSmallStatCard(Icons.smartphone, "Screen Time", "4.2h", "-30 min from avg", Colors.orange)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildSmallStatCard(Icons.volume_up, "Audio Levels", "65 dB", "Safe range", Colors.green)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildSmallStatCard(Icons.show_chart, "Active Minutes", "42 min", "Today", Colors.grey)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildSmallStatCard(Icons.location_on, "Locations", "4", "Places visited", Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- FLOATING NAV BAR ---
          Positioned(
            bottom: 30,
            left: 24,
            right: 24,
            child: _buildFloatingNavBar(context, primaryPurple),
          ),
        ],
      ),
    );
  }

  // --- HEADER WIDGET ---
  Widget _buildHeader(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: const BorderRadius.only(
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
          const SizedBox(height: 4),
          Text(
            "Deep dive into your metrics",
            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8)),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTabButton("Daily", false, primaryColor),
                _buildTabButton("Weekly", true, primaryColor),
                _buildTabButton("Monthly", false, primaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String text, bool isActive, Color primaryColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 12
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD1FAE5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: Color(0xFFD1FAE5), shape: BoxShape.circle),
            child: const Icon(Icons.monitor_heart_outlined, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Apple Health Connected", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF064E3B))),
                Text("Data syncing automatically", style: TextStyle(fontSize: 11, color: Color(0xFF065F46))),
              ],
            ),
          ),
          const Icon(Icons.sync, color: Colors.green, size: 20),
        ],
      ),
    );
  }

  // --- CHARTS & CARDS ---
  Widget _buildHeartRateCard(Color primaryColor) {
    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(Icons.favorite_border, "Heart Rate", "Resting: 68 bpm", "72", "Current", Colors.redAccent),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(painter: HeartRateLinePainter()),
          ),
          const SizedBox(height: 16),
          _buildTipBox("Your heart rate variability is healthy. Keep up your cardio routine.", const Color(0xFFFFF7ED), const Color(0xFF9A3412)),
        ],
      ),
    );
  }

  Widget _buildStepsCard(Color primaryColor) {
    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(Icons.directions_walk, "Daily Steps", "Goal: 10,000 steps", "9,540", "95% of goal", Colors.blueAccent),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildBar(0.3, primaryColor),
                _buildBar(0.5, primaryColor),
                _buildBar(0.2, primaryColor),
                _buildBar(0.7, primaryColor),
                _buildBar(0.4, primaryColor),
                _buildBar(0.6, primaryColor),
                _buildBar(0.1, primaryColor.withOpacity(0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepCard(Color primaryColor) {
    return _buildCardBase(
      child: Column(
        children: [
          _buildChartHeader(Icons.bedtime, "Sleep Duration", "Avg: 7.4 hours", "7.9h", "Last night", primaryColor),
          const SizedBox(height: 20),
          SizedBox(
            height: 150,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildBar(0.7, primaryColor, label: "Mon"),
                _buildBar(0.65, primaryColor, label: "Tue"),
                _buildBar(0.72, primaryColor, label: "Wed"),
                _buildBar(0.75, primaryColor, label: "Thu"),
                _buildBar(0.6, primaryColor, label: "Fri"),
                _buildBar(0.8, primaryColor, label: "Sat"),
                _buildBar(0.78, primaryColor, label: "Sun"),
              ],
            ),
          ),
          const SizedBox(height: 16),
           _buildTipBox("Your sleep quality improved by 15% this week. Your consistent bedtime is helping!", const Color(0xFFEFF6FF), const Color(0xFF1E40AF)),
        ],
      ),
    );
  }

  Widget _buildSmallStatCard(IconData icon, String title, String value, String subtext, Color subtextColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.circle, color: Color(0xFF857DEA), size: 10), 
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtext, style: TextStyle(fontSize: 11, color: subtextColor, fontWeight: FontWeight.bold)),
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
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildChartHeader(IconData icon, String title, String subtitle, String value, String valueSub, Color iconColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(valueSub, style: TextStyle(fontSize: 11, color: iconColor == Colors.redAccent ? Colors.grey : iconColor)),
          ],
        )
      ],
    );
  }

  Widget _buildBar(double heightFactor, Color color, {String? label}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 30,
          height: 100 * heightFactor,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]
      ],
    );
  }

  Widget _buildTipBox(String text, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb, size: 16, color: Colors.amber[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: textColor, height: 1.4),
            ),
          )
        ],
      ),
    );
  }

  // --- PREMIUM NAVIGATION BAR ---
  Widget _buildFloatingNavBar(BuildContext context, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(context, Icons.home, "Home", 0, primaryColor),
          _navItem(context, Icons.track_changes, "Goals", 1, primaryColor), 
          _navItem(context, Icons.bar_chart, "Dashboard", 2, primaryColor),
          _navItem(context, Icons.pets_rounded, "Panda", 3, primaryColor),
        ],
      ),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String label, int index, Color primaryColor) {
    bool isActive = index == 2; // Dashboard is active

    return GestureDetector(
      onTap: () {
        if (label == "Home") {
           Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        } else if (label == "Goals") {
           Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GoalsScreen()));
        } else if (label == "Panda") {
           Navigator.push(context, MaterialPageRoute(builder: (_) => const PandaScreen()));
        }
      },
      child: isActive
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.grey, size: 24),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10))
              ],
            ),
    );
  }
}

// Simple Painter for the Line Chart Curve
class HeartRateLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    Path path = Path();
    path.moveTo(0, size.height * 0.8);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.3, size.width * 0.5, size.height * 0.2);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.1, size.width, size.height * 0.6);

    canvas.drawPath(path, paint);

    Paint dotPaint = Paint()..color = Colors.redAccent;
    canvas.drawCircle(Offset(0, size.height * 0.8), 4, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.2), 4, dotPaint);
    canvas.drawCircle(Offset(size.width, size.height * 0.6), 4, dotPaint);
    
    TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    _drawText(canvas, textPainter, "6am", Offset(0, size.height + 5));
    _drawText(canvas, textPainter, "12pm", Offset(size.width * 0.45, size.height + 5));
    _drawText(canvas, textPainter, "9pm", Offset(size.width - 20, size.height + 5));
  }

  void _drawText(Canvas canvas, TextPainter tp, String text, Offset offset) {
    tp.text = TextSpan(text: text, style: TextStyle(color: Colors.grey[400], fontSize: 10));
    tp.layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}