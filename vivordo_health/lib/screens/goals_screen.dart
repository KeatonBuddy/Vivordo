import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'dashboard_screen.dart';
import 'panda_screen.dart';

class Goal {
  String id;
  String title;
  String subtext;
  Color color;
  Set<int> days; // Integers 0-6 representing M-S

  Goal({
    required this.id,
    required this.title,
    required this.subtext,
    required this.color,
    required this.days,
  });

  // --- DYNAMIC STREAK CALCULATION ---
  // Calculates the longest consecutive chain of days in the current week
  int get currentStreak {
    if (days.isEmpty) return 0;
    int maxStreak = 0;
    int currentRun = 0;

    for (int i = 0; i < 7; i++) {
      if (days.contains(i)) {
        currentRun++;
        if (currentRun > maxStreak) maxStreak = currentRun;
      } else {
        currentRun = 0;
      }
    }
    return maxStreak;
  }
}

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final Color primaryPurple = const Color(0xFF7B6EF6);
  final Color bgWhite = const Color(0xFFFBFAFF);
  final TextEditingController _goalController = TextEditingController();

  List<Goal> myGoals = [
    Goal(
      id: '1',
      title: 'Meditate 10 minutes daily',
      subtext: 'Daily',
      color: const Color(0xFF7B6EF6),
      days: {0, 1, 2}, 
    ),
    Goal(
      id: '2',
      title: 'Walk 10,000 steps',
      subtext: 'Daily',
      color: Colors.green,
      days: {0, 1, 2, 3, 4}, 
    ),
  ];

  // --- DYNAMIC BEST STREAK ---
  int get bestStreak => myGoals.isEmpty 
      ? 0 
      : myGoals.map((g) => g.currentStreak).reduce((a, b) => a > b ? a : b);

  void _confirmDelete(Goal goal) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Delete Goal?"),
        content: Text("Are you sure you want to remove '${goal.title}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              setState(() => myGoals.removeWhere((g) => g.id == goal.id));
              Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteMenu(Goal goal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text("Delete Goal", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(goal);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addNewGoal(String title) {
    if (title.trim().isEmpty) return;
    setState(() {
      myGoals.add(Goal(
        id: DateTime.now().toString(),
        title: title,
        subtext: 'Daily',
        color: primaryPurple,
        days: {},
      ));
    });
    _goalController.clear();
    Navigator.pop(context);
  }

  void _showAddGoalPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24, left: 24, right: 24,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _goalController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: "Enter your goal...",
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _addNewGoal(_goalController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryPurple,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("Create Goal", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgWhite,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 150),
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
                          _buildStatCard('Active', myGoals.length.toString(), Icons.track_changes, primaryPurple),
                          _buildStatCard('Best Streak', bestStreak.toString(), Icons.local_fire_department, Colors.orange),
                          _buildStatCard('Achieved', '12', Icons.emoji_events, Colors.green),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ...myGoals.map((goal) => Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: HabitGoalCard(
                          goal: goal,
                          onChanged: () => setState(() {}),
                          onLongPress: () => _showDeleteMenu(goal),
                        ),
                      )).toList(),
                      _buildAddButton(),
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

  // --- UI COMPONENTS ---
  Widget _buildHeader(Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30))),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("My Goals", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              Text("Keep the momentum going", style: TextStyle(fontSize: 14, color: Colors.white70)),
            ],
          ),
          Icon(Icons.calendar_today_outlined, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 100, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)]),
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

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _showAddGoalPopup,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          border: Border.all(color: primaryPurple.withOpacity(0.3), width: 2),
          borderRadius: BorderRadius.circular(20),
          color: primaryPurple.withOpacity(0.05),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: primaryPurple),
            const SizedBox(width: 8),
            const Text("Add New Goal", style: TextStyle(color: Color(0xFF7B6EF6), fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingNavBar(BuildContext context, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 5))]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(context, Icons.home, "Home", 0, primaryColor, false),
          _navItem(context, Icons.track_changes, "Goals", 1, primaryColor, true),
          _navItem(context, Icons.bar_chart, "Dashboard", 2, primaryColor, false),
          _navItem(context, Icons.pets_rounded, "Panda", 3, primaryColor, false),
        ],
      ),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String label, int index, Color color, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (isActive) return; 

        if (label == "Home") {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        } else if (label == "Goals") {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GoalsScreen()));
        } else if (label == "Dashboard") {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
        } else if (label == "Panda") {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PandaScreen()));
        }
      },
      child: isActive
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: color, 
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))
                ],
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min, 
              children: [
                Icon(icon, color: Colors.grey, size: 24),
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10))
              ],
            ),
    );
  }
}
// --- HABIT CARD WITH DYNAMIC STREAK ---
class HabitGoalCard extends StatefulWidget {
  final Goal goal;
  final VoidCallback onChanged;
  final VoidCallback onLongPress;

  const HabitGoalCard({super.key, required this.goal, required this.onChanged, required this.onLongPress});

  @override
  State<HabitGoalCard> createState() => _HabitGoalCardState();
}

class _HabitGoalCardState extends State<HabitGoalCard> {
  static const List<String> weekLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    double progress = widget.goal.days.length / 7;

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(20), 
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)]
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.goal.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      // STREAK UPDATES HERE
                      Text("${widget.goal.subtext} • 🔥 ${widget.goal.currentStreak} day streak", 
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
                SizedBox(
                  height: 40, width: 40,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(value: 1, strokeWidth: 4, color: widget.goal.color.withOpacity(0.1)),
                          CircularProgressIndicator(value: value, strokeWidth: 4, strokeCap: StrokeCap.round, color: widget.goal.color),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (index) {
                bool isSelected = widget.goal.days.contains(index);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      isSelected ? widget.goal.days.remove(index) : widget.goal.days.add(index);
                    });
                    widget.onChanged(); // Notify parent to update Top Stats
                  },
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: isSelected ? widget.goal.color : Colors.grey.withOpacity(0.1), shape: BoxShape.circle),
                    child: Center(child: Text(weekLabels[index], 
                      style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold))),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}