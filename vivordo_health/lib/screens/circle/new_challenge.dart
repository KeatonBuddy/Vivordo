part of '../circle_screen.dart';

/// The challenge types `createChallenge` accepts. Goal ranges sit inside the
/// backend's limits (functions/challenges.js CHALLENGE_TYPES).
enum _ChallengeType {
  workouts(
    backendType: 'workout_count',
    label: 'Workouts',
    presetTitle: 'Workout Streak',
    unit: 'workouts',
    allowsTarget: true,
    minimum: 1,
    maximum: 30,
    step: 1,
    initialGoal: 5,
  ),
  steps(
    backendType: 'step_total',
    label: 'Steps',
    presetTitle: 'Step Sprint',
    unit: 'steps',
    minimum: 5000,
    maximum: 300000,
    step: 5000,
    initialGoal: 30000,
  ),
  scans(
    backendType: 'scan_count',
    label: 'Heart scans',
    presetTitle: 'Pulse Check',
    unit: 'scans',
    minimum: 1,
    maximum: 30,
    step: 1,
    initialGoal: 5,
  ),
  activities(
    backendType: 'activity_count',
    label: 'Activities',
    presetTitle: 'Activity Challenge',
    unit: 'sessions',
    allowsTarget: true,
    minimum: 1,
    maximum: 30,
    step: 1,
    initialGoal: 5,
  ),
  journal(
    backendType: 'journal_count',
    label: 'Journal',
    presetTitle: 'Journal Streak',
    unit: 'days',
    minimum: 1,
    maximum: 30,
    step: 1,
    initialGoal: 7,
  );

  const _ChallengeType({
    required this.backendType,
    required this.label,
    required this.presetTitle,
    required this.unit,
    required this.minimum,
    required this.maximum,
    required this.step,
    required this.initialGoal,
    this.allowsTarget = false,
  });

  final String backendType;
  final String label;
  final String presetTitle;
  final String unit;
  final int minimum;
  final int maximum;
  final int step;
  final int initialGoal;
  final bool allowsTarget;

  static const presets = [workouts, steps, scans];

  // Every backend unit is a plain plural ("workouts", "days"), so the
  // singular just drops the final s.
  String goalLabel(int goal) =>
      '${_numberFormat.format(goal)} ${goal == 1 ? unit.substring(0, unit.length - 1) : unit}';
}

const _maxInvitees = 7;
const _durationChoices = [3, 7, 14, 30];

class _ChallengeDraft {
  const _ChallengeDraft({
    required this.type,
    required this.targetName,
    required this.goal,
    required this.durationDays,
    required this.friends,
    required this.message,
  });

  final _ChallengeType type;
  final String? targetName;
  final int goal;
  final int durationDays;
  final List<CircleProfile> friends;
  final String message;

  String get title => targetName ?? type.presetTitle;
}

/// Opens the new-challenge sheet and sends whatever it returns.
Future<void> _startNewChallenge(
  BuildContext context,
  CircleProfile me, {
  _ChallengeType? type,
  CircleProfile? friend,
}) async {
  final draft = await showModalBottomSheet<_ChallengeDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.circle.scrim,
    builder: (_) => _NewChallengeSheet(
      me: me,
      initialType: type ?? _ChallengeType.workouts,
      initialFriend: friend,
    ),
  );
  if (draft == null || !context.mounted) return;
  final recipients = draft.friends.length == 1
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
      type: draft.type.backendType,
      goal: draft.goal,
      durationDays: draft.durationDays,
      participantUids: [for (final friend in draft.friends) friend.uid],
      targetName: draft.targetName,
      message: draft.message,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('${draft.title} sent to $recipients.')),
      );
  } catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Could not send challenge: $error')),
      );
  }
}

class _NewChallengeSheet extends StatefulWidget {
  const _NewChallengeSheet({
    required this.me,
    required this.initialType,
    this.initialFriend,
  });

  final CircleProfile me;
  final _ChallengeType initialType;
  final CircleProfile? initialFriend;

  @override
  State<_NewChallengeSheet> createState() => _NewChallengeSheetState();
}

