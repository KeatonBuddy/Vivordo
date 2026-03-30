import 'package:flutter/material.dart';
import 'profile_screen.dart';
import 'panda_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final double stressScore = 42;
  int _selectedTimeFilter = 1;
  String _currentMood = 'Good';

  static const Color primaryPurple = Color(0xFF7B6EF6);
  static const Color bgWhite = Color(0xFFFBFAFF);
  static const Color textDark = Color(0xFF2D3142);
  static const Color textGrey = Color(0xFF9CA3AF);
  static const Color successGreen = Color(0xFF4ADE80);

  final double _headerHeight = 300.0;
  final Radius _overlapRadius = const Radius.circular(32);

  Color _getRingColor(double score) {
    if (score < 30) return const Color(0xFF4ADE80);
    if (score < 60) return const Color(0xFFFACC15);
    return const Color(0xFFFB7185);
  }

  void _openPanda() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PandaScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: primaryPurple,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openPanda,
        backgroundColor: Colors.white,
        elevation: 4,
        icon: Image.asset(
          'assets/panda_icon.png',
          height: 24,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.pets, color: primaryPurple),
        ),
        label: const Text(
          'Ask Panda',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: primaryPurple,
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildBackgroundHeader(),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: _headerHeight - 20)),
              SliverToBoxAdapter(child: _buildMainContent()),
            ],
          ),
          _buildTopBar(),
        ],
      ),
    );
  }

  // --- UI COMPONENTS ---

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
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
                        color: Colors.white.withOpacity(0.8), fontSize: 14),
                  ),
                  const Text(
                    'Sarah',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              _buildProfileButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileButton() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration:
            const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: const Icon(Icons.person, color: primaryPurple, size: 22),
      ),
    );
  }

  Widget _buildBackgroundHeader() {
    return Positioned.fill(
      child: Container(
        color: primaryPurple,
        child: Column(
          children: [
            const SafeArea(child: SizedBox(height: 80)),
            _buildPandaIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgWhite,
        borderRadius: BorderRadius.only(
          topLeft: _overlapRadius,
          topRight: _overlapRadius,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
        child: Column(
          children: [
            _buildTimeFilter(),
            const SizedBox(height: 24),
            _buildAIInsightsCard(primaryPurple, textDark),
            const SizedBox(height: 24),
            _buildTrendHeader(),
            const SizedBox(height: 16),
            _buildGraphPlaceholder(primaryPurple),
            const SizedBox(height: 24),
            _buildWeeklyChartContainer(),
            const SizedBox(height: 24),
            _buildStatsGrid(),
            const SizedBox(height: 24),
            _buildGoalCard(primaryPurple),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildTrendHeader() {
    String title = "Stress Trend (Today)";
    if (_selectedTimeFilter == 1) title = "Stress Trend (This Week)";
    if (_selectedTimeFilter == 2) title = "Stress Trend (This Month)";

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold, color: textDark),
      ),
    );
  }

  Widget _buildWeeklyChartContainer() {
    return Container(
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
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
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
          value: _currentMood,
          subText: 'Check in →',
          subTextColor: primaryPurple,
          icon: Icons.psychology_outlined,
          iconColor: primaryPurple,
          onTap: () => _showMoodCheck(primaryPurple),
        ),
      ],
    );
  }

  Widget _buildPandaIndicator() {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Panda image + stress ring stacked together
          SizedBox(
            height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onTap: _openPanda,
                  child: Image.asset(
                    'assets/panda_home_icon.png',
                    height: 160,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.pets, size: 80, color: Colors.white24),
                  ),
                ),
                // Stress ring — positioned at bottom of panda
                Positioned(
                  bottom: 0,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.15),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _getRingColor(stressScore).withOpacity(0.4),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 85,
                        height: 85,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: stressScore / 100),
                          duration: const Duration(milliseconds: 1800),
                          curve: Curves.easeOutBack,
                          builder: (context, value, child) {
                            return CircularProgressIndicator(
                              value: value,
                              strokeWidth: 8,
                              strokeCap: StrokeCap.round,
                              backgroundColor: Colors.white.withOpacity(0.3),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  _getRingColor(stressScore)),
                            );
                          },
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "STRESS",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white.withOpacity(0.8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            "${stressScore.toInt()}",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Chat with Panda button — sits cleanly below

        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subText,
    required Color subTextColor,
    required IconData icon,
    required Color iconColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }

  Widget _buildTimeFilter() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _filterButton("Daily", 0),
          _filterButton("Weekly", 1),
          _filterButton("Monthly", 2),
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

  Widget _buildAIInsightsCard(Color primaryColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology, color: primaryColor),
              const SizedBox(width: 12),
              Text('AI Insights',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Your stress levels have decreased by 15% this week. You're sleeping better and maintaining consistency.",
            style: TextStyle(color: Colors.blueGrey.shade700, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildGraphPlaceholder(Color color) {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
            color.withOpacity(0.1),
            Colors.white.withOpacity(0.0)
          ])),
      child: CustomPaint(painter: ChartPainter(color: color)),
    );
  }

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
              offset: const Offset(0, 10))
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current Goal',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          SizedBox(height: 8),
          Text('Meditate 10 minutes daily',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: 20),
          LinearProgressIndicator(
              value: 0.71,
              backgroundColor: Colors.white24,
              color: Colors.white),
        ],
      ),
    );
  }

  void _showMoodCheck(Color primaryColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(40),
              topRight: Radius.circular(40),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "How are you feeling?",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D3142),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Don't think too much, just tap.",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _moodOption('Great', '🤩', const Color(0xFFFFEDD5),
                      const Color(0xFFF97316)),
                  _moodOption('Good', '😊', const Color(0xFFDCFCE7),
                      const Color(0xFF22C55E)),
                  _moodOption('Okay', '😐', const Color(0xFFF3F4F6),
                      const Color(0xFF6B7280)),
                  _moodOption('Down', '😔', const Color(0xFFEDE9FE),
                      const Color(0xFF8B5CF6)),
                  _moodOption('Awful', '😫', const Color(0xFFFEE2E2),
                      const Color(0xFFEF4444)),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _moodOption(
      String label, String emoji, Color bgColor, Color accentColor) {
    bool isSelected = _currentMood == label;
    return GestureDetector(
      onTap: () {
        setState(() => _currentMood = label);
        Navigator.pop(context);
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isSelected ? accentColor : bgColor,
              shape: BoxShape.circle,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                          color: accentColor.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ]
                  : [],
            ),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
                color: isSelected
                    ? const Color(0xFF2D3142)
                    : const Color(0xFF9CA3AF),
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// --- PAINTERS ---

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