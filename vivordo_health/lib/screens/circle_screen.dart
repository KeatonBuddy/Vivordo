import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/activity_goals_service.dart';
import '../src/services/calendar_service.dart';
import '../src/services/circle_challenge_service.dart';
import '../src/services/circle_profile_service.dart';
import '../src/services/outlook_calendar_service.dart';
import '../src/services/workout_service.dart';
import '../src/utils/workout_activity_visual.dart';
import 'create_circle_profile_screen.dart';
import 'fitness_screen.dart'
    show
        ActivityRingsPainter,
        WorkoutExerciseCatalogItem,
        workoutExerciseCatalog;
import 'profile_screen.dart';

class CircleScreen extends StatelessWidget {
  const CircleScreen({super.key});

  static const _purple = Color(0xFF6250E8);
  static const _muted = Color(0xFF7F7F95);

  @override
  Widget build(BuildContext context) => StreamBuilder<CircleProfile?>(
    stream: CircleProfileService.watchCurrentProfile(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return Scaffold(
          backgroundColor: context.vivordoColors.page,
          body: const Center(child: CircularProgressIndicator(color: _purple)),
        );
      }
      final profile = snapshot.data;
      return profile == null
          ? _buildOnboarding(context)
          : _CircleProfileHome(profile: profile);
    },
  );

  Widget _buildOnboarding(BuildContext context) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    appBar: AppBar(
      backgroundColor: context.vivordoColors.page,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 4,
      title: const Text(
        'Your Circle',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -.6,
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          decoration: BoxDecoration(
            color: context.vivordoColors.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: context.vivordoColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              const _CircleOnboardingGraphic(),
              const SizedBox(height: 22),
              const Text(
                'Better together',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Share progress, encourage friends,\nand build healthy habits together.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 24),
              const _CircleBenefit(
                icon: Icons.lock_rounded,
                iconColor: _purple,
                iconBackground: Color(0xFFECE9FF),
                title: 'Private by default',
                detail: 'Only your circle sees what you share',
              ),
              const Divider(height: 1, indent: 0, endIndent: 0),
              const _CircleBenefit(
                icon: Icons.favorite_rounded,
                iconColor: Color(0xFF10B77A),
                iconBackground: Color(0xFFDDF7EC),
                title: 'Support each other',
                detail: 'Send encouragement without comparison',
              ),
              const Divider(height: 1, indent: 0, endIndent: 0),
              const _CircleBenefit(
                icon: Icons.groups_rounded,
                iconColor: Color(0xFFF28A18),
                iconBackground: Color(0xFFFFE8D0),
                title: 'Grow together',
                detail: 'Celebrate healthy habits and milestones',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CreateCircleProfileScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.person_rounded),
                  label: const Text('Create Profile'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text(
                  'Maybe Later',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text(
                'You control what you share.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CircleProfileHome extends StatefulWidget {
  const _CircleProfileHome({required this.profile});

  final CircleProfile profile;

  @override
  State<_CircleProfileHome> createState() => _CircleProfileHomeState();
}

class _CircleProfileHomeState extends State<_CircleProfileHome> {
  var _selectedTab = 0;
  late final Stream<List<CircleChallengeMembership>> _challengeMemberships;
  late final Stream<int> _incomingFriendRequestCount;

  CircleProfile get profile => widget.profile;

  @override
  void initState() {
    super.initState();
    _challengeMemberships = CircleChallengeService.watchMemberships();
    _incomingFriendRequestCount =
        CircleProfileService.watchIncomingRequestCount();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    appBar: AppBar(
      backgroundColor: context.vivordoColors.page,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 20,
      title: const Text(
        'Your Circle',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -.7,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _openProfile,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: _ProfileAvatar(profile: profile, radius: 21),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: StreamBuilder<List<CircleChallengeMembership>>(
        stream: _challengeMemberships,
        builder: (context, challengeSnapshot) {
          final memberships = challengeSnapshot.data ?? const [];
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
            children: [
              StreamBuilder<int>(
                stream: _incomingFriendRequestCount,
                initialData: 0,
                builder: (context, friendRequestSnapshot) => _CircleTabs(
                  selectedIndex: _selectedTab,
                  challengeInviteCount: memberships
                      .where((membership) => membership.isInvite)
                      .length,
                  friendRequestCount: friendRequestSnapshot.data ?? 0,
                  onChanged: (index) => setState(() => _selectedTab = index),
                ),
              ),
              const SizedBox(height: 26),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_selectedTab) {
                  0 => _ActivityTab(
                    profile: profile,
                    key: const ValueKey('activity'),
                  ),
                  1 => _FriendsTab(
                    profile: profile,
                    key: const ValueKey('friends'),
                  ),
                  _ => _ChallengesTab(
                    profile: profile,
                    memberships: memberships,
                    membershipsLoading:
                        challengeSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        !challengeSnapshot.hasData,
                    membershipsError: challengeSnapshot.error,
                    key: const ValueKey('challenges'),
                  ),
                },
              ),
            ],
          );
        },
      ),
    ),
  );

  void _openProfile() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CircleUserProfilePage(profile: profile, isOwner: true),
    ),
  );
}

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
  var _selectedTab = 0;

  @override
  Widget build(BuildContext context) => StreamBuilder<CircleProfile?>(
    stream: CircleProfileService.watchProfile(widget.profile.uid),
    initialData: widget.profile,
    builder: (context, snapshot) =>
        _buildPage(context, snapshot.data ?? widget.profile),
  );

  Widget _buildPage(BuildContext context, CircleProfile profile) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    body: SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(profile.uid)
            .collection('achievements')
            .snapshots(),
        builder: (context, snapshot) {
          final achievements = _profileAchievementsFromDocuments(
            profile,
            snapshot.data?.docs ?? const [],
          );
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 42),
            children: [
              _CircleProfileHeader(isOwner: widget.isOwner),
              const SizedBox(height: 22),
              _CircleProfileHero(
                profile: profile,
                isOwner: widget.isOwner,
                onEdit: () => _editProfile(profile),
                onShare: () => _shareProfile(profile),
              ),
              const SizedBox(height: 26),
              _CircleProfileFeaturedAchievements(
                profile: profile,
                achievements: achievements,
                onEdit: widget.isOwner
                    ? () => _editFeaturedAchievements(profile, achievements)
                    : null,
              ),
              const SizedBox(height: 20),
              _CircleProfileTabs(
                selectedIndex: _selectedTab,
                onChanged: (index) => setState(() => _selectedTab = index),
              ),
              const SizedBox(height: 26),
              switch (_selectedTab) {
                0 => _CircleProfileOverview(profile: profile),
                1 => _CircleProfileAchievementsTab(
                  achievements: achievements,
                  onOpenAll: () => _openAchievements(achievements),
                ),
                _ => _CircleProfileActivityTab(profile: profile),
              },
              if (!widget.isOwner) ...[
                const SizedBox(height: 26),
                _RemoveCircleFriendButton(profile: profile),
              ],
            ],
          );
        },
      ),
    ),
  );

  void _editProfile(CircleProfile profile) {
    if (!widget.isOwner) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreateCircleProfileScreen(initialProfile: profile),
      ),
    );
  }

  Future<void> _shareProfile(CircleProfile profile) async {
    final shareText =
        'Join ${profile.username} on Vivordo Circle. Friend code: ${profile.friendCode}';
    await Clipboard.setData(ClipboardData(text: shareText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile invite copied to clipboard')),
    );
  }

  void _openAchievements(List<_Achievement> achievements) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AchievementsPage(achievements: achievements),
      ),
    );
  }

  Future<void> _editFeaturedAchievements(
    CircleProfile profile,
    List<_Achievement> achievements,
  ) async {
    final earned = achievements
        .where((achievement) => achievement.unlocked)
        .toList(growable: false);
    if (earned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Earn an achievement before featuring it.'),
        ),
      );
      return;
    }
    final earnedIds = earned.map((achievement) => achievement.id).toSet();
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
      builder: (sheetContext) => _FeaturedAchievementPicker(
        achievements: earned,
        initialSelection: initial,
      ),
    );
    if (selected == null) return;
    try {
      await CircleProfileService.updateFeaturedAchievements(selected);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update featured achievements: $error'),
        ),
      );
    }
  }
}

class _CircleProfileHeader extends StatelessWidget {
  const _CircleProfileHeader({required this.isOwner});

  final bool isOwner;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _ProfileHeaderButton(
        icon: Icons.chevron_left_rounded,
        onTap: () => Navigator.maybePop(context),
      ),
      const SizedBox(width: 18),
      Expanded(
        child: Text(
          'Profile',
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 31,
            fontWeight: FontWeight.w900,
            letterSpacing: -.7,
          ),
        ),
      ),
      if (isOwner)
        _ProfileHeaderButton(
          icon: Icons.settings_outlined,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
    ],
  );
}

class _ProfileHeaderButton extends StatelessWidget {
  const _ProfileHeaderButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.vivordoColors.card,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 50,
        height: 50,
        child: Icon(icon, color: context.vivordoColors.textPrimary, size: 27),
      ),
    ),
  );
}

class _CircleProfileHero extends StatelessWidget {
  const _CircleProfileHero({
    required this.profile,
    required this.isOwner,
    required this.onEdit,
    required this.onShare,
  });

