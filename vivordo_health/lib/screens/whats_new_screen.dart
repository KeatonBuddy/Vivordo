import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

/// Release notes shown once to existing users after the major Vivordo refresh.
class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  static const _features = <_WhatsNewFeature>[
    _WhatsNewFeature(
      icon: Icons.fitness_center_rounded,
      colors: [Color(0xFF7B6EF6), Color(0xFF4935F5)],
      title: 'Complete Fitness',
      description:
          'Record 100+ exercises, build templates and track your progress.',
    ),
    _WhatsNewFeature(
      icon: Icons.donut_large_rounded,
      colors: [Color(0xFFA697FF), Color(0xFF6752EF)],
      title: 'Wellness & Metrics',
      description:
          'Explore detailed scores, trends, goals and personalized insights.',
    ),
    _WhatsNewFeature(
      icon: Icons.monitor_heart_outlined,
      colors: [Color(0xFFFF786C), Color(0xFFF0443D)],
      title: 'Smarter Scans',
      description:
          'Start scans when ready and use saved readings across Vivordo.',
    ),
    _WhatsNewFeature(
      icon: Icons.menu_book_rounded,
      colors: [Color(0xFF43D7C8), Color(0xFF00AFA1)],
      title: 'Private Journal',
      description: 'Track reflections and moods with biometric protection.',
    ),
    _WhatsNewFeature(
      icon: Icons.group_rounded,
      colors: [Color(0xFF9477F7), Color(0xFFFF6581), Color(0xFF31C9A8)],
      title: 'Introducing Circle',
      description:
          'Share selected moments, connect with friends and encourage each other.',
    ),
    _WhatsNewFeature(
      icon: Icons.military_tech_rounded,
      colors: [Color(0xFFFFD45C), Color(0xFFF2A900)],
      title: 'Achievements & Challenges',
      description:
          'Earn collectible badges and compete or collaborate with friends.',
    ),
    _WhatsNewFeature(
      icon: Icons.calendar_month_rounded,
      colors: [Color(0xFF76A7FF), Color(0xFF3478F6)],
      title: 'Smarter My Day',
      description: 'See Google and Outlook events together and find open time.',
    ),
    _WhatsNewFeature(
      icon: Icons.chat_bubble_outline_rounded,
      colors: [Color(0xFFA697FF), Color(0xFF6752EF)],
      title: 'Smarter AI Chat',
      description:
          'Get personalized answers from your relevant workout history.',
    ),
    _WhatsNewFeature(
      icon: Icons.dark_mode_rounded,
      colors: [Color(0xFF6E67A8), Color(0xFF302C68)],
      title: 'Dark Mode & New Design',
      description: 'Enjoy refreshed screens, navigation, cards and graphs.',
    ),
    _WhatsNewFeature(
      icon: Icons.phone_iphone_rounded,
      colors: [Color(0xFF9D8BFF), Color(0xFF6453E8)],
      title: 'Live Activities & Widgets',
      description:
          'Track workouts from the Lock Screen and add Home Screen widgets.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.page,
      body: Stack(
        children: [
          Positioned(
            top: -70,
            right: -100,
            child: _GlowOrb(
              size: 300,
              color: VivordoTheme.brand.withValues(alpha: isDark ? 0.13 : 0.09),
            ),
          ),
          Positioned(
            top: 150,
            left: -90,
            child: _GlowOrb(
              size: 210,
              color: const Color(
                0xFFB9AFFF,
              ).withValues(alpha: isDark ? 0.10 : 0.08),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onDismiss,
                      child: const Text(
                        'Not Now',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: SizedBox(
                      width: 340,
                      height: 104,
                      child: Image.asset(
                        'assets/vivordo_logo_long.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Meet the new Vivordo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 33,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your fitness, health and friends—completely reimagined.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 16,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4935F5), Color(0xFF7B6EF6)],
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'MAJOR UPDATE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.25,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: colors.border),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow,
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < _features.length;
                          index++
                        ) ...[
                          _FeatureRow(feature: _features[index]),
                          if (index != _features.length - 1)
                            Divider(
                              height: 1,
                              indent: 68,
                              color: colors.border.withValues(alpha: 0.75),
                            ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'And many more improvements throughout the app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Center(
                    child: TextButton(
                      onPressed: onDismiss,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                      child: const Text(
                        'Continue to Vivordo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});

  final _WhatsNewFeature feature;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: feature.colors,
              ),
              boxShadow: [
                BoxShadow(
                  color: feature.colors.last.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(feature.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  feature.description,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13.5,
                    height: 1.32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );
}

class _WhatsNewFeature {
  const _WhatsNewFeature({
    required this.icon,
    required this.colors,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final List<Color> colors;
  final String title;
  final String description;
}
