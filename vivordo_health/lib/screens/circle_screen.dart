import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/activity_goals_service.dart';
import '../src/services/calendar_service.dart';
import '../src/services/circle_profile_service.dart';
import '../src/services/outlook_calendar_service.dart';
import '../src/services/workout_service.dart';
import '../src/utils/workout_activity_visual.dart';
import 'create_circle_profile_screen.dart';
import 'fitness_screen.dart' show ActivityRingsPainter;
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

  CircleProfile get profile => widget.profile;

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
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
        children: [
          _CircleTabs(
            selectedIndex: _selectedTab,
            onChanged: (index) => setState(() => _selectedTab = index),
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
                key: const ValueKey('challenges'),
              ),
            },
          ),
        ],
      ),
    ),
  );

  void _openProfile() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _CircleUserProfilePage(profile: profile, isOwner: true),
    ),
  );
}

class _CircleUserProfilePage extends StatefulWidget {
  const _CircleUserProfilePage({required this.profile, required this.isOwner});

  final CircleProfile profile;
  final bool isOwner;

  @override
  State<_CircleUserProfilePage> createState() => _CircleUserProfilePageState();
}

class _CircleUserProfilePageState extends State<_CircleUserProfilePage> {
  var _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) return _buildPage(context, widget.profile);
    return StreamBuilder<CircleProfile?>(
      stream: CircleProfileService.watchCurrentProfile(),
      initialData: widget.profile,
      builder: (context, snapshot) =>
          _buildPage(context, snapshot.data ?? widget.profile),
    );
  }

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
  ]) {
    final data = byId[definition.$1];
    final tier = data?['tier'] as String?;
    final nextTier =
        data?['nextTier'] as String? ?? (tier == null ? 'bronze' : null);
    final shownTier = nextTier ?? tier ?? 'bronze';
    final assetPrefix = definition.$1;
    final defaultTarget = shownTier == 'bronze'
        ? (definition.$1 == 'pulse_check' ? 10 : 5)
        : shownTier == 'silver'
        ? (definition.$1 == 'pulse_check' ? 100 : 10)
        : (definition.$1 == 'pulse_check' ? 1000 : 100);
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
  const _CircleTabs({required this.selectedIndex, required this.onChanged});

  final int selectedIndex;
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
      children: [_tab('Activity', 0), _tab('Goals', 2), _tab('Friends', 1)],
    ),
  );

  Widget _tab(String label, int index) => Expanded(
    child: Material(
      color: selectedIndex == index ? CircleScreen._purple : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => onChanged(index),
        child: Center(
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
      ),
    ),
  );
}

class _ChallengesTab extends StatefulWidget {
  const _ChallengesTab({required this.profile, super.key});

  final CircleProfile profile;

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
          .limit(1)
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
    final journalEntries = results[2] as QuerySnapshot<Map<String, dynamic>>;
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
        earned: journalEntries.docs.isNotEmpty,
        progress: journalEntries.docs.isNotEmpty ? 1 : 0,
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
                'summary': achievement.requirement,
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
                  child: Row(
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
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const _CircleSectionTitle('NEXT ACHIEVEMENT'),
          const SizedBox(height: 14),
          if (next == null)
            const _ChallengeEmptyCard(
              icon: Icons.emoji_events_rounded,
              title: 'All achievements earned',
              detail: 'You completed every available achievement.',
            )
          else
            _NextAchievementCard(achievement: next),
          const SizedBox(height: 28),
          const _CircleSectionTitle('ACTIVE CHALLENGES'),
          const SizedBox(height: 14),
          const _ChallengeEmptyCard(
            icon: Icons.groups_rounded,
            title: 'No active challenges',
            detail: 'Challenges with your Circle will appear here.',
          ),
        ],
      );
    },
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

  bool _matchesFilter(_Achievement achievement) => switch (_filter) {
    _AchievementFilter.all => true,
    _AchievementFilter.earned => achievement.earned || achievement.tier != null,
    _AchievementFilter.inProgress =>
      !achievement.earned && (achievement.unlocked || achievement.progress > 0),
    _AchievementFilter.locked =>
      !achievement.unlocked && !achievement.earned && achievement.progress == 0,
  };

  @override
  Widget build(BuildContext context) {
    final oneTime = _oneTime;
    final tiered = _tiered;
    final visibleOneTime = oneTime
        .where(_matchesFilter)
        .toList(growable: false);
    final visibleTiered = tiered.where(_matchesFilter).toList(growable: false);
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
              _OneTimeAchievementGrid(achievements: visibleOneTime),
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
                  onTap: () => _showAchievementDetails(visibleTiered[index]),
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

  void _showAchievementDetails(_Achievement achievement) {
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
              _AchievementCollectionBadge(achievement: achievement, size: 94),
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
                achievement.requirement,
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
  const _OneTimeAchievementGrid({required this.achievements});

  final List<_Achievement> achievements;

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
      itemBuilder: (context, index) =>
          _OneTimeAchievementItem(achievement: achievements[index]),
    ),
  );
}