class _NewChallengeSheetState extends State<_NewChallengeSheet> {
  late var _type = widget.initialType;
  late var _goal = widget.initialType.initialGoal;
  var _durationDays = 7;
  String? _targetName;
  late final Set<String> _selected = {?widget.initialFriend?.uid};
  final _messageController = TextEditingController();
  late final Stream<List<CircleProfile>> _friends =
      CircleProfileService.watchFriends();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _selectType(_ChallengeType type) => setState(() {
    _type = type;
    _goal = type.initialGoal;
    _targetName = null;
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return DraggableScrollableSheet(
      initialChildSize: .94,
      minChildSize: .6,
      maxChildSize: .97,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: colors.page,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: StreamBuilder<List<CircleProfile>>(
          stream: _friends,
          builder: (context, snapshot) {
            final friends = snapshot.data ?? const <CircleProfile>[];
            final chosen = friends
                .where((friend) => _selected.contains(friend.uid))
                .toList(growable: false);
            return ListView(
              controller: scrollController,
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                18,
                10,
                18,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              children: [
                const _SheetGrabber(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _IconCircleButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Close',
                      onTap: () => Navigator.maybePop(context),
                    ),
                    Expanded(
                      child: Text(
                        'New challenge',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
                const SizedBox(height: 22),
                const _SectionHeader('Type'),
                const SizedBox(height: 12),
                _buildTypes(context),
                if (_type.allowsTarget) ...[
                  const SizedBox(height: 10),
                  _TargetPicker(
                    type: _type,
                    value: _targetName,
                    onChanged: (value) => setState(() => _targetName = value),
                  ),
                ],
                const SizedBox(height: 22),
                _buildGoal(context),
                const SizedBox(height: 22),
                const _SectionHeader('Duration'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final days in _durationChoices)
                      _FilterChip(
                        label: '$days days',
                        selected: _durationDays == days,
                        onTap: () => setState(() => _durationDays = days),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                _SectionHeader(
                  'Invite',
                  trailing: Text(
                    '${_selected.length} of $_maxInvitees',
                    style: TextStyle(color: context.muted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
                _buildFriends(context, snapshot, friends),
                const SizedBox(height: 22),
                const _SectionHeader('Message (optional)'),
                const SizedBox(height: 12),
                _MessageField(controller: _messageController),
                const SizedBox(height: 14),
                _CircleCard(
                  color: context.circle.accentTint,
                  borderColor: Colors.transparent,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 20,
                        color: context.circle.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _summary(chosen),
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: chosen.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _ChallengeDraft(
                            type: _type,
                            targetName: _targetName,
                            goal: _goal,
                            durationDays: _durationDays,
                            friends: List.unmodifiable(chosen),
                            message: _messageController.text.trim(),
                          ),
                        ),
                  icon: const Icon(Icons.send_rounded, size: 19),
                  label: const Text('Send challenge'),
                  style: _primaryButtonStyle(height: 54),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTypes(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final type in _ChallengeType.values)
            SizedBox(
              width: width,
              child: _TypeTile(
                type: type,
                selected: type == _type,
                onTap: () => _selectType(type),
              ),
            ),
        ],
      );
    },
  );

  Widget _buildGoal(BuildContext context) {
    final divisions = (_type.maximum - _type.minimum) ~/ _type.step;
    return _CircleCard(
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: _SectionHeader('Goal')),
              Text.rich(
                TextSpan(
                  text: _numberFormat.format(_goal),
                  style: TextStyle(
                    color: context.vivordoColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                  children: [
                    TextSpan(
                      text: ' ${_type.unit}',
                      style: TextStyle(
                        color: context.muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _brand,
              inactiveTrackColor: context.vivordoColors.cardMuted,
              thumbColor: _brand,
              overlayColor: _brand.withValues(alpha: .14),
              trackHeight: 5,
            ),
            child: Slider(
              value: _goal.toDouble(),
              min: _type.minimum.toDouble(),
              max: _type.maximum.toDouble(),
              divisions: divisions,
              semanticFormatterCallback: (_) => _type.goalLabel(_goal),
              onChanged: (value) => setState(() {
                final stepped =
                    _type.minimum +
                    ((value - _type.minimum) / _type.step).round() * _type.step;
                _goal = stepped.clamp(_type.minimum, _type.maximum);
              }),
            ),
          ),
          Row(
            children: [
              Text(
                _type.goalLabel(_type.minimum),
                style: TextStyle(color: context.muted, fontSize: 12),
              ),
              const Spacer(),
              Text(
                _type.goalLabel(_type.maximum),
                style: TextStyle(color: context.muted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFriends(
    BuildContext context,
    AsyncSnapshot<List<CircleProfile>> snapshot,
    List<CircleProfile> friends,
  ) {
    if (!snapshot.hasData &&
        snapshot.connectionState == ConnectionState.waiting) {
      return const _Loading(height: 96);
    }
    if (friends.isEmpty) {
      return _EmptyState(
        icon: Icons.person_add_alt_1_rounded,
        title: 'Add a friend first',
        detail:
            'Challenges need at least one Circle friend. Tap to find people.',
        onTap: () {
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.push(
            MaterialPageRoute<void>(builder: (_) => _PeoplePage(me: widget.me)),
          );
        },
      );
    }
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: friends.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final friend = friends[index];
          final selected = _selected.contains(friend.uid);
          return _FriendChoice(
            profile: friend,
            selected: selected,
            onTap: () => setState(() {
              if (selected) {
                _selected.remove(friend.uid);
              } else if (_selected.length < _maxInvitees) {
                _selected.add(friend.uid);
              } else {
                _showSnack(
                  context,
                  'You can invite up to $_maxInvitees friends.',
                );
              }
            }),
          );
        },
      ),
    );
  }

  String _summary(List<CircleProfile> chosen) {
    final subject = _targetName == null
        ? _type.goalLabel(_goal)
        : '${_type.goalLabel(_goal)} of $_targetName';
    final invitees = switch (chosen.length) {
      0 => 'Pick at least one friend to invite.',
      1 => '${chosen.first.username} gets an invite',
      2 => '${chosen.first.username} and ${chosen.last.username} get an invite',
      _ =>
        '${chosen.first.username} and ${chosen.length - 1} others get an invite',
    };
    return chosen.isEmpty
        ? 'Complete $subject in $_durationDays days. $invitees'
        : 'Complete $subject in $_durationDays days. $invitees and it starts once someone accepts.';
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final _ChallengeType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final visual = _challengeVisual(context, type.backendType);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? context.circle.accentTint : colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? _brand : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 60,
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
                      type.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.type,
    required this.value,
    required this.onChanged,
  });

  final _ChallengeType type;
  final String? value;
  final ValueChanged<String?> onChanged;

  bool get _activity => type == _ChallengeType.activities;

  List<WorkoutExerciseCatalogItem> get _exercises => _activity
      ? workoutExerciseCatalog
            .where(
              (exercise) =>
                  exercise.category == 'Cardio' ||
                  exercise.category == 'Sports',
            )
            .toList(growable: false)
      : workoutExerciseCatalog;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final anyLabel = _activity ? 'Any activity' : 'Any workout';
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final selection =
              await showModalBottomSheet<_SpecificExerciseSelection>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _SpecificExerciseSearchSheet(
                  exercises: _exercises,
                  selectedValue: value,
                  anyLabel: anyLabel,
                  subject: _activity ? 'activity' : 'workout',
                ),
              );
          if (selection != null) onChanged(selection.value);
        },
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Text(
                  'Counts',
                  style: TextStyle(color: context.muted, fontSize: 14),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value ?? anyLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down_rounded, color: context.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendChoice extends StatelessWidget {
  const _FriendChoice({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final CircleProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: profile.username,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? _brand : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: _ProfileAvatar(profile: profile, radius: 25),
                ),
                if (selected)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _brandStrong,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.vivordoColors.page,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              profile.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? context.vivordoColors.textPrimary
                    : context.muted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MessageField extends StatelessWidget {
  const _MessageField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return TextField(
      controller: controller,
      minLines: 2,
      maxLines: 4,
      maxLength: 200,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyle(color: colors.textPrimary, fontSize: 15, height: 1.35),
      decoration: InputDecoration(
        hintText: 'Add a note for your friends',
        hintStyle: TextStyle(color: context.muted),
        counterStyle: TextStyle(color: context.muted, fontSize: 11),
        filled: true,
        fillColor: colors.input,
        contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _brand, width: 1.5),
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
    required this.subject,
  });

  final List<WorkoutExerciseCatalogItem> exercises;
  final String? selectedValue;
  final String anyLabel;
  final String subject;

  @override
  State<_SpecificExerciseSearchSheet> createState() =>
      _SpecificExerciseSearchSheetState();
}

class _SpecificExerciseSearchSheetState
    extends State<_SpecificExerciseSearchSheet> {
  final _searchController = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final query = _query.trim().toLowerCase();
    final exercises = query.isEmpty
        ? widget.exercises
        : widget.exercises
              .where(
                (exercise) =>
                    exercise.name.toLowerCase().contains(query) ||
                    exercise.category.toLowerCase().contains(query),
              )
              .toList(growable: false);
    final showAny = query.isEmpty;
    return FractionallySizedBox(
      heightFactor: .82,
      child: Material(
        color: colors.page,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            const _SheetGrabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose ${widget.subject}',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _IconCircleButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onTap: () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _SearchField(
                controller: _searchController,
                hint: 'Search ${widget.subject}s',
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                children: [
                  if (showAny)
                    _ExerciseResultTile(
                      title: widget.anyLabel,
                      subtitle: 'Count any matching session',
                      icon: widget.subject == 'activity'
                          ? Icons.directions_run_rounded
                          : Icons.fitness_center_rounded,
                      color: _brand,
                      selected: widget.selectedValue == null,
                      onTap: () => Navigator.pop(
                        context,
                        const _SpecificExerciseSelection(null),
                      ),
                    ),
                  if (exercises.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'No ${widget.subject}s found',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.muted, fontSize: 15),
                      ),
                    ),
                  for (final exercise in exercises)
                    Builder(
                      builder: (context) {
                        final visual = workoutActivityVisual(
                          exercise.name,
                          category: exercise.category,
                        );
                        return _ExerciseResultTile(
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseResultTile extends StatelessWidget {
  const _ExerciseResultTile({
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
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? _brand : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                _IconTile(
                  icon: icon,
                  color: Colors.white,
                  background: color,
                  size: 40,
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
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: context.circle.accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: TextStyle(color: colors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.muted),
        prefixIcon: Icon(Icons.search_rounded, color: context.muted),
        filled: true,
        fillColor: colors.input,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _brand, width: 1.5),
        ),
      ),
    );
  }
}
