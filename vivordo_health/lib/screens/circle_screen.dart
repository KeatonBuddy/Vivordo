import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/data/exercise_library.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/activity_goals_service.dart';
import '../src/services/achievement_service.dart';
import '../src/services/circle_challenge_service.dart';
import '../src/services/circle_profile_service.dart';
import '../src/services/workout_service.dart';
import '../src/utils/workout_activity_visual.dart';
import '../widgets/report_post_sheet.dart';
import 'create_circle_profile_screen.dart';
import 'fitness_screen.dart' show ActivityRingsPainter;
import 'profile_screen.dart';

part 'circle/achievements.dart';
part 'circle/challenges.dart';
part 'circle/feed.dart';
part 'circle/new_challenge.dart';
part 'circle/people.dart';
part 'circle/profile.dart';
part 'circle/ui.dart';

class CircleScreen extends StatelessWidget {
  const CircleScreen({super.key, this.initialTab = 0});

  /// 0 Feed, 1 Challenges (a challenge or achievement notification).
  final int initialTab;

  @override
  Widget build(BuildContext context) => StreamBuilder<CircleProfile?>(
    stream: CircleProfileService.watchCurrentProfile(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return Scaffold(
          backgroundColor: context.vivordoColors.page,
          body: const _Loading(height: double.infinity),
        );
      }
      final profile = snapshot.data;
      return profile == null
          ? const CreateCircleProfileScreen(intro: _CircleOnboardingIntro())
          : _CircleProfileHome(profile: profile, initialTab: initialTab);
    },
  );
}

/// The first-run intro; the profile form beneath it is
/// CreateCircleProfileScreen's, so creating and editing share one form.
class _CircleOnboardingIntro extends StatelessWidget {
  const _CircleOnboardingIntro();

  @override
  Widget build(BuildContext context) {
    final palette = context.circle;
    return Column(
      children: [
        const _CircleOnboardingGraphic(),
        const SizedBox(height: 20),
        Text(
          'Better together',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Share progress, encourage friends, and build healthy habits together.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.muted, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 24),
        _CircleCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Column(
            children: [
              _CircleBenefit(
                icon: Icons.lock_rounded,
                color: palette.accent,
                background: palette.accentTint,
                title: 'Private by default',
                detail: 'Only people you accept see what you share',
              ),
              Divider(height: 1, color: context.vivordoColors.border),
              _CircleBenefit(
                icon: Icons.favorite_rounded,
                color: palette.success,
                background: palette.successTint,
                title: 'Support each other',
                detail: 'Likes and comments, without comparison',
              ),
              Divider(height: 1, color: context.vivordoColors.border),
              _CircleBenefit(
                icon: Icons.emoji_events_rounded,
                color: palette.streak,
                background: palette.streakTint,
                title: 'Challenge friends',
                detail: 'Workouts, step sprints and heart-scan goals',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleBenefit extends StatelessWidget {
  const _CircleBenefit({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      children: [
        _IconTile(icon: icon, color: color, background: background, size: 44),
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
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(color: context.muted, fontSize: 13),
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

  static const _satellites = [
    (Alignment(-.8, -.62), 40.0, Color(0xFF7EE2B8)),
    (Alignment(.8, -.62), 40.0, Color(0xFFFFC58A)),
    (Alignment(-.62, .86), 32.0, Color(0xFF8EC5FF)),
    (Alignment(.62, .86), 32.0, Color(0xFFF5A3C7)),
  ];

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    height: 150,
    child: CustomPaint(
      painter: _ConnectionsPainter(
        color: context.vivordoColors.border,
        targets: [for (final item in _satellites) item.$1],
      ),
      child: Stack(
        children: [
          for (final (alignment, size, color) in _satellites)
            Align(
              alignment: alignment,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          Align(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: context.circle.accentTint,
                shape: BoxShape.circle,
                border: Border.all(color: _brand, width: 3),
              ),
              child: Icon(
                Icons.groups_rounded,
                color: context.circle.accent,
                size: 36,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ConnectionsPainter extends CustomPainter {
  const _ConnectionsPainter({required this.color, required this.targets});

  final Color color;
  final List<Alignment> targets;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final target in targets) {
      final end = target.alongSize(size);
      final length = (end - center).distance;
      final direction = (end - center) / length;
      for (double distance = 0; distance < length; distance += 9) {
        canvas.drawLine(
          center + direction * distance,
          center + direction * math.min(distance + 3, length),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionsPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CircleProfileHome extends StatefulWidget {
  const _CircleProfileHome({required this.profile, this.initialTab = 0});

  final CircleProfile profile;
  final int initialTab;

  @override
  State<_CircleProfileHome> createState() => _CircleProfileHomeState();
}

class _CircleProfileHomeState extends State<_CircleProfileHome> {
  late var _tab = widget.initialTab;
  late var _challengesVisited = widget.initialTab == 1;
  late final Stream<List<CircleChallengeMembership>> _memberships =
      CircleChallengeService.watchMemberships();
  late final Stream<int> _requestCount =
      CircleProfileService.watchIncomingRequestCount();
  late final Stream<List<CircleProfile>> _friends =
      CircleProfileService.watchFriends();

  CircleProfile get profile => widget.profile;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.vivordoColors.page,
    body: SafeArea(
      bottom: false,
      child: StreamBuilder<List<CircleChallengeMembership>>(
        stream: _memberships,
        builder: (context, membershipSnapshot) =>
            StreamBuilder<List<CircleProfile>>(
              stream: _friends,
              builder: (context, friendsSnapshot) {
                final memberships = membershipSnapshot.data ?? const [];
                final friends = friendsSnapshot.data ?? const <CircleProfile>[];
                final challenges = _ChallengeData(
                  memberships: memberships,
                  loading:
                      membershipSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      !membershipSnapshot.hasData,
                  error: membershipSnapshot.error,
                  me: profile,
                  friendsById: {
                    for (final friend in friends) friend.uid: friend,
                  },
                );
                final inviteCount = memberships
                    .where((membership) => membership.isInvite)
                    .length;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                      child: _buildHeader(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: _SegmentedTabs(
                        labels: const ['Feed', 'Challenges'],
                        badges: [0, inviteCount],
                        selectedIndex: _tab,
                        onChanged: (index) => setState(() {
                          _tab = index;
                          if (index == 1) _challengesVisited = true;
                        }),
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _tab,
                        children: [
                          _FeedTab(
                            profile: profile,
                            friends: friends,
                            challenges: challenges,
                            onOpenChallenges: () => setState(() {
                              _tab = 1;
                              _challengesVisited = true;
                            }),
                          ),
                          // Built on first visit: its achievement summary costs a
                          // reconcile pass the feed does not need.
                          if (_challengesVisited)
                            _ChallengesTab(challenges: challenges)
                          else
                            const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
      ),
    ),
  );

  Widget _buildHeader(BuildContext context) => Row(
    children: [
      if (Navigator.canPop(context)) ...[
        const _BackButton(),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Text(
          'Your Circle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
          ),
        ),
      ),
      StreamBuilder<int>(
        stream: _requestCount,
        initialData: 0,
        builder: (context, snapshot) => _IconCircleButton(
          icon: Icons.person_add_alt_1_rounded,
          tooltip: 'People',
          badge: snapshot.data ?? 0,
          onTap: () => _openPeople(context, profile),
        ),
      ),
      const SizedBox(width: 8),
      Semantics(
        button: true,
        label: 'Your profile',
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  CircleUserProfilePage(profile: profile, isOwner: true),
            ),
          ),
          child: _ProfileAvatar(profile: profile, radius: 22),
        ),
      ),
    ],
  );
}
