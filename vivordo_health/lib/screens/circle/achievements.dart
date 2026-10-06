part of '../circle_screen.dart';

class _Achievement {
  const _Achievement({
    required this.id,
    required this.name,
    required this.requirement,
    required this.goalBadgeAsset,
    required this.earned,
    required this.progress,
    this.target = 1,
    this.earnedBadgeAsset,
    this.tier,
    this.goalTier,
    this.progressUnit,
    this.earnedAt,
  });

  final String id;
  final String name;
  final String requirement;
  final String goalBadgeAsset;
  final String? earnedBadgeAsset;
  final bool earned;
  final int progress;
  final int target;
  final String? tier;
  final String? goalTier;
  final String? progressUnit;
  final DateTime? earnedAt;

  bool get unlocked => earned || tier != null;
  bool get tiered => target > 1;
  bool get inProgress => !earned && (unlocked || progress > 0);
  double get fraction => target <= 0 ? 0 : (progress / target).clamp(0.0, 1.0);
  String get visibleBadgeAsset =>
      unlocked ? earnedBadgeAsset ?? goalBadgeAsset : goalBadgeAsset;
}

/// Milestones: one per one-time achievement, three per tiered one.
({int earned, int total, int inProgress}) _achievementTotals(
  List<_Achievement> achievements,
) {
  var earned = 0;
  var total = 0;
  for (final achievement in achievements) {
    if (achievement.tiered) {
      earned += _tierRankForDisplay(achievement.tier);
      total += 3;
    } else {
      if (achievement.earned) earned++;
      total++;
    }
  }
  return (
    earned: earned,
    total: total,
    inProgress: achievements.where((item) => item.inProgress).length,
  );
}

_Achievement? _nextAchievement(List<_Achievement> achievements) =>
    (achievements.where((item) => !item.earned).toList()
          ..sort((a, b) => b.fraction.compareTo(a.fraction)))
        .firstOrNull;

Future<List<_Achievement>> _loadAchievements(CircleProfile profile) async {
  final achievements = await AchievementService.reconcileAll(profile: profile);
  return [
    for (final achievement in achievements)
      _Achievement(
        id: achievement.id,
        name: achievement.name,
        requirement: achievement.requirement,
        goalBadgeAsset: achievement.goalBadgeAsset,
        earnedBadgeAsset: achievement.earnedBadgeAsset,
        earned: achievement.earned,
        progress: achievement.progress,
        target: achievement.target,
        tier: achievement.tier,
        goalTier: achievement.goalTier,
        progressUnit: achievement.progressUnit,
        earnedAt: achievement.earnedAt,
      ),
  ];
}

