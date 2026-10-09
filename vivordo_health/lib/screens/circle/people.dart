part of '../circle_screen.dart';

void _openPeople(BuildContext context, CircleProfile me) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => _PeoplePage(me: me)));

class _PeoplePage extends StatefulWidget {
  const _PeoplePage({required this.me});

  final CircleProfile me;

  @override
  State<_PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<_PeoplePage> {
  final _searchController = TextEditingController();
  late final Stream<List<CircleFriendRequest>> _requests =
      CircleProfileService.watchIncomingRequests();
  late final Stream<List<CircleProfile>> _friends =
      CircleProfileService.watchFriendsByRecentActivity();
  CircleProfile? _result;
  String? _message;
  var _searching = false;

  CircleProfile get me => widget.me;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      backgroundColor: colors.page,
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 40),
          children: [
            Row(
              children: [
                const _BackButton(),
                const SizedBox(width: 12),
                Text(
                  'People',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SearchField(
              controller: _searchController,
              hint: 'Search username or friend code',
              onSubmitted: (_) => _search(),
            ),
            if (_searching)
              const _Loading(height: 80)
            else if (_result != null) ...[
              const SizedBox(height: 12),
              _SearchResultCard(profile: _result!, onAdd: _sendRequest),
            ] else if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.muted),
              ),
            ],
            const SizedBox(height: 18),
            _FriendCodeCard(profile: me),
            // Keyed so ListView keeps these subscriptions when the search
            // result row above them appears or disappears.
            StreamBuilder<List<CircleFriendRequest>>(
              key: const ValueKey('requests'),
              stream: _requests,
              builder: (context, snapshot) {
                final requests = snapshot.data ?? const [];
                if (requests.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader('Requests', badge: requests.length),
                      const SizedBox(height: 12),
                      for (final request in requests) ...[
                        _CircleCard(
                          child: _FriendRequestRow(
                            key: ValueKey('people-${request.profile.uid}'),
                            request: request,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 26),
            StreamBuilder<List<CircleProfile>>(
              key: const ValueKey('friends'),
              stream: _friends,
              builder: (context, snapshot) {
                final friends = snapshot.data ?? const <CircleProfile>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      'Your friends · ${friends.length}',
                      trailing: friends.length > 1
                          ? Text(
                              'Most active first',
                              style: TextStyle(
                                color: context.muted,
                                fontSize: 12,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    if (!snapshot.hasData &&
                        snapshot.connectionState == ConnectionState.waiting)
                      const _Loading()
                    else if (friends.isEmpty)
                      const _EmptyState(
                        icon: Icons.groups_rounded,
                        title: 'No friends yet',
                        detail:
                            'Search above, or send someone your friend code.',
                      )
                    else
                      _CircleCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < friends.length;
                              index++
                            ) ...[
                              if (index > 0)
                                Divider(height: 1, color: colors.border),
                              _FriendRow(
                                key: ValueKey(friends[index].uid),
                                profile: friends[index],
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _result = null;
      _message = null;
    });
    try {
      final result = await CircleProfileService.findFriend(query);
      if (!mounted) return;
      setState(() {
        _result = result?.uid == me.uid ? null : result;
        _message = result == null
            ? 'No Circle profile found'
            : result.uid == me.uid
            ? 'That is your profile'
            : null;
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not search right now');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(CircleProfile recipient) async {
    try {
      await CircleProfileService.sendFriendRequest(recipient);
      if (!mounted) return;
      setState(() {
        _result = null;
        _message = 'Friend request sent to ${recipient.username}';
      });
    } catch (error) {
      debugPrint('Send friend request failed: $error');
      if (mounted) {
        // StateErrors from the service carry our own plain-English copy.
        _showSnack(
          context,
          error is StateError
              ? error.message
              : "Couldn't send the friend request. Try again.",
          kind: ToastKind.error,
        );
      }
    }
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.profile, required this.onAdd});

  final CircleProfile profile;
  final ValueChanged<CircleProfile> onAdd;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: Row(
      children: [
        _ProfileAvatar(profile: profile, radius: 23),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            profile.username,
            style: TextStyle(
              color: context.vivordoColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        FilledButton(
          onPressed: () => onAdd(profile),
          style: _primaryButtonStyle(height: 40),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

class _FriendCodeCard extends StatelessWidget {
  const _FriendCodeCard({required this.profile});

  final CircleProfile profile;

  @override
  Widget build(BuildContext context) => _CircleCard(
    color: context.circle.accentTint,
    borderColor: Colors.transparent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR FRIEND CODE',
          style: TextStyle(
            color: context.circle.accent,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          profile.friendCode,
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    _copy(context, profile.friendCode, 'Friend code copied'),
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: const Text('Copy code'),
                style: FilledButton.styleFrom(
                  backgroundColor: context.vivordoColors.card,
                  foregroundColor: context.vivordoColors.textPrimary,
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _copy(
                  context,
                  _inviteText(profile),
                  'Invite copied to clipboard',
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 17),
                label: const Text('Copy invite'),
                style: _primaryButtonStyle(height: 44),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

String _inviteText(CircleProfile profile) =>
    'Join ${profile.username} on Vivordo Circle. Friend code: ${profile.friendCode}';

Future<void> _copy(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) _showSnack(context, message);
}

class _FriendRow extends StatefulWidget {
  const _FriendRow({super.key, required this.profile});

  final CircleProfile profile;

  @override
  State<_FriendRow> createState() => _FriendRowState();
}

class _FriendRowState extends State<_FriendRow> {
  late final Stream<int> _streak = CircleProfileService.watchWorkoutStreak(
    widget.profile.uid,
  );

  CircleProfile get profile => widget.profile;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _openProfile(context, profile),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          _ProfileAvatar(profile: profile, radius: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  profile.bio.trim().isEmpty
                      ? 'In your Circle'
                      : profile.bio.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          StreamBuilder<int>(
            stream: _streak,
            builder: (context, snapshot) => (snapshot.data ?? 0) > 0
                ? Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _StreakLabel(days: snapshot.data!, size: 13),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: context.muted),
        ],
      ),
    ),
  );
}

void _openFriendQuickLook(BuildContext context, CircleProfile profile) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.circle.scrim,
      builder: (_) => _FriendQuickLookSheet(profile: profile),
    );

class _FriendQuickLookSheet extends StatefulWidget {
  const _FriendQuickLookSheet({required this.profile});

  final CircleProfile profile;

  @override
  State<_FriendQuickLookSheet> createState() => _FriendQuickLookSheetState();
}

class _FriendQuickLookSheetState extends State<_FriendQuickLookSheet> {
  late final Stream<int> _streak = CircleProfileService.watchWorkoutStreak(
    widget.profile.uid,
  );
  late final Stream<CircleDailyFitness?> _fitness =
      CircleProfileService.watchTodayFitness(widget.profile.uid);

  CircleProfile get profile => widget.profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetGrabber(),
              const SizedBox(height: 18),
              Row(
                children: [
                  _ProfileAvatar(profile: profile, radius: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        StreamBuilder<int>(
                          stream: _streak,
                          initialData: 0,
                          builder: (context, snapshot) {
                            final streak = snapshot.data ?? 0;
                            return _Pill(
                              icon: Icons.local_fire_department_rounded,
                              label: streak == 0
                                  ? 'No workout streak'
                                  : '$streak-day workout streak',
                              color: context.circle.streak,
                              background: context.circle.streakTint,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionHeader('Today'),
              const SizedBox(height: 12),
              StreamBuilder<CircleDailyFitness?>(
                stream: _fitness,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const _Loading(height: 124);
                  }
                  final fitness = snapshot.data;
                  if (fitness == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Nothing shared today yet.',
                        style: TextStyle(color: context.muted, fontSize: 14),
                      ),
                    );
                  }
                  return _TodayRings(fitness: fitness);
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
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
                      style: _secondaryButtonStyle(context),
                      child: const Text('View profile'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _challengeFromSheet(context, profile),
                      icon: const Icon(Icons.emoji_events_rounded, size: 18),
                      label: const Text('Challenge'),
                      style: _primaryButtonStyle(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Closes the sheet, then opens the new-challenge flow from the page under it.
Future<void> _challengeFromSheet(
  BuildContext sheetContext,
  CircleProfile friend,
) async {
  final me = await CircleProfileService.watchCurrentProfile().first;
  if (!sheetContext.mounted || me == null) return;
  final navigator = Navigator.of(sheetContext);
  navigator.pop();
  if (navigator.mounted) {
    await _startNewChallenge(navigator.context, me, friend: friend);
  }
}

class _TodayRings extends StatelessWidget {
  const _TodayRings({required this.fitness});

  final CircleDailyFitness fitness;

  @override
  Widget build(BuildContext context) {
    double part(int value, int goal) =>
        goal <= 0 ? 0 : (value / goal).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox.square(
          dimension: 112,
          child: CustomPaint(
            painter: ActivityRingsPainter(
              move: part(fitness.steps, fitness.stepsGoal),
              exercise: part(
                fitness.activeCalories,
                fitness.activeCaloriesGoal,
              ),
              stand: part(fitness.exerciseMinutes, fitness.exerciseMinutesGoal),
              moveColor: _ringSteps,
              trackColor: context.vivordoColors.cardMuted,
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RingMetric(
                color: _ringSteps,
                label: 'Steps',
                value: _numberFormat.format(fitness.steps),
                goal: _numberFormat.format(fitness.stepsGoal),
              ),
              const SizedBox(height: 10),
              _RingMetric(
                color: _ringCalories,
                label: 'Active calories',
                value: '${fitness.activeCalories}',
                goal: '${fitness.activeCaloriesGoal}',
              ),
              const SizedBox(height: 10),
              _RingMetric(
                color: _ringExercise,
                label: 'Exercise',
                value: '${fitness.exerciseMinutes}',
                goal: '${fitness.exerciseMinutesGoal} min',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RingMetric extends StatelessWidget {
  const _RingMetric({
    required this.color,
    required this.label,
    required this.value,
    required this.goal,
  });

  final Color color;
  final String label;
  final String value;
  final String goal;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label, style: TextStyle(color: context.muted, fontSize: 12)),
        ],
      ),
      Text.rich(
        TextSpan(
          text: value,
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
          children: [
            TextSpan(
              text: ' / $goal',
              style: TextStyle(
                color: context.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
