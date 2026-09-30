part of '../circle_screen.dart';

/// Rings, bars and selection outlines.
const _brand = VivordoTheme.brand;

/// Fills behind white text; [_brand] is too light for 4.5:1 there.
const _brandStrong = Color(0xFF6250E8);

/// Circle's accent roles, tuned separately for light and dark so tints and
/// accent text stay legible on either page colour.
@immutable
class _CirclePalette {
  const _CirclePalette({
    required this.accent,
    required this.accentTint,
    required this.streak,
    required this.streakTint,
    required this.success,
    required this.successTint,
    required this.info,
    required this.infoTint,
    required this.pink,
    required this.pinkTint,
    required this.gold,
    required this.goldTint,
    required this.danger,
    required this.scrim,
  });

  final Color accent;
  final Color accentTint;
  final Color streak;
  final Color streakTint;
  final Color success;
  final Color successTint;
  final Color info;
  final Color infoTint;
  final Color pink;
  final Color pinkTint;
  final Color gold;
  final Color goldTint;
  final Color danger;
  final Color scrim;

  static const light = _CirclePalette(
    accent: Color(0xFF5A48E0),
    accentTint: Color(0xFFECE9FF),
    streak: Color(0xFFB45309),
    streakTint: Color(0xFFFFE8D0),
    success: Color(0xFF0B8A5B),
    successTint: Color(0xFFDDF7EC),
    info: Color(0xFF2563EB),
    infoTint: Color(0xFFE0EEFF),
    pink: Color(0xFFC2366F),
    pinkTint: Color(0xFFFDE3EF),
    gold: Color(0xFF8A6800),
    goldTint: Color(0xFFFFF4D6),
    danger: Color(0xFFD93B41),
    scrim: Color(0x521C1838),
  );

  static const dark = _CirclePalette(
    accent: Color(0xFFB8AEFF),
    accentTint: Color(0xFF2C2750),
    streak: Color(0xFFFFB36B),
    streakTint: Color(0xFF3A2A18),
    success: Color(0xFF3FD39A),
    successTint: Color(0xFF13362A),
    info: Color(0xFF8EC5FF),
    infoTint: Color(0xFF172A40),
    pink: Color(0xFFF5A3C7),
    pinkTint: Color(0xFF3A1F30),
    gold: Color(0xFFF1D27A),
    goldTint: Color(0xFF3A3218),
    danger: Color(0xFFFF7A7F),
    scrim: Color(0xA8050508),
  );
}

extension _CircleContext on BuildContext {
  _CirclePalette get circle => Theme.of(this).brightness == Brightness.dark
      ? _CirclePalette.dark
      : _CirclePalette.light;

  Color get muted => vivordoColors.textSecondary;
}

// Matches ActivityRingsPainter so dots and rings agree.
const _ringSteps = _brand;
const _ringCalories = Color(0xFFFB923C);
const _ringExercise = Color(0xFF34D399);

class _CircleCard extends StatelessWidget {
  const _CircleCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color ?? colors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor ?? colors.border),
        boxShadow: dark || color != null
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0D1C1838),
                  blurRadius: 18,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {this.badge = 0, this.trailing});

  final String label;
  final int badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          color: context.muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
      if (badge > 0) ...[const SizedBox(width: 8), _CountBadge(count: badge)],
      const Spacer(),
      ?trailing,
    ],
  );
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: context.circle.accent,
      minimumSize: const Size(44, 36),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    child: Text(label),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFD93B41),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        height: 1,
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.color, this.background, this.icon});

  final String label;
  final Color? color;
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? context.circle.accent;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: background ?? context.circle.accentTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconCircleButton extends StatelessWidget {
  const _IconCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final int badge;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: filled ? _brandStrong : colors.card,
            shape: CircleBorder(
              side: filled ? BorderSide.none : BorderSide(color: colors.border),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox.square(
                dimension: 44,
                child: Icon(
                  icon,
                  size: 21,
                  color: filled ? Colors.white : colors.textPrimary,
                ),
              ),
            ),
          ),
          if (badge > 0)
            Positioned(right: -4, top: -4, child: _CountBadge(count: badge)),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => _IconCircleButton(
    icon: Icons.chevron_left_rounded,
    tooltip: 'Back',
    onTap: () => Navigator.maybePop(context),
  );
}

/// A pill-shaped segmented control; [badges] pairs with [labels].
class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.badges = const [],
    this.height = 50,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<int> badges;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: Semantics(
                selected: index == selectedIndex,
                button: true,
                child: Material(
                  color: index == selectedIndex
                      ? _brandStrong
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => onChanged(index),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          labels[index],
                          style: TextStyle(
                            color: index == selectedIndex
                                ? Colors.white
                                : context.muted,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (index < badges.length && badges[index] > 0) ...[
                          const SizedBox(width: 8),
                          _CountBadge(count: badges[index]),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? _brandStrong : colors.card,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? _brandStrong : colors.border),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            // widthFactor keeps the chip hugging its label inside a Wrap.
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    this.detail,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _CircleCard(
    onTap: onTap,
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: context.vivordoColors.cardMuted,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: context.muted, size: 23),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 3),
                Text(
                  detail!,
                  style: TextStyle(
                    color: context.muted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading({this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: const Center(child: CircularProgressIndicator(color: _brand)),
  );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.value,
    this.color = _brand,
    this.background,
    this.height = 8,
  });

  final double value;
  final Color color;
  final Color? background;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: LinearProgressIndicator(
      value: value.isFinite ? value.clamp(0.0, 1.0) : 0,
      minHeight: height,
      color: color,
      backgroundColor: background ?? context.vivordoColors.cardMuted,
    ),
  );
}

/// A rounded-square icon on a tinted or solid background.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.color,
    required this.background,
    this.size = 46,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: Icon(icon, color: color, size: size * .48),
  );
}

