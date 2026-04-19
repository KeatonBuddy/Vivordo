import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_screen.dart';
import 'package:vivordo_health/src/services/metrics_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onScanTap;
  const HomeScreen({super.key, this.onScanTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _currentMood = '--';

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

  String _todayPeriod() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _todayMetric(String metricType) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    final docId = '${user.uid}_${metricType}_${_todayPeriod()}';
    return FirebaseFirestore.instance.collection('metrics_daily').doc(docId).snapshots();
  }

  /// Reads stress score: prefers HRV-derived stress from HealthKit ('hrv' doc),
  /// falls back to manual 'stress' doc from seed data.
  Stream<double> _stressScoreStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0);
    final today = _todayPeriod();
    final uid = user.uid;

    // Try HRV doc first — if it has stressScore field, use it
    final hrvDoc = FirebaseFirestore.instance
        .collection('metrics_daily')
        .doc('${uid}_hrv_$today')
        .snapshots()
        .map((snap) => (snap.data()?['stressScore'] as num?)?.toDouble());

    final stressDoc = FirebaseFirestore.instance
        .collection('metrics_daily')
        .doc('${uid}_stress_$today')
        .snapshots()
        .map((snap) => (snap.data()?['avg'] as num?)?.toDouble());

    // Combine: return HRV-based stress if available, else manual stress
    return hrvDoc.asyncMap((hrv) async {
      if (hrv != null) return hrv;
      final stressSnap = await FirebaseFirestore.instance
          .collection('metrics_daily')
          .doc('${uid}_stress_$today')
          .get();
      return (stressSnap.data()?['avg'] as num?)?.toDouble() ?? 0.0;
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _goalsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('goals')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return _buildScaffold(stressScore: 0, sleepVal: '--', stepsVal: '--', hrVal: '--', goalTitle: 'No goal set', goalProgress: 0);
    }

    return StreamBuilder<double>(
      stream: _stressScoreStream(),
      builder: (context, stressSnap) {
        final stressScore = stressSnap.data ?? 0.0;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _todayMetric('sleep'),
          builder: (context, sleepSnap) {
            final sleepData = sleepSnap.data?.data();
            final sleepVal = sleepData != null
                ? '${(sleepData['avg'] as num?)?.toStringAsFixed(1) ?? '--'}h'
                : '--';

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _todayMetric('steps'),
              builder: (context, stepsSnap) {
                final stepsData = stepsSnap.data?.data();
                final steps = (stepsData?['sum'] as num?)?.toInt();
                final stepsVal = steps != null
                    ? (steps >= 1000 ? '${(steps / 1000).toStringAsFixed(1)}k' : steps.toString())
                    : '--';

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _todayMetric('heart_rate'),
                  builder: (context, hrSnap) {
                    final hrData = hrSnap.data?.data();
                    final hrVal = hrData != null
                        ? '${(hrData['avg'] as num?)?.round() ?? '--'} bpm'
                        : '--';

                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _todayMetric('mood'),
                      builder: (context, moodSnap) {
                        final moodData = moodSnap.data?.data();
                        if (moodData != null && _currentMood == '--') {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _currentMood = moodData['label'] as String? ?? '--');
                          });
                        }

                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _goalsStream(),
                          builder: (context, goalSnap) {
                            final goalDocs = goalSnap.data?.docs ?? [];
                            final goalData = goalDocs.isNotEmpty ? goalDocs.first.data() : null;
                            final goalTitle = goalData?['title'] as String? ?? 'No active goal';
                            final rawPercent = (goalData?['progress']?['completionPercent'] as num?)?.toDouble() ?? 0;
                            final goalProgress = (rawPercent / 100).clamp(0.0, 1.0);

                            return _buildScaffold(
                              stressScore: stressScore,
                              sleepVal: sleepVal,
                              stepsVal: stepsVal,
                              hrVal: hrVal,
                              goalTitle: goalTitle,
                              goalProgress: goalProgress,
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildScaffold({
    required double stressScore,
    required String sleepVal,
    required String stepsVal,
    required String hrVal,
    required String goalTitle,
    required double goalProgress,
  }) {
    return Scaffold(
      backgroundColor: primaryPurple,
      body: Stack(
        children: [
          _buildBackgroundHeader(stressScore),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: _headerHeight - 20)),
              SliverToBoxAdapter(child: _buildMainContent(
                sleepVal: sleepVal,
                stepsVal: stepsVal,
                hrVal: hrVal,
                goalTitle: goalTitle,
                goalProgress: goalProgress,
              )),
            ],
          ),
          _buildTopBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final user = FirebaseAuth.instance.currentUser;
    String firstName = 'there';
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      firstName = user.displayName!.split(' ').first;
    } else if (user?.email != null) {
      firstName = user!.email!.split('@').first;
    }
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning,' : hour < 17 ? 'Good afternoon,' : 'Good evening,';

    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(greeting, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                Text(firstName, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              ]),
              _buildProfileButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileButton() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: const Icon(Icons.person, color: primaryPurple, size: 22),
      ),
    );
  }

  Widget _buildBackgroundHeader(double stressScore) {
    return Positioned.fill(
      child: Container(
        color: primaryPurple,
        child: Column(children: [
          const SafeArea(child: SizedBox(height: 80)),
          _buildPandaIndicator(stressScore),
        ]),
      ),
    );
  }

  Widget _buildMainContent({
    required String sleepVal,
    required String stepsVal,
    required String hrVal,
    required String goalTitle,
    required double goalProgress,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgWhite,
        borderRadius: BorderRadius.only(topLeft: _overlapRadius, topRight: _overlapRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
        child: Column(children: [
          _buildAIInsightsCard(primaryPurple, textDark),
          const SizedBox(height: 24),
          _buildStatsGrid(sleepVal: sleepVal, stepsVal: stepsVal, hrVal: hrVal),
          const SizedBox(height: 24),
          _buildGoalCard(primaryPurple, goalTitle, goalProgress),
          const SizedBox(height: 120),
        ]),
      ),
    );
  }

  Widget _buildPandaIndicator(double stressScore) {
    return SizedBox(
      height: 180, width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset('assets/panda_home_icon.png', height: 200, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 80, color: Colors.white24)),
          Positioned(
            bottom: 0,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.15), shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: _getRingColor(stressScore).withOpacity(0.4), blurRadius: 15, spreadRadius: 2)],
                  ),
                ),
                SizedBox(
                  width: 85, height: 85,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: stressScore / 100),
                    duration: const Duration(milliseconds: 1800),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) => CircularProgressIndicator(
                      value: value, strokeWidth: 8, strokeCap: StrokeCap.round,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(_getRingColor(stressScore)),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("STRESS", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.8), letterSpacing: 0.5)),
                    Text(
                      stressScore > 0 ? stressScore.toInt().toString() : '--',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, height: 1.1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid({required String sleepVal, required String stepsVal, required String hrVal}) {
    return GridView.count(
      crossAxisCount: 2, shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.85,
      children: [
        _buildStatCard(title: 'Sleep', value: sleepVal, subText: 'Last night', subTextColor: textGrey, icon: Icons.bedtime_outlined, iconColor: primaryPurple),
        _buildStatCard(title: 'Steps', value: stepsVal, subText: 'Today', subTextColor: successGreen, icon: Icons.show_chart_rounded, iconColor: primaryPurple),
        _buildStatCard(title: 'Heart Rate', value: hrVal, subText: 'Resting avg', subTextColor: textGrey, icon: Icons.favorite_border, iconColor: primaryPurple),
        _buildStatCard(title: 'Mood', value: _currentMood, subText: 'Check in →', subTextColor: primaryPurple, icon: Icons.psychology_outlined, iconColor: primaryPurple, onTap: () => _showMoodCheck(primaryPurple)),
      ],
    );
  }

  Widget _buildStatCard({required String title, required String value, required String subText, required Color subTextColor, required IconData icon, required Color iconColor, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [Icon(icon, color: iconColor, size: 22), const SizedBox(width: 8), Text(title, style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14, fontWeight: FontWeight.w500))]),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
            Text(subText, style: TextStyle(color: subTextColor, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildAIInsightsCard(Color primaryColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(Icons.psychology, color: primaryColor), const SizedBox(width: 12), Text('AI Insights', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor))]),
          const SizedBox(height: 12),
          Text("Track your daily wellness metrics to receive personalized AI-powered insights.",
              style: TextStyle(color: Colors.blueGrey.shade700, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildGoalCard(Color primaryColor, String goalTitle, double goalProgress) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current Goal', style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 8),
          Text(goalTitle, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          LinearProgressIndicator(value: goalProgress, backgroundColor: Colors.white24, color: Colors.white),
        ],
      ),
    );
  }

  void _showMoodCheck(Color primaryColor) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(40), topRight: Radius.circular(40))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 32),
            const Text("How are you feeling?", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF2D3142), letterSpacing: -0.5)),
            const SizedBox(height: 8),
            const Text("Don't think too much, just tap.", style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _moodOption('Great', '🤩', const Color(0xFFFFEDD5), const Color(0xFFF97316)),
                _moodOption('Good', '😊', const Color(0xFFDCFCE7), const Color(0xFF22C55E)),
                _moodOption('Okay', '😐', const Color(0xFFF3F4F6), const Color(0xFF6B7280)),
                _moodOption('Down', '😔', const Color(0xFFEDE9FE), const Color(0xFF8B5CF6)),
                _moodOption('Awful', '😫', const Color(0xFFFEE2E2), const Color(0xFFEF4444)),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _moodOption(String label, String emoji, Color bgColor, Color accentColor) {
    bool isSelected = _currentMood == label;
    return GestureDetector(
      onTap: () async {
        setState(() => _currentMood = label);
        Navigator.pop(context);
        try { await MetricsService.saveMoodCheckIn(label); } catch (e) { debugPrint('Mood save failed: $e'); }
      },
      child: Column(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic,
          width: 60, height: 60,
          decoration: BoxDecoration(color: isSelected ? accentColor : bgColor, shape: BoxShape.circle,
              boxShadow: isSelected ? [BoxShadow(color: accentColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))] : []),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 28))),
        ),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(color: isSelected ? const Color(0xFF2D3142) : const Color(0xFF9CA3AF), fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
      ]),
    );
  }
}