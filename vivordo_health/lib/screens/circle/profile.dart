part of '../circle_screen.dart';

class CircleUserProfilePage extends StatefulWidget {
  const CircleUserProfilePage({
    required this.profile,
    required this.isOwner,
    super.key,
  });

  final CircleProfile profile;
  final bool isOwner;

  @override
  State<CircleUserProfilePage> createState() => _CircleUserProfilePageState();
}

class _CircleUserProfilePageState extends State<CircleUserProfilePage> {
  var _tab = 0;
  late final Stream<CircleProfile?> _profile =
      CircleProfileService.watchProfile(widget.profile.uid);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _achievementDocs =
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.profile.uid)
          .collection('achievements')
          .snapshots();

  bool get isOwner => widget.isOwner;

  @override
  Widget build(BuildContext context) => StreamBuilder<CircleProfile?>(
    stream: _profile,
    initialData: widget.profile,
    builder: (context, snapshot) {
      final profile = snapshot.data ?? widget.profile;
      return Scaffold(
        backgroundColor: context.vivordoColors.page,
        body: SafeArea(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _achievementDocs,
            builder: (context, achievementSnapshot) {
              final achievements = _profileAchievementsFromDocuments(
                profile,
                achievementSnapshot.data?.docs ?? const [],
              );
              return ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
                children: [
                  _buildHeader(context, profile),
                  const SizedBox(height: 10),
                  _ProfileHero(
                    profile: profile,
                    isOwner: isOwner,
                    onEdit: () => _edit(profile),
                  ),
                  if (!isOwner) ...[
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => _challenge(profile),
                      icon: const Icon(Icons.emoji_events_rounded, size: 19),
                      label: Text('Challenge ${profile.username}'),
                      style: _primaryButtonStyle(),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _ProfileStats(
                    profile: profile,
                    isOwner: isOwner,
                    achievementsEarned: achievements
                        .where((achievement) => achievement.unlocked)
                        .length,
                  ),
                  if (!isOwner) _FriendTodayCard(profile: profile),
                  const SizedBox(height: 18),
                  _FeaturedAchievementsCard(
                    profile: profile,
                    achievements: achievements,
                    onEdit: isOwner
                        ? () => _editFeatured(profile, achievements)
                        : null,
                  ),
                  const SizedBox(height: 22),
                  _SegmentedTabs(
                    labels: const ['Activity', 'Achievements'],
                    selectedIndex: _tab,
                    height: 46,
                    onChanged: (index) => setState(() => _tab = index),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == 0)
                    _ProfileActivityList(profile: profile)
                  else
                    _ProfileAchievementsSummary(achievements: achievements),
                ],
              );
            },
          ),
        ),
      );
    },
  );

  Widget _buildHeader(BuildContext context, CircleProfile profile) => Row(
    children: [
      if (Navigator.canPop(context)) const _BackButton(),
      const Spacer(),
      if (isOwner) ...[
        _IconCircleButton(
          icon: Icons.ios_share_rounded,
          tooltip: 'Copy invite',
          onTap: () => _copy(
            context,
            _inviteText(profile),
            'Invite copied to clipboard',
          ),
        ),
        const SizedBox(width: 8),
        _IconCircleButton(
          icon: Icons.edit_rounded,
          tooltip: 'Edit profile',
          onTap: () => _edit(profile),
        ),
        const SizedBox(width: 8),
        _IconCircleButton(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ] else
        _IconCircleButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'More options',
          onTap: () => _showFriendOptions(profile),
        ),
    ],
  );

  void _edit(CircleProfile profile) {
    if (!isOwner) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateCircleProfileScreen(initialProfile: profile),
      ),
    );
  }

  Future<void> _challenge(CircleProfile friend) async {
    final me = await CircleProfileService.watchCurrentProfile().first;
    if (!mounted || me == null) return;
    await _startNewChallenge(context, me, friend: friend);
  }

  Future<void> _showFriendOptions(CircleProfile profile) async {
    final palette = context.circle;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.vivordoColors.card,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_remove_rounded),
              title: const Text('Remove friend'),
              onTap: () => Navigator.pop(sheetContext, 'remove'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report profile'),
              onTap: () => Navigator.pop(sheetContext, 'report'),
            ),
            ListTile(
              leading: Icon(Icons.block_rounded, color: palette.danger),
              title: Text(
                'Block ${profile.username}',
                style: TextStyle(
                  color: palette.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () => Navigator.pop(sheetContext, 'block'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'remove':
        await _removeFriend(profile);
      case 'report':
        await _reportProfile(profile);
      case 'block':
        await _block(profile);
    }
  }

  Future<void> _removeFriend(CircleProfile profile) async {
    final confirmed = await _confirm(
      title: 'Remove ${profile.username}?',
      body:
          '${profile.username} will be removed from your Circle and their posts hidden. Two-person challenges will be cancelled and you will leave shared group challenges.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;
    try {
      await CircleProfileService.removeFriend(profile.uid);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('${profile.username} was removed.')),
      );
    } catch (error) {
      if (mounted) _showSnack(context, 'Could not remove friend: $error');
    }
  }

  Future<void> _block(CircleProfile profile) async {
    final confirmed = await _confirm(
      title: 'Block ${profile.username}?',
      body:
          'This removes your friendship and hides their posts. Two-person challenges will be cancelled and you will leave shared group challenges. They cannot find or add you while blocked. No block notification is sent.',
      action: 'Block',
    );
    if (!confirmed || !mounted) return;
    try {
      await CircleProfileService.blockUser(profile.uid);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('User blocked.')));
    } catch (_) {
      if (mounted) {
        _showSnack(context, 'Could not block user. Please try again.');
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD93B41),
              ),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _reportProfile(CircleProfile profile) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReportPostSheet(
        isProfile: true,
        onSubmit: (reason, details) async {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid == null) throw StateError('Sign in to report a profile.');
          await FirebaseFirestore.instance.collection('reports').add({
            'type': 'profile',
            'reporterUid': uid,
            'profileOwnerUid': profile.uid,
            'reason': reason,
            'details': details,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
        },
      ),
    );
    if (sent == true && mounted) {
      _showSnack(
        context,
        'Profile report submitted. Thank you for letting us know.',
      );
    }
  }

  Future<void> _editFeatured(
    CircleProfile profile,
    List<_Achievement> achievements,
  ) async {
    final earned = achievements
        .where((achievement) => achievement.unlocked)
        .toList(growable: false);
    if (earned.isEmpty) {
      _showSnack(context, 'Earn an achievement before featuring it.');
      return;
    }
    final earnedIds = {for (final achievement in earned) achievement.id};
    final initial = profile.featuredAchievementIds
        .where(earnedIds.contains)
        .take(3)
        .toList();
    if (initial.isEmpty) {
      initial.addAll(earned.take(3).map((achievement) => achievement.id));
    }
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FeaturedAchievementPicker(
        achievements: earned,
        initialSelection: initial,
      ),
    );
    if (selected == null) return;
    try {
      await CircleProfileService.updateFeaturedAchievements(selected);
    } catch (error) {
      if (mounted) {
        _showSnack(context, 'Could not update featured achievements: $error');
      }
    }
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.profile,
    required this.isOwner,
    required this.onEdit,
  });

  final CircleProfile profile;
  final bool isOwner;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final since =
        profile.createdAt ??
        (isOwner
            ? FirebaseAuth.instance.currentUser?.metadata.creationTime
            : null);
    final bio = profile.bio.trim();
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _brand, width: 3),
              ),
              child: _ProfileAvatar(profile: profile, radius: 48),
            ),
            if (isOwner)
              Positioned(
                right: -2,
                bottom: 2,
                child: _IconCircleButton(
                  icon: Icons.camera_alt_rounded,
                  tooltip: 'Change photo',
                  filled: true,
                  onTap: onEdit,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          profile.username,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        if (since != null) ...[
          const SizedBox(height: 4),
          Text(
            '${isOwner ? 'Member' : 'In Circle'} since ${DateFormat('MMM yyyy').format(since)}',
            style: TextStyle(color: context.muted, fontSize: 13),
          ),
        ],
        const SizedBox(height: 8),
        if (bio.isNotEmpty)
          Text(
            bio,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              height: 1.4,
            ),
          )
        else if (isOwner)
          _LinkButton(label: 'Add a short bio', onTap: onEdit),
      ],
    );
  }
}

