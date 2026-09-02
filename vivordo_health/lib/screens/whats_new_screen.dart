import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

/// Release notes shown once to existing users after the My Day refresh.
class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  static const _features = <_WhatsNewFeature>[
    _WhatsNewFeature(
      icon: Icons.speed_rounded,
      colors: [Color(0xFF7667F4), Color(0xFF4935F5)],
      title: 'Your day at a glance',
      description:
          'See today’s schedule load, scheduled time and longest opening instantly.',
    ),
    _WhatsNewFeature(
      icon: Icons.schedule_rounded,
      colors: [Color(0xFF77D36B), Color(0xFF37A84B)],
      title: 'Know what’s next',
      description:
          'Find your current opening and upcoming events from Google Calendar.',
    ),
    _WhatsNewFeature(
      icon: Icons.check_circle_rounded,
      colors: [Color(0xFF66D46A), Color(0xFF27A94B)],
      title: 'Independent daily priorities',
      description:
          'Use smart calendar suggestions or add your own, then check them off as you go.',
    ),
    _WhatsNewFeature(
      icon: Icons.account_tree_rounded,
      colors: [Color(0xFF76A7FF), Color(0xFF3478F6)],
      title: 'A connected timeline',
      description:
          'Follow the day in order, open events directly and jump into the full calendar.',
    ),
    _WhatsNewFeature(
      icon: Icons.add_rounded,
      colors: [Color(0xFFA697FF), Color(0xFF6752EF)],
      title: 'Add plans without leaving My Day',
      description:
          'Create calendar events or scheduled and repeating priorities in a few taps.',
    ),
    _WhatsNewFeature(
      icon: Icons.menu_book_rounded,
      colors: [Color(0xFF43D7C8), Color(0xFF00AFA1)],
      title: 'Reflect in the moment',
      description:
          'Your journal stays close by with the same private writing experience.',
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
                    'Your day, redesigned',
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
                    'A clearer way to plan what matters and move through your schedule.',
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
                        'MY DAY UPDATE',
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
                          'Built to help you spend less time organizing and more time doing.',
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