class _StreakLabel extends StatelessWidget {
  const _StreakLabel({required this.days, this.size = 12});

  final int days;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.local_fire_department_rounded,
        size: size + 2,
        color: context.circle.streak,
      ),
      Text(
        '$days',
        style: TextStyle(
          color: context.circle.streak,
          fontSize: size,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

ButtonStyle _primaryButtonStyle({double height = 50}) => FilledButton.styleFrom(
  backgroundColor: _brandStrong,
  foregroundColor: Colors.white,
  disabledBackgroundColor: _brandStrong.withValues(alpha: .4),
  disabledForegroundColor: Colors.white70,
  minimumSize: Size(0, height),
  padding: const EdgeInsets.symmetric(horizontal: 16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
);

ButtonStyle _secondaryButtonStyle(BuildContext context, {double height = 50}) =>
    FilledButton.styleFrom(
      backgroundColor: context.vivordoColors.cardMuted,
      foregroundColor: context.vivordoColors.textPrimary,
      minimumSize: Size(0, height),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    );

const _avatarPastels = [
  Color(0xFFB8AEFF),
  Color(0xFF7EE2B8),
  Color(0xFFFFC58A),
  Color(0xFF8EC5FF),
  Color(0xFFF5A3C7),
  Color(0xFFE6E08A),
  Color(0xFFA6E3E9),
];

String _initials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'[\s_]+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  final second = words.length > 1 ? words[1].characters.first : '';
  return (first + second).toUpperCase();
}

/// A photo avatar that falls back to initials on a pastel picked from [seed],
/// so the same person keeps the same colour everywhere.
class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.name,
    required this.seed,
    required this.size,
    this.photoUrl,
    this.borderColor,
  });

  final String name;
  final String seed;
  final double size;
  final String? photoUrl;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final label = name.trim().startsWith('+') ? name.trim() : _initials(name);
    final pastel =
        _avatarPastels[seed.codeUnits.fold<int>(0, (a, b) => a + b) %
            _avatarPastels.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pastel,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 2),
        image: photoUrl == null
            ? null
            : DecorationImage(
                image: NetworkImage(photoUrl!),
                fit: BoxFit.cover,
              ),
      ),
      alignment: Alignment.center,
      child: photoUrl == null
          ? Text(
              label,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: const Color(0xFF15131F),
                fontSize: size * .32,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.profile,
    required this.radius,
    this.borderColor,
  });

  final CircleProfile profile;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => _InitialsAvatar(
    name: profile.username,
    seed: profile.uid,
    size: radius * 2,
    photoUrl: profile.photoUrl,
    borderColor: borderColor,
  );
}

/// Overlapping avatars for a group, with a "+N" chip past [max].
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.people, this.size = 28});

  final List<CircleProfile> people;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(3).toList(growable: false);
    final extra = people.length - shown.length;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    final step = size * .72;
    final border = context.vivordoColors.card;
    return SizedBox(
      width: size + step * (count - 1),
      height: size,
      child: Stack(
        children: [
          for (var index = 0; index < shown.length; index++)
            Positioned(
              left: step * index,
              child: _ProfileAvatar(
                profile: shown[index],
                radius: size / 2,
                borderColor: border,
              ),
            ),
          if (extra > 0)
            Positioned(
              left: step * shown.length,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.vivordoColors.cardMuted,
                  border: Border.all(color: border, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: size * .34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: context.vivordoColors.border,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}

String _relativeActivityTime(DateTime date) {
  final difference = DateTime.now().difference(date.toLocal());
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays == 1) return 'Yesterday';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return DateFormat('MMM d').format(date.toLocal());
}

String _tierLabel(String tier) => switch (tier) {
  'bronze' => 'Bronze',
  'silver' => 'Silver',
  'gold' => 'Gold',
  _ => tier,
};

int _tierRankForDisplay(String? tier) => switch (tier) {
  'bronze' => 1,
  'silver' => 2,
  'gold' => 3,
  _ => 0,
};

String _tierForRank(int rank) => switch (rank) {
  1 => 'bronze',
  2 => 'silver',
  _ => 'gold',
};

Color _achievementTierColor(String tier) => switch (tier) {
  'gold' => const Color(0xFFD99A17),
  'silver' => const Color(0xFF7F899B),
  _ => const Color(0xFFC86A31),
};

void _showSnack(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

void _openProfile(BuildContext context, CircleProfile profile) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CircleUserProfilePage(
        profile: profile,
        isOwner: FirebaseAuth.instance.currentUser?.uid == profile.uid,
      ),
    ),
  );
}