  final CircleProfile profile;
  final bool isOwner;
  final VoidCallback onEdit;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final authCreatedAt = isOwner
        ? FirebaseAuth.instance.currentUser?.metadata.creationTime
        : null;
    final memberSince = profile.createdAt ?? authCreatedAt;
    return _CircleCard(
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _ProfileAvatar(profile: profile, radius: 54),
              if (isOwner)
                Positioned(
                  right: -4,
                  bottom: 2,
                  child: Material(
                    color: CircleScreen._purple,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: onEdit,
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            profile.username,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.vivordoColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            profile.bio.trim().isEmpty
                ? 'Building healthier habits, one day at a time.'
                : profile.bio.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CircleScreen._muted,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          _ChallengeMedalCount(count: profile.challengeMedalCount),
          const SizedBox(height: 14),
          _CircleProfileStats(
            profile: profile,
            isOwner: isOwner,
            memberSince: memberSince,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (isOwner) ...[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit Profile'),
                    style: FilledButton.styleFrom(
                      backgroundColor: CircleScreen._purple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Share Profile'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CircleScreen._purple,
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: CircleScreen._purple),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChallengeMedalCount extends StatelessWidget {
  const _ChallengeMedalCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(7, 6, 14, 6),
    decoration: BoxDecoration(
      color: CircleScreen._purple.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: CircleScreen._purple.withValues(alpha: .18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/achievements/challenge_medal.png',
          width: 40,
          height: 40,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 8),
        Text(
          '$count ${count == 1 ? 'challenge medal' : 'challenge medals'}',
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _CircleProfileStats extends StatelessWidget {
  const _CircleProfileStats({
    required this.profile,
    required this.isOwner,
    required this.memberSince,
  });

  final CircleProfile profile;
  final bool isOwner;
  final DateTime? memberSince;

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: isOwner
        ? CircleProfileService.watchFriends().map((friends) => friends.length)
        : CircleProfileService.watchWorkoutStreak(profile.uid),
    initialData: 0,
    builder: (context, snapshot) {
      final count = snapshot.data ?? 0;
      final firstStat = isOwner
          ? '$count ${count == 1 ? 'friend' : 'friends'}'
          : '$count-day streak';
      final joined = memberSince == null
          ? 'Vivordo member'
          : 'Member since ${DateFormat('MMM yyyy').format(memberSince!)}';
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(firstStat, style: const TextStyle(color: CircleScreen._muted)),
          const Text('•', style: TextStyle(color: CircleScreen._muted)),
          Text(joined, style: const TextStyle(color: CircleScreen._muted)),
        ],
      );
    },
  );
}

class _CircleProfileFeaturedAchievements extends StatelessWidget {
  const _CircleProfileFeaturedAchievements({
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
    final earnedById = {
      for (final achievement in earned) achievement.id: achievement,
    };
    final selected = profile.featuredAchievementIds
        .map((id) => earnedById[id])
        .whereType<_Achievement>()
        .take(3)
        .toList(growable: false);
    final featured = selected.isEmpty
        ? earned.take(3).toList(growable: false)
        : selected;
    final oneTime = achievements.where((item) => item.target == 1).toList();
    final tiered = achievements.where((item) => item.target > 1).toList();
    final earnedCount =
        oneTime.where((item) => item.earned).length +
        tiered.fold<int>(
          0,
          (total, item) => total + _tierRankForDisplay(item.tier),
        );
    final total = oneTime.length + tiered.length * 3;
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: _CircleSectionTitle('FEATURED ACHIEVEMENTS')),
            if (onEdit != null)
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 17),
                label: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _CircleCard(
          child: Column(
            children: [
              if (featured.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'Earn an achievement to feature it here.',
                    style: TextStyle(color: CircleScreen._muted),
                  ),
                )
              else
                Row(
                  children: [
                    for (var index = 0; index < featured.length; index++) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          children: [
                            _AchievementBadge(
                              assetPath: featured[index].visibleBadgeAsset,
                              size: 72,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              featured[index].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: 15),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : earnedCount / total,
                  minHeight: 7,
                  backgroundColor: context.vivordoColors.cardMuted,
                  color: CircleScreen._purple,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$earnedCount of $total achievements earned',
                  style: const TextStyle(
                    color: CircleScreen._muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
  late final List<String> _selected;

  int get _requiredCount => math.min(3, widget.achievements.length);

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection.toList();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: context.vivordoColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Featured Achievements',
            style: TextStyle(
              color: context.vivordoColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Choose $_requiredCount earned ${_requiredCount == 1 ? 'achievement' : 'achievements'} to display on your profile.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.vivordoColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            '${_selected.length} / $_requiredCount selected',
            style: const TextStyle(
              color: CircleScreen._purple,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: GridView.builder(
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
                final selectedIndex = _selected.indexOf(achievement.id);
                final isSelected = selectedIndex >= 0;
                return Material(
                  color: isSelected
                      ? CircleScreen._purple.withValues(alpha: .12)
                      : context.vivordoColors.cardMuted,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: () => _toggle(achievement.id),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? CircleScreen._purple
                              : context.vivordoColors.border,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _AchievementBadge(
                                assetPath: achievement.visibleBadgeAsset,
                                size: 58,
                              ),
                              const SizedBox(height: 7),
                              SizedBox(
                                width: double.infinity,
                                child: Text(
                                  achievement.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isSelected)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: CircleScreen._purple,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${selectedIndex + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected.length == _requiredCount
                  ? () => Navigator.pop(context, _selected)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: CircleScreen._purple,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                'Save Featured Achievements',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _toggle(String id) {
    setState(() {
      if (_selected.remove(id)) return;
      if (_selected.length < _requiredCount) _selected.add(id);
    });
  }
}

class _CircleProfileTabs extends StatelessWidget {
  const _CircleProfileTabs({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < 3; index++) ...[
        if (index > 0) const SizedBox(width: 8),
        Expanded(
          child: Material(
            color: selectedIndex == index
                ? CircleScreen._purple
                : context.vivordoColors.card,
            borderRadius: BorderRadius.circular(15),
            child: InkWell(
              onTap: () => onChanged(index),
              borderRadius: BorderRadius.circular(15),
              child: SizedBox(
                height: 50,
                child: Center(
                  child: Text(
                    const ['Overview', 'Achievements', 'Activity'][index],
                    style: TextStyle(
                      color: selectedIndex == index
                          ? Colors.white
                          : CircleScreen._muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class _CircleProfileOverview extends StatelessWidget {
  const _CircleProfileOverview({required this.profile});

  final CircleProfile profile;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _CircleSectionTitle('ACTIVE CHALLENGE'),
      const SizedBox(height: 12),
      const _ChallengeEmptyCard(
        icon: Icons.groups_rounded,
        title: 'No active challenge',
        detail: 'Active Circle challenges will appear here later.',
      ),
      const SizedBox(height: 26),
      const _CircleSectionTitle('RECENT ACTIVITY'),
      const SizedBox(height: 12),
      _CircleProfileActivityList(profile: profile, limit: 3),
    ],
  );
}

class _CircleProfileAchievementsTab extends StatelessWidget {
  const _CircleProfileAchievementsTab({
    required this.achievements,
    required this.onOpenAll,
  });

  final List<_Achievement> achievements;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final earned = achievements
        .where((achievement) => achievement.unlocked)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _CircleSectionTitle('ACHIEVEMENTS')),
            TextButton(onPressed: onOpenAll, child: const Text('View All')),
          ],
        ),
        const SizedBox(height: 12),
        if (earned.isEmpty)
          const _ChallengeEmptyCard(
            icon: Icons.emoji_events_rounded,
            title: 'No achievements yet',
            detail: 'Earned achievements will appear here.',
          )
        else
          _RecentlyEarnedCard(achievements: earned.take(3).toList()),
      ],
    );
  }
}

class _CircleProfileActivityTab extends StatelessWidget {
  const _CircleProfileActivityTab({required this.profile});

  final CircleProfile profile;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _CircleSectionTitle('ACTIVITY'),
      const SizedBox(height: 12),
      _CircleProfileActivityList(profile: profile, scrollable: true),
    ],
  );
}

class _CircleProfileActivityList extends StatelessWidget {
  const _CircleProfileActivityList({
    required this.profile,
    this.limit,
    this.scrollable = false,
  });

  final CircleProfile profile;
  final int? limit;
  final bool scrollable;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CircleActivity>>(
    stream: CircleProfileService.watchMyRecentActivities(
      profile,
      days: scrollable ? null : 30,
      limit: scrollable ? null : 20,
    ),
    builder: (context, snapshot) {
      if (!snapshot.hasData &&
          snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: CircularProgressIndicator(color: CircleScreen._purple),
          ),
        );
      }
      final all = snapshot.data ?? const <CircleActivity>[];
      final activities = limit == null ? all : all.take(limit!).toList();
      if (activities.isEmpty) {
        return const _ChallengeEmptyCard(
          icon: Icons.directions_run_rounded,
          title: 'No recent activity',
          detail: 'Shared workouts and journal entries will appear here.',
        );
      }
      if (scrollable) {
        return SizedBox(
          height: 340,
          child: ListView.separated(
            primary: false,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 4),
            itemCount: activities.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) =>
                _CircleProfileActivityTile(activity: activities[index]),
          ),
        );
      }
      return Column(
        children: [
          for (var index = 0; index < activities.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            _CircleProfileActivityTile(activity: activities[index]),
          ],
        ],
      );
    },
  );
}

class _CircleProfileActivityTile extends StatelessWidget {
  const _CircleProfileActivityTile({required this.activity});

  final CircleActivity activity;

  @override
  Widget build(BuildContext context) {
    final isJournal = activity.kind == 'journal';
    final isAchievement = activity.kind == 'achievement';
    final visual = workoutActivityVisual(
      activity.name,
      category: activity.activityCategory,
    );
    return Material(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _openCircleActivityDetails(context, activity),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (isAchievement)
                _AchievementActivityBadge(activity: activity, size: 50)
              else
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: (isJournal ? CircleScreen._purple : visual.color)
                        .withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isJournal ? Icons.menu_book_rounded : visual.icon,
                    color: isJournal ? CircleScreen._purple : visual.color,
                  ),
                ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isJournal
                          ? 'Journal Entry'
                          : isAchievement
                          ? 'Earned ${activity.name}'
                          : activity.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isJournal
                          ? activity.mood ?? 'Shared reflection'
                          : isAchievement
                          ? '${activity.achievementTier == null ? 'Achievement unlocked' : '${_tierLabel(activity.achievementTier!)} tier unlocked'}  •  ${_relativeActivityTime(activity.day)}'
                          : '${activity.minutes} min  •  ${_relativeActivityTime(activity.day)}',
                      style: const TextStyle(color: CircleScreen._muted),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: CircleScreen._muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemoveCircleFriendButton extends StatefulWidget {
  const _RemoveCircleFriendButton({required this.profile});

  final CircleProfile profile;

  @override
  State<_RemoveCircleFriendButton> createState() =>
      _RemoveCircleFriendButtonState();
}

class _RemoveCircleFriendButtonState extends State<_RemoveCircleFriendButton> {
  var _removing = false;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: _removing ? null : _remove,
      icon: _removing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.person_remove_rounded),
      label: Text(_removing ? 'Removing…' : 'Remove Friend'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: BorderSide(color: Colors.red.withValues(alpha: .5)),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
  );

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${widget.profile.username}?'),
        content: Text(
          '${widget.profile.username} will be removed from your Circle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    try {
      await CircleProfileService.removeFriend(widget.profile.uid);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _removing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove friend: $error')),
      );
    }
  }
}

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
  ]) {
    final data = byId[definition.$1];
    final tier = data?['tier'] as String?;
    final nextTier =
        data?['nextTier'] as String? ?? (tier == null ? 'bronze' : null);
    final shownTier = nextTier ?? tier ?? 'bronze';
    final assetPrefix = definition.$1;
    final defaultTarget = switch ((definition.$1, shownTier)) {
      ('pulse_check', 'bronze') => 10,
      ('pulse_check', 'silver') => 100,
      ('pulse_check', _) => 1000,
      ('story_keeper', 'bronze') => 5,
      ('story_keeper', 'silver') => 20,
      ('story_keeper', _) => 100,
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
            'Complete $defaultTarget ${definition.$3}',
        goalBadgeAsset: 'assets/achievements/${assetPrefix}_$shownTier.png',
        earnedBadgeAsset: tier == null
            ? null
            : 'assets/achievements/${assetPrefix}_$tier.png',
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

class _CircleTabs extends StatelessWidget {
  const _CircleTabs({
    required this.selectedIndex,
    required this.challengeInviteCount,
    required this.friendRequestCount,
    required this.onChanged,
  });

  final int selectedIndex;
  final int challengeInviteCount;
  final int friendRequestCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 54,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Row(
      children: [
        _tab('Activity', 0),
        _tab('Goals', 2, badgeCount: challengeInviteCount),
        _tab('Friends', 1, badgeCount: friendRequestCount),
      ],
    ),
  );

  Widget _tab(String label, int index, {int badgeCount = 0}) => Expanded(
    child: Material(
      color: selectedIndex == index ? CircleScreen._purple : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => onChanged(index),
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsets.only(right: badgeCount > 0 ? 12 : 0),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selectedIndex == index
                        ? Colors.white
                        : CircleScreen._muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (badgeCount > 0)
                Positioned(
                  right: -8,
                  top: -8,
                  child: _ChallengeInviteBadge(count: badgeCount),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ChallengeInviteBadge extends StatelessWidget {
  const _ChallengeInviteBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFFF5264),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.vivordoColors.card, width: 1.5),
    ),
    alignment: Alignment.center,
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        height: 1,
      ),
    ),
  );
}

class _ChallengesTab extends StatefulWidget {
  const _ChallengesTab({
    required this.profile,
    required this.memberships,
    required this.membershipsLoading,
    required this.membershipsError,
    super.key,
  });

  final CircleProfile profile;
  final List<CircleChallengeMembership> memberships;
  final bool membershipsLoading;
  final Object? membershipsError;

  @override
  State<_ChallengesTab> createState() => _ChallengesTabState();
}

class _ChallengesTabState extends State<_ChallengesTab> {
  late Future<List<_Achievement>> _achievements;

  @override
  void initState() {
    super.initState();
    _achievements = _loadAchievements();
  }

  Future<List<_Achievement>> _loadAchievements() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];

    final firestore = FirebaseFirestore.instance;
    final results = await Future.wait<Object>([
      firestore.collection('users').doc(user.uid).collection('workouts').get(),
      firestore
          .collection('users')
          .doc(user.uid)
          .collection('metrics_daily')
          .get(),
      firestore
          .collection('users')
          .doc(user.uid)
          .collection('journal_entries')
          .count()
          .get(),
      firestore
          .collection('users')
          .doc(user.uid)
          .collection('achievements')
          .get(),
      CircleProfileService.watchFriends().first,
      _hasGoogleCalendar(),
      _hasOutlookCalendar(),
    ]);

    final workouts = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final metricDays = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final journalEntryCount =
        (results[2] as AggregateQuerySnapshot).count?.toInt() ?? 0;
    final savedAchievements = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final friends = results[4] as List<CircleProfile>;
    final googleCalendarConnected = results[5] as bool;
    final outlookCalendarConnected = results[6] as bool;
    final savedById = {
      for (final document in savedAchievements.docs) document.id: document,
    };
    final heartRateScanCount = metricDays.docs.fold<int>(0, (total, document) {
      final scan = document.data()['heart_rate_scan'];
      if (scan is! Map) return total;
      final entries = scan['entries'];
      if (entries is List && entries.isNotEmpty) {
        return total + entries.length;
      }
      // Older daily records stored only the aggregate camera reading.
      if (scan['source'] == 'camera_ppg' || scan['avg'] is num) {
        return total + 1;
      }
      return total;
    });
    final completedHeartScan = heartRateScanCount > 0;
    final cardioOrSportsActivityCount = workouts.docs.where((document) {
      final data = document.data();
      final activityCategory = data['activityCategory'] as String?;
      if (activityCategory == 'Cardio' || activityCategory == 'Sports') {
        return true;
      }
      final exercises = (data['exercises'] as List? ?? const [])
          .whereType<Map>()
          .toList(growable: false);
      if (exercises.isEmpty) return false;
      return exercises.every((exercise) {
        final category = exercise['category'] as String?;
        return category == 'Cardio' || category == 'Sports';
      });
    }).length;
    final strengthWorkoutCount =
        workouts.docs.length - cardioOrSportsActivityCount;
    final savedMomentumTier =
        savedById['workout_momentum']?.data()['tier'] as String?;
    final calculatedMomentumTier = strengthWorkoutCount >= 100
        ? 'gold'
        : strengthWorkoutCount >= 10
        ? 'silver'
        : strengthWorkoutCount >= 5
        ? 'bronze'
        : null;
    final momentumTier = _highestTier(
      savedMomentumTier,
      calculatedMomentumTier,
    );
    final momentumTarget = switch (momentumTier) {
      'gold' => 100,
      'silver' => 100,
      'bronze' => 10,
      _ => 5,
    };
    final momentumGoalBadge = switch (momentumTier) {
      'gold' => 'assets/achievements/workout_momentum_gold.png',
      'silver' => 'assets/achievements/workout_momentum_gold.png',
      'bronze' => 'assets/achievements/workout_momentum_silver.png',
      _ => 'assets/achievements/workout_momentum_bronze.png',
    };
    final momentumEarnedBadge = switch (momentumTier) {
      'gold' => 'assets/achievements/workout_momentum_gold.png',
      'silver' => 'assets/achievements/workout_momentum_silver.png',
      _ => 'assets/achievements/workout_momentum_bronze.png',
    };
    final momentumGoalTier = switch (momentumTier) {
      'gold' => null,
      'silver' => 'gold',
      'bronze' => 'silver',
      _ => 'bronze',
    };
    final savedEnduranceTier =
        savedById['endurance']?.data()['tier'] as String?;
    final calculatedEnduranceTier = cardioOrSportsActivityCount >= 100
        ? 'gold'
        : cardioOrSportsActivityCount >= 10
        ? 'silver'
        : cardioOrSportsActivityCount >= 5
        ? 'bronze'
        : null;
    final enduranceTier = _highestTier(
      savedEnduranceTier,
      calculatedEnduranceTier,
    );
    final enduranceTarget = switch (enduranceTier) {
      'gold' => 100,
      'silver' => 100,
      'bronze' => 10,
      _ => 5,
    };
    final enduranceGoalBadge = switch (enduranceTier) {
      'gold' => 'assets/achievements/endurance_gold.png',
      'silver' => 'assets/achievements/endurance_gold.png',
      'bronze' => 'assets/achievements/endurance_silver.png',
      _ => 'assets/achievements/endurance_bronze.png',
    };
    final enduranceEarnedBadge = switch (enduranceTier) {
      'gold' => 'assets/achievements/endurance_gold.png',
      'silver' => 'assets/achievements/endurance_silver.png',
      _ => 'assets/achievements/endurance_bronze.png',
    };
    final enduranceGoalTier = switch (enduranceTier) {
      'gold' => null,
      'silver' => 'gold',
      'bronze' => 'silver',
      _ => 'bronze',
    };
    final savedPulseCheckTier =
        savedById['pulse_check']?.data()['tier'] as String?;
    final calculatedPulseCheckTier = heartRateScanCount >= 1000
        ? 'gold'
        : heartRateScanCount >= 100
        ? 'silver'
        : heartRateScanCount >= 10
        ? 'bronze'
        : null;
    final pulseCheckTier = _highestTier(
      savedPulseCheckTier,
      calculatedPulseCheckTier,
    );
    final pulseCheckTarget = switch (pulseCheckTier) {
      'gold' => 1000,
      'silver' => 1000,
      'bronze' => 100,
      _ => 10,
    };
    final pulseCheckGoalBadge = switch (pulseCheckTier) {
      'gold' => 'assets/achievements/pulse_check_gold.png',
      'silver' => 'assets/achievements/pulse_check_gold.png',
      'bronze' => 'assets/achievements/pulse_check_silver.png',
      _ => 'assets/achievements/pulse_check_bronze.png',
    };
    final pulseCheckEarnedBadge = switch (pulseCheckTier) {
      'gold' => 'assets/achievements/pulse_check_gold.png',
      'silver' => 'assets/achievements/pulse_check_silver.png',
      _ => 'assets/achievements/pulse_check_bronze.png',
    };
    final pulseCheckGoalTier = switch (pulseCheckTier) {
      'gold' => null,
      'silver' => 'gold',
      'bronze' => 'silver',
      _ => 'bronze',
    };
    final savedStoryKeeperTier =
        savedById['story_keeper']?.data()['tier'] as String?;
    final calculatedStoryKeeperTier = journalEntryCount >= 100
        ? 'gold'
        : journalEntryCount >= 20
        ? 'silver'
        : journalEntryCount >= 5
        ? 'bronze'
        : null;
    final storyKeeperTier = _highestTier(
      savedStoryKeeperTier,
      calculatedStoryKeeperTier,
    );
    final storyKeeperTarget = switch (storyKeeperTier) {
      'gold' => 100,
      'silver' => 100,
      'bronze' => 20,
      _ => 5,
    };
    final storyKeeperGoalBadge = switch (storyKeeperTier) {
      'gold' => 'assets/achievements/story_keeper_gold.png',
      'silver' => 'assets/achievements/story_keeper_gold.png',
      'bronze' => 'assets/achievements/story_keeper_silver.png',
      _ => 'assets/achievements/story_keeper_bronze.png',
    };
    final storyKeeperEarnedBadge = switch (storyKeeperTier) {
      'gold' => 'assets/achievements/story_keeper_gold.png',
      'silver' => 'assets/achievements/story_keeper_silver.png',
      _ => 'assets/achievements/story_keeper_bronze.png',
    };
    final storyKeeperGoalTier = switch (storyKeeperTier) {
      'gold' => null,
      'silver' => 'gold',
      'bronze' => 'silver',
      _ => 'bronze',
    };

    final achievementChecks = [
      _Achievement(
        id: 'in_motion',
        name: 'In Motion',
        requirement: 'Complete your first activity',
        goalBadgeAsset: 'assets/achievements/in_motion.png',
        earned: workouts.docs.isNotEmpty,
        progress: workouts.docs.isNotEmpty ? 1 : 0,
      ),
      _Achievement(
        id: 'first_pulse',
        name: 'First Pulse',
        requirement: 'Complete your first heart-rate scan',
        goalBadgeAsset: 'assets/achievements/first_pulse.png',
        earned: completedHeartScan,
        progress: completedHeartScan ? 1 : 0,
      ),
      _Achievement(
        id: 'dear_diary',
        name: 'Dear Diary',
        requirement: 'Write your first journal entry',
        goalBadgeAsset: 'assets/achievements/dear_diary.png',
        earned: journalEntryCount > 0,
        progress: journalEntryCount > 0 ? 1 : 0,
      ),
      _Achievement(
        id: 'your_circle',
        name: 'Your Circle',
        requirement: 'Create your Circle profile',
        goalBadgeAsset: 'assets/achievements/your_circle.png',
        earned: widget.profile.username.trim().isNotEmpty,
        progress: widget.profile.username.trim().isNotEmpty ? 1 : 0,
      ),
      _Achievement(
        id: 'better_together',
        name: 'Better Together',
        requirement: 'Add your first friend',
        goalBadgeAsset: 'assets/achievements/better_together.png',
        earned: friends.isNotEmpty,
        progress: friends.isNotEmpty ? 1 : 0,
      ),
      _Achievement(
        id: 'day_planner',
        name: 'Day Planner',
        requirement: 'Connect your calendar',
        goalBadgeAsset: 'assets/achievements/day_planner.png',
        earned: googleCalendarConnected || outlookCalendarConnected,
        progress: googleCalendarConnected || outlookCalendarConnected ? 1 : 0,
      ),
      _Achievement(
        id: 'workout_momentum',
        name: 'Workout Momentum',
        requirement: 'Complete $momentumTarget strength workouts',
        goalBadgeAsset: momentumGoalBadge,
        earnedBadgeAsset: momentumEarnedBadge,
        earned: momentumTier == 'gold',
        progress: strengthWorkoutCount,
        target: momentumTarget,
        tier: momentumTier,
        goalTier: momentumGoalTier,
        progressUnit: 'workouts',
      ),
      _Achievement(
        id: 'endurance',
        name: 'Endurance',
        requirement: 'Complete $enduranceTarget cardio or sports activities',
        goalBadgeAsset: enduranceGoalBadge,
        earnedBadgeAsset: enduranceEarnedBadge,
        earned: enduranceTier == 'gold',
        progress: cardioOrSportsActivityCount,
        target: enduranceTarget,
        tier: enduranceTier,
        goalTier: enduranceGoalTier,
        progressUnit: 'activities',
      ),
      _Achievement(
        id: 'pulse_check',
        name: 'Pulse Check',
        requirement: 'Complete $pulseCheckTarget heart-rate scans',
        goalBadgeAsset: pulseCheckGoalBadge,
        earnedBadgeAsset: pulseCheckEarnedBadge,
        earned: pulseCheckTier == 'gold',
        progress: heartRateScanCount,
        target: pulseCheckTarget,
        tier: pulseCheckTier,
        goalTier: pulseCheckGoalTier,
        progressUnit: 'scans',
      ),
      _Achievement(
        id: 'story_keeper',
        name: 'Story Keeper',
        requirement: 'Write $storyKeeperTarget journal entries',
        goalBadgeAsset: storyKeeperGoalBadge,
        earnedBadgeAsset: storyKeeperEarnedBadge,
        earned: storyKeeperTier == 'gold',
        progress: journalEntryCount,
        target: storyKeeperTarget,
        tier: storyKeeperTier,
        goalTier: storyKeeperGoalTier,
        progressUnit: 'entries',
      ),
    ];
    final batch = firestore.batch();
    final now = DateTime.now();
    final resolved = achievementChecks
        .map((achievement) {
          final saved = savedById[achievement.id];
          final savedData = saved?.data();
          final wasEarned = savedData?['completed'] == true;
          final isEarned = achievement.earned || wasEarned;
          final savedTier = savedData?['tier'] as String?;
          final tierAdvanced =
              _tierRank(achievement.tier) > _tierRank(savedTier);
          final wasUnlocked = wasEarned || savedTier != null;
          final newUnlock =
              achievement.unlocked && (!wasUnlocked || tierAdvanced);
          final earnedAt = newUnlock
              ? now
              : (savedData?['earnedAt'] as Timestamp?)?.toDate();
          batch.set(
            firestore
                .collection('users')
                .doc(user.uid)
                .collection('achievements')
                .doc(achievement.id),
            {
              'achievementId': achievement.id,
              'name': achievement.name,
              'requirement': achievement.requirement,
              'badgeAsset': achievement.earnedBadgeAsset,
              'progress': achievement.progress,
              'target': achievement.target,
              if (achievement.progressUnit != null)
                'progressUnit': achievement.progressUnit,
              'completed': isEarned,
              if (achievement.tier != null) 'tier': achievement.tier,
              if (achievement.goalTier != null)
                'nextTier': achievement.goalTier,
              if (newUnlock) 'earnedAt': FieldValue.serverTimestamp(),
              if (tierAdvanced)
                'earnedTiers': FieldValue.arrayUnion([achievement.tier]),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          if (newUnlock) {
            final unlockedTier = achievement.tier;
            final unlockedRequirement = _achievementRequirementForTier(
              achievement,
              unlockedTier,
            );
            final activityId = unlockedTier == null
                ? 'achievement_${achievement.id}'
                : 'achievement_${achievement.id}_$unlockedTier';
            batch.set(
              firestore
                  .collection('users')
                  .doc(user.uid)
                  .collection('circle_activity')
                  .doc(activityId),
              {
                'kind': 'achievement',
                'name': achievement.name,
                'summary': unlockedRequirement,
                'achievementId': achievement.id,
                'achievementBadgeAsset': achievement.earnedBadgeAsset,
                'achievementTier': ?unlockedTier,
                'minutes': 0,
                'day': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
          return achievement.copyWith(earned: isEarned, earnedAt: earnedAt);
        })
        .toList(growable: false);
    await batch.commit();
    return resolved;
  }

  String? _highestTier(String? saved, String? calculated) {
    return _tierRank(saved) >= _tierRank(calculated) ? saved : calculated;
  }

  int _tierRank(String? tier) => switch (tier) {
    'bronze' => 1,
    'silver' => 2,
    'gold' => 3,
    _ => 0,
  };

  Future<bool> _hasGoogleCalendar() async {
    try {
      return await CalendarService.hasCalendarAccess();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasOutlookCalendar() async {
    try {
      return await OutlookCalendarService.isSignedIn();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<_Achievement>>(
    future: _achievements,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _ChallengeEmptyCard(
          icon: Icons.refresh_rounded,
          title: 'Could not load achievements',
          detail: 'Tap to try again.',
          onTap: () => setState(() => _achievements = _loadAchievements()),
        );
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 70),
          child: Center(
            child: CircularProgressIndicator(color: CircleScreen._purple),
          ),
        );
      }
      final achievements = snapshot.data!;
      final nextCandidates = achievements.where((item) => !item.earned).toList()
        ..sort(
          (a, b) => (b.progress / b.target).compareTo(a.progress / a.target),
        );
      final next = nextCandidates.firstOrNull;
      final oneTimeAchievements = achievements
          .where((achievement) => achievement.target == 1)
          .toList(growable: false);
      final tieredAchievements = achievements
          .where((achievement) => achievement.target > 1)
          .toList(growable: false);
      final earnedMilestoneCount =
          oneTimeAchievements
              .where((achievement) => achievement.earned)
              .length +
          tieredAchievements.fold<int>(
            0,
            (total, achievement) =>
                total + _tierRankForDisplay(achievement.tier),
          );
      final totalMilestoneCount =
          oneTimeAchievements.length + (tieredAchievements.length * 3);
      final inProgressCount = achievements
          .where(
            (achievement) =>
                !achievement.earned &&
                (achievement.unlocked || achievement.progress > 0),
          )
          .length;
      final percent = totalMilestoneCount == 0
          ? 0
          : ((earnedMilestoneCount / totalMilestoneCount) * 100).round();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CircleSectionTitle('ACHIEVEMENTS'),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: 'Open achievements',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _AchievementsPage(achievements: achievements),
                ),
              ),
              child: _CircleCard(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _ProfileAvatar(profile: widget.profile, radius: 34),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '$earnedMilestoneCount achievements',
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: context.vivordoColors.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  next == null
                                      ? 'All achievements earned'
                                      : '$inProgressCount in progress',
                                  style: const TextStyle(
                                    color: CircleScreen._muted,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: totalMilestoneCount == 0
                                        ? 0
                                        : earnedMilestoneCount /
                                              totalMilestoneCount,
                                    minHeight: 8,
                                    backgroundColor:
                                        context.vivordoColors.cardMuted,
                                    color: CircleScreen._purple,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '$percent% complete',
                                  style: const TextStyle(
                                    color: CircleScreen._muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          _ChallengeProgressRing(
                            earned: earnedMilestoneCount,
                            total: totalMilestoneCount,
                          ),
                        ],
                      ),
                      if (next != null) ...[
                        const SizedBox(height: 18),
                        Divider(color: context.vivordoColors.border),
                        const SizedBox(height: 14),
                        _NextAchievementSummary(achievement: next),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              const _CircleSectionTitle('CHALLENGES'),
              const Spacer(),
              TextButton(
                onPressed: _openChallenges,
                child: const Text(
                  'View All',
                  style: TextStyle(
                    color: CircleScreen._purple,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildChallengesCard(context),
        ],
      );
    },
  );

  Widget _buildChallengesCard(BuildContext context) {
    if (widget.membershipsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 42),
        child: Center(
          child: CircularProgressIndicator(color: CircleScreen._purple),
        ),
      );
    }
    if (widget.membershipsError != null) {
      debugPrint(
        'Circle challenges: membership stream failed: '
        '${widget.membershipsError}',
      );
      return _ChallengeEmptyCard(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load challenges',
        detail: 'Tap to open Challenges and try again.',
        onTap: _openChallenges,
      );
    }

    final invites = widget.memberships
        .where((membership) => membership.isInvite)
        .toList(growable: false);
    final ongoing = widget.memberships
        .where((membership) => membership.isOngoing)
        .toList(growable: false);
    if (invites.isEmpty && ongoing.isEmpty) {
      return _ChallengeEmptyCard(
        icon: Icons.groups_rounded,
        title: 'No active challenges',
        detail: 'Tap to challenge a friend and build a healthy habit.',
        onTap: _openChallenges,
      );
    }
    return _GoalsChallengesCard(
      profile: widget.profile,
      activeChallenge: ongoing.firstOrNull,
      invite: invites.firstOrNull,
      inviteCount: invites.length,
      onOpenActive: _openChallenges,
      onOpenInvites: () => _openChallenges(initialTab: 1),
    );
  }

  void _openChallenges({int initialTab = 0}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _CircleChallengesPage(
        profile: widget.profile,
        initialTab: initialTab,
      ),
    ),
  );
}

class _GoalsChallengesCard extends StatefulWidget {
  const _GoalsChallengesCard({
    required this.profile,
    required this.activeChallenge,
    required this.invite,
    required this.inviteCount,
    required this.onOpenActive,
    required this.onOpenInvites,
  });

  final CircleProfile profile;
  final CircleChallengeMembership? activeChallenge;
  final CircleChallengeMembership? invite;
  final int inviteCount;
  final VoidCallback onOpenActive;
  final VoidCallback onOpenInvites;

  @override
  State<_GoalsChallengesCard> createState() => _GoalsChallengesCardState();
}

class _GoalsChallengesCardState extends State<_GoalsChallengesCard> {
  bool _responding = false;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.activeChallenge case final active?)
          _activeChallenge(context, active),
        if (widget.activeChallenge != null && widget.invite != null) ...[
          const SizedBox(height: 20),
          Divider(color: context.vivordoColors.border, height: 1),
          const SizedBox(height: 18),
        ],
        if (widget.invite case final invite?) _invite(context, invite),
      ],
    ),
  );

  Widget _activeChallenge(
    BuildContext context,
    CircleChallengeMembership challenge,
  ) {
    final progress = challenge.goal <= 0
        ? 0.0
        : (challenge.progress / challenge.goal).clamp(0.0, 1.0);
    final waiting = challenge.status == 'waiting';
    final daysLeft = _daysLeft(challenge);
    return InkWell(
      onTap: widget.onOpenActive,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: CircleScreen._purple,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  waiting ? 'WAITING' : 'ACTIVE',
                  style: const TextStyle(
                    color: CircleScreen._muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '$daysLeft day${daysLeft == 1 ? '' : 's'} left',
                    style: const TextStyle(
                      color: Color(0xFFE97922),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _ChallengeParticipantCluster(
                  profile: widget.profile,
                  challenge: challenge,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        challenge.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.vivordoColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${NumberFormat.decimalPattern().format(challenge.progress)} / '
                        '${NumberFormat.decimalPattern().format(challenge.goal)} '
                        '${challenge.unit}',
                        style: const TextStyle(
                          color: CircleScreen._muted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          color: CircleScreen._purple,
                          backgroundColor: context.vivordoColors.cardMuted,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        waiting
                            ? 'Waiting for friends to respond'
                            : '${challenge.participantUids.length} participants',
                        style: const TextStyle(
                          color: CircleScreen._muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: CircleScreen._muted,
                  size: 28,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _invite(BuildContext context, CircleChallengeMembership challenge) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: widget.onOpenInvites,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Text(
                    'NEW INVITE',
                    style: TextStyle(
                      color: CircleScreen._purple,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ChallengeInviteBadge(count: widget.inviteCount),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChallengeInitialAvatar(name: challenge.creatorName, size: 54),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.vivordoColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${challenge.creatorName} invited you · '
                      '${challenge.durationDays} days',
                      style: const TextStyle(
                        color: CircleScreen._muted,
                        fontSize: 13,
                      ),
                    ),
                    if (challenge.message.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '“${challenge.message}”',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.vivordoColors.textPrimary,
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              SizedBox(
                width: 104,
                height: 44,
                child: OutlinedButton(
                  onPressed: _responding ? null : () => _respond(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CircleScreen._muted,
                    side: const BorderSide(color: CircleScreen._muted),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Decline',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 112,
                height: 44,
                child: FilledButton(
                  onPressed: _responding ? null : () => _respond(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: CircleScreen._purple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: _responding
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Accept',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
            ],
          ),
        ],
      );

  int _daysLeft(CircleChallengeMembership challenge) {
    final endAt = challenge.endAt;
    if (endAt == null) return challenge.durationDays;
    final hours = endAt.difference(DateTime.now()).inHours;
    if (hours <= 0) return 0;
    return (hours + 23) ~/ 24;
  }

  Future<void> _respond(bool accept) async {
    final invite = widget.invite;
    if (invite == null || _responding) return;
    setState(() => _responding = true);
    try {
      await CircleChallengeService.respond(
        challengeId: invite.challengeId,
        accept: accept,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Challenge accepted.' : 'Challenge declined.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update challenge: $error')),
      );
      setState(() => _responding = false);
    }
  }
}

class _ChallengeParticipantCluster extends StatelessWidget {
  const _ChallengeParticipantCluster({
    required this.profile,
    required this.challenge,
  });

  final CircleProfile profile;
  final CircleChallengeMembership challenge;

  @override
  Widget build(BuildContext context) {
    final count = challenge.participantUids.length;
    final width = count <= 1
        ? 50.0
        : count == 2
        ? 82.0
        : 112.0;
    return SizedBox(
      width: width,
      height: 54,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _ChallengeAvatarBorder(
              child: _ProfileAvatar(profile: profile, radius: 24),
            ),
          ),
          if (count > 1)
            Positioned(
              left: 32,
              child: _ChallengeInitialAvatar(
                name: challenge.creatorUid == profile.uid
                    ? 'Friend'
                    : challenge.creatorName,
                size: 50,
              ),
            ),
          if (count > 2)
            Positioned(
              left: 64,
              child: _ChallengeInitialAvatar(name: '+${count - 2}', size: 50),
            ),
        ],
      ),
    );
  }
}

class _ChallengeAvatarBorder extends StatelessWidget {
  const _ChallengeAvatarBorder({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      shape: BoxShape.circle,
    ),
    child: child,
  );
}

class _ChallengeInitialAvatar extends StatelessWidget {
  const _ChallengeInitialAvatar({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final label = trimmed.startsWith('+')
        ? trimmed
        : trimmed.isEmpty
        ? '?'
        : trimmed.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFE2E4),
        shape: BoxShape.circle,
        border: Border.all(color: context.vivordoColors.card, width: 2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: const Color(0xFFFF5264),
          fontSize: size * .4,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CircleChallengesPage extends StatefulWidget {
  const _CircleChallengesPage({required this.profile, this.initialTab = 0});

  final CircleProfile profile;
  final int initialTab;

  @override
  State<_CircleChallengesPage> createState() => _CircleChallengesPageState();
}

class _CircleChallengesPageState extends State<_CircleChallengesPage> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab == 1 ? 1 : 0;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    body: SafeArea(
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 44),
        children: [
          Row(
            children: [
              _ProfileHeaderButton(
                icon: Icons.chevron_left_rounded,
                onTap: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  'Challenges',
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 31,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.7,
                  ),
                ),
              ),
              _ProfileHeaderButton(
                icon: Icons.history_rounded,
                onTap: () =>
                    _showComingSoon('Completed challenges will appear here.'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _ChallengeHero(
            profile: widget.profile,
            onCreate: _openCustomChallenge,
          ),
          const SizedBox(height: 16),
          _ChallengePageTabs(
            selectedIndex: _selectedTab,
            onChanged: (index) => setState(() => _selectedTab = index),
          ),
          const SizedBox(height: 28),
          _CircleSectionTitle(
            _selectedTab == 0 ? 'ACTIVE CHALLENGES' : 'CHALLENGE INVITES',
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<CircleChallengeMembership>>(
            stream: CircleChallengeService.watchMemberships(),
            builder: (context, snapshot) => _ChallengeMembershipList(
              memberships: (snapshot.data ?? const [])
                  .where(
                    (membership) => _selectedTab == 0
                        ? membership.isOngoing
                        : membership.isInvite,
                  )
                  .toList(growable: false),
              loading:
                  snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData,
              error: snapshot.error,
              invites: _selectedTab == 1,
              onRespond: _respondToChallenge,
            ),
          ),
          const SizedBox(height: 28),
          const _CircleSectionTitle('QUICK CHALLENGES'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _QuickChallengeCard(
                  icon: Icons.fitness_center_rounded,
                  color: CircleScreen._purple,
                  title: 'Workout Streak',
                  onTap: () => _openQuickChallenge(
                    const _QuickChallengeDefinition.workoutStreak(),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _QuickChallengeCard(
                  icon: Icons.directions_walk_rounded,
                  color: const Color(0xFF0FB986),
                  title: 'Step Sprint',
                  onTap: () => _openQuickChallenge(
                    const _QuickChallengeDefinition.stepSprint(),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _QuickChallengeCard(
                  icon: Icons.monitor_heart_rounded,
                  color: const Color(0xFFFF5264),
                  title: 'Pulse Check',
                  onTap: () => _openQuickChallenge(
                    const _QuickChallengeDefinition.pulseCheck(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  void _showComingSoon(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openCustomChallenge() async {
    final draft = await showModalBottomSheet<_CustomChallengeDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .54),
      builder: (_) => const _CreateCustomChallengeSheet(),
    );
    if (!mounted || draft == null) return;
    final recipientLabel = draft.friends.length == 1
        ? draft.friends.first.username
        : '${draft.friends.length} friends';
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        duration: Duration(minutes: 1),
        content: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Sending challenge…'),
          ],
        ),
      ),
    );
    try {
      await CircleChallengeService.create(
        type: draft.definition.backendType,
        goal: draft.goal,
        durationDays: draft.durationDays,
        participantUids: draft.friends
            .map((friend) => friend.uid)
            .toList(growable: false),
        targetName: draft.specificExercise,
        message: draft.message,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${draft.title} sent to $recipientLabel.')),
        );
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not send challenge: $error')),
        );
    }
  }

  Future<void> _openQuickChallenge(_QuickChallengeDefinition challenge) async {
    final draft = await showModalBottomSheet<_QuickChallengeDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .54),
      builder: (_) => _CreateQuickChallengeSheet(challenge: challenge),
    );
    if (!mounted || draft == null) return;
    final recipientLabel = draft.friends.length == 1
        ? draft.friends.first.username
        : '${draft.friends.length} friends';
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        duration: Duration(minutes: 1),
        content: Row(
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Sending challenge…'),
          ],
        ),
      ),
    );
    try {
      await CircleChallengeService.create(
        type: draft.challenge.backendType,
        goal: draft.goal,
        durationDays: draft.durationDays,
        participantUids: draft.friends.map((friend) => friend.uid).toList(),
        message: draft.message,
      );
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${draft.challenge.title} sent to $recipientLabel.'),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not send challenge: $error')),
        );
    }
  }

  Future<void> _respondToChallenge(
    CircleChallengeMembership membership,
    bool accept,
  ) async {
    try {
      await CircleChallengeService.respond(
        challengeId: membership.challengeId,
        accept: accept,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Challenge accepted.' : 'Challenge declined.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update challenge: $error')),
      );
    }
  }
}

class _ChallengeHero extends StatelessWidget {
  const _ChallengeHero({required this.profile, required this.onCreate});

  final CircleProfile profile;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CircleProfile>>(
    stream: CircleProfileService.watchFriends(),
    builder: (context, snapshot) {
      final friend = snapshot.data?.firstOrNull;
      return Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7C75FF), Color(0xFF4D32ED)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x334D32ED),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 30,
              child: Icon(
                Icons.emoji_events_rounded,
                color: Colors.white.withValues(alpha: .26),
                size: 112,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 104,
                  height: 58,
                  child: Stack(
                    children: [
                      _ProfileAvatar(profile: profile, radius: 29),
                      Positioned(
                        left: 45,
                        child: friend == null
                            ? CircleAvatar(
                                radius: 29,
                                backgroundColor: const Color(0xFFFFE2E6),
                                child: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                  color: Color(0xFFFF5264),
                                ),
                              )
                            : _ProfileAvatar(profile: friend, radius: 29),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Challenge a friend',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                const SizedBox(
                  width: 225,
                  child: Text(
                    'Pick a goal, choose a friend, and build healthy habits together.',
                    style: TextStyle(
                      color: Color(0xFFE9E7FF),
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Create Challenge'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: CircleScreen._purple,
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _ChallengePageTabs extends StatelessWidget {
  const _ChallengePageTabs({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 56,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Row(
      children: [
        _tab('Active', 0),
        const SizedBox(width: 4),
        _tab('Invites', 1),
      ],
    ),
  );

  Widget _tab(String label, int index) => Expanded(
    child: Material(
      color: selectedIndex == index ? CircleScreen._purple : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => onChanged(index),
        borderRadius: BorderRadius.circular(14),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selectedIndex == index
                  ? Colors.white
                  : CircleScreen._muted,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ChallengeMembershipList extends StatelessWidget {
  const _ChallengeMembershipList({
    required this.memberships,
    required this.loading,
    required this.error,
    required this.invites,
    required this.onRespond,
  });

  final List<CircleChallengeMembership> memberships;
  final bool loading;
  final Object? error;
  final bool invites;
  final Future<void> Function(CircleChallengeMembership, bool) onRespond;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 42),
        child: Center(
          child: CircularProgressIndicator(color: CircleScreen._purple),
        ),
      );
    }
    if (error != null) {
      return _ChallengeEmptyCard(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load challenges',
        detail: 'Check your connection, then reopen this screen.',
      );
    }
    if (memberships.isEmpty) {
      return _ChallengeEmptyCard(
        icon: invites ? Icons.mail_outline_rounded : Icons.flag_rounded,
        title: invites ? 'No challenge invites' : 'No active challenges',
        detail: invites
            ? 'Invitations from your friends will appear here.'
            : 'Create a challenge and invite a friend to join you.',
      );
    }
    return Column(
      children: [
        for (var index = 0; index < memberships.length; index++) ...[
          _ChallengeMembershipCard(
            membership: memberships[index],
            invite: invites,
            onRespond: onRespond,
            onOpen: invites
                ? null
                : () =>
                      _showActiveChallengeDetails(context, memberships[index]),
          ),
          if (index != memberships.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ChallengeMembershipCard extends StatefulWidget {
  const _ChallengeMembershipCard({
    required this.membership,
    required this.invite,
    required this.onRespond,
    required this.onOpen,
  });

  final CircleChallengeMembership membership;
  final bool invite;
  final Future<void> Function(CircleChallengeMembership, bool) onRespond;
  final VoidCallback? onOpen;

  @override
  State<_ChallengeMembershipCard> createState() =>
      _ChallengeMembershipCardState();
}

class _ChallengeMembershipCardState extends State<_ChallengeMembershipCard> {
  var _responding = false;

  @override
  Widget build(BuildContext context) {
    final membership = widget.membership;
    final color = switch (membership.type) {
      'step_total' => const Color(0xFF0FB986),
      'activity_count' => const Color(0xFF0FB986),
      'journal_count' => const Color(0xFF08A7AA),
      'scan_count' => const Color(0xFFFF5264),
      _ => CircleScreen._purple,
    };
    final icon = switch (membership.type) {
      'step_total' => Icons.directions_walk_rounded,
      'activity_count' => Icons.directions_run_rounded,
      'journal_count' => Icons.menu_book_rounded,
      'scan_count' => Icons.monitor_heart_rounded,
      _ => Icons.fitness_center_rounded,
    };
    final progress = membership.goal <= 0
        ? 0.0
        : (membership.progress / membership.goal).clamp(0.0, 1.0);
    final progressLabel =
        '${NumberFormat.decimalPattern().format(membership.progress)} / '
        '${NumberFormat.decimalPattern().format(membership.goal)} '
        '${membership.unit}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onOpen,
      child: _CircleCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership.title,
                      style: TextStyle(
                        color: context.vivordoColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.invite
                          ? '${membership.creatorName} invited you'
                          : membership.status == 'waiting'
                          ? 'Waiting for friends to respond'
                          : '${membership.participantUids.length} participants',
                      style: const TextStyle(
                        color: CircleScreen._muted,
                        fontSize: 13,
                      ),
                    ),
                    if (widget.invite && membership.message.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: context.vivordoColors.cardMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '“${membership.message}”',
                          style: TextStyle(
                            color: context.vivordoColors.textPrimary,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      progressLabel,
                      style: TextStyle(
                        color: context.vivordoColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: context.vivordoColors.cardMuted,
                        color: color,
                      ),
                    ),
                    if (widget.invite) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _responding
                                  ? null
                                  : () => _respond(false),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Decline',
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: FilledButton(
                              onPressed: _responding
                                  ? null
                                  : () => _respond(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: CircleScreen._purple,
                              ),
                              child: _responding
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Accept'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _respond(bool accept) async {
    setState(() => _responding = true);
    await widget.onRespond(widget.membership, accept);
    if (mounted) setState(() => _responding = false);
  }
}

Future<void> _showActiveChallengeDetails(
  BuildContext context,
  CircleChallengeMembership membership,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  builder: (sheetContext) => AnimatedPadding(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.only(
      bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
    ),
    child: _ActiveChallengeDetailSheet(membership: membership),
  ),
);

class _ActiveChallengeDetailSheet extends StatefulWidget {
  const _ActiveChallengeDetailSheet({required this.membership});

  final CircleChallengeMembership membership;

  @override
  State<_ActiveChallengeDetailSheet> createState() =>
      _ActiveChallengeDetailSheetState();
}

class _ActiveChallengeDetailSheetState
    extends State<_ActiveChallengeDetailSheet> {
  late Future<CircleChallengeDetails> _details;
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  ScrollController? _sheetScrollController;
  var _postingComment = false;

  @override
  void initState() {
    super.initState();
    _details = CircleChallengeService.loadDetails(
      widget.membership.challengeId,
    );
    _commentFocusNode.addListener(_handleCommentFocus);
  }

  @override
  void dispose() {
    _commentFocusNode.removeListener(_handleCommentFocus);
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .92,
    minChildSize: .62,
    maxChildSize: .97,
    expand: false,
    builder: (context, scrollController) {
      _sheetScrollController = scrollController;
      return Container(
        decoration: BoxDecoration(
          color: context.vivordoColors.page,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: ListView(
          controller: scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 34),
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: CircleScreen._muted.withValues(alpha: .42),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildHeading(context)),
                IconButton.filled(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: context.vivordoColors.cardMuted,
                    foregroundColor: CircleScreen._muted,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FutureBuilder<CircleChallengeDetails>(
              future: _details,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: CircleScreen._purple,
                      ),
                    ),
                  );
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return _ChallengeEmptyCard(
                    icon: Icons.cloud_off_rounded,
                    title: 'Could not load challenge details',
                    detail: 'Check your connection and try again.',
                    onTap: _reload,
                  );
                }
                return _buildDetails(context, snapshot.requireData);
              },
            ),
          ],
        ),
      );
    },
  );

  void _handleCommentFocus() {
    if (!_commentFocusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCommentBox());
    Future<void>.delayed(
      const Duration(milliseconds: 280),
      _scrollToCommentBox,
    );
  }

  void _scrollToCommentBox() {
    final controller = _sheetScrollController;
    if (!mounted ||
        !_commentFocusNode.hasFocus ||
        controller == null ||
        !controller.hasClients) {
      return;
    }
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildHeading(BuildContext context) {
    final membership = widget.membership;
    final waiting = membership.status == 'waiting';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: waiting
                ? null
                : const LinearGradient(
                    colors: [Color(0xFF5341EF), Color(0xFF6B4EF2)],
                  ),
            color: waiting ? context.vivordoColors.cardMuted : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            waiting ? 'WAITING' : 'ACTIVE',
            style: TextStyle(
              color: waiting ? CircleScreen._muted : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          membership.title,
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Complete ${NumberFormat.decimalPattern().format(membership.goal)} '
          '${membership.unit}',
          style: const TextStyle(color: CircleScreen._muted, fontSize: 15),
        ),
        const SizedBox(height: 13),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0E5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '${_daysLeft(membership)} days left',
            style: const TextStyle(
              color: Color(0xFFE97922),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context, CircleChallengeDetails details) {
    final participants = [...details.participants]
      ..sort((a, b) => b.progress.compareTo(a.progress));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChallengeStandingsCard(
          membership: widget.membership,
          participants: participants,
        ),
        if (widget.membership.message.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _CircleSectionTitle('CHALLENGE MESSAGE'),
          const SizedBox(height: 12),
          _ChallengeCreatorMessageCard(
            creatorName: widget.membership.creatorName,
            message: widget.membership.message,
          ),
        ],
        const SizedBox(height: 24),
        const _CircleSectionTitle('RECENT PROGRESS'),
        const SizedBox(height: 12),
        _ChallengeRecentProgressCard(
          participants: participants,
          contributions: details.contributions.take(4).toList(),
        ),
        const SizedBox(height: 24),
        const _CircleSectionTitle('COMMENTS'),
        const SizedBox(height: 12),
        _ChallengeCommentsSection(
          challengeId: widget.membership.challengeId,
          participants: participants,
          controller: _commentController,
          focusNode: _commentFocusNode,
          posting: _postingComment,
          onSend: _postComment,
          onDelete: _deleteComment,
        ),
      ],
    );
  }

  void _reload() => setState(() {
    _details = CircleChallengeService.loadDetails(
      widget.membership.challengeId,
    );
  });

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _postingComment) return;
    setState(() => _postingComment = true);
    try {
      await CircleChallengeService.addComment(
        challengeId: widget.membership.challengeId,
        text: text,
      );
      _commentController.clear();
      _commentFocusNode.unfocus();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not post comment: $error')));
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  Future<void> _deleteComment(CircleChallengeComment comment) async {
    try {
      await CircleChallengeService.deleteComment(
        challengeId: widget.membership.challengeId,
        commentId: comment.id,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete comment: $error')),
      );
    }
  }

  int _daysLeft(CircleChallengeMembership membership) {
    final endAt = membership.endAt;
    if (endAt == null) return membership.durationDays;
    final hours = endAt.difference(DateTime.now()).inHours;
    return hours <= 0 ? 0 : (hours + 23) ~/ 24;
  }
}

class _ChallengeCommentsSection extends StatefulWidget {
  const _ChallengeCommentsSection({
    required this.challengeId,
    required this.participants,
    required this.controller,
    required this.focusNode,
    required this.posting,
    required this.onSend,
    required this.onDelete,
  });

  final String challengeId;
  final List<CircleChallengeParticipant> participants;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool posting;
  final VoidCallback onSend;
  final ValueChanged<CircleChallengeComment> onDelete;

  @override
  State<_ChallengeCommentsSection> createState() =>
      _ChallengeCommentsSectionState();
}

class _ChallengeCommentsSectionState extends State<_ChallengeCommentsSection> {
  late Stream<List<CircleChallengeComment>> _comments;

  @override
  void initState() {
    super.initState();
    _comments = CircleChallengeService.watchComments(widget.challengeId);
  }

  @override
  void didUpdateWidget(covariant _ChallengeCommentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.challengeId != widget.challengeId) {
      _comments = CircleChallengeService.watchComments(widget.challengeId);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<List<CircleChallengeComment>>(
          stream: _comments,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Comments could not be loaded.',
                  style: TextStyle(color: CircleScreen._muted),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(22),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: CircleScreen._purple,
                    ),
                  ),
                ),
              );
            }
            final comments = snapshot.requireData;
            if (comments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
                child: Text(
                  'No comments yet. Start the conversation.',
                  style: TextStyle(color: CircleScreen._muted, fontSize: 14),
                ),
              );
            }
            return Column(
              children: [
                for (var index = 0; index < comments.length; index++) ...[
                  _ChallengeCommentRow(
                    comment: comments[index],
                    participant: _participantFor(comments[index].authorUid),
                    onDelete: widget.onDelete,
                  ),
                  if (index != comments.length - 1)
                    Divider(
                      height: 1,
                      indent: 62,
                      color: context.vivordoColors.border,
                    ),
                ],
              ],
            );
          },
        ),
        Divider(height: 1, color: context.vivordoColors.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  scrollPadding: const EdgeInsets.only(bottom: 110),
                  style: TextStyle(color: context.vivordoColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Add a comment…',
                    counterText: '',
                    filled: true,
                    fillColor: context.vivordoColors.cardMuted,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: widget.posting ? null : widget.onSend,
                style: IconButton.styleFrom(
                  backgroundColor: CircleScreen._purple,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: CircleScreen._purple.withValues(
                    alpha: .45,
                  ),
                ),
                icon: widget.posting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  CircleChallengeParticipant? _participantFor(String uid) {
    for (final participant in widget.participants) {
      if (participant.uid == uid) return participant;
    }
    return null;
  }
}

class _ChallengeCommentRow extends StatelessWidget {
  const _ChallengeCommentRow({
    required this.comment,
    required this.participant,
    required this.onDelete,
  });

  final CircleChallengeComment comment;
  final CircleChallengeParticipant? participant;
  final ValueChanged<CircleChallengeComment> onDelete;

  @override
  Widget build(BuildContext context) {
    final name = participant == null
        ? 'Circle member'
        : _challengeDisplayName(participant!);
    final isMine = comment.authorUid == FirebaseAuth.instance.currentUser?.uid;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChallengeInitialAvatar(name: name, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.vivordoColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _challengeCommentTime(comment.createdAt),
                      style: const TextStyle(
                        color: CircleScreen._muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.text,
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (isMine)
            PopupMenuButton<String>(
              tooltip: 'Comment options',
              icon: const Icon(
                Icons.more_horiz_rounded,
                size: 20,
                color: CircleScreen._muted,
              ),
              onSelected: (value) {
                if (value == 'delete') onDelete(comment);
              },
              itemBuilder: (_) => const [
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                      ),
                      SizedBox(width: 10),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _challengeCommentTime(DateTime? createdAt) {
  if (createdAt == null) return 'Just now';
  final difference = DateTime.now().difference(createdAt);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return DateFormat.MMMd().format(createdAt);
}

class _ChallengeCreatorMessageCard extends StatelessWidget {
  const _ChallengeCreatorMessageCard({
    required this.creatorName,
    required this.message,
  });

  final String creatorName;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ChallengeInitialAvatar(name: creatorName, size: 48),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                creatorName,
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '“$message”',
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ChallengeStandingsCard extends StatelessWidget {
  const _ChallengeStandingsCard({
    required this.membership,
    required this.participants,
  });

  final CircleChallengeMembership membership;
  final List<CircleChallengeParticipant> participants;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Row(
            children: [
              const Text(
                'GROUP PROGRESS',
                style: TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${participants.length} participants',
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        for (var index = 0; index < participants.length; index++)
          _ChallengeStandingRow(
            rank: index + 1,
            participant: participants[index],
            goal: membership.goal,
            color: _challengeParticipantColor(index),
            leading: index == 0,
          ),
        Divider(height: 1, color: context.vivordoColors.border),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: _ChallengeInfoItem(
                  icon: Icons.calendar_month_rounded,
                  text: _challengeDateRange(membership),
                ),
              ),
              Expanded(
                child: _ChallengeInfoItem(
                  icon: _challengeTypeIcon(membership.type),
                  text: membership.title,
                ),
              ),
              Expanded(
                child: _ChallengeInfoItem(
                  icon: Icons.groups_rounded,
                  text: '${participants.length} participants',
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ChallengeStandingRow extends StatelessWidget {
  const _ChallengeStandingRow({
    required this.rank,
    required this.participant,
    required this.goal,
    required this.color,
    required this.leading,
  });

  final int rank;
  final CircleChallengeParticipant participant;
  final int goal;
  final Color color;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    final isCurrent = participant.uid == FirebaseAuth.instance.currentUser?.uid;
    final value = goal <= 0
        ? 0.0
        : (participant.progress / goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.vivordoColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: TextStyle(
                color: context.vivordoColors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _ChallengeInitialAvatar(name: participant.username, size: 46),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        participant.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.vivordoColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 6),
                      _ChallengePill(label: 'You', color: CircleScreen._purple),
                    ],
                    if (leading) ...[
                      const Spacer(),
                      _ChallengePill(
                        label: 'Leading',
                        color: CircleScreen._purple,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${participant.progress} of $goal',
                  style: const TextStyle(
                    color: CircleScreen._muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
                    color: color,
                    backgroundColor: context.vivordoColors.cardMuted,
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

class _ChallengePill extends StatelessWidget {
  const _ChallengePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
    ),
  );
}

class _ChallengeInfoItem extends StatelessWidget {
  const _ChallengeInfoItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: CircleScreen._purple, size: 22),
      const SizedBox(height: 5),
      Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.vivordoColors.textPrimary,
          fontSize: 11,
        ),
      ),
    ],
  );
}

class _ChallengeRecentProgressCard extends StatelessWidget {
  const _ChallengeRecentProgressCard({
    required this.participants,
    required this.contributions,
  });

  final List<CircleChallengeParticipant> participants;
  final List<CircleChallengeContribution> contributions;

  @override
  Widget build(BuildContext context) {
    if (contributions.isEmpty) {
      return _ChallengeEmptyCard(
        icon: Icons.hourglass_empty_rounded,
        title: 'No progress yet',
        detail: 'Completed activities will appear here.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Column(
        children: [
          for (var index = 0; index < contributions.length; index++) ...[
            _ChallengeContributionRow(
              contribution: contributions[index],
              participant: participants.firstWhere(
                (participant) => participant.uid == contributions[index].uid,
                orElse: () => const CircleChallengeParticipant(
                  uid: '',
                  username: 'Circle member',
                  role: 'participant',
                  status: 'active',
                  progress: 0,
                ),
              ),
            ),
            if (index != contributions.length - 1)
              Divider(
                height: 1,
                indent: 70,
                color: context.vivordoColors.border,
              ),
          ],
        ],
      ),
    );
  }
}

class _ChallengeContributionRow extends StatelessWidget {
  const _ChallengeContributionRow({
    required this.contribution,
    required this.participant,
  });

  final CircleChallengeContribution contribution;
  final CircleChallengeParticipant participant;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    child: Row(
      children: [
        _ChallengeInitialAvatar(name: participant.username, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_challengeDisplayName(participant)} '
                '${_challengeContributionLabel(contribution)}',
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _challengeContributionTime(contribution),
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Color _challengeParticipantColor(int index) => const [
  CircleScreen._purple,
  Color(0xFFFF5264),
  Color(0xFF0FB986),
  Color(0xFF2684FF),
][index % 4];

IconData _challengeTypeIcon(String type) => switch (type) {
  'step_total' => Icons.directions_walk_rounded,
  'activity_count' => Icons.directions_run_rounded,
  'journal_count' => Icons.menu_book_rounded,
  'scan_count' => Icons.monitor_heart_rounded,
  _ => Icons.fitness_center_rounded,
};

String _challengeDateRange(CircleChallengeMembership membership) {
  final start = membership.startAt ?? membership.createdAt;
  final end =
      membership.endAt ?? start.add(Duration(days: membership.durationDays));
  if (start.month == end.month) {
    return '${DateFormat.MMM().format(start)} ${start.day}–${end.day}';
  }
  return '${DateFormat.MMMd().format(start)}–${DateFormat.MMMd().format(end)}';
}

String _challengeDisplayName(CircleChallengeParticipant participant) =>
    participant.uid == FirebaseAuth.instance.currentUser?.uid
    ? 'You'
    : participant.username;

String _challengeContributionLabel(
  CircleChallengeContribution contribution,
) => switch (contribution.sourceType) {
  'workout' => 'completed a workout',
  'activity' => 'completed an activity',
  'journal_day' => 'added a journal entry',
  'steps_day' =>
    'added ${NumberFormat.decimalPattern().format(contribution.value)} steps',
  'scans_day' =>
    'completed ${contribution.value} heart scan${contribution.value == 1 ? '' : 's'}',
  _ => 'made challenge progress',
};

String _challengeContributionTime(CircleChallengeContribution contribution) {
  final occurredAt = contribution.occurredAt;
  if (occurredAt == null) return '+${contribution.value} progress';
  final now = DateTime.now();
  final difference = now.difference(occurredAt);
  final when = difference.inHours < 24
      ? difference.inHours <= 0
            ? 'Just now'
            : '${difference.inHours}h ago'
      : DateFormat.MMMd().format(occurredAt);
  return '$when · +${NumberFormat.decimalPattern().format(contribution.value)} progress';
}

class _QuickChallengeCard extends StatelessWidget {
  const _QuickChallengeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.vivordoColors.card,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 180,
        padding: const EdgeInsets.fromLTRB(12, 15, 12, 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.vivordoColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(height: 11),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.vivordoColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.add_circle_outline_rounded,
                color: CircleScreen._purple,
                size: 28,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

enum _CustomChallengeCount { workout, activity, journal, heartScans }

class _CustomChallengeDefinition {
  const _CustomChallengeDefinition({
    required this.kind,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.unit,
  });

  final _CustomChallengeCount kind;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final String unit;

  String get backendType => switch (kind) {
    _CustomChallengeCount.workout => 'workout_count',
    _CustomChallengeCount.activity => 'activity_count',
    _CustomChallengeCount.journal => 'journal_count',
    _CustomChallengeCount.heartScans => 'scan_count',
  };

  static const values = [
    _CustomChallengeDefinition(
      kind: _CustomChallengeCount.workout,
      title: 'Workout',
      detail: 'Any or specific',
      icon: Icons.fitness_center_rounded,
      color: CircleScreen._purple,
      unit: 'workouts',
    ),
    _CustomChallengeDefinition(
      kind: _CustomChallengeCount.activity,
      title: 'Activity',
      detail: 'Run, walk & more',
      icon: Icons.directions_run_rounded,
      color: Color(0xFF0FB986),
      unit: 'sessions',
    ),
    _CustomChallengeDefinition(
      kind: _CustomChallengeCount.journal,
      title: 'Journal Streak',
      detail: 'Daily entries',
      icon: Icons.menu_book_rounded,
      color: Color(0xFF08A7AA),
      unit: 'days',
    ),
    _CustomChallengeDefinition(
      kind: _CustomChallengeCount.heartScans,
      title: 'Heart Scans',
      detail: 'Completed scans',
      icon: Icons.monitor_heart_rounded,
      color: Color(0xFFFF5264),
      unit: 'scans',
    ),
  ];
}

class _CustomChallengeDraft {
  const _CustomChallengeDraft({
    required this.definition,
    required this.specificExercise,
    required this.goal,
    required this.friends,
    required this.durationDays,
    required this.message,
  });

  final _CustomChallengeDefinition definition;
  final String? specificExercise;
  final int goal;
  final List<CircleProfile> friends;
  final int durationDays;
  final String message;

  String get title => specificExercise ?? definition.title;
}

class _CreateCustomChallengeSheet extends StatefulWidget {
  const _CreateCustomChallengeSheet();

  @override
  State<_CreateCustomChallengeSheet> createState() =>
      _CreateCustomChallengeSheetState();
}

class _CreateCustomChallengeSheetState
    extends State<_CreateCustomChallengeSheet> {
  final Set<String> _selectedFriendUids = {};
  final TextEditingController _messageController = TextEditingController();
  var _definition = _CustomChallengeDefinition.values[0];
  String? _specificExercise;
  var _goal = 5;
  var _durationDays = 7;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .94,
    minChildSize: .72,
    maxChildSize: .98,
    expand: false,
    builder: (context, scrollController) => Container(
      decoration: BoxDecoration(
        color: context.vivordoColors.page,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: StreamBuilder<List<CircleProfile>>(
        stream: CircleProfileService.watchFriends(),
        builder: (context, snapshot) {
          final friends = snapshot.data ?? const <CircleProfile>[];
          final selectedFriends = friends
              .where((friend) => _selectedFriendUids.contains(friend.uid))
              .toList(growable: false);
          return ListView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.vivordoColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Create Challenge',
                      style: TextStyle(
                        color: context.vivordoColors.textPrimary,
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  _ChallengeSheetCloseButton(
                    onTap: () => Navigator.maybePop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _ChallengeSheetLabel('WHAT COUNTS?'),
              const SizedBox(height: 12),
              for (var row = 0; row < 2; row++) ...[
                Row(
                  children: [
                    for (var column = 0; column < 2; column++) ...[
                      if (column > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _CustomChallengeCountTile(
                          definition: _CustomChallengeDefinition
                              .values[row * 2 + column],
                          selected:
                              _definition.kind ==
                              _CustomChallengeDefinition
                                  .values[row * 2 + column]
                                  .kind,
                          onTap: () => setState(() {
                            _definition = _CustomChallengeDefinition
                                .values[row * 2 + column];
                            _specificExercise = null;
                            _goal = 5;
                          }),
                        ),
                      ),
                    ],
                  ],
                ),
                if (row == 0) const SizedBox(height: 10),
              ],
              if (_definition.kind == _CustomChallengeCount.workout ||
                  _definition.kind == _CustomChallengeCount.activity) ...[
                const SizedBox(height: 22),
                _ChallengeSheetLabel(
                  _definition.kind == _CustomChallengeCount.workout
                      ? 'SPECIFIC WORKOUT'
                      : 'SPECIFIC ACTIVITY',
                ),
                const SizedBox(height: 10),
                _CustomActivityPicker(
                  value: _specificExercise,
                  exercises: _availableSpecificExercises,
                  anyLabel: _definition.kind == _CustomChallengeCount.workout
                      ? 'Any workout'
                      : 'Any activity',
                  fallbackIcon: _definition.icon,
                  fallbackColor: _definition.color,
                  onChanged: (value) =>
                      setState(() => _specificExercise = value),
                ),
              ],
              const SizedBox(height: 22),
              _CustomChallengeSlider(
                sectionLabel: 'GOAL',
                valueLabel: '$_goal ${_definition.unit}',
                minimumLabel: '1',
                maximumLabel: '20',
                value: _goal,
                minimum: 1,
                maximum: 20,
                onChanged: (value) => setState(() => _goal = value),
              ),
              const SizedBox(height: 22),
              const _ChallengeSheetLabel('CHALLENGE FRIENDS'),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
                const SizedBox(
                  height: 105,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: CircleScreen._purple,
                    ),
                  ),
                )
              else if (friends.isEmpty)
                _ChallengeNoFriendsCard(
                  onClose: () => Navigator.maybePop(context),
                )
              else
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: friends.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 20),
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      return _ChallengeFriendChoice(
                        profile: friend,
                        selected: _selectedFriendUids.contains(friend.uid),
                        onTap: () => setState(() {
                          if (!_selectedFriendUids.add(friend.uid)) {
                            _selectedFriendUids.remove(friend.uid);
                          }
                        }),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              _CustomChallengeSlider(
                sectionLabel: 'DURATION',
                valueLabel:
                    '$_durationDays day${_durationDays == 1 ? '' : 's'}',
                minimumLabel: '1 day',
                maximumLabel: '30 days',
                value: _durationDays,
                minimum: 1,
                maximum: 30,
                onChanged: (value) => setState(() => _durationDays = value),
              ),
              const SizedBox(height: 22),
              _ChallengeMessageField(controller: _messageController),
              const SizedBox(height: 18),
              _CustomChallengeSummary(
                definition: _definition,
                specificExercise: _specificExercise,
                goal: _goal,
                friends: selectedFriends,
                durationDays: _durationDays,
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: selectedFriends.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _CustomChallengeDraft(
                            definition: _definition,
                            specificExercise: _specificExercise,
                            goal: _goal,
                            friends: List.unmodifiable(selectedFriends),
                            durationDays: _durationDays,
                            message: _messageController.text.trim(),
                          ),
                        ),
                  icon: const Icon(Icons.send_rounded, size: 22),
                  label: const Text('Send Challenge'),
                  style: FilledButton.styleFrom(
                    backgroundColor: CircleScreen._purple,
                    disabledBackgroundColor: context.vivordoColors.cardMuted,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: CircleScreen._muted,
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  List<WorkoutExerciseCatalogItem> get _availableSpecificExercises {
    if (_definition.kind == _CustomChallengeCount.activity) {
      return workoutExerciseCatalog
          .where(
            (exercise) =>
                exercise.category == 'Cardio' || exercise.category == 'Sports',
          )
          .toList(growable: false);
    }
    return workoutExerciseCatalog;
  }
}

class _CustomChallengeCountTile extends StatelessWidget {
  const _CustomChallengeCountTile({
    required this.definition,
    required this.selected,
    required this.onTap,
  });

  final _CustomChallengeDefinition definition;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.vivordoColors.card,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 100,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? CircleScreen._purple
                : context.vivordoColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: definition.color.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(definition.icon, color: definition.color, size: 25),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    definition.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.vivordoColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    definition.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CircleScreen._muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CustomActivityPicker extends StatelessWidget {
  const _CustomActivityPicker({
    required this.value,
    required this.exercises,
    required this.anyLabel,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.onChanged,
  });

  final String? value;
  final List<WorkoutExerciseCatalogItem> exercises;
  final String anyLabel;
  final IconData fallbackIcon;
  final Color fallbackColor;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedExercise = exercises
        .where((exercise) => exercise.name == value)
        .firstOrNull;
    final visual = selectedExercise == null
        ? WorkoutActivityVisual(fallbackIcon, fallbackColor)
        : workoutActivityVisual(
            selectedExercise.name,
            category: selectedExercise.category,
          );
    return Material(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          final selection =
              await showModalBottomSheet<_SpecificExerciseSelection>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _SpecificExerciseSearchSheet(
                  exercises: exercises,
                  selectedValue: value,
                  anyLabel: anyLabel,
                  fallbackIcon: fallbackIcon,
                  fallbackColor: fallbackColor,
                ),
              );
          if (selection != null) onChanged(selection.value);
        },
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.vivordoColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: visual.color.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(visual.icon, color: visual.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selectedExercise?.name ?? anyLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: context.vivordoColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpecificExerciseSelection {
  const _SpecificExerciseSelection(this.value);

  final String? value;
}

class _SpecificExerciseSearchSheet extends StatefulWidget {
  const _SpecificExerciseSearchSheet({
    required this.exercises,
    required this.selectedValue,
    required this.anyLabel,
    required this.fallbackIcon,
    required this.fallbackColor,
  });

  final List<WorkoutExerciseCatalogItem> exercises;
  final String? selectedValue;
  final String anyLabel;
  final IconData fallbackIcon;
  final Color fallbackColor;

  @override
  State<_SpecificExerciseSearchSheet> createState() =>
      _SpecificExerciseSearchSheetState();
}

class _SpecificExerciseSearchSheetState
    extends State<_SpecificExerciseSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<WorkoutExerciseCatalogItem> get _filteredExercises {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.exercises;
    return widget.exercises
        .where(
          (exercise) =>
              exercise.name.toLowerCase().contains(query) ||
              exercise.category.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final exercises = _filteredExercises;
    final isActivityPicker = widget.anyLabel.toLowerCase().contains('activity');
    final subjectLabel = isActivityPicker ? 'Activity' : 'Workout';
    return FractionallySizedBox(
      heightFactor: .82,
      child: Material(
        color: context.vivordoColors.page,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: context.vivordoColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select $subjectLabel',
                      style: TextStyle(
                        color: context.vivordoColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _ChallengeSheetCloseButton(
                    onTap: () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search ${subjectLabel.toLowerCase()}s',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: context.vivordoColors.input,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  if (_query.trim().isEmpty) ...[
                    _SpecificExerciseResultTile(
                      title: widget.anyLabel,
                      subtitle: 'Count any matching session',
                      icon: widget.fallbackIcon,
                      color: widget.fallbackColor,
                      selected: widget.selectedValue == null,
                      onTap: () => Navigator.pop(
                        context,
                        const _SpecificExerciseSelection(null),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (exercises.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 44),
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 42,
                            color: context.vivordoColors.textSecondary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No ${subjectLabel.toLowerCase()}s found',
                            style: TextStyle(
                              color: context.vivordoColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final exercise in exercises) ...[
                      Builder(
                        builder: (context) {
                          final visual = workoutActivityVisual(
                            exercise.name,
                            category: exercise.category,
                          );
                          return _SpecificExerciseResultTile(
                            title: exercise.name,
                            subtitle: exercise.category,
                            icon: visual.icon,
                            color: visual.color,
                            selected: widget.selectedValue == exercise.name,
                            onTap: () => Navigator.pop(
                              context,
                              _SpecificExerciseSelection(exercise.name),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecificExerciseResultTile extends StatelessWidget {
  const _SpecificExerciseResultTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.vivordoColors.card,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? CircleScreen._purple
                : context.vivordoColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 23),
            ),
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
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.vivordoColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: CircleScreen._purple,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _CustomChallengeSlider extends StatelessWidget {
  const _CustomChallengeSlider({
    required this.sectionLabel,
    required this.valueLabel,
    required this.minimumLabel,
    required this.maximumLabel,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
  });

  final String sectionLabel;
  final String valueLabel;
  final String minimumLabel;
  final String maximumLabel;
  final int value;
  final int minimum;
  final int maximum;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          _ChallengeSheetLabel(sectionLabel),
          const Spacer(),
          Text(
            valueLabel,
            style: TextStyle(
              color: context.vivordoColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: CircleScreen._purple,
          inactiveTrackColor: context.vivordoColors.cardMuted,
          thumbColor: CircleScreen._purple,
          overlayColor: CircleScreen._purple.withValues(alpha: .13),
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 19),
        ),
        child: Slider(
          value: value.toDouble(),
          min: minimum.toDouble(),
          max: maximum.toDouble(),
          divisions: maximum - minimum,
          label: valueLabel,
          semanticFormatterCallback: (_) => valueLabel,
          onChanged: (rawValue) => onChanged(rawValue.round()),
        ),
      ),
      Row(
        children: [
          Text(
            minimumLabel,
            style: const TextStyle(color: CircleScreen._muted, fontSize: 11),
          ),
          const Spacer(),
          Text(
            maximumLabel,
            style: const TextStyle(color: CircleScreen._muted, fontSize: 11),
          ),
        ],
      ),
    ],
  );
}

class _CustomChallengeSummary extends StatelessWidget {
  const _CustomChallengeSummary({
    required this.definition,
    required this.specificExercise,
    required this.goal,
    required this.friends,
    required this.durationDays,
  });

  final _CustomChallengeDefinition definition;
  final String? specificExercise;
  final int goal;
  final List<CircleProfile> friends;
  final int durationDays;

  @override
  Widget build(BuildContext context) {
    final subject = specificExercise ?? definition.title;
    final friendLabel = switch (friends.length) {
      0 => 'Select friends',
      1 => friends.first.username,
      _ => '${friends.first.username} + ${friends.length - 1}',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.vivordoColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: definition.color.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(definition.icon, color: definition.color, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$subject with $friendLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Complete $goal ${definition.unit} · $durationDays day${durationDays == 1 ? '' : 's'}',
                  maxLines: 2,
                  style: const TextStyle(
                    color: CircleScreen._muted,
                    fontSize: 12,
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

enum _QuickChallengeKind { workoutStreak, stepSprint, pulseCheck }

class _QuickChallengeDefinition {
  const _QuickChallengeDefinition.workoutStreak()
    : kind = _QuickChallengeKind.workoutStreak,
      title = 'Workout Streak',
      description = 'Complete workouts together',
      icon = Icons.fitness_center_rounded,
      color = CircleScreen._purple,
      initialGoal = 5,
      goalStep = 1,
      minimumGoal = 1,
      maximumGoal = 100;

  const _QuickChallengeDefinition.stepSprint()
    : kind = _QuickChallengeKind.stepSprint,
      title = 'Step Sprint',
      description = 'Reach a step goal together',
      icon = Icons.directions_walk_rounded,
      color = const Color(0xFF0FB986),
      initialGoal = 30000,
      goalStep = 5000,
      minimumGoal = 5000,
      maximumGoal = 1000000;

  const _QuickChallengeDefinition.pulseCheck()
    : kind = _QuickChallengeKind.pulseCheck,
      title = 'Pulse Check',
      description = 'Complete heart-rate scans together',
      icon = Icons.monitor_heart_rounded,
      color = const Color(0xFFFF5264),
      initialGoal = 5,
      goalStep = 1,
      minimumGoal = 1,
      maximumGoal = 100;

  final _QuickChallengeKind kind;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final int initialGoal;
  final int goalStep;
  final int minimumGoal;
  final int maximumGoal;

  String get backendType => switch (kind) {
    _QuickChallengeKind.workoutStreak => 'workout_count',
    _QuickChallengeKind.stepSprint => 'step_total',
    _QuickChallengeKind.pulseCheck => 'scan_count',
  };

  String goalLabel(int goal) => switch (kind) {
    _QuickChallengeKind.workoutStreak => '$goal workout${goal == 1 ? '' : 's'}',
    _QuickChallengeKind.stepSprint =>
      '${NumberFormat.decimalPattern().format(goal)} steps',
    _QuickChallengeKind.pulseCheck => '$goal scan${goal == 1 ? '' : 's'}',
  };
}

class _QuickChallengeDraft {
  const _QuickChallengeDraft({
    required this.challenge,
    required this.friends,
    required this.goal,
    required this.durationDays,
    required this.message,
  });

  final _QuickChallengeDefinition challenge;
  final List<CircleProfile> friends;
  final int goal;
  final int durationDays;
  final String message;
}

class _CreateQuickChallengeSheet extends StatefulWidget {
  const _CreateQuickChallengeSheet({required this.challenge});

  final _QuickChallengeDefinition challenge;

  @override
  State<_CreateQuickChallengeSheet> createState() =>
      _CreateQuickChallengeSheetState();
}

class _CreateQuickChallengeSheetState
    extends State<_CreateQuickChallengeSheet> {
  final Set<String> _selectedFriendUids = {};
  final TextEditingController _messageController = TextEditingController();
  late int _goal;
  var _durationDays = 7;

  @override
  void initState() {
    super.initState();
    _goal = widget.challenge.initialGoal;
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .9,
    minChildSize: .68,
    maxChildSize: .96,
    expand: false,
    builder: (context, scrollController) => Container(
      decoration: BoxDecoration(
        color: context.vivordoColors.page,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: StreamBuilder<List<CircleProfile>>(
        stream: CircleProfileService.watchFriends(),
        builder: (context, snapshot) {
          final friends = snapshot.data ?? const <CircleProfile>[];
          final selectedFriends = friends
              .where((friend) => _selectedFriendUids.contains(friend.uid))
              .toList(growable: false);
          return ListView(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.vivordoColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Create Challenge',
                      style: TextStyle(
                        color: context.vivordoColors.textPrimary,
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  _ChallengeSheetCloseButton(
                    onTap: () => Navigator.maybePop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _ChallengeTypeSummary(challenge: widget.challenge),
              const SizedBox(height: 22),
              const _ChallengeSheetLabel('CHALLENGE FRIENDS'),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
                const SizedBox(
                  height: 105,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: CircleScreen._purple,
                    ),
                  ),
                )
              else if (friends.isEmpty)
                _ChallengeNoFriendsCard(
                  onClose: () => Navigator.maybePop(context),
                )
              else
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    itemCount: friends.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 20),
                    itemBuilder: (context, index) {
                      final friend = friends[index];
                      return _ChallengeFriendChoice(
                        profile: friend,
                        selected: _selectedFriendUids.contains(friend.uid),
                        onTap: () => setState(() {
                          if (!_selectedFriendUids.add(friend.uid)) {
                            _selectedFriendUids.remove(friend.uid);
                          }
                        }),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              const _ChallengeSheetLabel('GOAL'),
              const SizedBox(height: 10),
              _ChallengeValueSlider(
                label: widget.challenge.goalLabel(_goal),
                minimumLabel: widget.challenge.goalLabel(
                  widget.challenge.minimumGoal,
                ),
                maximumLabel: widget.challenge.goalLabel(
                  widget.challenge.maximumGoal,
                ),
                value: _goal,
                minimum: widget.challenge.minimumGoal,
                maximum: widget.challenge.maximumGoal,
                step: widget.challenge.goalStep,
                onChanged: (value) => setState(() => _goal = value),
              ),
              const SizedBox(height: 22),
              const _ChallengeSheetLabel('DURATION'),
              const SizedBox(height: 10),
              _ChallengeValueSlider(
                label: '$_durationDays day${_durationDays == 1 ? '' : 's'}',
                minimumLabel: '1 day',
                maximumLabel: '14 days',
                value: _durationDays,
                minimum: 1,
                maximum: 14,
                step: 1,
                onChanged: (value) => setState(() => _durationDays = value),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    color: CircleScreen._muted,
                    size: 19,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Ends ${DateFormat('MMMM d').format(DateTime.now().add(Duration(days: _durationDays)))}',
                    style: const TextStyle(
                      color: CircleScreen._muted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _ChallengeMessageField(controller: _messageController),
              const SizedBox(height: 24),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: selectedFriends.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _QuickChallengeDraft(
                            challenge: widget.challenge,
                            friends: List.unmodifiable(selectedFriends),
                            goal: _goal,
                            durationDays: _durationDays,
                            message: _messageController.text.trim(),
                          ),
                        ),
                  icon: const Icon(Icons.send_rounded, size: 21),
                  label: const Text('Send Challenge'),
                  style: FilledButton.styleFrom(
                    backgroundColor: CircleScreen._purple,
                    disabledBackgroundColor: context.vivordoColors.cardMuted,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: CircleScreen._muted,
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                selectedFriends.isEmpty
                    ? 'Select at least one friend to continue.'
                    : '${_acceptanceLabel(selectedFriends)} will need to accept before it starts.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 13,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  String _acceptanceLabel(List<CircleProfile> friends) {
    if (friends.length == 1) return friends.first.username;
    if (friends.length == 2) {
      return '${friends.first.username} and ${friends.last.username}';
    }
    return '${friends.first.username} and ${friends.length - 1} others';
  }
}

class _ChallengeSheetCloseButton extends StatelessWidget {
  const _ChallengeSheetCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: context.vivordoColors.cardMuted,
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 46,
        height: 46,
        child: Icon(
          Icons.close_rounded,
          color: context.vivordoColors.textPrimary,
        ),
      ),
    ),
  );
}

class _ChallengeTypeSummary extends StatelessWidget {
  const _ChallengeTypeSummary({required this.challenge});

  final _QuickChallengeDefinition challenge;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: challenge.color.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: Icon(challenge.icon, color: challenge.color, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                challenge.title,
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                challenge.description,
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ChallengeMessageField extends StatelessWidget {
  const _ChallengeMessageField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _ChallengeSheetLabel('MESSAGE (OPTIONAL)'),
      const SizedBox(height: 10),
      TextField(
        controller: controller,
        minLines: 2,
        maxLines: 3,
        maxLength: 200,
        textCapitalization: TextCapitalization.sentences,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        style: TextStyle(
          color: context.vivordoColors.textPrimary,
          fontSize: 15,
          height: 1.35,
        ),
        decoration: InputDecoration(
          hintText: 'Add a note for your friends…',
          hintStyle: const TextStyle(color: CircleScreen._muted),
          filled: true,
          fillColor: context.vivordoColors.card,
          counterStyle: const TextStyle(
            color: CircleScreen._muted,
            fontSize: 11,
          ),
          contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: BorderSide(color: context.vivordoColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(
              color: CircleScreen._purple,
              width: 1.5,
            ),
          ),
        ),
      ),
    ],
  );
}

class _ChallengeSheetLabel extends StatelessWidget {
  const _ChallengeSheetLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: CircleScreen._muted,
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: .45,
    ),
  );
}

class _ChallengeFriendChoice extends StatelessWidget {
  const _ChallengeFriendChoice({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final CircleProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 70,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(34),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? CircleScreen._purple : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: _ProfileAvatar(profile: profile, radius: 28),
              ),
              if (selected)
                const Positioned(
                  right: -1,
                  bottom: 1,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: CircleScreen._purple,
                    child: Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            profile.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? context.vivordoColors.textPrimary
                  : CircleScreen._muted,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChallengeNoFriendsCard extends StatelessWidget {
  const _ChallengeNoFriendsCard({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Row(
      children: [
        const Icon(Icons.person_add_alt_1_rounded, color: CircleScreen._purple),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Add a Circle friend before creating a challenge.',
            style: TextStyle(
              color: context.vivordoColors.textPrimary,
              fontSize: 14,
            ),
          ),
        ),
        TextButton(onPressed: onClose, child: const Text('Close')),
      ],
    ),
  );
}

class _ChallengeValueSlider extends StatelessWidget {
  const _ChallengeValueSlider({
    required this.label,
    required this.minimumLabel,
    required this.maximumLabel,
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final String minimumLabel;
  final String maximumLabel;
  final int value;
  final int minimum;
  final int maximum;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: CircleScreen._purple,
            inactiveTrackColor: context.vivordoColors.cardMuted,
            thumbColor: CircleScreen._purple,
            overlayColor: CircleScreen._purple.withValues(alpha: .13),
            trackHeight: 5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            value: value.toDouble(),
            min: minimum.toDouble(),
            max: maximum.toDouble(),
            divisions: (maximum - minimum) ~/ step,
            label: label,
            semanticFormatterCallback: (_) => label,
            onChanged: (rawValue) {
              final steppedValue =
                  minimum + (((rawValue - minimum) / step).round() * step);
              onChanged(steppedValue.clamp(minimum, maximum));
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                minimumLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 11,
                ),
              ),
            ),
            Expanded(
              child: Text(
                maximumLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

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
  String get visibleBadgeAsset =>
      unlocked ? earnedBadgeAsset ?? goalBadgeAsset : goalBadgeAsset;

  _Achievement copyWith({bool? earned, DateTime? earnedAt}) => _Achievement(
    id: id,
    name: name,
    requirement: requirement,
    goalBadgeAsset: goalBadgeAsset,
    earnedBadgeAsset: earnedBadgeAsset,
    earned: earned ?? this.earned,
    progress: progress,
    target: target,
    tier: tier,
    goalTier: goalTier,
    progressUnit: progressUnit,
    earnedAt: earnedAt ?? this.earnedAt,
  );
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

  List<_Achievement> get _oneTime => widget.achievements
      .where((achievement) => achievement.target == 1)
      .toList(growable: false);

  List<_Achievement> get _tiered => widget.achievements
      .where((achievement) => achievement.target > 1)
      .toList(growable: false);

  bool _matchesOneTimeFilter(_Achievement achievement) => switch (_filter) {
    _AchievementFilter.all => true,
    _AchievementFilter.earned => achievement.earned || achievement.tier != null,
    _AchievementFilter.inProgress =>
      !achievement.earned && (achievement.unlocked || achievement.progress > 0),
    _AchievementFilter.locked =>
      !achievement.unlocked && !achievement.earned && achievement.progress == 0,
  };

  bool _matchesTieredFilter(_Achievement achievement) => switch (_filter) {
    _AchievementFilter.all => true,
    _AchievementFilter.earned => achievement.tier != null,
    _AchievementFilter.inProgress =>
      !achievement.earned && (achievement.unlocked || achievement.progress > 0),
    _AchievementFilter.locked =>
      !achievement.earned && achievement.goalTier != null,
  };

  @override
  Widget build(BuildContext context) {
    final oneTime = _oneTime;
    final tiered = _tiered;
    final visibleOneTime = oneTime
        .where(_matchesOneTimeFilter)
        .toList(growable: false);
    final visibleTiered = tiered
        .where(_matchesTieredFilter)
        .toList(growable: false);
    final oneTimeEarned = oneTime
        .where((achievement) => achievement.earned)
        .length;
    final tieredEarned = tiered.fold<int>(
      0,
      (total, achievement) => total + _tierRankForDisplay(achievement.tier),
    );
    final earned = oneTimeEarned + tieredEarned;
    final total = oneTime.length + (tiered.length * 3);
    final percent = total == 0 ? 0 : ((earned / total) * 100).round();
    final inProgress = widget.achievements
        .where(
          (achievement) =>
              !achievement.earned &&
              (achievement.unlocked || achievement.progress > 0),
        )
        .length;
    final recentlyEarned =
        widget.achievements
            .where((achievement) => achievement.unlocked)
            .toList()
          ..sort(
            (a, b) => (b.earnedAt ?? DateTime(1970)).compareTo(
              a.earnedAt ?? DateTime(1970),
            ),
          );

    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 44),
          children: [
            _AchievementsHeader(onFilterPressed: _showFilterSheet),
            const SizedBox(height: 24),
            _AchievementSummaryCard(
              earned: earned,
              total: total,
              inProgress: inProgress,
              percent: percent,
            ),
            const SizedBox(height: 28),
            const _CircleSectionTitle('RECENTLY EARNED'),
            const SizedBox(height: 12),
            if (recentlyEarned.isEmpty)
              const _ChallengeEmptyCard(
                icon: Icons.workspace_premium_rounded,
                title: 'Nothing earned yet',
                detail: 'Completed achievements will appear here.',
              )
            else
              _RecentlyEarnedCard(
                achievements: recentlyEarned.take(3).toList(),
                onAchievementTap: _showAchievementDetails,
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                for (final filter in _AchievementFilter.values) ...[
                  if (filter != _AchievementFilter.all)
                    const SizedBox(width: 8),
                  Expanded(
                    child: _AchievementFilterChip(
                      filter: filter,
                      selected: _filter == filter,
                      onTap: () => setState(() => _filter = filter),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 28),
            _AchievementPageSectionHeader(
              title: 'ONE-TIME',
              count: '$oneTimeEarned / ${oneTime.length}',
            ),
            const SizedBox(height: 12),
            if (visibleOneTime.isEmpty)
              const _AchievementFilteredEmpty()
            else
              _OneTimeAchievementGrid(
                achievements: visibleOneTime,
                onAchievementTap: _showAchievementDetails,
              ),
            const SizedBox(height: 28),
            _AchievementPageSectionHeader(
              title: 'TIERED ACHIEVEMENTS',
              count: '$tieredEarned / ${tiered.length * 3}',
            ),
            const SizedBox(height: 12),
            if (visibleTiered.isEmpty)
              const _AchievementFilteredEmpty()
            else
              for (var index = 0; index < visibleTiered.length; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                _TieredAchievementCard(
                  achievement: visibleTiered[index],
                  showCompletedTiers: _filter == _AchievementFilter.earned,
                  showNextTier: _filter == _AchievementFilter.locked,
                  onTap: () => _showAchievementDetails(
                    visibleTiered[index],
                    showNextTier: _filter == _AchievementFilter.locked,
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          decoration: BoxDecoration(
            color: sheetContext.vivordoColors.card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: sheetContext.vivordoColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: sheetContext.vivordoColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Filter achievements',
                style: TextStyle(
                  color: sheetContext.vivordoColors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              for (final filter in _AchievementFilter.values)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  title: Text(_achievementFilterLabel(filter)),
                  trailing: Icon(
                    _filter == filter
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: _filter == filter
                        ? CircleScreen._purple
                        : CircleScreen._muted,
                  ),
                  onTap: () {
                    setState(() => _filter = filter);
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAchievementDetails(
    _Achievement achievement, {
    bool showNextTier = false,
  }) {
    final unit = achievement.progressUnit ?? 'activities';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
          decoration: BoxDecoration(
            color: sheetContext.vivordoColors.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: sheetContext.vivordoColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: sheetContext.vivordoColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 20),
              _AchievementCollectionBadge(
                achievement: achievement,
                size: 94,
                showGoalTier: showNextTier,
              ),
              const SizedBox(height: 14),
              Text(
                achievement.name,
                style: TextStyle(
                  color: sheetContext.vivordoColors.textPrimary,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                achievement.target > 1
                    ? _tieredAchievementGoalDescription(achievement)
                    : achievement.requirement,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '${achievement.progress} / ${achievement.target} $unit',
                style: const TextStyle(
                  color: CircleScreen._purple,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: (achievement.progress / achievement.target).clamp(
                    0,
                    1,
                  ),
                  minHeight: 8,
                  color: CircleScreen._purple,
                  backgroundColor: sheetContext.vivordoColors.cardMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementsHeader extends StatelessWidget {
  const _AchievementsHeader({required this.onFilterPressed});

  final VoidCallback onFilterPressed;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _AchievementHeaderButton(
        icon: Icons.chevron_left_rounded,
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).pop(),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Text(
          'Achievements',
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -.7,
          ),
        ),
      ),
      _AchievementHeaderButton(
        icon: Icons.tune_rounded,
        tooltip: 'Filter achievements',
        onPressed: onFilterPressed,
      ),
    ],
  );
}

class _AchievementHeaderButton extends StatelessWidget {
  const _AchievementHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: context.vivordoColors.card,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            border: Border.all(color: context.vivordoColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: context.vivordoColors.textPrimary, size: 28),
        ),
      ),
    ),
  );
}

class _AchievementSummaryCard extends StatelessWidget {
  const _AchievementSummaryCard({
    required this.earned,
    required this.total,
    required this.inProgress,
    required this.percent,
  });

  final int earned;
  final int total;
  final int inProgress;
  final int percent;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$earned of $total earned',
                  maxLines: 1,
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Keep building healthy habits',
                style: TextStyle(color: CircleScreen._muted, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : earned / total,
                  minHeight: 7,
                  color: CircleScreen._purple,
                  backgroundColor: context.vivordoColors.cardMuted,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '$inProgress in progress',
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        _AchievementPercentRing(percent: percent),
      ],
    ),
  );
}

class _AchievementPercentRing extends StatelessWidget {
  const _AchievementPercentRing({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 106,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CircularProgressIndicator(
            value: percent / 100,
            strokeWidth: 9,
            color: CircleScreen._purple,
            backgroundColor: context.vivordoColors.cardMuted,
          ),
        ),
        Text(
          '$percent%',
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            color: CircleScreen._purple,
            fontSize: 27,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _AchievementFilterChip extends StatelessWidget {
  const _AchievementFilterChip({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final _AchievementFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? CircleScreen._purple : context.vivordoColors.card,
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? CircleScreen._purple
                : context.vivordoColors.border,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _achievementFilterLabel(filter),
            maxLines: 1,
            style: TextStyle(
              color: selected ? Colors.white : CircleScreen._muted,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}

String _achievementFilterLabel(_AchievementFilter filter) => switch (filter) {
  _AchievementFilter.all => 'All',
  _AchievementFilter.earned => 'Earned',
  _AchievementFilter.inProgress => 'In Progress',
  _AchievementFilter.locked => 'Locked',
};

class _AchievementPageSectionHeader extends StatelessWidget {
  const _AchievementPageSectionHeader({
    required this.title,
    required this.count,
  });

  final String title;
  final String count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _CircleSectionTitle(title)),
      Text(
        count,
        style: const TextStyle(color: CircleScreen._muted, fontSize: 14),
      ),
    ],
  );
}

class _OneTimeAchievementGrid extends StatelessWidget {
  const _OneTimeAchievementGrid({
    required this.achievements,
    required this.onAchievementTap,
  });

  final List<_Achievement> achievements;
  final ValueChanged<_Achievement> onAchievementTap;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: achievements.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 18,
        crossAxisSpacing: 8,
        mainAxisExtent: 146,
      ),
      itemBuilder: (context, index) => _OneTimeAchievementItem(
        achievement: achievements[index],
        onTap: () => onAchievementTap(achievements[index]),
      ),
    ),
  );
}

class _OneTimeAchievementItem extends StatelessWidget {
  const _OneTimeAchievementItem({
    required this.achievement,
    required this.onTap,
  });

  final _Achievement achievement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          _AchievementCollectionBadge(achievement: achievement, size: 72),
          const SizedBox(height: 7),
          Text(
            achievement.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.vivordoColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                achievement.earned
                    ? Icons.check_circle_rounded
                    : Icons.lock_rounded,
                size: 15,
                color: achievement.earned
                    ? const Color(0xFF18B747)
                    : CircleScreen._muted,
              ),
              const SizedBox(width: 4),
              Text(
                achievement.earned ? 'Earned' : 'Locked',
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (achievement.earned && achievement.earnedAt != null) ...[
            const SizedBox(height: 3),
            Text(
              DateFormat('MMM d').format(achievement.earnedAt!),
              style: const TextStyle(color: CircleScreen._muted, fontSize: 10),
            ),
          ],
        ],
      ),
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
    if (!locked) return badge;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        .2126,
        .7152,
        .0722,
        0,
        0,
        .2126,
        .7152,
        .0722,
        0,
        0,
        .2126,
        .7152,
        .0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: badge,
    );
  }
}

class _TieredAchievementCard extends StatelessWidget {
  const _TieredAchievementCard({
    required this.achievement,
    required this.showCompletedTiers,
    this.showNextTier = false,
    required this.onTap,
  });

  final _Achievement achievement;
  final bool showCompletedTiers;
  final bool showNextTier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tier = showNextTier
        ? achievement.goalTier ?? 'bronze'
        : achievement.tier ?? achievement.goalTier ?? 'bronze';
    final tierColor = _achievementTierColor(tier);
    final tierStatus = showNextTier
        ? '${_tierLabel(achievement.goalTier ?? 'bronze')} next'
        : achievement.earned
        ? 'Gold earned'
        : achievement.tier != null
        ? '${_tierLabel(achievement.tier!)} earned'
        : '${_tierLabel(achievement.goalTier ?? 'bronze')} next';
    return Material(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.vivordoColors.border),
          ),
          child: Row(
            children: [
              _AchievementCollectionBadge(
                achievement: achievement,
                size: 72,
                showGoalTier: showNextTier,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            achievement.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.vivordoColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          '${achievement.progress} / ${achievement.target}',
                          style: TextStyle(
                            color: context.vivordoColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _tieredAchievementGoalDescription(achievement),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CircleScreen._muted,
                        fontSize: 13,
                      ),
                    ),
                    if (showCompletedTiers && achievement.tier != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (
                            var rank = 1;
                            rank <= _tierRankForDisplay(achievement.tier);
                            rank++
                          )
                            _CompletedTierPill(tier: _tierForRank(rank)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (achievement.progress / achievement.target)
                                  .clamp(0, 1),
                              minHeight: 6,
                              color: CircleScreen._purple,
                              backgroundColor: context.vivordoColors.cardMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            tierStatus,
                            style: TextStyle(
                              color: tierColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                Icons.chevron_right_rounded,
                color: CircleScreen._muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedTierPill extends StatelessWidget {
  const _CompletedTierPill({required this.tier});

  final String tier;

  @override
  Widget build(BuildContext context) {
    final color = _achievementTierColor(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, color: color, size: 12),
          const SizedBox(width: 3),
          Text(
            _tierLabel(tier),
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

String _tierForRank(int rank) => switch (rank) {
  1 => 'bronze',
  2 => 'silver',
  _ => 'gold',
};

String _tieredAchievementGoalDescription(_Achievement achievement) {
  final goalTier = achievement.goalTier ?? achievement.tier ?? 'bronze';
  return '${_tierLabel(goalTier)} goal: ${achievement.requirement}';
}

String _achievementRequirementForTier(_Achievement achievement, String? tier) {
  if (tier == null) return achievement.requirement;
  final target = switch ((achievement.id, tier)) {
    ('workout_momentum', 'bronze') => 5,
    ('workout_momentum', 'silver') => 10,
    ('workout_momentum', 'gold') => 100,
    ('endurance', 'bronze') => 5,
    ('endurance', 'silver') => 10,
    ('endurance', 'gold') => 100,
    ('pulse_check', 'bronze') => 10,
    ('pulse_check', 'silver') => 100,
    ('pulse_check', 'gold') => 1000,
    ('story_keeper', 'bronze') => 5,
    ('story_keeper', 'silver') => 20,
    ('story_keeper', 'gold') => 100,
    _ => null,
  };
  if (target == null) return achievement.requirement;
  return switch (achievement.id) {
    'workout_momentum' => 'Complete $target strength workouts',
    'endurance' => 'Complete $target cardio or sports activities',
    'pulse_check' => 'Complete $target heart-rate scans',
    'story_keeper' => 'Write $target journal entries',
    _ => achievement.requirement,
  };
}

Color _achievementTierColor(String tier) => switch (tier) {
  'gold' => const Color(0xFFD99A17),
  'silver' => const Color(0xFF7F899B),
  _ => const Color(0xFFC86A31),
};

int _tierRankForDisplay(String? tier) => switch (tier) {
  'bronze' => 1,
  'silver' => 2,
  'gold' => 3,
  _ => 0,
};

class _AchievementFilteredEmpty extends StatelessWidget {
  const _AchievementFilteredEmpty();

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Text(
        'No achievements match this filter.',
        textAlign: TextAlign.center,
        style: TextStyle(color: CircleScreen._muted, fontSize: 13),
      ),
    ),
  );
}

String _tierLabel(String tier) => switch (tier) {
  'bronze' => 'Bronze',
  'silver' => 'Silver',
  'gold' => 'Gold',
  _ => tier,
};

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
    opacity: locked ? .32 : 1,
    child: SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          alignment: Alignment.center,
          fit: BoxFit.cover,
        ),
      ),
    ),
  );
}

class _NextAchievementSummary extends StatelessWidget {
  const _NextAchievementSummary({required this.achievement});

  final _Achievement achievement;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _AchievementBadge(assetPath: achievement.goalBadgeAsset, size: 52),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Next: ${achievement.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.vivordoColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${achievement.progress}/${achievement.target}',
                  style: const TextStyle(
                    color: CircleScreen._purple,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              achievement.goalTier == null
                  ? achievement.requirement
                  : '${_tierLabel(achievement.goalTier!)} tier · ${achievement.requirement}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CircleScreen._muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: (achievement.progress / achievement.target).clamp(0, 1),
                minHeight: 6,
                color: CircleScreen._purple,
                backgroundColor: context.vivordoColors.cardMuted,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _RecentlyEarnedCard extends StatelessWidget {
  const _RecentlyEarnedCard({
    required this.achievements,
    this.onAchievementTap,
  });

  final List<_Achievement> achievements;
  final ValueChanged<_Achievement>? onAchievementTap;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < achievements.length; index++) ...[
            if (index > 0)
              Container(
                width: 1,
                height: 92,
                color: context.vivordoColors.border,
              ),
            Expanded(
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: onAchievementTap == null
                      ? null
                      : () => onAchievementTap!(achievements[index]),
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    children: [
                      _AchievementBadge(
                        assetPath: achievements[index].visibleBadgeAsset,
                        size: 62,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        achievements[index].tier == null
                            ? achievements[index].name
                            : '${achievements[index].name} · ${_tierLabel(achievements[index].tier!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.vivordoColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _CircleSectionTitle extends StatelessWidget {
  const _CircleSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: CircleScreen._muted,
      fontSize: 14,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
    ),
  );
}

class _ChallengeProgressRing extends StatelessWidget {
  const _ChallengeProgressRing({required this.earned, required this.total});

  final int earned;
  final int total;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 96,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CircularProgressIndicator(
            value: total == 0 ? 0 : earned / total,
            strokeWidth: 7,
            backgroundColor: context.vivordoColors.cardMuted,
            color: CircleScreen._purple,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$earned',
                    style: const TextStyle(
                      color: CircleScreen._purple,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: ' / $total',
                    style: const TextStyle(
                      color: CircleScreen._muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              textScaler: TextScaler.noScaling,
              maxLines: 1,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ChallengeEmptyCard extends StatelessWidget {
  const _ChallengeEmptyCard({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: context.vivordoColors.cardMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: CircleScreen._muted, size: 27),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.vivordoColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: CircleScreen._muted,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.profile, super.key});

  final CircleProfile profile;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'THIS WEEK',
        style: TextStyle(
          color: CircleScreen._muted,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.6,
        ),
      ),
      const SizedBox(height: 14),
      const _CircleFitnessSummary(),
      const SizedBox(height: 14),
      _YourCircleCard(profile: profile),
      const SizedBox(height: 28),
      const Text(
        'MY ACTIVITY',
        style: TextStyle(
          color: CircleScreen._muted,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 14),
      _MyCircleActivityFeed(profile: profile),
      const SizedBox(height: 28),
      const Text(
        'FRIENDS ACTIVITY',
        style: TextStyle(
          color: CircleScreen._muted,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 14),
      const _CircleRecentActivityFeed(),
    ],
  );
}

class _MyCircleActivityFeed extends StatelessWidget {
  const _MyCircleActivityFeed({required this.profile});

  final CircleProfile profile;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CircleActivity>>(
    stream: CircleProfileService.watchMyRecentActivities(profile),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return const SizedBox(
          height: 146,
          child: Center(
            child: CircularProgressIndicator(color: CircleScreen._purple),
          ),
        );
      }
      final activities = snapshot.data ?? const <CircleActivity>[];
      if (activities.isEmpty) {
        return const _CircleEmptyRow(
          icon: Icons.directions_run_rounded,
          text: 'No shared activity in the last 7 days',
        );
      }
      return SizedBox(
        height: 146,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: activities.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) =>
              _MyActivityCard(activity: activities[index]),
        ),
      );
    },
  );
}

class _MyActivityCard extends StatelessWidget {
  const _MyActivityCard({required this.activity});

  final CircleActivity activity;

  @override
  Widget build(BuildContext context) {
    final isJournal = activity.kind == 'journal';
    final isAchievement = activity.kind == 'achievement';
    final visual = workoutActivityVisual(
      activity.name,
      category: activity.activityCategory,
    );
    final detail = isJournal
        ? activity.mood ?? 'Shared reflection'
        : isAchievement
        ? activity.achievementTier == null
              ? 'Achievement unlocked'
              : '${_tierLabel(activity.achievementTier!)} tier'
        : activity.km != null
        ? '${activity.km!.toStringAsFixed(1)} km'
        : activity.sets != null && activity.sets! > 0
        ? '${activity.sets} sets'
        : '${activity.minutes} min';
    return Material(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openCircleActivityDetails(context, activity),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isAchievement)
                    _AchievementActivityBadge(activity: activity, size: 36)
                  else
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF0EEFF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isJournal ? Icons.menu_book_rounded : visual.icon,
                        color: isJournal ? CircleScreen._purple : visual.color,
                        size: 20,
                      ),
                    ),
                  const Spacer(),
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: CircleScreen._muted,
                    size: 19,
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                isAchievement ? 'Earned ${activity.name}' : activity.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$detail · ${_relativeActivityTime(activity.day)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YourCircleCard extends StatefulWidget {
  const _YourCircleCard({required this.profile});

  final CircleProfile profile;

  @override
  State<_YourCircleCard> createState() => _YourCircleCardState();
}

class _YourCircleCardState extends State<_YourCircleCard> {
  final ScrollController _membersController = ScrollController();

  @override
  void dispose() {
    _membersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CircleProfile>>(
    stream: CircleProfileService.watchFriendsByRecentActivity(),
    builder: (context, snapshot) {
      final friends = snapshot.data ?? const <CircleProfile>[];
      return _CircleCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Circle',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              friends.isEmpty
                  ? 'No friends yet'
                  : '${friends.length} ${friends.length == 1 ? 'friend' : 'friends'}',
              style: const TextStyle(color: CircleScreen._muted, fontSize: 14),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 98,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final memberCount = friends.length + 1;
                  final contentWidth =
                      memberCount * 92.0 +
                      (memberCount - 1).clamp(0, memberCount) * 10.0;
                  final overflows = contentWidth > constraints.maxWidth;
                  return Scrollbar(
                    controller: _membersController,
                    thumbVisibility: overflows,
                    interactive: true,
                    thickness: 3,
                    radius: const Radius.circular(3),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListView.separated(
                        controller: _membersController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        itemCount: memberCount,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final isCurrentUser = index == 0;
                          final person = isCurrentUser
                              ? widget.profile
                              : friends[index - 1];
                          return Semantics(
                            button: !isCurrentUser,
                            label: isCurrentUser
                                ? 'You'
                                : 'View ${person.username} activity rings',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: isCurrentUser
                                  ? null
                                  : () => _openFriendFitness(context, person),
                              child: SizedBox(
                                width: 92,
                                child: Column(
                                  children: [
                                    _ProfileAvatar(profile: person, radius: 27),
                                    const SizedBox(height: 7),
                                    _CircleMemberNameAndStreak(
                                      profile: person,
                                      label: isCurrentUser
                                          ? 'You'
                                          : person.username,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _CircleMemberNameAndStreak extends StatelessWidget {
  const _CircleMemberNameAndStreak({
    required this.profile,
    required this.label,
  });

  final CircleProfile profile;
  final String label;

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: CircleProfileService.watchWorkoutStreak(profile.uid),
    initialData: 0,
    builder: (context, snapshot) {
      final streak = snapshot.data ?? 0;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 3),
          const Icon(
            Icons.local_fire_department_rounded,
            color: Color(0xFFFF7A00),
            size: 13,
          ),
          Text(
            '$streak',
            style: const TextStyle(
              color: Color(0xFFFF6B00),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    },
  );
}

void _openFriendFitness(BuildContext context, CircleProfile profile) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _FriendFitnessSheet(profile: profile),
  );
}

class _FriendFitnessSheet extends StatelessWidget {
  const _FriendFitnessSheet({required this.profile});

  final CircleProfile profile;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: context.vivordoColors.card,
        borderRadius: BorderRadius.circular(28),
      ),
      child: StreamBuilder<CircleDailyFitness?>(
        stream: CircleProfileService.watchTodayFitness(profile.uid),
        builder: (context, snapshot) {
          final fitness = snapshot.data;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: context.vivordoColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 22),
              _ProfileAvatar(profile: profile, radius: 34),
              const SizedBox(height: 10),
              Text(
                profile.username,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                "Today's Activity",
                style: TextStyle(color: CircleScreen._muted),
              ),
              const SizedBox(height: 22),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.all(35),
                  child: CircularProgressIndicator(color: CircleScreen._purple),
                )
              else if (fitness == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Column(
                    children: [
                      Icon(
                        Icons.donut_large_rounded,
                        color: CircleScreen._muted,
                        size: 42,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'No activity ring shared today.',
                        style: TextStyle(color: CircleScreen._muted),
                      ),
                    ],
                  ),
                )
              else
                _FriendFitnessContent(fitness: fitness),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    navigator.pop();
                    navigator.push(
                      MaterialPageRoute<void>(
                        builder: (_) => CircleUserProfilePage(
                          profile: profile,
                          isOwner: false,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_outline_rounded),
                  label: const Text('View Profile'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CircleScreen._purple,
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: CircleScreen._purple),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _FriendFitnessContent extends StatelessWidget {
  const _FriendFitnessContent({required this.fitness});

  final CircleDailyFitness fitness;

  @override
  Widget build(BuildContext context) {
    final stepsProgress = (fitness.steps / fitness.stepsGoal).clamp(0.0, 1.0);
    final caloriesProgress =
        (fitness.activeCalories / fitness.activeCaloriesGoal).clamp(0.0, 1.0);
    final exerciseProgress =
        (fitness.exerciseMinutes / fitness.exerciseMinutesGoal).clamp(0.0, 1.0);
    final percent =
        ((stepsProgress + caloriesProgress + exerciseProgress) / 3 * 100)
            .round();
    return _CircleCard(
      child: Row(
        children: [
          SizedBox(
            width: 105,
            height: 105,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size.square(105),
                  painter: ActivityRingsPainter(
                    move: stepsProgress,
                    exercise: caloriesProgress,
                    stand: exerciseProgress,
                  ),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CircleMetricLine(
                  color: CircleScreen._purple,
                  text:
                      '${NumberFormat.decimalPattern().format(fitness.steps)} / ${NumberFormat.decimalPattern().format(fitness.stepsGoal)}',
                ),
                const SizedBox(height: 9),
                _CircleMetricLine(
                  color: const Color(0xFFFB923C),
                  text:
                      '${fitness.activeCalories} / ${fitness.activeCaloriesGoal} cal',
                ),
                const SizedBox(height: 9),
                _CircleMetricLine(
                  color: const Color(0xFF34D399),
                  text:
                      '${fitness.exerciseMinutes} / ${fitness.exerciseMinutesGoal} min',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleRecentActivityFeed extends StatelessWidget {
  const _CircleRecentActivityFeed();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CircleActivity>>(
    stream: CircleProfileService.watchLatestFriendActivities(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return const _CircleCard(
          child: Center(
            child: CircularProgressIndicator(color: CircleScreen._purple),
          ),
        );
      }
      final activities = snapshot.data ?? const [];
      if (activities.isEmpty) {
        return const _CircleCard(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(
                  Icons.favorite_border_rounded,
                  color: CircleScreen._purple,
                  size: 34,
                ),
                SizedBox(height: 12),
                Text(
                  'No recent friend activity',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 6),
                Text(
                  "Your friends' latest shared activities will appear here.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: CircleScreen._muted, height: 1.35),
                ),
              ],
            ),
          ),
        );
      }
      return Column(
        children: activities
            .map(
              (activity) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CircleActivityTile(activity: activity),
              ),
            )
            .toList(),
      );
    },
  );
}

class _CircleActivityTile extends StatelessWidget {
  const _CircleActivityTile({required this.activity});

  final CircleActivity activity;

  @override
  Widget build(BuildContext context) {
    final isJournal = activity.kind == 'journal';
    final isAchievement = activity.kind == 'achievement';
    final visual = workoutActivityVisual(
      activity.name,
      category: activity.activityCategory,
    );
    final details = <String>[];
    if (activity.km != null) {
      details.add('${activity.km!.toStringAsFixed(1)} km');
    }
    if (activity.minutes > 0) details.add('${activity.minutes} min');
    if (activity.sets != null && activity.sets! > 0) {
      details.add('${activity.sets} sets');
    }
    return Material(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openCircleActivityDetails(context, activity),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _ProfileAvatar(profile: activity.profile, radius: 29),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.profile.username,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isJournal
                          ? 'shared a Journal Entry${activity.mood == null ? '' : ' · ${activity.mood}'}'
                          : isAchievement
                          ? 'earned ${activity.name}${activity.achievementTier == null ? '' : ' · ${_tierLabel(activity.achievementTier!)}'}'
                          : details.isEmpty
                          ? 'completed ${activity.name}'
                          : 'completed ${activity.name} · ${details.join(' · ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CircleScreen._muted,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _relativeActivityTime(activity.day),
                      style: const TextStyle(
                        color: CircleScreen._muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAchievement)
                _AchievementActivityBadge(activity: activity, size: 42)
              else
                Icon(
                  isJournal ? Icons.menu_book_rounded : visual.icon,
                  color: isJournal ? CircleScreen._purple : visual.color,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AchievementActivityBadge extends StatelessWidget {
  const _AchievementActivityBadge({required this.activity, required this.size});

  final CircleActivity activity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = activity.achievementBadgeAsset;
    if (asset == null || asset.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: CircleScreen._purple.withValues(alpha: .12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.emoji_events_rounded,
          color: CircleScreen._purple,
          size: size * .52,
        ),
      );
    }
    return ClipOval(
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: CircleScreen._purple.withValues(alpha: .12),
          child: Icon(
            Icons.emoji_events_rounded,
            color: CircleScreen._purple,
            size: size * .52,
          ),
        ),
      ),
    );
  }
}

void _openCircleActivityDetails(
  BuildContext context,
  CircleActivity activity,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _CircleActivityDetailsSheet(activity: activity),
);

class _CircleActivityDetailsSheet extends StatefulWidget {
  const _CircleActivityDetailsSheet({required this.activity});

  final CircleActivity activity;

  @override
  State<_CircleActivityDetailsSheet> createState() =>
      _CircleActivityDetailsSheetState();
}

class _CircleActivityDetailsSheetState
    extends State<_CircleActivityDetailsSheet> {
  final _commentController = TextEditingController();
  bool _sending = false;

  CircleActivity get activity => widget.activity;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: DraggableScrollableSheet(
      initialChildSize: .72,
      minChildSize: .48,
      maxChildSize: .94,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.vivordoColors.page,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: context.vivordoColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                children: [
                  _CircleCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _ProfileAvatar(
                              profile: activity.profile,
                              radius: 28,
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    activity.profile.username,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    _relativeActivityTime(activity.day),
                                    style: const TextStyle(
                                      color: CircleScreen._muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (activity.kind == 'achievement') ...[
                          Center(
                            child: _AchievementActivityBadge(
                              activity: activity,
                              size: 108,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Text(
                          activity.kind == 'achievement'
                              ? 'Earned ${activity.name}'
                              : activity.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if ((activity.kind == 'journal' ||
                                activity.kind == 'achievement') &&
                            activity.summary?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 10),
                          Text(
                            activity.summary!,
                            style: const TextStyle(
                              color: CircleScreen._muted,
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (activity.minutes > 0)
                              _ActivityDetailChip(
                                icon: Icons.timer_outlined,
                                label: '${activity.minutes} min',
                              ),
                            if (activity.km != null)
                              _ActivityDetailChip(
                                icon: Icons.route_rounded,
                                label: '${activity.km!.toStringAsFixed(1)} km',
                              ),
                            if (activity.sets != null && activity.sets! > 0)
                              _ActivityDetailChip(
                                icon: Icons.fitness_center_rounded,
                                label: '${activity.sets} sets',
                              ),
                            if (activity.kind == 'achievement')
                              _ActivityDetailChip(
                                icon: Icons.emoji_events_rounded,
                                label: activity.achievementTier == null
                                    ? 'Achievement unlocked'
                                    : '${_tierLabel(activity.achievementTier!)} tier',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _ActivityLikesSection(activity: activity),
                  const SizedBox(height: 22),
                  const _CircleSectionLabel('COMMENTS'),
                  const SizedBox(height: 12),
                  StreamBuilder<List<CircleActivityComment>>(
                    stream: CircleProfileService.watchActivityComments(
                      activity,
                    ),
                    builder: (context, snapshot) {
                      final comments = snapshot.data ?? const [];
                      if (comments.isEmpty) {
                        return const _CircleEmptyRow(
                          icon: Icons.chat_bubble_outline_rounded,
                          text: 'Be the first to leave a comment',
                        );
                      }
                      return Column(
                        children: comments
                            .map(
                              (comment) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _CircleCommentTile(comment: comment),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: context.vivordoColors.card,
                  border: Border(
                    top: BorderSide(color: context.vivordoColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        maxLength: 500,
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Leave a comment',
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFF4F4F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      style: IconButton.styleFrom(
                        backgroundColor: CircleScreen._purple,
                        foregroundColor: Colors.white,
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _send() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await CircleProfileService.addActivityComment(activity, text);
      _commentController.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not post your comment')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _ActivityLikesSection extends StatefulWidget {
  const _ActivityLikesSection({required this.activity});

  final CircleActivity activity;

  @override
  State<_ActivityLikesSection> createState() => _ActivityLikesSectionState();
}

class _ActivityLikesSectionState extends State<_ActivityLikesSection> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CircleActivityLike>>(
    stream: CircleProfileService.watchActivityLikes(widget.activity),
    builder: (context, snapshot) {
      final likes = snapshot.data ?? const <CircleActivityLike>[];
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final liked = uid != null && likes.any((like) => like.userUid == uid);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () => _setLiked(currentlyLiked: liked),
                style: FilledButton.styleFrom(
                  backgroundColor: liked
                      ? CircleScreen._purple
                      : const Color(0xFFF0EEFF),
                  foregroundColor: liked ? Colors.white : CircleScreen._purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                      ),
                label: Text(liked ? 'Liked' : 'Like'),
              ),
              const SizedBox(width: 12),
              Text(
                '${likes.length} ${likes.length == 1 ? 'like' : 'likes'}',
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (likes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _CircleSectionLabel('LIKED BY'),
            const SizedBox(height: 10),
            _CircleCard(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: likes
                    .map((like) => _ActivityLiker(like: like))
                    .toList(),
              ),
            ),
          ],
        ],
      );
    },
  );

  Future<void> _setLiked({required bool currentlyLiked}) async {
    setState(() => _saving = true);
    try {
      await CircleProfileService.setActivityLiked(
        widget.activity,
        liked: !currentlyLiked,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update your like')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ActivityLiker extends StatelessWidget {
  const _ActivityLiker({required this.like});

  final CircleActivityLike like;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 66,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFFE9E5FF),
          backgroundImage: like.photoUrl == null
              ? null
              : NetworkImage(like.photoUrl!),
          child: like.photoUrl == null
              ? Text(
                  like.username.isEmpty ? '?' : like.username[0].toUpperCase(),
                  style: const TextStyle(
                    color: CircleScreen._purple,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 5),
        Text(
          like.username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: CircleScreen._muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _ActivityDetailChip extends StatelessWidget {
  const _ActivityDetailChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF0EEFF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: CircleScreen._purple, size: 17),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _CircleCommentTile extends StatelessWidget {
  const _CircleCommentTile({required this.comment});

  final CircleActivityComment comment;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 19,
          backgroundColor: const Color(0xFFE9E5FF),
          backgroundImage: comment.authorPhotoUrl == null
              ? null
              : NetworkImage(comment.authorPhotoUrl!),
          child: comment.authorPhotoUrl == null
              ? Text(
                  comment.authorName.isEmpty
                      ? '?'
                      : comment.authorName[0].toUpperCase(),
                  style: const TextStyle(
                    color: CircleScreen._purple,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      comment.authorName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (comment.createdAt != null)
                    Text(
                      _relativeActivityTime(comment.createdAt!),
                      style: const TextStyle(
                        color: CircleScreen._muted,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(comment.text, style: const TextStyle(height: 1.35)),
            ],
          ),
        ),
      ],
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

class _CircleFitnessSummary extends StatefulWidget {
  const _CircleFitnessSummary();

  @override
  State<_CircleFitnessSummary> createState() => _CircleFitnessSummaryState();
}

class _CircleFitnessSummaryState extends State<_CircleFitnessSummary> {
  late final Stream<List<SavedWorkout>> _workoutsStream;
  String? _lastPublishedFitness;

  @override
  void initState() {
    super.initState();
    _workoutsStream = WorkoutService.watchAll();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final now = DateTime.now();
    final dayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final metricsStream = user == null
        ? const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty()
        : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('metrics_daily')
              .doc(dayKey)
              .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: metricsStream,
      builder: (context, metricsSnapshot) {
        final data = metricsSnapshot.data?.data();
        final steps = ((data?['steps'] as Map?)?['sum'] as num?)?.round() ?? 0;
        final calories =
            ((data?['active_calories'] as Map?)?['sum'] as num?)?.round() ?? 0;
        final exercise =
            ((data?['exercise_time'] as Map?)?['sum'] as num?)?.round() ?? 0;

        return StreamBuilder<ActivityGoals>(
          stream: ActivityGoalsService.watch(),
          initialData: const ActivityGoals(),
          builder: (context, goalsSnapshot) {
            final goals = goalsSnapshot.data ?? const ActivityGoals();
            final stepsProgress = (steps / goals.steps).clamp(0.0, 1.0);
            final caloriesProgress = (calories / goals.activeCalories).clamp(
              0.0,
              1.0,
            );
            final exerciseProgress = (exercise / goals.exerciseMinutes).clamp(
              0.0,
              1.0,
            );
            final overallPercent =
                ((stepsProgress + caloriesProgress + exerciseProgress) /
                        3 *
                        100)
                    .round();
            _publishFitnessSummary(
              steps: steps,
              stepsGoal: goals.steps,
              calories: calories,
              caloriesGoal: goals.activeCalories,
              exercise: exercise,
              exerciseGoal: goals.exerciseMinutes,
            );

            return StreamBuilder<List<SavedWorkout>>(
              stream: _workoutsStream,
              builder: (context, workoutsSnapshot) {
                final streak = WorkoutService.calculateCurrentStreak(
                  workoutsSnapshot.data ?? const [],
                );
                return _CircleCard(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
                        height: 88,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size.square(88),
                              painter: ActivityRingsPainter(
                                move: stepsProgress,
                                exercise: caloriesProgress,
                                stand: exerciseProgress,
                              ),
                            ),
                            Text(
                              '$overallPercent%',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Today's Fitness",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 7),
                            _CircleMetricLine(
                              color: CircleScreen._purple,
                              text:
                                  '${NumberFormat.decimalPattern().format(steps)} / ${NumberFormat.decimalPattern().format(goals.steps)}',
                            ),
                            const SizedBox(height: 5),
                            _CircleMetricLine(
                              color: const Color(0xFFFB923C),
                              text: '$calories / ${goals.activeCalories} cal',
                            ),
                            const SizedBox(height: 5),
                            _CircleMetricLine(
                              color: const Color(0xFF34D399),
                              text: '$exercise / ${goals.exerciseMinutes} min',
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E7),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.local_fire_department_rounded,
                              color: Color(0xFFFF7A00),
                              size: 24,
                            ),
                            Text(
                              '$streak',
                              style: const TextStyle(
                                color: Color(0xFFFF6B00),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Text(
                              'DAY STREAK',
                              style: TextStyle(
                                color: Color(0xFFFF6B00),
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _publishFitnessSummary({
    required int steps,
    required int stepsGoal,
    required int calories,
    required int caloriesGoal,
    required int exercise,
    required int exerciseGoal,
  }) {
    final signature =
        '$steps:$stepsGoal:$calories:$caloriesGoal:$exercise:$exerciseGoal';
    if (_lastPublishedFitness == signature) return;
    _lastPublishedFitness = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CircleProfileService.publishTodayFitness(
        steps: steps,
        stepsGoal: stepsGoal,
        activeCalories: calories,
        activeCaloriesGoal: caloriesGoal,
        exerciseMinutes: exercise,
        exerciseMinutesGoal: exerciseGoal,
      ).catchError((Object error) {
        debugPrint('Circle fitness summary publish failed: $error');
      });
    });
  }
}

class _CircleMetricLine extends StatelessWidget {
  const _CircleMetricLine({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: CircleScreen._muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _FriendsTab extends StatefulWidget {
  const _FriendsTab({required this.profile, super.key});

  final CircleProfile profile;

  @override
  State<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<_FriendsTab> {
  final _searchController = TextEditingController();
  CircleProfile? _searchResult;
  bool _searching = false;
  String? _searchMessage;

  CircleProfile get profile => widget.profile;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        height: 58,
        decoration: BoxDecoration(
          color: context.vivordoColors.card,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'Search username or friend code',
            hintStyle: const TextStyle(color: CircleScreen._muted),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: CircleScreen._muted,
            ),
            suffixIcon: IconButton(
              onPressed: _showMyCode,
              icon: const Icon(
                Icons.qr_code_scanner_rounded,
                color: CircleScreen._purple,
              ),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
          ),
        ),
      ),
      if (_searching) ...[
        const SizedBox(height: 14),
        const Center(
          child: CircularProgressIndicator(color: CircleScreen._purple),
        ),
      ] else if (_searchResult != null) ...[
        const SizedBox(height: 14),
        _FriendSearchResult(
          profile: _searchResult!,
          onAdd: () => _sendRequest(_searchResult!),
        ),
      ] else if (_searchMessage != null) ...[
        const SizedBox(height: 12),
        Center(
          child: Text(
            _searchMessage!,
            style: const TextStyle(color: CircleScreen._muted),
          ),
        ),
      ],
      const SizedBox(height: 28),
      Row(
        children: [
          const Expanded(child: _CircleSectionLabel('FRIEND REQUESTS')),
          StreamBuilder<List<CircleFriendRequest>>(
            stream: CircleProfileService.watchIncomingRequests(),
            builder: (context, snapshot) => Text(
              '${snapshot.data?.length ?? 0}',
              style: const TextStyle(
                color: CircleScreen._purple,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      StreamBuilder<List<CircleFriendRequest>>(
        stream: CircleProfileService.watchIncomingRequests(),
        builder: (context, snapshot) {
          final requests = snapshot.data ?? const [];
          if (requests.isEmpty) {
            return const _CircleEmptyRow(
              icon: Icons.person_add_alt_1_rounded,
              text: 'No pending friend requests',
            );
          }
          return Column(
            children: requests
                .map(
                  (request) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FriendRequestTile(
                      request: request,
                      onAccept: () => _accept(request.profile),
                      onDecline: () => _decline(request.profile),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
      const SizedBox(height: 24),
      StreamBuilder<List<CircleProfile>>(
        stream: CircleProfileService.watchFriends(),
        builder: (context, snapshot) {
          final friends = snapshot.data ?? const [];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CircleSectionLabel('YOUR FRIENDS  ${friends.length}'),
              const SizedBox(height: 12),
              if (friends.isEmpty)
                const _CircleEmptyRow(
                  icon: Icons.groups_rounded,
                  text: 'Your friends will appear here',
                )
              else
                ...friends.map(
                  (friend) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FriendTile(profile: friend),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchResult = null;
      _searchMessage = null;
    });
    try {
      final result = await CircleProfileService.findFriend(query);
      if (!mounted) return;
      setState(() {
        _searchResult = result?.uid == profile.uid ? null : result;
        _searchMessage = result == null
            ? 'No Circle profile found'
            : result.uid == profile.uid
            ? 'That is your profile'
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _searchMessage = 'Could not search right now');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(CircleProfile recipient) async {
    try {
      await CircleProfileService.sendFriendRequest(recipient);
      if (!mounted) return;
      setState(() {
        _searchResult = null;
        _searchMessage = 'Friend request sent to ${recipient.username}';
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _accept(CircleProfile requester) async {
    try {
      await CircleProfileService.acceptFriendRequest(requester.uid);
      if (mounted) _showSnack('${requester.username} joined your Circle');
    } catch (_) {
      if (mounted) _showSnack('Could not accept this request');
    }
  }

  Future<void> _decline(CircleProfile requester) async {
    try {
      await CircleProfileService.declineFriendRequest(requester.uid);
    } catch (_) {
      if (mounted) _showSnack('Could not decline this request');
    }
  }

  void _showSnack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _showMyCode() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Your friend code'),
      content: Material(
        color: const Color(0xFFF0EEFF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _copyFriendCode(context, profile.friendCode),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              profile.friendCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CircleScreen._purple,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class _CircleSectionLabel extends StatelessWidget {
  const _CircleSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: CircleScreen._muted,
      fontSize: 14,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
    ),
  );
}

class _FriendSearchResult extends StatelessWidget {
  const _FriendSearchResult({required this.profile, required this.onAdd});

  final CircleProfile profile;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: Row(
      children: [
        _ProfileAvatar(profile: profile, radius: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            profile.username,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        FilledButton(
          onPressed: onAdd,
          style: FilledButton.styleFrom(
            backgroundColor: CircleScreen._purple,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

class _FriendRequestTile extends StatelessWidget {
  const _FriendRequestTile({
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  final CircleFriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: Row(
      children: [
        _ProfileAvatar(profile: request.profile, radius: 27),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.profile.username,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Wants to join your Circle',
                style: TextStyle(color: CircleScreen._muted, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onDecline, child: const Text('Decline')),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: onAccept,
          style: FilledButton.styleFrom(
            backgroundColor: CircleScreen._purple,
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          child: const Text('Accept'),
        ),
      ],
    ),
  );
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.profile});

  final CircleProfile profile;

  @override
  Widget build(BuildContext context) => Material(
    color: context.vivordoColors.card,
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CircleUserProfilePage(profile: profile, isOwner: false),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            _ProfileAvatar(profile: profile, radius: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.username,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    profile.bio.isEmpty ? 'In your Circle' : profile.bio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: CircleScreen._muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: CircleScreen._muted),
          ],
        ),
      ),
    ),
  );
}

// Kept temporarily for compatibility with any in-flight route callbacks from
// hot reload; new friend taps open the full profile page above.
// ignore: unused_element
void _showFriendProfile(BuildContext context, CircleProfile profile) {
  var removing = false;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setModalState) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            decoration: BoxDecoration(
              color: context.vivordoColors.card,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.vivordoColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 24),
                _ProfileAvatar(profile: profile, radius: 48),
                const SizedBox(height: 14),
                Text(
                  profile.username,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  profile.bio.trim().isEmpty
                      ? 'No bio added yet.'
                      : profile.bio.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CircleScreen._muted,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                StreamBuilder<int>(
                  stream: CircleProfileService.watchWorkoutStreak(profile.uid),
                  initialData: 0,
                  builder: (context, snapshot) {
                    final streak = snapshot.data ?? 0;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: context.vivordoColors.cardMuted,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            color: Color(0xFFFF7500),
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$streak-day streak',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: removing
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: sheetContext,
                              builder: (dialogContext) => AlertDialog(
                                title: Text('Remove ${profile.username}?'),
                                content: Text(
                                  '${profile.username} will be removed from your Circle. '
                                  "You won't see each other's shared activity unless you become friends again.",
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !sheetContext.mounted) {
                              return;
                            }

                            setModalState(() => removing = true);
                            final messenger = ScaffoldMessenger.of(
                              sheetContext,
                            );
                            try {
                              await CircleProfileService.removeFriend(
                                profile.uid,
                              );
                              if (!sheetContext.mounted) return;
                              Navigator.of(sheetContext).pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${profile.username} was removed from your Circle.',
                                  ),
                                ),
                              );
                            } catch (error) {
                              if (!sheetContext.mounted) return;
                              setModalState(() => removing = false);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not remove friend: $error',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: removing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_remove_rounded),
                    label: Text(removing ? 'Removing…' : 'Remove Friend'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
  );
}

class _CircleEmptyRow extends StatelessWidget {
  const _CircleEmptyRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Icon(icon, color: CircleScreen._purple),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: CircleScreen._muted)),
      ],
    ),
  );
}

Future<void> _copyFriendCode(BuildContext context, String friendCode) async {
  await Clipboard.setData(ClipboardData(text: friendCode));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Friend code copied'),
      duration: Duration(seconds: 2),
    ),
  );
}

class _CircleCard extends StatelessWidget {
  const _CircleCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: context.vivordoColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, required this.radius});

  final CircleProfile profile;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFFE9E5FF),
    backgroundImage: profile.photoUrl == null
        ? null
        : NetworkImage(profile.photoUrl!),
    child: profile.photoUrl == null
        ? Icon(Icons.person_rounded, color: CircleScreen._purple, size: radius)
        : null,
  );
}

class _CircleBenefit extends StatelessWidget {
  const _CircleBenefit({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: iconBackground,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 23),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  color: CircleScreen._muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CircleOnboardingGraphic extends StatelessWidget {
  const _CircleOnboardingGraphic();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 250,
    height: 210,
    child: CustomPaint(
      painter: const _CircleConnectionsPainter(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final alignment in const [
            Alignment(-.72, -.72),
            Alignment(.72, -.72),
            Alignment(-.72, .72),
            Alignment(.72, .72),
          ])
            Align(
              alignment: alignment,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF9F8FF),
                  border: Border.all(color: const Color(0xFFE9E6FF), width: 3),
                ),
              ),
            ),
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF7767F5), Color(0xFF4F3BDB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 39,
            ),
          ),
          const Align(
            alignment: Alignment(-.98, -.35),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFC8C2FF),
              size: 18,
            ),
          ),
          const Align(
            alignment: Alignment(.98, -.35),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFC8C2FF),
              size: 18,
            ),
          ),
          const Align(
            alignment: Alignment(-.93, .26),
            child: Icon(
              Icons.favorite_border_rounded,
              color: Color(0xFFC8C2FF),
              size: 21,
            ),
          ),
          const Align(
            alignment: Alignment(.95, .34),
            child: Icon(
              Icons.auto_awesome_outlined,
              color: Color(0xFFC8C2FF),
              size: 20,
            ),
          ),
        ],
      ),
    ),
  );
}

class _CircleConnectionsPainter extends CustomPainter {
  const _CircleConnectionsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .36;
    final paint = Paint()
      ..color = const Color(0xFFCFC9FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    const dashLength = 2.5;
    const gapLength = 7.0;
    final circumference = math.pi * 2 * radius;
    for (
      double distance = 0;
      distance < circumference;
      distance += dashLength + gapLength
    ) {
      final start = distance / radius;
      final sweep = math.min(dashLength, circumference - distance) / radius;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircleConnectionsPainter oldDelegate) => false;
}
