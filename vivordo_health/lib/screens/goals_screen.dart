import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'dashboard_screen.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryPurple = const Color(0xFF857DEA);
    final Color bgPurple = const Color(0xFFFBFAFF);

    return Scaffold(
      backgroundColor: bgPurple,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              children: [
                _buildHeader(primaryPurple),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatCard('Active', '4', Icons.track_changes, primaryPurple),
                          _buildStatCard('Day Streak', '5', Icons.local_fire_department, Colors.orange),
                          _buildStatCard('Achieved', '12', Icons.emoji_events, Colors.green),
                        ],
                      ),
                      const SizedBox(height: 24),

                      HabitGoalCard(
                        title: 'Meditate 10 minutes daily',
                        subtext: 'Daily • 🔥 3 day streak',
                        progress: 0.71,
                        primaryColor: primaryPurple,
                        initialSelectedDays: {0, 1, 3, 4, 6},
                      ),
                      const SizedBox(height: 16),

                      HabitGoalCard(
                        title: 'Walk 10,000 steps',
                        subtext: 'Daily • 🔥 5 day streak',
                        progress: 0.85,
                        primaryColor: Colors.green,
                        initialSelectedDays: {0, 1, 2, 3, 4, 6},
                      ),
                      const SizedBox(height: 16),

                      HabitGoalCard(
                        title: 'Practice gratitude journaling',
                        subtext: 'Daily • 🔥 2 day streak',
                        progress: 0.57,
                        primaryColor: primaryPurple,
                        initialSelectedDays: {1, 2, 5},
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ],
            ),
          ),

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

  // ---------- HEADER ----------
  Widget _buildHeader(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "My Goals",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              SizedBox(height: 4),
              Text(
                "Keep the momentum going",
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
          Icon(Icons.calendar_today_outlined, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  // ---------- NAV ----------
  Widget _buildFloatingNavBar(BuildContext context, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(context, Icons.home, "Home", false, primaryColor),
          _navItem(context, Icons.track_changes, "Goals", true, primaryColor),
          _navItem(context, Icons.bar_chart, "Dashboard", false, primaryColor),
        ],
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    IconData icon,
    String label,
    bool isActive,
    Color primaryColor,
  ) {
    return GestureDetector(
      onTap: () {
        if (label == "Home" && !isActive) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        }
        if (label == "Dashboard" && !isActive) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
        }
      },
      child: Column(
        children: [
          Icon(icon, color: isActive ? primaryColor : Colors.grey),
          Text(label, style: TextStyle(fontSize: 10, color: isActive ? primaryColor : Colors.grey)),
        ],
      ),
    );
  }
}

//
// ======================
// HABIT GOAL CARD
// ======================
//

class HabitGoalCard extends StatefulWidget {
  final String title;
  final String subtext;
  final double progress;
  final Color primaryColor;
  final bool isGreenTheme;
  final Set<int> initialSelectedDays;

  const HabitGoalCard({
    super.key,
    required this.title,
    required this.subtext,
    required this.progress,
    required this.primaryColor,
    this.isGreenTheme = false,
    required this.initialSelectedDays,
  });

  @override
  State<HabitGoalCard> createState() => _HabitGoalCardState();
}

class _HabitGoalCardState extends State<HabitGoalCard> {
  static const List<String> weekLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  late Set<int> selectedDays;

  @override
  void initState() {
    super.initState();
    selectedDays = {...widget.initialSelectedDays};
  }

  void toggleDay(int index) {
    setState(() {
      selectedDays.contains(index)
          ? selectedDays.remove(index)
          : selectedDays.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: widget.isGreenTheme ? const Color(0xFFECFDF5) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!widget.isGreenTheme)
            BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(widget.subtext,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              CircularProgressIndicator(
                value: widget.progress,
                strokeWidth: 6,
                backgroundColor: widget.primaryColor.withOpacity(0.2),
                color: widget.primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              final bool selected = selectedDays.contains(index);

              return GestureDetector(
                onTap: () => toggleDay(index),
                child: Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? widget.primaryColor : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? widget.primaryColor
                              : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      weekLabels[index],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: selected ? widget.primaryColor : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
