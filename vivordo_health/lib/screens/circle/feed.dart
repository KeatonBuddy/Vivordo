part of '../circle_screen.dart';

class _FeedTab extends StatelessWidget {
  const _FeedTab({
    required this.profile,
    required this.friends,
    required this.challenges,
    required this.onOpenChallenges,
  });

  final CircleProfile profile;
  final List<CircleProfile> friends;
  final _ChallengeData challenges;
  final VoidCallback onOpenChallenges;

  @override
  Widget build(BuildContext context) {
    final ongoing = challenges.ongoing;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 40),
      children: [
        _TodayStrip(profile: profile),
        const SizedBox(height: 22),
        _NeedsYouCard(
          key: const ValueKey('needs-you'),
          invites: challenges.invites,
          challenges: challenges,
        ),
        if (ongoing.isNotEmpty) ...[
          _SectionHeader(
            'Active challenges',
            trailing: _LinkButton(label: 'See all', onTap: onOpenChallenges),
          ),
          const SizedBox(height: 10),
          if (ongoing.length == 1)
            _ChallengeSummaryCard(
              membership: ongoing.single,
              challenges: challenges,
              compact: true,
            )
          else
            _HorizontalStrip(
              children: [
                for (final membership in ongoing)
                  SizedBox(
                    width: 272,
                    child: _ChallengeSummaryCard(
                      membership: membership,
                      challenges: challenges,
                      compact: true,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 26),
        ],
        const _SectionHeader('Recent activity'),
        const SizedBox(height: 12),
        _ActivityFeed(
          key: const ValueKey('activity-feed'),
          profile: profile,
          hasFriends: friends.isNotEmpty,
        ),
      ],
    );
  }
}

/// Today's activity ring for you and each friend. Also keeps today's summary
/// published so friends' strips can show your ring.
class _TodayStrip extends StatefulWidget {
  const _TodayStrip({required this.profile});

  final CircleProfile profile;

  @override
  State<_TodayStrip> createState() => _TodayStripState();
}

class _TodayStripState extends State<_TodayStrip> {
  late final Stream<List<CircleProfile>> _friends =
      CircleProfileService.watchFriendsByRecentActivity();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CircleProfile>>(
    stream: _friends,
    builder: (context, snapshot) {
      final friends = snapshot.data ?? const <CircleProfile>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader('Today in your circle'),
          const SizedBox(height: 12),
          _HorizontalStrip(
            spacing: 14,
            children: [
              _MyTodayRing(profile: widget.profile),
              for (final friend in friends)
                _FriendTodayRing(key: ValueKey(friend.uid), profile: friend),
              if (friends.isEmpty)
                _AddFriendRing(
                  onTap: () => _openPeople(context, widget.profile),
                ),
            ],
          ),
        ],
      );
    },
  );
}

/// A sideways-scrolling row that sizes to its tallest child, so larger text
/// grows the row instead of overflowing a fixed height.
class _HorizontalStrip extends StatelessWidget {
  const _HorizontalStrip({required this.children, this.spacing = 12});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    physics: const BouncingScrollPhysics(),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: spacing,
      children: children,
    ),
  );
}

class _MyTodayRing extends StatefulWidget {
  const _MyTodayRing({required this.profile});

  final CircleProfile profile;

  @override
  State<_MyTodayRing> createState() => _MyTodayRingState();
}

class _MyTodayRingState extends State<_MyTodayRing> {
  late final Stream<List<SavedWorkout>> _workouts = WorkoutService.watchAll();
  late final Stream<ActivityGoals> _goals = ActivityGoalsService.watch();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _metrics =
      _todayMetrics();
  String? _lastPublished;