/// Builds another user's achievements from their stored documents; the
/// reconcile pass only runs for the signed-in user.
List<_Achievement> _profileAchievementsFromDocuments(
  CircleProfile profile,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
) {
  final byId = {for (final document in documents) document.id: document.data()};
  const oneTime = <(String, String, String, String)>[
    (
      'in_motion',
      'In Motion',
      'Complete your first activity',
      'assets/achievements/in_motion.png',
    ),
    (
      'first_pulse',
      'First Pulse',
      'Complete your first heart-rate scan',
      'assets/achievements/first_pulse.png',
    ),
    (
      'dear_diary',
      'Dear Diary',
      'Write your first journal entry',
      'assets/achievements/dear_diary.png',
    ),
    (
      'your_circle',
      'Your Circle',
      'Create your Circle profile',
      'assets/achievements/your_circle.png',
    ),
    (
      'better_together',
      'Better Together',
      'Add your first friend',
      'assets/achievements/better_together.png',
    ),
    (
      'day_planner',
      'Day Planner',
      'Connect your calendar',
      'assets/achievements/day_planner.png',
    ),
  ];
  final result = <_Achievement>[];
  for (final definition in oneTime) {
    final data = byId[definition.$1];
    final earned =
        data?['completed'] == true ||
        (definition.$1 == 'your_circle' && profile.username.trim().isNotEmpty);
    result.add(
      _Achievement(
        id: definition.$1,
        name: data?['name'] as String? ?? definition.$2,
        requirement: data?['requirement'] as String? ?? definition.$3,
        goalBadgeAsset: definition.$4,
        earned: earned,
        progress: (data?['progress'] as num?)?.round() ?? (earned ? 1 : 0),
        earnedAt: (data?['earnedAt'] as Timestamp?)?.toDate(),
      ),
    );
  }
  for (final definition in const [
    ('workout_momentum', 'Workout Momentum', 'workouts'),
    ('endurance', 'Endurance', 'activities'),
    ('pulse_check', 'Pulse Check', 'scans'),
    ('story_keeper', 'Story Keeper', 'entries'),
    ('mood_keeper', 'Mood Keeper', 'check-ins'),
    ('full_circle', 'Full Circle', 'days'),
  ]) {
    final data = byId[definition.$1];
    final tier = data?['tier'] as String?;
    final nextTier =
        data?['nextTier'] as String? ?? (tier == null ? 'bronze' : null);
    final shownTier = nextTier ?? tier ?? 'bronze';
    final defaultTarget = switch ((definition.$1, shownTier)) {
      ('pulse_check', 'bronze') => 10,
      ('pulse_check', 'silver') => 100,
      ('pulse_check', _) => 1000,
      ('story_keeper', 'bronze') => 5,
      ('story_keeper', 'silver') => 20,
      ('story_keeper', _) => 100,
      ('mood_keeper', 'bronze') => 5,
      ('mood_keeper', 'silver') => 20,
      ('mood_keeper', _) => 100,
      ('full_circle', 'bronze') => 7,
      ('full_circle', 'silver') => 30,
      ('full_circle', _) => 100,
      (_, 'bronze') => 5,
      (_, 'silver') => 10,
      _ => 100,
    };
    result.add(
      _Achievement(
        id: definition.$1,
        name: data?['name'] as String? ?? definition.$2,
        requirement:
            data?['requirement'] as String? ??
            (definition.$1 == 'full_circle'
                ? 'Fill all activity rings on $defaultTarget days'
                : definition.$1 == 'mood_keeper'
                ? 'Complete $defaultTarget mood check-ins'
                : 'Complete $defaultTarget ${definition.$3}'),
        goalBadgeAsset: 'assets/achievements/${definition.$1}_$shownTier.png',
        earnedBadgeAsset: tier == null
            ? null
            : 'assets/achievements/${definition.$1}_$tier.png',
        earned: data?['completed'] == true,
        progress: (data?['progress'] as num?)?.round() ?? 0,
        target: (data?['target'] as num?)?.round() ?? defaultTarget,
        tier: tier,
        goalTier: nextTier,
        progressUnit: data?['progressUnit'] as String? ?? definition.$3,
        earnedAt: (data?['earnedAt'] as Timestamp?)?.toDate(),
      ),
    );
  }
  return result;
}

void _openAchievements(BuildContext context, List<_Achievement> achievements) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AchievementsPage(achievements: achievements),
      ),
    );

/// The Challenges tab's link into your achievements.
class _AchievementsLinkCard extends StatefulWidget {
  const _AchievementsLinkCard({super.key, required this.profile});

  final CircleProfile profile;

  @override
  State<_AchievementsLinkCard> createState() => _AchievementsLinkCardState();
}

