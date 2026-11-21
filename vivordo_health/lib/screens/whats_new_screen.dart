import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

/// Release notes shown once to existing users after an update (1.2).
class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  static const _features = <_WhatsNewFeature>[
    _WhatsNewFeature(
      icon: CupertinoIcons.chart_bar_alt_fill,
      colors: [Color(0xFF76A7FF), Color(0xFF3478F6)],
      title: 'Months of your health at a glance',
      description:
          'Steps, sleep, heart rate, mood and more now go back 6 months and a year, with a calendar for every month.',
    ),
    _WhatsNewFeature(
      icon: CupertinoIcons.person_2_fill,
      colors: [Color(0xFFA697FF), Color(0xFF6752EF)],
      title: 'Invite friends to plans',
      description:
          'Add Circle friends to any event, even a repeating one. They see how it fits their day before they answer.',
    ),
    _WhatsNewFeature(
      icon: CupertinoIcons.mic_fill,
      colors: [Color(0xFF7667F4), Color(0xFF4935F5)],
      title: 'Talk to Vivordo AI',
      description:
          'Tap the mic and say it. Your words turn into text on your iPhone, ready to check before you send.',
    ),
    _WhatsNewFeature(
      icon: Icons.fitness_center_rounded,
      colors: [Color(0xFFFFB067), Color(0xFFF27A1A)],
      title: 'Drop sets and supersets',
      description:
          'Add a drop set, or pair another exercise as a superset, from any set in your workout.',
    ),
    _WhatsNewFeature(
      icon: CupertinoIcons.moon_fill,
      colors: [Color(0xFF43D7C8), Color(0xFF00AFA1)],
      title: 'See when sleep runs short',
      description:
          'Sleep now counts your short nights over the last two weeks, and tells you when you’ve caught up.',
    ),
    _WhatsNewFeature(
      icon: CupertinoIcons.square_split_2x1,
      colors: [Color(0xFF77D36B), Color(0xFF37A84B)],
      title: 'Made for iPhone Duo',
      description:
          'Open it up for two panes side by side, or stand it up for a desk view of your day.',
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
                        // Ink-coloured on a dark page, as on sign-in.
                        color: Theme.of(context).brightness == Brightness.dark
                            ? colors.textPrimary
                            : null,
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'What’s new in Vivordo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 34,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'More history, friends in your plans, and a new way to talk to Vivordo AI.',
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
                          colors: [Color(0xFF4935F5), VivordoTheme.brand],
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'Version 1.2',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(20),
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
                          'Thanks for growing with Vivordo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 15,
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
                          fontSize: 17,
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
                    fontSize: 13,
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