  static Stream<DocumentSnapshot<Map<String, dynamic>>> _todayMetrics() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Stream.empty();
    final now = DateTime.now();
    final dayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('metrics_daily')
        .doc(dayKey)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _metrics,
        builder: (context, metricsSnapshot) {
          final data = metricsSnapshot.data?.data();
          int sum(String key) =>
              ((data?[key] as Map?)?['sum'] as num?)?.round() ?? 0;
          final steps = sum('steps');
          final calories = sum('active_calories');
          final exercise = sum('exercise_time');
          return StreamBuilder<ActivityGoals>(
            stream: _goals,
            initialData: const ActivityGoals(),
            builder: (context, goalsSnapshot) {
              final goals = goalsSnapshot.data ?? const ActivityGoals();
              _publish(
                steps: steps,
                stepsGoal: goals.steps,
                calories: calories,
                caloriesGoal: goals.activeCalories,
                exercise: exercise,
                exerciseGoal: goals.exerciseMinutes,
              );
              final ring = _RingProgress.from(
                steps: steps,
                stepsGoal: goals.steps,
                calories: calories,
                caloriesGoal: goals.activeCalories,
                exercise: exercise,
                exerciseGoal: goals.exerciseMinutes,
              );
              return StreamBuilder<List<SavedWorkout>>(
                stream: _workouts,
                builder: (context, workoutsSnapshot) => _RingAvatar(
                  profile: widget.profile,
                  label: 'You',
                  ring: ring,
                  streak: WorkoutService.calculateCurrentStreak(
                    workoutsSnapshot.data ?? const [],
                  ),
                  onTap: () => _openProfile(context, widget.profile),
                ),
              );
            },
          );
        },
      );

  void _publish({
    required int steps,
    required int stepsGoal,
    required int calories,
    required int caloriesGoal,
    required int exercise,
    required int exerciseGoal,
  }) {
    final signature =
        '$steps:$stepsGoal:$calories:$caloriesGoal:$exercise:$exerciseGoal';
    if (_lastPublished == signature) return;
    _lastPublished = signature;
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

class _FriendTodayRing extends StatefulWidget {
  const _FriendTodayRing({super.key, required this.profile});

  final CircleProfile profile;

  @override
  State<_FriendTodayRing> createState() => _FriendTodayRingState();
}

class _FriendTodayRingState extends State<_FriendTodayRing> {
  late final Stream<CircleDailyFitness?> _fitness =
      CircleProfileService.watchTodayFitness(widget.profile.uid);
  late final Stream<int> _streak = CircleProfileService.watchWorkoutStreak(
    widget.profile.uid,
  );

  CircleProfile get profile => widget.profile;

  @override
  Widget build(BuildContext context) => StreamBuilder<CircleDailyFitness?>(
    stream: _fitness,
    builder: (context, fitnessSnapshot) {
      final fitness = fitnessSnapshot.data;
      return StreamBuilder<int>(
        stream: _streak,
        initialData: 0,
        builder: (context, streakSnapshot) => _RingAvatar(
          profile: profile,
          label: profile.username,
          ring: fitness == null
              ? const _RingProgress(0, closed: false)
              : _RingProgress.from(
                  steps: fitness.steps,
                  stepsGoal: fitness.stepsGoal,
                  calories: fitness.activeCalories,
                  caloriesGoal: fitness.activeCaloriesGoal,
                  exercise: fitness.exerciseMinutes,
                  exerciseGoal: fitness.exerciseMinutesGoal,
                ),
          streak: streakSnapshot.data ?? 0,
          onTap: () => _openFriendQuickLook(context, profile),
        ),
      );
    },
  );
}

/// Average of the three activity goals; [closed] once every goal is met.
class _RingProgress {
  const _RingProgress(this.value, {required this.closed});

  factory _RingProgress.from({
    required int steps,
    required int stepsGoal,
    required int calories,
    required int caloriesGoal,
    required int exercise,
    required int exerciseGoal,
  }) {
    double part(int value, int goal) =>
        goal <= 0 ? 0 : (value / goal).clamp(0.0, 1.0);
    final parts = [
      part(steps, stepsGoal),
      part(calories, caloriesGoal),
      part(exercise, exerciseGoal),
    ];
    return _RingProgress(
      parts.reduce((a, b) => a + b) / 3,
      closed: parts.every((value) => value >= 1),
    );
  }

  final double value;
  final bool closed;
}

class _RingAvatar extends StatelessWidget {
  const _RingAvatar({
    required this.profile,
    required this.label,
    required this.ring,
    required this.streak,
    required this.onTap,
  });

  final CircleProfile profile;
  final String label;
  final _RingProgress ring;
  final int streak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = ring.closed ? _ringExercise : _brand;
    return Semantics(
      button: true,
      label:
          '$label, ${(ring.value * 100).round()}% of today\'s goals, $streak day workout streak',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 68,
          child: Column(
            children: [
              SizedBox.square(
                dimension: 68,
                child: CustomPaint(
                  painter: _RingPainter(
                    progress: ring.value,
                    color: color,
                    track: ring.closed
                        ? context.circle.successTint
                        : context.circle.accentTint,
                  ),
                  child: Center(
                    child: _ProfileAvatar(profile: profile, radius: 26),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              if (streak > 0)
                _StreakLabel(days: streak)
              else
                Text(
                  'no streak',
                  style: TextStyle(color: context.muted, fontSize: 11),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddFriendRing extends StatelessWidget {
  const _AddFriendRing({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Add friends',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.circle.accentTint,
                border: Border.all(color: _brand, width: 2),
              ),
              child: Icon(Icons.add_rounded, color: context.circle.accent),
            ),
            const SizedBox(height: 6),
            Text(
              'Add',
              style: TextStyle(
                color: context.vivordoColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    this.strokeWidth = 4,
  });

  final double progress;
  final Color color;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, paint..color = track);
    if (progress <= 0) return;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.track != track;
}

/// Challenge invites and friend requests in one place; hidden when empty.
class _NeedsYouCard extends StatefulWidget {
  const _NeedsYouCard({
    super.key,
    required this.invites,
    required this.challenges,
  });

  final List<CircleChallengeMembership> invites;
  final _ChallengeData challenges;

  @override
  State<_NeedsYouCard> createState() => _NeedsYouCardState();
}

class _NeedsYouCardState extends State<_NeedsYouCard> {
  late final Stream<List<CircleFriendRequest>> _requests =
      CircleProfileService.watchIncomingRequests();

  List<CircleChallengeMembership> get invites => widget.invites;
  _ChallengeData get challenges => widget.challenges;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<CircleFriendRequest>>(
        stream: _requests,
        builder: (context, snapshot) {
          final requests = snapshot.data ?? const <CircleFriendRequest>[];
          final rows = <Widget>[
            for (final invite in invites)
              _InviteRow(
                key: ValueKey('invite-${invite.challengeId}'),
                membership: invite,
                challenges: challenges,
              ),
            for (final request in requests)
              _FriendRequestRow(
                key: ValueKey('request-${request.profile.uid}'),
                request: request,
              ),
          ];
          if (rows.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 26),
            child: _CircleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Needs you',
                          style: TextStyle(
                            color: context.vivordoColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _CountBadge(count: rows.length),
                    ],
                  ),
                  for (var index = 0; index < rows.length; index++) ...[
                    if (index > 0)
                      Divider(height: 1, color: context.vivordoColors.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: rows[index],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
}

class _InviteRow extends StatefulWidget {
  const _InviteRow({
    super.key,
    required this.membership,
    required this.challenges,
  });

  final CircleChallengeMembership membership;
  final _ChallengeData challenges;

  @override
  State<_InviteRow> createState() => _InviteRowState();
}

class _InviteRowState extends State<_InviteRow> {
  var _responding = false;

  @override
  Widget build(BuildContext context) {
    final invite = widget.membership;
    final visual = _challengeVisual(context, invite.type);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconTile(
          icon: visual.icon,
          color: visual.color,
          background: visual.tint,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${invite.creatorName} challenged you to ${invite.title}',
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_goalLabel(invite)} in ${invite.durationDays} day${invite.durationDays == 1 ? '' : 's'}',
                style: TextStyle(color: context.muted, fontSize: 13),
              ),
              if (invite.message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '“${invite.message}”',
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
              const SizedBox(height: 10),
              _AcceptDeclineButtons(
                busy: _responding,
                onDecline: () => _respond(false),
                onAccept: () => _respond(true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _respond(bool accept) async {
    setState(() => _responding = true);
    final ok = await _respondToChallenge(context, widget.membership, accept);
    if (mounted && !ok) setState(() => _responding = false);
  }
}

class _FriendRequestRow extends StatefulWidget {
  const _FriendRequestRow({super.key, required this.request});

  final CircleFriendRequest request;

  @override
  State<_FriendRequestRow> createState() => _FriendRequestRowState();
}

class _FriendRequestRowState extends State<_FriendRequestRow> {
  var _responding = false;

  @override
  Widget build(BuildContext context) {
    final requester = widget.request.profile;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileAvatar(profile: requester, radius: 23),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${requester.username} wants to join your circle',
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (widget.request.createdAt != null) ...[
                const SizedBox(height: 3),
                Text(
                  _relativeActivityTime(widget.request.createdAt!),
                  style: TextStyle(color: context.muted, fontSize: 13),
                ),
              ],
              const SizedBox(height: 10),
              _AcceptDeclineButtons(
                busy: _responding,
                onDecline: () => _respond(false),
                onAccept: () => _respond(true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _respond(bool accept) async {
    setState(() => _responding = true);
    final ok = await _respondToFriendRequest(
      context,
      widget.request.profile,
      accept,
    );
    if (mounted && !ok) setState(() => _responding = false);
  }
}

class _AcceptDeclineButtons extends StatelessWidget {
  const _AcceptDeclineButtons({
    required this.busy,
    required this.onDecline,
    required this.onAccept,
  });

  final bool busy;
  final VoidCallback onDecline;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      FilledButton(
        onPressed: busy ? null : onDecline,
        style: _secondaryButtonStyle(context, height: 40),
        child: const Text('Decline'),
      ),
      const SizedBox(width: 8),
      FilledButton(
        onPressed: busy ? null : onAccept,
        style: _primaryButtonStyle(height: 40),
        child: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Accept'),
      ),
    ],
  );
}

/// Accepts or declines a friend request; false when it failed.
Future<bool> _respondToFriendRequest(
  BuildContext context,
  CircleProfile requester,
  bool accept,
) async {
  try {
    if (accept) {
      await CircleProfileService.acceptFriendRequest(requester.uid);
      if (context.mounted) {
        _showSnack(context, '${requester.username} joined your Circle');
      }
    } else {
      await CircleProfileService.declineFriendRequest(requester.uid);
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      _showSnack(
        context,
        accept
            ? 'Could not accept this request'
            : 'Could not decline this request',
      );
    }
    return false;
  }
}

enum _ActivityFilter { all, workouts, achievements }

/// Your recent posts merged with friends', newest first.
class _ActivityFeed extends StatefulWidget {
  const _ActivityFeed({
    super.key,
    required this.profile,
    required this.hasFriends,
  });

  final CircleProfile profile;
  final bool hasFriends;

  @override
  State<_ActivityFeed> createState() => _ActivityFeedState();
}

class _ActivityFeedState extends State<_ActivityFeed> {
  var _filter = _ActivityFilter.all;
  late final Stream<List<CircleActivity>> _mine =
      CircleProfileService.watchMyRecentActivities(
        widget.profile,
        days: 7,
        limit: 5,
      );
  late final Stream<List<CircleActivity>> _friends =
      CircleProfileService.watchLatestFriendActivities();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CircleActivity>>(
    stream: _friends,
    builder: (context, friendsSnapshot) => StreamBuilder<List<CircleActivity>>(
      stream: _mine,
      builder: (context, mineSnapshot) {
        if (!friendsSnapshot.hasData && !mineSnapshot.hasData) {
          return const _Loading();
        }
        final all = [...?friendsSnapshot.data, ...?mineSnapshot.data]
          ..sort((a, b) => b.day.compareTo(a.day));
        final visible = all
            .where(
              (activity) => switch (_filter) {
                _ActivityFilter.all => true,
                _ActivityFilter.workouts =>
                  activity.kind != 'achievement' && activity.kind != 'journal',
                _ActivityFilter.achievements => activity.kind == 'achievement',
              },
            )
            .take(10)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in _ActivityFilter.values)
                  _FilterChip(
                    label: switch (filter) {
                      _ActivityFilter.all => 'All',
                      _ActivityFilter.workouts => 'Workouts',
                      _ActivityFilter.achievements => 'Achievements',
                    },
                    selected: _filter == filter,
                    onTap: () => setState(() => _filter = filter),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (visible.isEmpty)
              _EmptyState(
                icon: Icons.favorite_border_rounded,
                title: all.isEmpty
                    ? 'No recent activity'
                    : _filter == _ActivityFilter.workouts
                    ? 'No workouts yet'
                    : 'No achievements yet',
                detail: widget.hasFriends
                    ? 'Shared workouts and achievements from your circle show up here.'
                    : 'Add friends to see what they share.',
              )
            else
              for (final activity in visible) ...[
                _ActivityPostCard(
                  key: ValueKey('${activity.profile.uid}/${activity.id}'),
                  activity: activity,
                ),
                const SizedBox(height: 10),
              ],
          ],
        );
      },
    ),
  );
}

bool _isMine(CircleActivity activity) =>
    activity.profile.uid == FirebaseAuth.instance.currentUser?.uid;

String _activityDetails(CircleActivity activity) => [
  if (activity.minutes > 0) '${activity.minutes} min',
  if (activity.km != null) '${activity.km!.toStringAsFixed(1)} km',
  if (activity.sets != null && activity.sets! > 0) '${activity.sets} sets',
].join(' · ');

/// The icon tile a post shows on the right: badge art for achievements,
/// otherwise the activity's own icon and colour.
class _ActivityVisual extends StatelessWidget {
  const _ActivityVisual({required this.activity, this.size = 46});

  final CircleActivity activity;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (activity.kind == 'achievement') {
      return _AchievementActivityBadge(activity: activity, size: size + 6);
    }
    if (activity.kind == 'journal') {
      return _IconTile(
        icon: Icons.menu_book_rounded,
        color: context.circle.pink,
        background: context.circle.pinkTint,
        size: size,
      );
    }
    final visual = workoutActivityVisual(
      activity.name,
      category: activity.activityCategory,
    );
    return _IconTile(
      icon: visual.icon,
      color: Colors.white,
      background: visual.color,
      size: size,
    );
  }
}

class _ActivityPostCard extends StatelessWidget {
  const _ActivityPostCard({super.key, required this.activity});

  final CircleActivity activity;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final details = _activityDetails(activity);
    final (verb, subject) = switch (activity.kind) {
      'journal' => ('shared a', 'Journal Entry'),
      'achievement' => (
        'earned',
        activity.achievementTier == null
            ? activity.name
            : '${activity.name} · ${_tierLabel(activity.achievementTier!)}',
      ),
      _ => ('completed', activity.name),
    };
    return _CircleCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      onTap: () => _openActivityDetails(context, activity),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openProfile(context, activity.profile),
                child: _ProfileAvatar(profile: activity.profile, radius: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            activity.profile.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_isMine(activity)) ...[
                          const SizedBox(width: 8),
                          const _Pill(label: 'You'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        text: '$verb ',
                        children: [
                          TextSpan(
                            text: subject,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (activity.kind == 'journal' &&
                              activity.mood != null)
                            TextSpan(text: ' · ${activity.mood}'),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.muted,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    if (details.isNotEmpty &&
                        activity.kind != 'achievement') ...[
                      const SizedBox(height: 2),
                      Text(
                        details,
                        style: TextStyle(color: context.muted, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      _relativeActivityTime(activity.day),
                      style: TextStyle(color: context.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _ActivityVisual(activity: activity),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: colors.border),
          _EngagementBar(activity: activity),
        ],
      ),
    );
  }
}

class _EngagementBar extends StatefulWidget {
  const _EngagementBar({required this.activity});

  final CircleActivity activity;

  @override
  State<_EngagementBar> createState() => _EngagementBarState();
}

class _EngagementBarState extends State<_EngagementBar> {
  var _saving = false;
  late final Stream<List<CircleActivityLike>> _likes =
      CircleProfileService.watchActivityLikes(widget.activity);
  late final Stream<List<CircleActivityComment>> _comments =
      CircleProfileService.watchActivityComments(widget.activity);

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CircleActivityLike>>(
    stream: _likes,
    builder: (context, likesSnapshot) {
      final likes = likesSnapshot.data ?? const <CircleActivityLike>[];
      final liked = _likedByMe(likes);
      return StreamBuilder<List<CircleActivityComment>>(
        stream: _comments,
        builder: (context, commentsSnapshot) => Row(
          children: [
            _EngagementButton(
              icon: liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: '${likes.length}',
              semanticLabel: liked ? 'Unlike' : 'Like',
              active: liked,
              busy: _saving,
              onTap: () => _toggle(liked),
            ),
            const SizedBox(width: 10),
            _EngagementButton(
              icon: Icons.chat_bubble_outline_rounded,
              label: '${commentsSnapshot.data?.length ?? 0}',
              semanticLabel: 'Comments',
              onTap: () => _openActivityDetails(context, widget.activity),
            ),
            const Spacer(),
            if (!_isMine(widget.activity))
              IconButton(
                tooltip: 'Report post',
                icon: Icon(Icons.flag_outlined, color: context.muted, size: 20),
                onPressed: () => _reportPost(context, widget.activity),
              ),
          ],
        ),
      );
    },
  );

  Future<void> _toggle(bool liked) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await CircleProfileService.setActivityLiked(
        widget.activity,
        liked: !liked,
      );
    } catch (_) {
      if (mounted) _showSnack(context, 'Could not update your like');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

bool _likedByMe(List<CircleActivityLike> likes) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return uid != null && likes.any((like) => like.userUid == uid);
}

class _EngagementButton extends StatelessWidget {
  const _EngagementButton({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.active = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool active;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = active ? context.circle.accent : context.muted;
    return Semantics(
      button: true,
      label: '$semanticLabel, $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, size: 21, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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

class _AchievementActivityBadge extends StatelessWidget {
  const _AchievementActivityBadge({required this.activity, required this.size});

  final CircleActivity activity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = _IconTile(
      icon: Icons.emoji_events_rounded,
      color: context.circle.accent,
      background: context.circle.accentTint,
      size: size,
    );
    final asset = activity.achievementBadgeAsset;
    if (asset == null || asset.trim().isEmpty) return fallback;
    return ClipOval(
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

Future<void> _reportPost(BuildContext context, CircleActivity activity) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ReportPostSheet(
      onSubmit: (reason, details) async {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) throw StateError('Sign in to report a post.');
        await FirebaseFirestore.instance.collection('reports').add({
          'reporterUid': uid,
          'postOwnerUid': activity.profile.uid,
          'postId': activity.id,
          'reason': reason,
          'details': details,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      },
    ),
  );
  if (submitted == true && context.mounted) {
    _showSnack(context, 'Report submitted. Thank you for letting us know.');
  }
}

Future<void> _reportComment(
  BuildContext context,
  CircleActivity activity,
  CircleActivityComment comment,
) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ReportPostSheet(
      isComment: true,
      onSubmit: (reason, details) async {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) throw StateError('Sign in to report.');
        await FirebaseFirestore.instance.collection('reports').add({
          'type': 'comment',
          'reporterUid': uid,
          'postOwnerUid': activity.profile.uid,
          'postId': activity.id,
          'commentId': comment.id,
          'commentAuthorUid': comment.authorUid,
          'reason': reason,
          'details': details,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      },
    ),
  );
  if (sent == true && context.mounted) {
    _showSnack(context, 'Comment report submitted.');
  }
}

void _openActivityDetails(BuildContext context, CircleActivity activity) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.circle.scrim,
      builder: (_) => _ActivityDetailsSheet(activity: activity),
    );

class _ActivityDetailsSheet extends StatefulWidget {
  const _ActivityDetailsSheet({required this.activity});

  final CircleActivity activity;

  @override
  State<_ActivityDetailsSheet> createState() => _ActivityDetailsSheetState();
}

class _ActivityDetailsSheetState extends State<_ActivityDetailsSheet> {
  final _commentController = TextEditingController();
  var _sending = false;
  var _savingLike = false;
  late final Stream<List<CircleActivityLike>> _likes =
      CircleProfileService.watchActivityLikes(activity);
  late final Stream<List<CircleActivityComment>> _comments =
      CircleProfileService.watchActivityComments(activity);

  CircleActivity get activity => widget.activity;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final palette = context.circle;
    final title = switch (activity.kind) {
      'achievement' => 'Earned ${activity.name}',
      'journal' => 'Journal Entry',
      _ => activity.name,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: .8,
        minChildSize: .5,
        maxChildSize: .95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              const _SheetGrabber(),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _openProfile(context, activity.profile),
                          child: _ProfileAvatar(
                            profile: activity.profile,
                            radius: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                activity.profile.username,
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                _relativeActivityTime(activity.day),
                                style: TextStyle(
                                  color: context.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_isMine(activity))
                          _IconCircleButton(
                            icon: Icons.flag_outlined,
                            tooltip: 'Report post',
                            onTap: () => _reportPost(context, activity),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (activity.kind == 'achievement') ...[
                      Center(
                        child: _AchievementActivityBadge(
                          activity: activity,
                          size: 104,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (activity.minutes > 0)
                          _StatChip(label: '${activity.minutes} min'),
                        if (activity.km != null)
                          _StatChip(
                            label: '${activity.km!.toStringAsFixed(1)} km',
                          ),
                        if (activity.sets != null && activity.sets! > 0)
                          _StatChip(label: '${activity.sets} sets'),
                        if (activity.activityCategory != null)
                          _StatChip(
                            label: activity.activityCategory!,
                            color: palette.accent,
                            background: palette.accentTint,
                          ),
                        if (activity.kind == 'achievement')
                          _StatChip(
                            label: activity.achievementTier == null
                                ? 'Achievement unlocked'
                                : '${_tierLabel(activity.achievementTier!)} tier',
                            color: palette.accent,
                            background: palette.accentTint,
                          ),
                        if (activity.mood != null)
                          _StatChip(
                            label: 'Mood · ${activity.mood}',
                            color: palette.success,
                            background: palette.successTint,
                          ),
                      ],
                    ),
                    if (activity.summary?.trim().isNotEmpty == true &&
                        activity.kind != 'activity' &&
                        activity.kind != 'workout') ...[
                      const SizedBox(height: 12),
                      Text(
                        activity.summary!.trim(),
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _buildLikes(context),
                    const SizedBox(height: 18),
                    Divider(height: 1, color: colors.border),
                    const SizedBox(height: 18),
                    _buildComments(context),
                  ],
                ),
              ),
              _buildComposer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLikes(
    BuildContext context,
  ) => StreamBuilder<List<CircleActivityLike>>(
    stream: _likes,
    builder: (context, snapshot) {
      final likes = snapshot.data ?? const <CircleActivityLike>[];
      final liked = _likedByMe(likes);
      final names = [
        if (liked) 'you',
        ...likes
            .where((like) => like.userUid != _myUid)
            .map((like) => like.username),
      ];
      final summary = switch (names.length) {
        0 => 'No likes yet',
        1 => 'Liked by ${names[0]}',
        2 => 'Liked by ${names[0]} and ${names[1]}',
        _ => 'Liked by ${names[0]}, ${names[1]} and ${names.length - 2} others',
      };
      return Row(
        children: [
          if (likes.isNotEmpty) ...[
            _LikerStack(likes: likes),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              summary,
              style: TextStyle(color: context.muted, fontSize: 13),
            ),
          ),
          _IconCircleButton(
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            tooltip: liked ? 'Unlike' : 'Like',
            filled: liked,
            onTap: _savingLike ? null : () => _toggleLike(liked),
          ),
        ],
      );
    },
  );

  Widget _buildComments(BuildContext context) =>
      StreamBuilder<List<CircleActivityComment>>(
        stream: _comments,
        builder: (context, snapshot) {
          final comments = snapshot.data ?? const <CircleActivityComment>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader('Comments · ${comments.length}'),
              const SizedBox(height: 12),
              if (comments.isEmpty)
                Text(
                  'Be the first to leave a comment.',
                  style: TextStyle(color: context.muted, fontSize: 14),
                )
              else
                for (final comment in comments)
                  _CommentRow(
                    name: comment.authorUid == _myUid
                        ? 'You'
                        : comment.authorName,
                    avatarName: comment.authorName,
                    seed: comment.authorUid,
                    photoUrl: comment.authorPhotoUrl,
                    text: comment.text,
                    time: comment.createdAt == null
                        ? null
                        : _relativeActivityTime(comment.createdAt!),
                    onReport: comment.authorUid == _myUid
                        ? null
                        : () => _reportComment(context, activity, comment),
                  ),
            ],
          );
        },
      );

  Widget _buildComposer(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: _CommentComposer(
        controller: _commentController,
        sending: _sending,
        onSend: _send,
      ),
    ),
  );

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _toggleLike(bool liked) async {
    setState(() => _savingLike = true);
    try {
      await CircleProfileService.setActivityLiked(activity, liked: !liked);
    } catch (_) {
      if (mounted) _showSnack(context, 'Could not update your like');
    } finally {
      if (mounted) setState(() => _savingLike = false);
    }
  }

  Future<void> _send() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await CircleProfileService.addActivityComment(activity, text);
      _commentController.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (_) {
      if (mounted) _showSnack(context, 'Could not post your comment');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, this.color, this.background});

  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: background ?? context.vivordoColors.cardMuted,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Center(
      widthFactor: 1,
      child: Text(
        label,
        style: TextStyle(
          color: color ?? context.vivordoColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _LikerStack extends StatelessWidget {
  const _LikerStack({required this.likes});

  final List<CircleActivityLike> likes;

  @override
  Widget build(BuildContext context) {
    final shown = likes.take(3).toList(growable: false);
    const size = 28.0;
    return SizedBox(
      width: size + (shown.length - 1) * 20,
      height: size,
      child: Stack(
        children: [
          for (var index = 0; index < shown.length; index++)
            Positioned(
              left: index * 20.0,
              child: _InitialsAvatar(
                name: shown[index].username,
                seed: shown[index].userUid,
                photoUrl: shown[index].photoUrl,
                size: size,
                borderColor: context.vivordoColors.card,
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.name,
    required this.seed,
    required this.text,
    this.avatarName,
    this.photoUrl,
    this.time,
    this.onReport,
    this.onDelete,
  });

  final String name;
  final String seed;
  final String text;

  /// Initials source when [name] is a label such as "You".
  final String? avatarName;
  final String? photoUrl;
  final String? time;
  final VoidCallback? onReport;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InitialsAvatar(
          name: avatarName ?? name,
          seed: seed,
          photoUrl: photoUrl,
          size: 34,
        ),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (time != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      time!,
                      style: TextStyle(color: context.muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        if (onReport != null || onDelete != null)
          PopupMenuButton<String>(
            tooltip: 'Comment options',
            icon: Icon(
              Icons.more_horiz_rounded,
              size: 20,
              color: context.muted,
            ),
            onSelected: (value) =>
                value == 'delete' ? onDelete?.call() : onReport?.call(),
            itemBuilder: (_) => [
              if (onReport != null)
                const PopupMenuItem(value: 'report', child: Text('Report')),
              if (onDelete != null)
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
      ],
    ),
  );
}

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            maxLength: 500,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            // Return sends: the app's floating assistant can cover the
            // send button while the keyboard is up.
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: TextStyle(color: colors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Add a comment',
              hintStyle: TextStyle(color: context.muted),
              counterText: '',
              filled: true,
              fillColor: colors.input,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: const BorderSide(color: _brand, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        sending
            ? const SizedBox.square(
                dimension: 44,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _IconCircleButton(
                icon: Icons.send_rounded,
                tooltip: 'Send comment',
                filled: true,
                onTap: onSend,
              ),
      ],
    );
  }
}
