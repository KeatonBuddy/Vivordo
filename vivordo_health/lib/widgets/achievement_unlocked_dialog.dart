import 'package:flutter/material.dart';
import 'package:vivordo_health/src/services/achievement_unlock_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

class AchievementUnlockedDialog extends StatelessWidget {
  const AchievementUnlockedDialog({
    required this.achievement,
    required this.onDismiss,
    super.key,
  });

  final AchievementUnlock achievement;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final tierLabel = achievement.tier == null
        ? null
        : '${achievement.tier![0].toUpperCase()}${achievement.tier!.substring(1)}';
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: const Color(0xFF8B70F6), width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x665F45E8),
                blurRadius: 34,
                spreadRadius: 2,
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    const Text(
                      'ACHIEVEMENT UNLOCKED',
                      style: TextStyle(
                        color: Color(0xFFB7A4FF),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: IconButton.filled(
                          onPressed: onDismiss,
                          style: IconButton.styleFrom(
                            backgroundColor: colors.cardMuted,
                            side: BorderSide(color: colors.border),
                          ),
                          icon: Icon(
                            Icons.close_rounded,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _CelebrationBadge(assetPath: achievement.badgeAsset),
                const SizedBox(height: 20),
                Text(
                  achievement.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.7,
                  ),
                ),
                if (tierLabel != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    '$tierLabel tier',
                    style: const TextStyle(
                      color: Color(0xFF9C83FF),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  achievement.requirement,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 17,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Earned just now',
                  style: TextStyle(color: Color(0xFF8F8FA5), fontSize: 14),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6D55EA).withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF8B70F6).withValues(alpha: .35),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFF9C83FF),
                      ),
                      SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Added to your achievements',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFB7A4FF),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: onDismiss,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6250E8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CelebrationBadge extends StatelessWidget {
  const _CelebrationBadge({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    height: 210,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 178,
          height: 178,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x557A5AF8),
                blurRadius: 42,
                spreadRadius: 10,
              ),
            ],
          ),
        ),
        ClipOval(
          child: Image.asset(
            assetPath,
            width: 178,
            height: 178,
            fit: BoxFit.cover,
          ),
        ),
        for (final sparkle in const [
          (Alignment(-.92, -.65), Color(0xFFFFCD57), 17.0),
          (Alignment(.86, -.76), Color(0xFF8C72FF), 14.0),
          (Alignment(-.96, .52), Color(0xFF75D6A9), 12.0),
          (Alignment(.98, .48), Color(0xFFFF7668), 13.0),
          (Alignment(-.65, .92), Color(0xFF8C72FF), 11.0),
          (Alignment(.65, .93), Color(0xFFFFCD57), 16.0),
        ])
          Align(
            alignment: sparkle.$1,
            child: Icon(
              Icons.auto_awesome,
              color: sparkle.$2,
              size: sparkle.$3,
            ),
          ),
      ],
    ),
  );
}
