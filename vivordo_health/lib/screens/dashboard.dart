import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: DashboardScreen(),
  ));
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  final double stressScore = 42;

  @override
  Widget build(BuildContext context) {
    // Color Palette from the design
    final Color primaryPurple = const Color(0xFF7B6EF6);
    final Color bgWhite = const Color(0xFFFBFAFF);
    final Color cardYellow = const Color(0xFFFFFBE5);
    final Color yellowAccent = const Color(0xFFD4A017);
    final Color textDark = const Color(0xFF2D3142);

    return Scaffold(
      backgroundColor: bgWhite,
      body: Stack(
        children: [
          // 1. Background Scrollable Content
          SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(primaryPurple),
                
                // Overlapping Content
                Transform.translate(
                  offset: const Offset(0, -60), // Pull card up into the purple area
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        // Stress Score Card
                        _buildStressCard(stressScore, cardYellow, yellowAccent, textDark),
                        
                        const SizedBox(height: 24),
                        
                        // Time Filter (Daily/Weekly/Monthly)
                        _buildTimeFilter(primaryPurple),
                        
                        const SizedBox(height: 24),
                        
                        // AI Insights Card
                        _buildAIInsightsCard(primaryPurple, textDark),

                        const SizedBox(height: 24),

                        // Stress Trend Header (Chart placeholder)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Stress Trend (This Week)",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textDark,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildGraphPlaceholder(primaryPurple),
                        
                        // Extra space for the floating bottom bar
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Custom Floating Bottom Navigation Bar
          Positioned(
            bottom: 30,
            left: 24,
            right: 24,
            child: _buildFloatingNavBar(primaryPurple),
          ),
        ],
      ),
    );
  }

  // --- Widgets ---

  Widget _buildHeader(Color color) {
    return Container(
      height: 260, // Tall header to allow overlap
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good morning,',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                      const Text(
                        'Sarah',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  // Notification/Profile Icon bubble
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.waving_hand, color: Colors.amber, size: 20),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStressCard(double score, Color bgColor, Color accentColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_down, color: accentColor),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Stress Level',
                        style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 12),
                      ),
                      Text(
                        'Moderate',
                        style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    score.toInt().toString(),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                  Text(
                    'out of 100',
                    style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 10),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 24),
          // Custom Progress Bar
          Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              FractionallySizedBox(
                widthFactor: score / 100,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: textColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('View Stress Insights', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeFilter(Color activeColor) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _filterButton('Daily', false, activeColor),
          _filterButton('Weekly', true, activeColor), // Active
          _filterButton('Monthly', false, activeColor),
        ],
      ),
    );
  }

  Widget _filterButton(String text, bool isActive, Color activeColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.grey,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              fontSize: 13
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAIInsightsCard(Color primaryColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.psychology, color: primaryColor),
              ),
              const SizedBox(width: 12),
              Text(
                'AI Insights',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Your stress levels have decreased by 15% this week. You're sleeping better and maintaining consistent activity levels.",
            style: TextStyle(color: Colors.blueGrey.shade700, height: 1.5),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: (){},
            child: Row(
              children: [
                Text('Read More', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold)),
                Icon(Icons.keyboard_arrow_down, color: primaryColor, size: 18)
              ],
            ),
          )
        ],
      ),
    );
  }

  // A simple placeholder drawing for the chart at the bottom
  Widget _buildGraphPlaceholder(Color color) {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
         gradient: LinearGradient(
           begin: Alignment.topCenter,
           end: Alignment.bottomCenter,
           colors: [color.withOpacity(0.1), Colors.white.withOpacity(0.0)]
         )
      ),
      child: CustomPaint(
        painter: ChartPainter(color: color),
      ),
    );
  }

  Widget _buildFloatingNavBar(Color primaryColor) {
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
          _navItem(Icons.home, "Home", true, primaryColor),
          _navItem(Icons.track_changes, "Goals", false, primaryColor),
          _navItem(Icons.bar_chart, "Dashboards", false, primaryColor),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool isActive, Color primaryColor) {
    return isActive
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
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                )
              ],
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.grey, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              )
            ],
          );
  }
}

// Simple Painter to draw a curved line
class ChartPainter extends CustomPainter {
  final Color color;
  ChartPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, size.height * 0.7);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.8, size.width * 0.5, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.1, size.width, size.height * 0.6);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}