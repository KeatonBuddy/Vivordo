import 'package:flutter/material.dart';
import 'goals_screen.dart';
import 'dashboard_screen.dart';
import 'panda_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final double stressScore = 42;
  int _selectedIndex = 0; // Track active tab

  @override
  Widget build(BuildContext context) {
    // Colors
    final Color primaryPurple = const Color(0xFF7B6EF6);
    final Color bgWhite = const Color(0xFFFBFAFF);
    final Color cardYellow = const Color(0xFFFFFBE5);
    final Color yellowAccent = const Color(0xFFD4A017);
    final Color textDark = const Color(0xFF2D3142);
    final Color textGrey = const Color(0xFF9CA3AF);
    final Color successGreen = const Color(0xFF4ADE80);

    return Scaffold(
      backgroundColor: bgWhite,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              children: [
                _buildHeader(primaryPurple),
                Transform.translate(
                  offset: const Offset(0, -60),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        _buildStressCard(stressScore, cardYellow, yellowAccent, textDark),
                        const SizedBox(height: 24),
                        _buildTimeFilter(primaryPurple),
                        const SizedBox(height: 24),
                        _buildAIInsightsCard(primaryPurple, textDark),
                        const SizedBox(height: 24),
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
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 20,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: SizedBox(
                            height: 100,
                            child: CustomPaint(
                              painter: WeeklyChartPainter(color: primaryPurple),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.85,
                          children: [
                            _buildStatCard(
                              title: 'Sleep',
                              value: '7.5h',
                              subText: '+30 min',
                              subTextColor: successGreen,
                              icon: Icons.bedtime_outlined,
                              iconColor: primaryPurple,
                            ),
                            _buildStatCard(
                              title: 'Steps',
                              value: '8,420',
                              subText: 'Goal reached',
                              subTextColor: successGreen,
                              icon: Icons.show_chart_rounded,
                              iconColor: primaryPurple,
                            ),
                            _buildStatCard(
                              title: 'Heart Rate',
                              value: '68 bpm',
                              subText: 'Resting avg',
                              subTextColor: textGrey,
                              icon: Icons.favorite_border,
                              iconColor: primaryPurple,
                            ),
                            _buildStatCard(
                              title: 'Mood',
                              value: 'Good',
                              subText: 'Check in →',
                              subTextColor: primaryPurple,
                              icon: Icons.psychology_outlined,
                              iconColor: primaryPurple,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildGoalCard(primaryPurple),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  // --- HEADER ---
  Widget _buildHeader(Color color) {
    return Container(
      height: 260,
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
          child: Row(
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
        ),
      ),
    );
  }

  // --- STRESS CARD ---
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

  // --- TIME FILTER ---
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
          _filterButton('Weekly', true, activeColor),
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

  // --- AI INSIGHTS ---
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

  // --- GRAPH PLACEHOLDER ---
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

  // --- STAT CARD ---
  Widget _buildStatCard({
    required String title,
    required String value,
    required String subText,
    required Color subTextColor,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          Text(
            subText,
            style: TextStyle(
              color: subTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --- GOAL CARD ---
  Widget _buildGoalCard(Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.4),
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.track_changes, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Current Goal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Icon(Icons.bookmark_border, color: Colors.white.withOpacity(0.7)),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Meditate 10 minutes daily',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '5 of 7 days this week',
                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
              ),
              const Text(
                '71%',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                height: 8,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              FractionallySizedBox(
                widthFactor: 0.71,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: const [
              Icon(Icons.local_fire_department, color: Colors.orangeAccent, size: 18),
              SizedBox(width: 6),
              Text(
                '3 day streak',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  // --- FLOATING NAV BAR ---
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
          _navItem(Icons.home, "Home", 0, primaryColor),
          _navItem(Icons.track_changes, "Goals", 1, primaryColor),
          _navItem(Icons.bar_chart, "Dashboard", 2, primaryColor),
          _navItem(Icons.pets_rounded, "Panda", 3, primaryColor),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index, Color primaryColor) {
  bool isActive = _selectedIndex == index;

  return GestureDetector(
    onTap: () {
      if (label == "Home" && !isActive) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else if (label == "Goals" && !isActive) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const GoalsScreen()),
        );
      } else if (label == "Dashboard" && !isActive) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      } else if (label == "Panda" && !isActive) {
        Navigator.push( // Use push so we can come back to Home
          context,
          MaterialPageRoute(builder: (context) => const PandaScreen()),
      );
      } else {
        setState(() => _selectedIndex = index);
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
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.grey, size: 24),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
  );
}
}

// --- CHART PAINTER PLACEHOLDER ---
class ChartPainter extends CustomPainter {
  final Color color;
  ChartPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height * 0.6);
    path.lineTo(size.width * 0.25, size.height * 0.4);
    path.lineTo(size.width * 0.5, size.height * 0.5);
    path.lineTo(size.width * 0.75, size.height * 0.3);
    path.lineTo(size.width, size.height * 0.4);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// --- WEEKLY CHART PAINTER PLACEHOLDER ---
class WeeklyChartPainter extends CustomPainter {
  final Color color;
  WeeklyChartPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height * 0.5);
    path.lineTo(size.width * 0.2, size.height * 0.3);
    path.lineTo(size.width * 0.4, size.height * 0.6);
    path.lineTo(size.width * 0.6, size.height * 0.2);
    path.lineTo(size.width * 0.8, size.height * 0.5);
    path.lineTo(size.width, size.height * 0.3);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}