class _OneTimeAchievementItem extends StatelessWidget {
  const _OneTimeAchievementItem({required this.achievement});

  final _Achievement achievement;

  @override
  Widget build(BuildContext context) => Column(
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
            style: const TextStyle(color: CircleScreen._muted, fontSize: 11),
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
  );
}

class _AchievementCollectionBadge extends StatelessWidget {
  const _AchievementCollectionBadge({
    required this.achievement,
    required this.size,
  });

  final _Achievement achievement;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = _AchievementBadge(
      assetPath: achievement.visibleBadgeAsset,
      size: size,
      locked: !achievement.unlocked && achievement.progress == 0,
    );
    if (achievement.unlocked || achievement.progress > 0) return badge;
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
    required this.onTap,
  });

  final _Achievement achievement;
  final bool showCompletedTiers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tier = achievement.tier ?? achievement.goalTier ?? 'bronze';
    final tierColor = _achievementTierColor(tier);
    final tierStatus = achievement.earned
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
              _AchievementCollectionBadge(achievement: achievement, size: 72),
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
                      _tieredAchievementDescription(achievement),
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

String _tieredAchievementDescription(_Achievement achievement) =>
    switch (achievement.id) {
      'workout_momentum' => 'Complete strength workouts',
      'endurance' => 'Complete cardio or sports activities',
      'pulse_check' => 'Complete heart-rate scans',
      _ => achievement.requirement,
    };

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

class _NextAchievementCard extends StatelessWidget {
  const _NextAchievementCard({required this.achievement});

  final _Achievement achievement;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          _AchievementBadge(assetPath: achievement.goalBadgeAsset, size: 74),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.name,
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (achievement.goalTier != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${_tierLabel(achievement.goalTier!).toUpperCase()} TIER',
                    style: const TextStyle(
                      color: CircleScreen._purple,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  achievement.requirement,
                  style: const TextStyle(
                    color: CircleScreen._muted,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      '${achievement.progress} / ${achievement.target}',
                      style: const TextStyle(
                        color: CircleScreen._purple,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (achievement.target > 1) ...[
                      const SizedBox(width: 5),
                      Text(
                        achievement.progressUnit ?? 'activities',
                        style: const TextStyle(
                          color: CircleScreen._muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: (achievement.progress / achievement.target).clamp(
                      0,
                      1,
                    ),
                    minHeight: 7,
                    color: CircleScreen._purple,
                    backgroundColor: context.vivordoColors.cardMuted,
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

class _RecentlyEarnedCard extends StatelessWidget {
  const _RecentlyEarnedCard({required this.achievements});

  final List<_Achievement> achievements;

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
                        builder: (_) => _CircleUserProfilePage(
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
              _CircleUserProfilePage(profile: profile, isOwner: false),
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
