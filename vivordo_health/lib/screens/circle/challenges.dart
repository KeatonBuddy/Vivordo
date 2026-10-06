part of '../circle_screen.dart';

/// The membership stream plus what the challenge UI needs to resolve
/// participant uids into people.
class _ChallengeData {
  const _ChallengeData({
    required this.memberships,
    required this.loading,
    required this.error,
    required this.me,
    required this.friendsById,
  });

  final List<CircleChallengeMembership> memberships;
  final bool loading;
  final Object? error;
  final CircleProfile me;
  final Map<String, CircleProfile> friendsById;

  List<CircleChallengeMembership> get invites =>
      memberships.where((membership) => membership.isInvite).toList();

  List<CircleChallengeMembership> get ongoing =>
      memberships.where((membership) => membership.isOngoing).toList();

  List<CircleChallengeMembership> get finished =>
      memberships
          .where(
            (membership) =>
                membership.status == 'completed' ||
                membership.status == 'expired',
          )
          .toList()
        ..sort(
          (a, b) => (b.endAt ?? b.createdAt).compareTo(a.endAt ?? a.createdAt),
        );

  /// Participants you can put a face to: you first, then friends.
  List<CircleProfile> peopleIn(CircleChallengeMembership membership) => [
    if (membership.participantUids.contains(me.uid)) me,
    for (final uid in membership.participantUids)
      if (uid != me.uid && friendsById[uid] != null) friendsById[uid]!,
  ];
}

typedef _ChallengeVisual = ({IconData icon, Color color, Color tint});

_ChallengeVisual _challengeVisual(BuildContext context, String type) {
  final palette = context.circle;
  return switch (type) {
    'step_total' => (
      icon: Icons.directions_walk_rounded,
      color: palette.info,
      tint: palette.infoTint,
    ),
    'scan_count' => (
      icon: Icons.monitor_heart_rounded,
      color: palette.streak,
      tint: palette.streakTint,
    ),
    'activity_count' => (
      icon: Icons.directions_run_rounded,
      color: palette.success,
      tint: palette.successTint,
    ),
    'journal_count' => (
      icon: Icons.menu_book_rounded,
      color: palette.pink,
      tint: palette.pinkTint,
    ),
    _ => (
      icon: Icons.fitness_center_rounded,
      color: palette.accent,
      tint: palette.accentTint,
    ),
  };
}

final _numberFormat = NumberFormat.decimalPattern();

String _goalLabel(CircleChallengeMembership membership) =>
    '${_numberFormat.format(membership.goal)} ${membership.unit}';

String _progressLabel(CircleChallengeMembership membership, int progress) =>
    '${_numberFormat.format(progress)} / ${_goalLabel(membership)}';

int _daysLeft(CircleChallengeMembership membership) {
  final endAt = membership.endAt;
  if (endAt == null) return membership.durationDays;
  final hours = endAt.difference(DateTime.now()).inHours;
  return hours <= 0 ? 0 : (hours + 23) ~/ 24;
}

String _daysLeftLabel(CircleChallengeMembership membership) {
  final days = _daysLeft(membership);
  return days == 0 ? 'Ends today' : '$days day${days == 1 ? '' : 's'} left';
}

/// Accepts or declines an invite; false when it failed.
Future<bool> _respondToChallenge(
  BuildContext context,
  CircleChallengeMembership membership,
  bool accept,
) async {
  try {
    await CircleChallengeService.respond(
      challengeId: membership.challengeId,
      accept: accept,
    );
    if (context.mounted) {
      _showSnack(
        context,
        accept ? 'Challenge accepted.' : 'Challenge declined.',
      );
    }
    return true;
  } catch (error) {
    debugPrint('Respond to challenge failed: $error');
    if (context.mounted) {
      _showSnack(
        context,
        "Couldn't update the challenge. Try again.",
        kind: ToastKind.error,
      );
    }
    return false;
  }
}

void _openChallengeDetail(
  BuildContext context,
  CircleChallengeMembership membership,
  _ChallengeData challenges,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) =>
        _ChallengeDetailPage(membership: membership, challenges: challenges),
  ),
);

class _ChallengesTab extends StatelessWidget {
  const _ChallengesTab({required this.challenges});

  final _ChallengeData challenges;