class _ProfileStats extends StatefulWidget {
  const _ProfileStats({
    required this.profile,
    required this.isOwner,
    required this.achievementsEarned,
  });

  final CircleProfile profile;
  final bool isOwner;
  final int achievementsEarned;

  @override
  State<_ProfileStats> createState() => _ProfileStatsState();
}

class _ProfileStatsState extends State<_ProfileStats> {
  // Your own streak counts every saved workout, matching the Feed ring; a
  // friend's can only count what they shared.
  late final Stream<int> _streak = widget.isOwner
      ? WorkoutService.watchAll().map(WorkoutService.calculateCurrentStreak)
      : CircleProfileService.watchWorkoutStreak(widget.profile.uid);
  late final Stream<List<CircleProfile>> _friends =
      CircleProfileService.watchFriends();

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final isOwner = widget.isOwner;
    final palette = context.circle;
    final streak = StreamBuilder<int>(
      stream: _streak,
      initialData: 0,
      builder: (context, snapshot) => _StatTile(
        value: '${snapshot.data ?? 0}',
        label: 'Day streak',
        color: palette.streak,
      ),
    );
    final medals = _StatTile(
      value: '${profile.challengeMedalCount}',
      label: profile.challengeMedalCount == 1 ? 'Medal' : 'Medals',
      color: palette.gold,
    );
    return Row(
      children: [
        Expanded(
          child: isOwner
              ? StreamBuilder<List<CircleProfile>>(
                  stream: _friends,
                  builder: (context, snapshot) => _StatTile(
                    value: '${snapshot.data?.length ?? 0}',
                    label: (snapshot.data?.length ?? 0) == 1
                        ? 'Friend'
                        : 'Friends',
                    onTap: () => _openPeople(context, profile),
                  ),
                )
              : streak,
        ),
        const SizedBox(width: 10),
        Expanded(child: isOwner ? streak : medals),
        const SizedBox(width: 10),
        Expanded(
          child: isOwner
              ? medals
              : _StatTile(
                  value: '${widget.achievementsEarned}',
                  label: 'Achievements',
                ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    this.color,
    this.onTap,
  });

  final String value;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _CircleCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
    child: Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color ?? context.vivordoColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _FriendTodayCard extends StatefulWidget {
  const _FriendTodayCard({required this.profile});

  final CircleProfile profile;

  @override
  State<_FriendTodayCard> createState() => _FriendTodayCardState();
}

class _FriendTodayCardState extends State<_FriendTodayCard> {
  late final Stream<CircleDailyFitness?> _fitness =
      CircleProfileService.watchTodayFitness(widget.profile.uid);

  @override
  Widget build(BuildContext context) => StreamBuilder<CircleDailyFitness?>(
    stream: _fitness,
    builder: (context, snapshot) {
      final fitness = snapshot.data;
      if (fitness == null) return const SizedBox.shrink();
      Widget metric(
        String value,
        String label,
        int now,
        int goal,
        Color color,
      ) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: context.vivordoColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            _ProgressBar(
              value: goal <= 0 ? 0 : now / goal,
              color: color,
              height: 6,
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: context.muted, fontSize: 12)),
          ],
        ),
      );
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: _CircleCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader('Today'),
              const SizedBox(height: 12),
              Row(
                children: [
                  metric(
                    _numberFormat.format(fitness.steps),
                    'Steps',
                    fitness.steps,
                    fitness.stepsGoal,
                    _ringSteps,
                  ),
                  const SizedBox(width: 14),
                  metric(
                    '${fitness.activeCalories}',
                    'Active cal',
                    fitness.activeCalories,
                    fitness.activeCaloriesGoal,
                    _ringCalories,
                  ),
                  const SizedBox(width: 14),
                  metric(
                    '${fitness.exerciseMinutes} min',
                    'Exercise',
                    fitness.exerciseMinutes,
                    fitness.exerciseMinutesGoal,
                    _ringExercise,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _FeaturedAchievementsCard extends StatelessWidget {
  const _FeaturedAchievementsCard({
    required this.profile,
    required this.achievements,
    required this.onEdit,
  });

  final CircleProfile profile;
  final List<_Achievement> achievements;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final earned = achievements.where((achievement) => achievement.unlocked);
    final earnedById = {for (final item in earned) item.id: item};
    final selected = profile.featuredAchievementIds
        .map((id) => earnedById[id])
        .whereType<_Achievement>()
        .take(3)
        .toList(growable: false);
    final featured = selected.isEmpty
        ? earned.take(3).toList(growable: false)
        : selected;
    return _CircleCard(
      child: Column(
        children: [
          _SectionHeader(
            'Featured',
            trailing: onEdit == null
                ? null
                : _LinkButton(label: 'Edit', onTap: onEdit!),
          ),
          const SizedBox(height: 10),
          if (featured.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                onEdit == null
                    ? 'Nothing featured yet.'
                    : 'Earn an achievement to feature it here.',
                style: TextStyle(color: context.muted, fontSize: 14),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final achievement in featured)
                  Expanded(
                    child: Column(
                      children: [
                        _AchievementBadge(
                          assetPath: achievement.visibleBadgeAsset,
                          size: 68,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          achievement.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.vivordoColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (achievement.tier != null)
                          Text(
                            _tierLabel(achievement.tier!),
                            style: TextStyle(
                              color: context.muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                for (var index = featured.length; index < 3; index++)
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
        ],
      ),
    );
  }
}

class _ProfileActivityList extends StatefulWidget {
  const _ProfileActivityList({required this.profile});

  final CircleProfile profile;

  @override
  State<_ProfileActivityList> createState() => _ProfileActivityListState();
}

class _ProfileActivityListState extends State<_ProfileActivityList> {
  late final Stream<List<CircleActivity>> _activities =
      CircleProfileService.watchMyRecentActivities(
        widget.profile,
        days: 30,
        limit: 20,
      );

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CircleActivity>>(
    stream: _activities,
    builder: (context, snapshot) {
      if (!snapshot.hasData &&
          snapshot.connectionState == ConnectionState.waiting) {
        return const _Loading();
      }
      final activities = snapshot.data ?? const <CircleActivity>[];
      if (activities.isEmpty) {
        return const _EmptyState(
          icon: Icons.directions_run_rounded,
          title: 'No recent activity',
          detail: 'Shared workouts and journal entries will appear here.',
        );
      }
      return Column(
        children: [
          for (final activity in activities) ...[
            _ProfileActivityRow(activity: activity),
            const SizedBox(height: 10),
          ],
        ],
      );
    },
  );
}

class _ProfileActivityRow extends StatelessWidget {
  const _ProfileActivityRow({required this.activity});

  final CircleActivity activity;

  @override
  Widget build(BuildContext context) {
    final title = switch (activity.kind) {
      'achievement' =>
        activity.achievementTier == null
            ? 'Earned ${activity.name}'
            : 'Earned ${activity.name} · ${_tierLabel(activity.achievementTier!)}',
      'journal' => 'Journal Entry',
      _ => activity.name,
    };
    final details = activity.kind == 'journal'
        ? activity.mood ?? 'Shared reflection'
        : _activityDetails(activity);
    return _CircleCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => _openActivityDetails(context, activity),
      child: Row(
        children: [
          _ActivityVisual(activity: activity, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (details.isNotEmpty) details,
                    _relativeActivityTime(activity.day),
                  ].join(' · '),
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
  }
}

class _FeaturedAchievementPicker extends StatefulWidget {
  const _FeaturedAchievementPicker({
    required this.achievements,
    required this.initialSelection,
  });

  final List<_Achievement> achievements;
  final List<String> initialSelection;

  @override
  State<_FeaturedAchievementPicker> createState() =>
      _FeaturedAchievementPickerState();
}

class _FeaturedAchievementPickerState
    extends State<_FeaturedAchievementPicker> {
  late final List<String> _selected = widget.initialSelection.toList();

  int get _requiredCount => math.min(3, widget.achievements.length);

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetGrabber(),
              const SizedBox(height: 18),
              Text(
                'Featured achievements',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Choose $_requiredCount to show on your profile · ${_selected.length}/$_requiredCount selected',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: .82,
                  ),
                  itemCount: widget.achievements.length,
                  itemBuilder: (context, index) {
                    final achievement = widget.achievements[index];
                    final order = _selected.indexOf(achievement.id);
                    final selected = order >= 0;
                    return Material(
                      color: selected
                          ? context.circle.accentTint
                          : colors.cardMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: selected ? _brand : colors.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => setState(() {
                          if (_selected.remove(achievement.id)) return;
                          if (_selected.length < _requiredCount) {
                            _selected.add(achievement.id);
                          }
                        }),
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _AchievementBadge(
                                    assetPath: achievement.visibleBadgeAsset,
                                    size: 56,
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    achievement.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: CircleAvatar(
                                  radius: 11,
                                  backgroundColor: _brandStrong,
                                  child: Text(
                                    '${order + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.length == _requiredCount
                      ? () => Navigator.pop(context, _selected)
                      : null,
                  style: _primaryButtonStyle(),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