class _AchievementsLinkCardState extends State<_AchievementsLinkCard> {
  late Future<List<_Achievement>> _achievements = _loadAchievements(
    widget.profile,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<List<_Achievement>>(
    future: _achievements,
    builder: (context, snapshot) {
      final achievements = snapshot.data;
      final String detail;
      if (snapshot.hasError) {
        detail = 'Could not load. Tap to try again.';
      } else if (achievements == null) {
        detail = 'Loading…';
      } else {
        final totals = _achievementTotals(achievements);
        final next = _nextAchievement(achievements);
        detail = next == null
            ? '${totals.earned} earned · all complete'
            : '${totals.earned} earned · next: ${next.name} ${(next.fraction * 100).round()}%';
      }
      return _CircleCard(
        onTap: snapshot.hasError
            ? () => setState(
                () => _achievements = _loadAchievements(widget.profile),
              )
            : achievements == null
            ? null
            : () => _openAchievements(context, achievements),
        child: Row(
          children: [
            _IconTile(
              icon: Icons.workspace_premium_rounded,
              color: context.circle.accent,
              background: context.circle.accentTint,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your achievements',
                    style: TextStyle(
                      color: context.vivordoColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.muted),
          ],
        ),
      );
    },
  );
}

class _ProfileAchievementsSummary extends StatelessWidget {
  const _ProfileAchievementsSummary({required this.achievements});

  final List<_Achievement> achievements;

  @override
  Widget build(BuildContext context) {
    final totals = _achievementTotals(achievements);
    final recent =
        achievements.where((achievement) => achievement.unlocked).toList()
          ..sort(
            (a, b) => (b.earnedAt ?? DateTime(1970)).compareTo(
              a.earnedAt ?? DateTime(1970),
            ),
          );
    return _CircleCard(
      onTap: () => _openAchievements(context, achievements),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${totals.earned} of ${totals.total} earned',
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _LinkButton(
                label: 'View all',
                onTap: () => _openAchievements(context, achievements),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ProgressBar(
            value: totals.total == 0 ? 0 : totals.earned / totals.total,
          ),
          const SizedBox(height: 16),
          if (recent.isEmpty)
            Text(
              'Earned achievements will appear here.',
              style: TextStyle(color: context.muted, fontSize: 14),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final achievement in recent.take(3))
                  Expanded(
                    child: Column(
                      children: [
                        _AchievementBadge(
                          assetPath: achievement.visibleBadgeAsset,
                          size: 58,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          achievement.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.vivordoColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                for (var index = recent.length; index < 3; index++)
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
        ],
      ),
    );
  }
}

enum _AchievementFilter { all, earned, inProgress, locked }

class _AchievementsPage extends StatefulWidget {
  const _AchievementsPage({required this.achievements});

  final List<_Achievement> achievements;

  @override
  State<_AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<_AchievementsPage> {
  var _filter = _AchievementFilter.all;

  bool _matches(_Achievement achievement) => switch (_filter) {
    _AchievementFilter.all => true,
    _AchievementFilter.earned => achievement.unlocked,
    _AchievementFilter.inProgress => achievement.inProgress,
    _AchievementFilter.locked =>
      achievement.tiered
          ? !achievement.earned && achievement.goalTier != null
          : !achievement.unlocked && achievement.progress == 0,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final achievements = widget.achievements;
    final totals = _achievementTotals(achievements);
    final percent = totals.total == 0
        ? 0
        : (totals.earned / totals.total * 100).round();
    final next = _nextAchievement(achievements);
    final oneTime = achievements
        .where((item) => !item.tiered && _matches(item))
        .toList(growable: false);
    final tiered = achievements
        .where((item) => item.tiered && _matches(item))
        .toList(growable: false);
    return Scaffold(
      backgroundColor: colors.page,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
          children: [
            Row(
              children: [
                const _BackButton(),
                const SizedBox(width: 12),
                Text(
                  'Achievements',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _CircleCard(
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 92,
                    child: CustomPaint(
                      painter: _RingPainter(
                        progress: percent / 100,
                        color: _brand,
                        track: colors.cardMuted,
                        strokeWidth: 10,
                      ),
                      child: Center(
                        child: Text(
                          '$percent%',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${totals.earned} achievements',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'of ${totals.total} milestones · ${totals.inProgress} in progress',
                          style: TextStyle(color: context.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (next != null) ...[
              const SizedBox(height: 12),
              _CircleCard(
                color: context.circle.accentTint,
                borderColor: Colors.transparent,
                onTap: () => _showDetails(next, showGoalTier: true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UP NEXT',
                      style: TextStyle(
                        color: context.circle.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _AchievementBadge(
                          assetPath: next.goalBadgeAsset,
                          size: 52,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      next.goalTier == null
                                          ? next.name
                                          : '${next.name} · ${_tierLabel(next.goalTier!)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${next.progress}/${next.target}',
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _ProgressBar(
                                value: next.fraction,
                                background: colors.card,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in _AchievementFilter.values)
                  _FilterChip(
                    label: switch (filter) {
                      _AchievementFilter.all => 'All',
                      _AchievementFilter.earned => 'Earned',
                      _AchievementFilter.inProgress => 'In progress',
                      _AchievementFilter.locked => 'Locked',
                    },
                    selected: _filter == filter,
                    onTap: () => setState(() => _filter = filter),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const _SectionHeader('Tiered'),
            const SizedBox(height: 12),
            if (tiered.isEmpty)
              const _EmptyState(
                icon: Icons.filter_alt_off_rounded,
                title: 'Nothing matches this filter',
              )
            else
              GridView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tiered.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 168,
                ),
                itemBuilder: (context, index) => _TieredAchievementTile(
                  achievement: tiered[index],
                  showGoalTier: _filter == _AchievementFilter.locked,
                  onTap: () => _showDetails(
                    tiered[index],
                    showGoalTier: _filter == _AchievementFilter.locked,
                  ),
                ),
              ),
            const SizedBox(height: 22),
            const _SectionHeader('One-time'),
            const SizedBox(height: 12),
            if (oneTime.isEmpty)
              const _EmptyState(
                icon: Icons.filter_alt_off_rounded,
                title: 'Nothing matches this filter',
              )
            else
              GridView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: oneTime.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 138,
                ),
                itemBuilder: (context, index) => _OneTimeAchievementTile(
                  achievement: oneTime[index],
                  onTap: () => _showDetails(oneTime[index]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDetails(_Achievement achievement, {bool showGoalTier = false}) {
    final unit = achievement.progressUnit ?? 'activities';
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colors = sheetContext.vivordoColors;
        return Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SheetGrabber(),
                  const SizedBox(height: 20),
                  _AchievementCollectionBadge(
                    achievement: achievement,
                    size: 94,
                    showGoalTier: showGoalTier,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    achievement.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    achievement.tiered
                        ? '${_tierLabel(achievement.goalTier ?? achievement.tier ?? 'bronze')} goal: ${achievement.requirement}'
                        : achievement.requirement,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: sheetContext.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${achievement.progress} / ${achievement.target} $unit',
                    style: TextStyle(
                      color: sheetContext.circle.accent,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ProgressBar(value: achievement.fraction),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TieredAchievementTile extends StatelessWidget {
  const _TieredAchievementTile({
    required this.achievement,
    required this.showGoalTier,
    required this.onTap,
  });

  final _Achievement achievement;
  final bool showGoalTier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rank = _tierRankForDisplay(achievement.tier);
    final status = achievement.earned
        ? 'Gold earned'
        : achievement.tier != null && !showGoalTier
        ? '${_tierLabel(achievement.tier!)} · ${(achievement.fraction * 100).round()}% to next'
        : '${(achievement.fraction * 100).round()}% to ${_tierLabel(achievement.goalTier ?? 'bronze')}';
    return _CircleCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        children: [
          _AchievementCollectionBadge(
            achievement: achievement,
            size: 64,
            showGoalTier: showGoalTier,
          ),
          const SizedBox(height: 8),
          Text(
            achievement.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.vivordoColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var tier = 1; tier <= 3; tier++) ...[
                if (tier > 1) const SizedBox(width: 5),
                _TierDot(tier: _tierForRank(tier), earned: tier <= rank),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TierDot extends StatelessWidget {
  const _TierDot({required this.tier, required this.earned});

  final String tier;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final color = _achievementTierColor(tier);
    return Semantics(
      label: '${_tierLabel(tier)} ${earned ? 'earned' : 'not earned'}',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: earned ? color : Colors.transparent,
          border: Border.all(color: color, width: 1.5),
        ),
      ),
    );
  }
}

class _OneTimeAchievementTile extends StatelessWidget {
  const _OneTimeAchievementTile({
    required this.achievement,
    required this.onTap,
  });

  final _Achievement achievement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _CircleCard(
    padding: const EdgeInsets.fromLTRB(6, 14, 6, 10),
    onTap: onTap,
    child: Column(
      children: [
        _AchievementCollectionBadge(achievement: achievement, size: 56),
        const SizedBox(height: 8),
        Text(
          achievement.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              achievement.earned
                  ? Icons.check_circle_rounded
                  : Icons.lock_rounded,
              size: 13,
              color: achievement.earned
                  ? context.circle.success
                  : context.muted,
            ),
            const SizedBox(width: 3),
            Text(
              achievement.earned && achievement.earnedAt != null
                  ? DateFormat('MMM d').format(achievement.earnedAt!)
                  : achievement.earned
                  ? 'Earned'
                  : 'Locked',
              style: TextStyle(color: context.muted, fontSize: 11),
            ),
          ],
        ),
      ],
    ),
  );
}

class _AchievementCollectionBadge extends StatelessWidget {
  const _AchievementCollectionBadge({
    required this.achievement,
    required this.size,
    this.showGoalTier = false,
  });

  final _Achievement achievement;
  final double size;
  final bool showGoalTier;

  static const _greyscale = ColorFilter.matrix([
    .2126, .7152, .0722, 0, 0, //
    .2126, .7152, .0722, 0, 0, //
    .2126, .7152, .0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final locked =
        showGoalTier || (!achievement.unlocked && achievement.progress == 0);
    final badge = _AchievementBadge(
      assetPath: showGoalTier
          ? achievement.goalBadgeAsset
          : achievement.visibleBadgeAsset,
      size: size,
      locked: locked,
    );
    return locked
        ? ColorFiltered(colorFilter: _greyscale, child: badge)
        : badge;
  }
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({
    required this.assetPath,
    required this.size,
    this.locked = false,
  });

  final String assetPath;
  final double size;
  final bool locked;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: locked ? .35 : 1,
    child: ClipOval(
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _IconTile(
          icon: Icons.emoji_events_rounded,
          color: context.circle.accent,
          background: context.circle.accentTint,
          size: size,
        ),
      ),
    ),
  );
}