  @override
  Widget build(BuildContext context) {
    final invites = challenges.invites;
    final ongoing = challenges.ongoing;
    final finished = challenges.finished.take(5).toList(growable: false);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 40),
      children: [
        _StartChallengeCard(challenges: challenges),
        const SizedBox(height: 26),
        if (challenges.loading)
          const _Loading()
        else if (challenges.error != null)
          const _EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load challenges',
            detail: 'Check your connection, then reopen Circle.',
          )
        else ...[
          if (invites.isNotEmpty) ...[
            _SectionHeader('Invites', badge: invites.length),
            const SizedBox(height: 12),
            for (final invite in invites) ...[
              _CircleCard(
                child: _InviteRow(
                  key: ValueKey('invite-card-${invite.challengeId}'),
                  membership: invite,
                  challenges: challenges,
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 16),
          ],
          _SectionHeader('Active · ${ongoing.length}'),
          const SizedBox(height: 12),
          if (ongoing.isEmpty)
            const _EmptyState(
              icon: Icons.flag_rounded,
              title: 'No active challenges',
              detail: 'Start one above and invite a friend to join you.',
            )
          else
            for (final membership in ongoing) ...[
              _ChallengeSummaryCard(
                membership: membership,
                challenges: challenges,
              ),
              const SizedBox(height: 10),
            ],
          if (finished.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _SectionHeader('Finished'),
            const SizedBox(height: 12),
            _CircleCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Column(
                children: [
                  for (var index = 0; index < finished.length; index++) ...[
                    if (index > 0)
                      Divider(height: 1, color: context.vivordoColors.border),
                    _FinishedChallengeRow(membership: finished[index]),
                  ],
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 26),
        _AchievementsLinkCard(
          key: const ValueKey('achievements-link'),
          profile: challenges.me,
        ),
      ],
    );
  }
}

class _StartChallengeCard extends StatelessWidget {
  const _StartChallengeCard({required this.challenges});

  final _ChallengeData challenges;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start a challenge',
          style: TextStyle(
            color: context.vivordoColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Pick a preset or build your own.',
          style: TextStyle(color: context.muted, fontSize: 13),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          // Without this the grid inherits the page's bottom safe-area inset.
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.5,
          children: [
            for (final type in _ChallengeType.presets)
              _PresetButton(
                type: type,
                onTap: () =>
                    _startNewChallenge(context, challenges.me, type: type),
              ),
            _PresetButton(
              onTap: () => _startNewChallenge(context, challenges.me),
            ),
          ],
        ),
      ],
    ),
  );
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({required this.onTap, this.type});

  final _ChallengeType? type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final visual = type == null
        ? (
            icon: Icons.add_rounded,
            color: colors.textPrimary,
            tint: colors.card,
          )
        : _challengeVisual(context, type!.backendType);
    return Material(
      color: colors.cardMuted,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _IconTile(
                icon: visual.icon,
                color: visual.color,
                background: visual.tint,
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  type?.presetTitle ?? 'Custom',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChallengeSummaryCard extends StatelessWidget {
  const _ChallengeSummaryCard({
    required this.membership,
    required this.challenges,
    this.compact = false,
  });

  final CircleChallengeMembership membership;
  final _ChallengeData challenges;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final visual = _challengeVisual(context, membership.type);
    final waiting = membership.status == 'waiting';
    final people = challenges.peopleIn(membership);
    final names = [
      for (final person in people)
        person.uid == challenges.me.uid ? 'You' : person.username,
    ];
    final unknown = membership.participantUids.length - people.length;
    return _CircleCard(
      onTap: () => _openChallengeDetail(context, membership, challenges),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _IconTile(
                icon: visual.icon,
                color: visual.color,
                background: visual.tint,
                size: 44,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      membership.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      waiting
                          ? 'Waiting for friends to join'
                          : _daysLeftLabel(membership),
                      style: TextStyle(color: context.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 12 : 14),
          Text.rich(
            TextSpan(
              text: _numberFormat.format(membership.progress),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              children: [
                TextSpan(
                  text: ' / ${_goalLabel(membership)}',
                  style: TextStyle(
                    color: context.muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _ProgressBar(
            value: membership.goal <= 0
                ? 0
                : membership.progress / membership.goal,
            color: membership.type == 'scan_count' ? _ringCalories : _brand,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _AvatarStack(people: people, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  [...names, if (unknown > 0) '$unknown more'].join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FinishedChallengeRow extends StatelessWidget {
  const _FinishedChallengeRow({required this.membership});

  final CircleChallengeMembership membership;

  @override
  Widget build(BuildContext context) {
    final completed = membership.status == 'completed';
    final palette = context.circle;
    final end = membership.endAt ?? membership.createdAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.vivordoColors.cardMuted,
              border: Border.all(
                color: completed
                    ? const Color(0xFFD9A92A)
                    : context.vivordoColors.border,
                width: 3,
              ),
            ),
            child: Icon(
              completed
                  ? Icons.emoji_events_rounded
                  : _challengeVisual(context, membership.type).icon,
              size: 19,
              color: completed ? palette.gold : context.muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  membership.title,
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
                  '${completed ? 'Completed' : 'Ended at ${_progressLabel(membership, membership.progress)}'} · ${DateFormat.MMMd().format(end)}',
                  style: TextStyle(color: context.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (completed)
            _Pill(
              label: 'Medal',
              color: palette.gold,
              background: palette.goldTint,
            ),
        ],
      ),
    );
  }
}

class _ChallengeDetailPage extends StatefulWidget {
  const _ChallengeDetailPage({
    required this.membership,
    required this.challenges,
  });

  final CircleChallengeMembership membership;
  final _ChallengeData challenges;

  @override
  State<_ChallengeDetailPage> createState() => _ChallengeDetailPageState();
}

class _ChallengeDetailPageState extends State<_ChallengeDetailPage> {
  late Future<CircleChallengeDetails> _details = _load();
  late final Stream<List<CircleChallengeComment>> _comments =
      CircleChallengeService.watchComments(membership.challengeId);
  final _commentController = TextEditingController();
  var _posting = false;

  CircleChallengeMembership get membership => widget.membership;
  _ChallengeData get challenges => widget.challenges;

  Future<CircleChallengeDetails> _load() =>
      CircleChallengeService.loadDetails(membership.challengeId);

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final canCancel =
        membership.creatorUid == challenges.me.uid &&
        (membership.isOngoing || membership.isInvite);
    return Scaffold(
      backgroundColor: colors.page,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
              child: Row(
                children: [
                  const _BackButton(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      membership.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (canCancel)
                    _IconCircleButton(
                      icon: Icons.more_horiz_rounded,
                      tooltip: 'Challenge options',
                      onTap: _showOptions,
                    )
                  else
                    const SizedBox(width: 44),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<CircleChallengeDetails>(
                future: _details,
                builder: (context, snapshot) {
                  final details = snapshot.data;
                  final participants = [...?details?.participants]
                    ..sort((a, b) => b.progress.compareTo(a.progress));
                  return RefreshIndicator(
                    color: _brand,
                    onRefresh: () async {
                      setState(() => _details = _load());
                      await _details;
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                      children: [
                        _buildHero(context, participants),
                        if (membership.message.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _CreatorNoteCard(
                            membership: membership,
                            creator: _personFor(membership.creatorUid),
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const _Loading()
                        else if (details == null)
                          _EmptyState(
                            icon: Icons.cloud_off_rounded,
                            title: 'Could not load challenge details',
                            detail: 'Tap to try again.',
                            onTap: () => setState(() => _details = _load()),
                          )
                        else ...[
                          _buildStandings(context, participants),
                          const SizedBox(height: 14),
                          _buildRecentProgress(context, details, participants),
                        ],
                        const SizedBox(height: 14),
                        // Keyed: the rows above change count while
                        // details load, and the comments stream only
                        // allows one listener.
                        KeyedSubtree(
                          key: const ValueKey('comments'),
                          child: _buildComments(context, participants),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                child: _CommentComposer(
                  controller: _commentController,
                  sending: _posting,
                  onSend: _postComment,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(
    BuildContext context,
    List<CircleChallengeParticipant> participants,
  ) {
    final colors = context.vivordoColors;
    final me = participants
        .where((participant) => participant.uid == challenges.me.uid)
        .firstOrNull;
    final progress = me?.progress ?? membership.progress;
    final leading =
        participants.length > 1 &&
        participants.first.uid == challenges.me.uid &&
        participants.first.progress > 0;
    final end =
        membership.endAt ??
        (membership.startAt ?? membership.createdAt).add(
          Duration(days: membership.durationDays),
        );
    final creatorLabel = membership.creatorUid == challenges.me.uid
        ? 'You created this'
        : 'Created by ${membership.creatorName}';
    return _CircleCard(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Column(
        children: [
          SizedBox.square(
            dimension: 148,
            child: CustomPaint(
              painter: _RingPainter(
                progress: membership.goal <= 0 ? 0 : progress / membership.goal,
                color: _brand,
                track: colors.cardMuted,
                strokeWidth: 14,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: FittedBox(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_numberFormat.format(progress)}/${_numberFormat.format(membership.goal)}',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          membership.unit,
                          style: TextStyle(color: context.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Complete ${_goalLabel(membership)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (membership.status == 'waiting')
                const _Pill(label: 'Waiting for friends'),
              if (membership.status == 'completed')
                _Pill(
                  label: 'Completed',
                  color: context.circle.success,
                  background: context.circle.successTint,
                ),
              if (leading) const _Pill(label: "You're leading"),
              _Pill(
                label: creatorLabel,
                color: colors.textPrimary,
                background: colors.cardMuted,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _InfoCell(
                value: membership.isOngoing
                    ? '${_daysLeft(membership)}'
                    : '${membership.durationDays}',
                label: membership.isOngoing ? 'days left' : 'days',
              ),
              const SizedBox(width: 8),
              _InfoCell(value: DateFormat.MMMd().format(end), label: 'ends'),
              const SizedBox(width: 8),
              _InfoCell(
                value: '${membership.participantUids.length}',
                label: 'people',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStandings(
    BuildContext context,
    List<CircleChallengeParticipant> participants,
  ) => _CircleCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Standings'),
        for (var index = 0; index < participants.length; index++) ...[
          const SizedBox(height: 14),
          _StandingRow(
            rank: index + 1,
            participant: participants[index],
            person: _personFor(participants[index].uid),
            goal: membership.goal,
            isMe: participants[index].uid == challenges.me.uid,
            leading:
                index == 0 &&
                participants.length > 1 &&
                participants[index].progress > 0,
          ),
        ],
      ],
    ),
  );

  Widget _buildRecentProgress(
    BuildContext context,
    CircleChallengeDetails details,
    List<CircleChallengeParticipant> participants,
  ) {
    final contributions = details.contributions.take(5).toList();
    return _CircleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader('Recent progress'),
          const SizedBox(height: 6),
          if (contributions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Completed activities will appear here.',
                style: TextStyle(color: context.muted, fontSize: 14),
              ),
            )
          else
            for (final contribution in contributions)
              _ContributionRow(
                contribution: contribution,
                name: _nameFor(contribution.uid, participants),
                person: _personFor(contribution.uid),
              ),
        ],
      ),
    );
  }

  Widget _buildComments(
    BuildContext context,
    List<CircleChallengeParticipant> participants,
  ) => _CircleCard(
    child: StreamBuilder<List<CircleChallengeComment>>(
      stream: _comments,
      builder: (context, snapshot) {
        final comments = snapshot.data ?? const <CircleChallengeComment>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('Comments · ${comments.length}'),
            const SizedBox(height: 12),
            if (snapshot.hasError)
              Text(
                'Comments could not be loaded.',
                style: TextStyle(color: context.muted),
              )
            else if (!snapshot.hasData)
              const _Loading(height: 60)
            else if (comments.isEmpty)
              Text(
                'No comments yet. Start the conversation.',
                style: TextStyle(color: context.muted, fontSize: 14),
              )
            else
              for (final comment in comments)
                _CommentRow(
                  name: _nameFor(comment.authorUid, participants),
                  seed: comment.authorUid,
                  avatarName: _personFor(comment.authorUid)?.username,
                  photoUrl: _personFor(comment.authorUid)?.photoUrl,
                  text: comment.text,
                  time: _commentTime(comment.createdAt),
                  onDelete: comment.authorUid == challenges.me.uid
                      ? () => _deleteComment(comment)
                      : null,
                ),
          ],
        );
      },
    ),
  );

  CircleProfile? _personFor(String uid) =>
      uid == challenges.me.uid ? challenges.me : challenges.friendsById[uid];

  String _nameFor(String uid, List<CircleChallengeParticipant> participants) {
    if (uid == challenges.me.uid) return 'You';
    return _personFor(uid)?.username ??
        participants
            .where((participant) => participant.uid == uid)
            .firstOrNull
            ?.username ??
        'Circle member';
  }

  Future<void> _showOptions() async {
    final action = await showAppleActionSheet<String>(
      context,
      message: 'Ends it for everyone who joined.',
      actions: const [
        AppleSheetAction('Cancel challenge', 'cancel', destructive: true),
      ],
    );
    if (action != 'cancel' || !mounted) return;
    final confirmed = await confirmAction(
      context,
      title: 'Cancel ${membership.title}?',
      message:
          "Everyone in this challenge will see it as cancelled. This can't be undone.",
      cancelLabel: 'Keep it',
      confirmLabel: 'Cancel challenge',
    );
    if (!confirmed || !mounted) return;
    try {
      await CircleChallengeService.cancel(membership.challengeId);
      if (!mounted) return;
      _showSnack(context, 'Challenge cancelled.');
      Navigator.of(context).pop();
    } catch (error) {
      debugPrint('Cancel challenge failed: $error');
      if (mounted) {
        _showSnack(
          context,
          "Couldn't cancel the challenge. Try again.",
          kind: ToastKind.error,
        );
      }
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      await CircleChallengeService.addComment(
        challengeId: membership.challengeId,
        text: text,
      );
      _commentController.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (error) {
      debugPrint('Post challenge comment failed: $error');
      if (mounted) {
        _showSnack(
          context,
          "Couldn't post your comment. Try again.",
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _deleteComment(CircleChallengeComment comment) async {
    try {
      await CircleChallengeService.deleteComment(
        challengeId: membership.challengeId,
        commentId: comment.id,
      );
    } catch (error) {
      debugPrint('Delete challenge comment failed: $error');
      if (mounted) {
        _showSnack(
          context,
          "Couldn't delete the comment. Try again.",
          kind: ToastKind.error,
        );
      }
    }
  }
}

String _commentTime(DateTime? createdAt) {
  if (createdAt == null) return 'Just now';
  final difference = DateTime.now().difference(createdAt);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return DateFormat.MMMd().format(createdAt);
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: context.vivordoColors.cardMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.vivordoColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label, style: TextStyle(color: context.muted, fontSize: 12)),
        ],
      ),
    ),
  );
}

class _CreatorNoteCard extends StatelessWidget {
  const _CreatorNoteCard({required this.membership, required this.creator});

  final CircleChallengeMembership membership;
  final CircleProfile? creator;

  @override
  Widget build(BuildContext context) => _CircleCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        creator == null
            ? _InitialsAvatar(
                name: membership.creatorName,
                seed: membership.creatorUid,
                size: 36,
              )
            : _ProfileAvatar(profile: creator!, radius: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${membership.creatorName} · note from the creator',
                style: TextStyle(
                  color: context.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                membership.message,
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.participant,
    required this.person,
    required this.goal,
    required this.isMe,
    required this.leading,
  });

  final int rank;
  final CircleChallengeParticipant participant;
  final CircleProfile? person;
  final int goal;
  final bool isMe;
  final bool leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '$rank',
            style: TextStyle(
              color: rank == 1 ? context.circle.accent : context.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        person == null
            ? _InitialsAvatar(
                name: participant.username,
                seed: participant.uid,
                size: 36,
              )
            : _ProfileAvatar(profile: person!, radius: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      isMe ? 'You' : participant.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (leading) ...[
                    const SizedBox(width: 6),
                    const _Pill(label: 'Leading'),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              _ProgressBar(
                value: goal <= 0 ? 0 : participant.progress / goal,
                color: isMe ? _brand : context.muted.withValues(alpha: .55),
                height: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${_numberFormat.format(participant.progress)}/${_numberFormat.format(goal)}',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ContributionRow extends StatelessWidget {
  const _ContributionRow({
    required this.contribution,
    required this.name,
    required this.person,
  });

  final CircleChallengeContribution contribution;
  final String name;
  final CircleProfile? person;

  @override
  Widget build(BuildContext context) {
    final action = switch (contribution.sourceType) {
      'workout' => 'completed a workout',
      'activity' => 'completed an activity',
      'journal_day' => 'added a journal entry',
      'steps_day' => 'added ${_numberFormat.format(contribution.value)} steps',
      'scans_day' =>
        'completed ${contribution.value} heart scan${contribution.value == 1 ? '' : 's'}',
      _ => 'made progress',
    };
    final occurredAt = contribution.occurredAt;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          person == null
              ? _InitialsAvatar(name: name, seed: contribution.uid, size: 32)
              : _ProfileAvatar(profile: person!, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name $action',
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (occurredAt != null)
                  Text(
                    _relativeActivityTime(occurredAt),
                    style: TextStyle(color: context.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          _Pill(
            label: '+${_numberFormat.format(contribution.value)}',
            color: context.circle.success,
            background: context.circle.successTint,
          ),
        ],
      ),
    );
  }
}
