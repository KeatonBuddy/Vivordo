import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'profile_screen.dart';
import 'package:vivordo_health/src/services/metrics_service.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onScanTap;
  const HomeScreen({super.key, this.onScanTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _currentMood = 'Good';
  bool _messageCopied = false;

  // Cached streams — created once in initState to avoid duplicate Firestore listeners
  late Stream<double> _stressStream;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _sleepStream;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _stepsStream;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _hrStream;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _moodStream;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _goalsStreamCached;

  static const Color bgColor = Color(0xFFF2F2F7);
  static const Color cardWhite = Colors.white;
  static const Color accentPurple = Color(0xFF7B6EF6);
  static const Color textDark = Color(0xFF1C1C1E);
  static const Color textGrey = Color(0xFF8E8E93);
  static const Color greenColor = Color(0xFF34C759);
  static const Color orangeColor = Color(0xFFFF9500);

  @override
  void initState() {
    super.initState();
    _stressStream = _stressScoreStream();
    final today = _todayPeriod();
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    _sleepStream = uid != null
        ? FirebaseFirestore.instance.collection('metrics_daily').doc('${uid}_sleep_$today').snapshots()
        : const Stream.empty();
    _stepsStream = uid != null
        ? FirebaseFirestore.instance.collection('metrics_daily').doc('${uid}_steps_$today').snapshots()
        : const Stream.empty();
    _hrStream = uid != null
        ? FirebaseFirestore.instance.collection('metrics_daily').doc('${uid}_heart_rate_$today').snapshots()
        : const Stream.empty();
    _moodStream = uid != null
        ? FirebaseFirestore.instance.collection('metrics_daily').doc('${uid}_mood_$today').snapshots()
        : const Stream.empty();
    _goalsStreamCached = _goalsStream();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _getFirstName() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Alex';
    return displayName.split(' ').first;
  }

  Color _getStressColor(double score) {
    if (score < 30) return greenColor;
    if (score < 60) return const Color(0xFFFFCC00);
    return const Color(0xFFFF3B30);
  }

  String _getStressLabel(double score) {
    if (score < 30) return 'Very Low Stress';
    if (score < 60) return "Low Stress — You're in good shape";
    if (score < 80) return 'Moderate Stress';
    return 'High Stress';
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
      stream: _stressStream,
      builder: (context, stressSnap) {
        final stressScore = stressSnap.data ?? 0.0;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _sleepStream,
          builder: (context, sleepSnap) {
            final sleepData = sleepSnap.data?.data();
            final sleepVal = sleepData != null
                ? '${(sleepData['avg'] as num?)?.toStringAsFixed(1) ?? '--'}h'
                : '--';

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _stepsStream,
              builder: (context, stepsSnap) {
                final stepsData = stepsSnap.data?.data();
                final steps = (stepsData?['sum'] as num?)?.toInt();
                final stepsVal = steps != null
                    ? (steps >= 1000 ? '${(steps / 1000).toStringAsFixed(1)}k' : steps.toString())
                    : '--';

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _hrStream,
                  builder: (context, hrSnap) {
                    final hrData = hrSnap.data?.data();
                    final hrVal = hrData != null
                        ? '${(hrData['avg'] as num?)?.round() ?? '--'} bpm'
                        : '--';

                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _moodStream,
                      builder: (context, moodSnap) {
                        final moodData = moodSnap.data?.data();
                        if (moodData != null && _currentMood == '--') {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _currentMood = moodData['label'] as String? ?? '--');
                          });
                        }

                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _goalsStreamCached,
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
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildStressCard(stressScore),
              const SizedBox(height: 28),
              _buildSectionTitle('QUICK ACTIONS'),
              const SizedBox(height: 12),
              _buildQuickActions(),
              const SizedBox(height: 28),
              _buildSectionTitle("TODAY'S INSIGHTS"),
              const SizedBox(height: 12),
              _buildInsightCard(
                icon: Icons.nightlight_round,
                iconColor: accentPurple,
                iconBg: Color(0x1F7B6EF6),
                title: 'Great sleep last night',
                subtitle: '7h 42min - your HRV is up 12% vs. yesterday',
              ),
              const SizedBox(height: 10),
              _buildInsightCard(
                icon: Icons.psychology_outlined,
                iconColor: orangeColor,
                iconBg: Color(0x1FFF9500),
                title: 'Low cognitive load after 9:30 PM',
                subtitle: 'Good window for a 20-min call with someone you care about',
              ),
              const SizedBox(height: 28),
              _buildSectionTitle('REACHABLE WINDOWS'),
              const SizedBox(height: 12),
              _buildReachableWindows(),
              const SizedBox(height: 28),
              _buildSectionTitle('SMART MESSAGE'),
              const SizedBox(height: 12),
              _buildSmartMessageCard(),
              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_getGreeting()},',
              style: const TextStyle(
                color: textGrey,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _getFirstName(),
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 6),
                const Text('👋', style: TextStyle(fontSize: 26)),
              ],
            ),
          ],
        ),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cardWhite,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(Icons.person, color: accentPurple, size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildStressCard(double stressScore) {
    final statusColor = _getStressColor(stressScore);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: accentPurple,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: accentPurple.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative circle top-right
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Stress Level',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: stressScore),
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.easeOutCubic,
                        builder: (_, value, __) => Text(
                          value.toInt().toString(),
                          style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.0,
                            letterSpacing: -2,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8, left: 4),
                        child: Text(
                          '/100',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.white60,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _getStressLabel(stressScore),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: stressScore / 100),
                      duration: const Duration(milliseconds: 1400),
                      curve: Curves.easeOutCubic,
                      builder: (_, value, __) => LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: textGrey,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
            icon: Icons.flash_on_rounded,
            iconColor: accentPurple,
            iconBg: Color(0x1F7B6EF6),
            title: 'Quick Scan',
            subtitle: '60-sec stress check',
            onTap: () => widget.onScanTap?.call(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionCard(
            icon: Icons.edit_note_rounded,
            iconColor: greenColor,
            iconBg: Color(0x1F34C759),
            title: 'Check In',
            subtitle: 'Daily wellness log',
            onTap: _showMoodCheck,
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 15,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: textDark,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                color: textGrey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 15,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: textGrey,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReachableWindows() {
    final windows = [
      {'time': '12:30 - 1:00 PM', 'label': 'Low stress', 'color': greenColor},
      {'time': '6:00 - 7:30 PM', 'label': 'Post-workout calm', 'color': accentPurple},
      {'time': '9:30 - 10:30 PM', 'label': 'Moderate - winding down', 'color': orangeColor},
    ];

    return Column(
      children: windows.map((w) {
        final color = w['color'] as Color;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: cardWhite,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  w['time'] as String,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  w['label'] as String,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSmartMessageCard() {
    const message =
        "Hey, today's been manageable, want to FaceTime around 9:30?";
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 15,
            offset: Offset(0, 4),
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
                  color: Color(0x1A7B6EF6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: accentPurple, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'AI-Generated',
                style: TextStyle(
                  color: accentPurple,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '"Hey, today\'s been manageable, want to FaceTime around 9:30?"',
            style: TextStyle(
              color: textDark,
              fontSize: 15,
              height: 1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              await Clipboard.setData(const ClipboardData(text: message));
              setState(() => _messageCopied = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _messageCopied = false);
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _messageCopied ? greenColor : accentPurple,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _messageCopied ? Icons.check_rounded : Icons.copy_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _messageCopied ? 'Copied!' : 'Copy & Send',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoodCheck() {
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
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: accentPurple.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accentPurple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mood_rounded, color: accentPurple, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                "How are you feeling?",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D3142),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Don't think too much, just tap.",
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _moodOption('Great', '🤩', const Color(0xFFFFEDD5), const Color(0xFFF97316)),
                  _moodOption('Good', '😊', const Color(0xFFDCFCE7), const Color(0xFF22C55E)),
                  _moodOption('Okay', '😐', const Color(0xFFF3F4F6), const Color(0xFF6B7280)),
                  _moodOption('Down', '😔', const Color(0xFFEDE9FE), accentPurple),
                  _moodOption('Awful', '😫', const Color(0xFFFEE2E2), const Color(0xFFEF4444)),
                ],
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Your mood shapes your daily insights',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: accentPurple.withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        );
      },
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
                  ? [BoxShadow(color: accentColor.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]
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
              color: isSelected ? const Color(0xFF2D3142) : const Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
