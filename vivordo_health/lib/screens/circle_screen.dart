import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/activity_goals_service.dart';
import '../src/services/circle_profile_service.dart';
import '../src/services/workout_service.dart';
import 'create_circle_profile_screen.dart';
import 'fitness_screen.dart' show ActivityRingsPainter;

class CircleScreen extends StatelessWidget {
  const CircleScreen({super.key});

  static const _purple = Color(0xFF6250E8);
  static const _background = Color(0xFFF4F4F9);
  static const _ink = Color(0xFF17172B);
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
            color: context.vivordoColors.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _showProfile,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: _ProfileAvatar(profile: profile, radius: 18),
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
            child: _selectedTab == 0
                ? _ActivityTab(
                    profile: profile,
                    key: const ValueKey('activity'),
                  )
                : _FriendsTab(profile: profile, key: const ValueKey('friends')),
          ),
        ],
      ),
    ),
  );

  void _showProfile() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          decoration: BoxDecoration(
            color: sheetContext.vivordoColors.card,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFDADAE4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 22),
              _ProfileAvatar(profile: profile, radius: 42),
              const SizedBox(height: 13),
              Text(
                profile.username,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (profile.bio.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  profile.bio,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CircleScreen._muted,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          CreateCircleProfileScreen(initialProfile: profile),
                    ),
                  );
                },
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit Profile'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: CircleScreen._purple,
                  minimumSize: const Size.fromHeight(46),
                  side: const BorderSide(color: CircleScreen._purple),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'FRIEND CODE',
                  style: TextStyle(
                    color: CircleScreen._muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: const Color(0xFFF0EEFF),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () =>
                      _copyFriendCode(sheetContext, profile.friendCode),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          profile.friendCode,
                          style: const TextStyle(
                            color: CircleScreen._purple,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.copy_rounded,
                          color: CircleScreen._purple,
                          size: 19,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Tap your code to copy it',
                style: TextStyle(color: CircleScreen._muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    child: Row(children: [_tab('Activity', 0), _tab('Friends', 1)]),
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
    final detail = isJournal
        ? activity.mood ?? 'Shared reflection'
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
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0EEFF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isJournal
                          ? Icons.menu_book_rounded
                          : activity.km != null
                          ? Icons.directions_walk_rounded
                          : Icons.fitness_center_rounded,
                      color: CircleScreen._purple,
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
                activity.name,
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
              Icon(
                isJournal
                    ? Icons.menu_book_rounded
                    : activity.km != null
                    ? Icons.directions_walk_rounded
                    : Icons.fitness_center_rounded,
                color: isJournal
                    ? CircleScreen._purple
                    : activity.km != null
                    ? const Color(0xFF10B77A)
                    : CircleScreen._purple,
              ),
            ],
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
                        Text(
                          activity.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (activity.kind == 'journal' &&
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
      onTap: () => _showFriendProfile(context, profile),
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

void _showFriendProfile(BuildContext context, CircleProfile profile) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => SafeArea(
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
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
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
          ],
        ),
      ),
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
