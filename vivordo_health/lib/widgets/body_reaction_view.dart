import 'package:flutter/material.dart';

import '../src/utils/body_reaction.dart';

/// Label, icon and colours for the reactions worth showing; null for
/// steady, which isn't shown. [accent] reads on light and dark; [fg]/[bg]
/// are the light-mode chip.
({String label, IconData icon, Color accent, Color fg, Color bg})?
bodyReactionStyle(BodyReactionLevel level) => switch (level) {
  BodyReactionLevel.calm => (
    label: 'Calm',
    icon: Icons.spa_outlined,
    accent: const Color(0xFF1D9E75),
    fg: const Color(0xFF085041),
    bg: const Color(0xFFE1F5EE),
  ),
  BodyReactionLevel.up => (
    label: 'Heart rate up',
    icon: Icons.trending_up_rounded,
    accent: const Color(0xFFEF9F27),
    fg: const Color(0xFF633806),
    bg: const Color(0xFFFAEEDA),
  ),
  BodyReactionLevel.high => (
    label: 'Heart rate high',
    icon: Icons.monitor_heart_outlined,
    accent: const Color(0xFFE0703F),
    fg: const Color(0xFF712B13),
    bg: const Color(0xFFFAECE7),
  ),
  BodyReactionLevel.steady => null,
};

/// The small pill under a past event on My Day's timeline. A label, not a
/// button: tapping there opens the event, whose summary has the details.
class BodyReactionChip extends StatelessWidget {
  const BodyReactionChip({super.key, required this.reaction});

  final BodyReaction reaction;

  @override
  Widget build(BuildContext context) {
    final style = bodyReactionStyle(reaction.level);
    if (style == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? style.accent : style.fg;
    return Semantics(
      container: true,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: dark ? style.accent.withValues(alpha: .18) : style.bg,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(
              style.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
