import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vivordo_health/src/models/goal.dart';
import 'package:vivordo_health/src/services/goal_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GoalsScreen — dev UI + Firestore backend
// UI is driven from dev branch; database layer wired in feature/database.
// ─────────────────────────────────────────────────────────────────────────────

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  static const Color primaryPurple = Color(0xFF7B6EF6);
  static const Color bgWhite = Color(0xFFFBFAFF);

  final TextEditingController _goalController = TextEditingController();

  List<Goal> myGoals = [];
  bool _loading = true;
  int _achievedCount = 0;

  int get bestStreak => myGoals.isEmpty
      ? 0
      : myGoals.map((g) => g.currentStreak).reduce((a, b) => a > b ? a : b);

  @override
  void initState() {
    super.initState();
    _loadGoals();
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  // ─── Firestore ─────────────────────────────────────────────────────────────

  Future<void> _loadGoals() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final goals = await GoalService.getGoals(userId: user.uid);
      final achievedSnap = await FirebaseFirestore.instance
          .collection('goals')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'achieved')
          .get();
      setState(() {
        myGoals = goals;
        _achievedCount = achievedSnap.docs.length;
        _loading = false;
      });
    } catch (e) {
      debugPrint('GoalsScreen._loadGoals: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _addNewGoal(String title) async {
    if (title.trim().isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    Navigator.pop(context);

    // Optimistic insert
    final temp = Goal(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim(),
      subtext: 'Daily',
      color: primaryPurple,
      days: {},
    );
    setState(() => myGoals.add(temp));
    _goalController.clear();

    try {
      await GoalService.createGoal(
        userId: user.uid,
        title: title.trim(),
        status: 'active',
      );
      await _loadGoals(); // refresh with real Firestore ID
    } catch (e) {
      debugPrint('GoalsScreen._addNewGoal: $e');
      setState(() => myGoals.removeWhere((g) => g.id == temp.id));
    }
  }

  Future<void> _deleteGoal(Goal goal) async {
    setState(() => myGoals.removeWhere((g) => g.id == goal.id));
    try {
      await FirebaseFirestore.instance.collection('goals').doc(goal.id).delete();
    } catch (e) {
      debugPrint('GoalsScreen._deleteGoal: $e');
      await _loadGoals();
    }
  }

  // ─── Dialogs ────────────────────────────────────────────────────────────────

  void _confirmDelete(Goal goal) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete Goal?'),
        content: Text("Remove '${goal.title}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteGoal(goal);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteMenu(Goal goal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
              title: const Text('Delete Goal',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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

  void _showAddGoalPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
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
                  hintText: 'Enter your goal...',
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
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
                  child: const Text('Create Goal',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgWhite,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 120),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildStatCard('Active', myGoals.length.toString(),
                                Icons.track_changes, primaryPurple),
                            _buildStatCard('Best Streak', bestStreak.toString(),
                                Icons.local_fire_department, Colors.orange),
                            _buildStatCard('Achieved', _achievedCount.toString(),
                                Icons.emoji_events, Colors.green),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (myGoals.isEmpty) _buildEmptyState(),
                        ...myGoals.map((goal) => Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: HabitGoalCard(
                                goal: goal,
                                onChanged: () => setState(() {}),
                                onLongPress: () => _showDeleteMenu(goal),
                              ),
                            )),
                        _buildAddButton(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 30),
      decoration: const BoxDecoration(
        color: primaryPurple,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Goals',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Keep the momentum going',
                  style: TextStyle(fontSize: 14, color: Colors.white70)),
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
        boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 10)],
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

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.flag_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('No goals yet',
              style: TextStyle(color: Colors.grey[400], fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('Tap + to create your first goal',
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
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
          border: Border.all(color: primaryPurple.withValues(alpha: 0.3), width: 2),
          borderRadius: BorderRadius.circular(20),
          color: primaryPurple.withValues(alpha: 0.05),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: primaryPurple),
            SizedBox(width: 8),
            Text('Add New Goal',
                style: TextStyle(color: primaryPurple, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// ─── HabitGoalCard — reused from dev branch verbatim ────────────────────────

class HabitGoalCard extends StatefulWidget {
  final Goal goal;
  final VoidCallback onChanged;
  final VoidCallback onLongPress;

  const HabitGoalCard({
    super.key,
    required this.goal,
    required this.onChanged,
    required this.onLongPress,
  });

  @override
  State<HabitGoalCard> createState() => _HabitGoalCardState();
}

class _HabitGoalCardState extends State<HabitGoalCard> {
  static const List<String> weekLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final double progress = widget.goal.days.length / 7;

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 10)],
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
                      Text(widget.goal.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.goal.subtext} • 🔥 ${widget.goal.currentStreak} day streak',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 40,
                  width: 40,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (context, value, _) => Stack(
                      fit: StackFit.expand,
                      children: [
                        CircularProgressIndicator(
                          value: 1,
                          strokeWidth: 4,
                          color: widget.goal.color.withValues(alpha: 0.1),
                        ),
                        CircularProgressIndicator(
                          value: value,
                          strokeWidth: 4,
                          strokeCap: StrokeCap.round,
                          color: widget.goal.color,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (index) {
                final isSelected = widget.goal.days.contains(index);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      isSelected
                          ? widget.goal.days.remove(index)
                          : widget.goal.days.add(index);
                    });
                    widget.onChanged();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? widget.goal.color
                          : Colors.grey.withValues(alpha: 0.1),
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
      ),
    );
  }
}
