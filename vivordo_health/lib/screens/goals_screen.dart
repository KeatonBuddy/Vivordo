import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'dashboard_screen.dart';
import 'panda_screen.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryPurple = const Color(0xFF7B6EF6);
    final Color bgWhite = const Color(0xFFFBFAFF);

    return Scaffold(
      backgroundColor: bgWhite,
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

                      // Habit Cards
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

  // --- HEADER WIDGET ---
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
                style: TextStyle(
                  fontSize: 28, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.white
                ),
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
    bool isActive = index == 1; // "Goals" is active for this screen

    return GestureDetector(
      onTap: () {
        if (label == "Home") {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        } else if (label == "Dashboard") {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
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

// --- HABIT GOAL CARD COMPONENT ---
class HabitGoalCard extends StatefulWidget {
  final String title;
  final String subtext;
  final double progress;
  final Color primaryColor;
  final Set<int> initialSelectedDays;

  const HabitGoalCard({
    super.key,
    required this.title,
    required this.subtext,
    required this.progress,
    required this.primaryColor,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text("${(widget.progress * 100).toInt()}%", 
                style: TextStyle(color: widget.primaryColor, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(widget.subtext, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 16),
          // Week Day Selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (index) {
              bool isSelected = selectedDays.contains(index);
              return GestureDetector(
                onTap: () => setState(() => isSelected ? selectedDays.remove(index) : selectedDays.add(index)),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected ? widget.primaryColor : Colors.grey.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      weekLabels[index],
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}