import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/meeting_patterns_service.dart';
import '../src/services/weekly_review_service.dart';
import '../src/utils/weekly_review.dart';
import '../widgets/apple_ui.dart';
import '../widgets/contextual_insight_bar.dart';

const _teal = Color(0xFF1D9E75);
const _amber = Color(0xFFEF9F27);
const _coral = Color(0xFFE24B4A);
const _purple = Color(0xFF7F77DD);

/// "Anything else going on this week?" options; "Something else…" opens a
/// short note instead.
const weeklyReviewContextOptions = [
  'Busy at home',
  'Not feeling well',
  'Travel',
  'Big deadline',
];

const _noteLimit = 80;

/// A drained/helped line's name: meetings are stored by series and named
/// from the calendar, so no event title is saved.
String reviewLineName(ReviewLine line) => line.seriesKey == null
    ? line.title
    : MeetingPatternsService.names[line.seriesKey] ?? 'A recurring meeting';

/// A line's detail with its events named, from the calendar
/// (MeetingPatternsService.loadWeekNames).
String reviewLineDetailNamed(ReviewLine line) => reviewLineDetail(
  line,
  (e) =>
      MeetingPatternsService.eventNames[e.key] ??
      MeetingPatternsService.names[e.series],
);

IconData _icon(String kind) => switch (kind) {
  'sick' => Icons.sick_outlined,
  'travel' => Icons.flight_rounded,
  'heavyDay' => Icons.trending_up_rounded,
  'bigDay' => Icons.bolt_rounded,
  'meeting' => Icons.groups_outlined,
  'lateNight' => Icons.nightlight_outlined,
  'lieIn' => Icons.wb_twilight_outlined,
  'afterHours' => Icons.schedule_rounded,
  'training' => Icons.fitness_center_rounded,
  'priority' => Icons.flag_outlined,
  'sleep' => Icons.bedtime_outlined,
  'fixes' => Icons.auto_fix_high_rounded,
  'calm' => Icons.spa_outlined,
  _ => Icons.circle_outlined,
};

Color _nextColor(String label) => switch (label) {
  'Light' => _teal,
  'More than your usual' => _coral,
  _ => _purple,
};

/// Opens the review full screen, from My Day's card or Journal.
Future<void> openWeeklyReview(BuildContext context, WeeklyReview review) {
  // Looked up here: the route below sits outside the tabs.
  final ask = vivordoAiAsker(context);
  unawaited(WeeklyReviewService.markIntroSeen());
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => WeeklyReviewScreen(review: review, ask: ask),
    ),
  );
}

/// My Day on Sundays: the week's headline, a few facts, and the way in.
/// The first one also explains itself and offers the Sunday reminder.
class WeeklyReviewCard extends StatelessWidget {
  const WeeklyReviewCard({super.key, required this.state});

  final WeeklyReviewCardState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final review = state.review;
    final secondary = TextStyle(
      fontSize: 13,
      height: 1.45,
      color: colors.textSecondary,
    );
    return Material(
      color: Color.alphaBlend(_purple.withValues(alpha: .10), colors.card),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _purple.withValues(alpha: .40)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openWeeklyReview(context, review),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your week · ${review.range}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _purple,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hide for today',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        unawaited(WeeklyReviewService.hideForToday()),
                    icon: Icon(
                      CupertinoIcons.xmark,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.intro) ...[
                      Text(
                        'New: a look back at your week, every Sunday. What '
                        'drained you, what helped, and what next week looks '
                        'like.',
                        style: secondary,
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      review.headline,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(review.why, style: secondary),
                    const SizedBox(height: 10),
                    _Chips(review.chips),
                    if (state.intro)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: MergeSemantics(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Remind me on Sundays',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                              AppSwitch(
                                value: state.reminder,
                                onChanged: (on) => unawaited(
                                  WeeklyReviewService.setReminder(on),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => openWeeklyReview(context, review),
                        style: TextButton.styleFrom(
                          foregroundColor: _purple,
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('See your week ›'),
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
}

class _Chips extends StatelessWidget {
  const _Chips(this.chips);

  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final chip in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              chip,
              style: TextStyle(fontSize: 12, color: colors.textPrimary),
            ),
          ),
      ],
    );
  }
}

/// The review: the week at a glance, what drained and helped, next week,
/// and "anything else going on".
class WeeklyReviewScreen extends StatelessWidget {
  const WeeklyReviewScreen({super.key, required this.review, this.ask});

  final WeeklyReview review;

  /// Opens Vivordo AI; null where there's no chat.
  final void Function(ScreenInsight insight)? ask;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final secondary = TextStyle(
      fontSize: 14,
      height: 1.45,
      color: colors.textSecondary,
    );
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.textSecondary,
        ),
      ),
    );
    Widget card(List<Widget> children) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
    Widget lines(List<ReviewLine> lines, Color color) => card([
      for (final (i, line) in lines.indexed)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon(line.kind), size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reviewLineName(line),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (line.events.isEmpty)
                      Text(line.detail, style: secondary.copyWith(fontSize: 13))
                    else
                      FutureBuilder(
                        future: MeetingPatternsService.loadWeekNames(
                          DateTime.parse(review.weekStart),
                        ),
                        builder: (context, _) => Text(
                          reviewLineDetailNamed(line),
                          style: secondary.copyWith(fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ]);
    final ask = this.ask;
    return Scaffold(
      backgroundColor: colors.page,
      appBar: AppBar(
        backgroundColor: colors.page,
        surfaceTintColor: Colors.transparent,
        title: Text('Week of ${review.range}'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(
              review.headline,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(review.why, style: secondary),
            if (review.lastWeekNote case final note?) ...[
              const SizedBox(height: 8),
              Text(
                'Last week you mentioned: $note.',
                style: secondary.copyWith(fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            _Chips(review.chips),
            section('The week at a glance'),
            card([
              _EffortChart(review: review),
              for (final row in review.rows)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.label,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          row.value,
                          textAlign: TextAlign.right,
                          style: secondary.copyWith(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
            if (review.drained.isNotEmpty) ...[
              section('What drained you'),
              lines(review.drained, _coral),
            ],
            if (review.offDayNote case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(note, style: secondary.copyWith(fontSize: 12)),
              ),
            if (review.helped.isNotEmpty) ...[
              section('What helped'),
              lines(review.helped, _teal),
            ],
            if (review.burnout != null) ...[
              const SizedBox(height: 14),
              card([
                Text(
                  'The burnout check was at '
                  '${review.burnout == 'warning' ? 'Warning' : 'Watch'} '
                  'this week.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'An easier week ahead helps it settle. It\'s on My Day '
                  'while it lasts.',
                  style: secondary.copyWith(fontSize: 13),
                ),
              ]),
            ],
            if (review.nextWeek.isNotEmpty) ...[
              section('Next week'),
              card([
                if (review.nextHeadline case final headline?)
                  Text(
                    headline,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final d in review.nextWeek)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              d.day.substring(0, math.min(3, d.day.length)),
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: _nextColor(
                                  d.label,
                                ).withValues(alpha: .7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              d.label == 'More than your usual'
                                  ? 'Busy'
                                  : d.label == 'About usual'
                                  ? 'Usual'
                                  : d.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: _nextColor(d.label),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (review.suggestion case final suggestion?) ...[
                  const SizedBox(height: 14),
                  Text(
                    suggestion,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Busy is more than your usual Capacity: each day is priced '
                  'from your calendar and priorities, as My Day does.',
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ]),
            ],
            if (ask != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  ask(
                    ScreenInsight(
                      'weekly_review',
                      'Weekly review',
                      '${review.headline}. ${review.why}',
                      context: review.chatContext(
                        reviewLineName,
                        detail: reviewLineDetailNamed,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('Plan next week with Vivordo AI'),
                style: FilledButton.styleFrom(
                  backgroundColor: _purple.withValues(alpha: .14),
                  foregroundColor: _purple,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
            section('Anything else going on this week?'),
            _ContextPicker(review: review),
            const SizedBox(height: 24),
            Text(
              'Body signals here are wellness signals, not a diagnosis.',
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Each day's Effort as a bar against the usual Capacity line: heavy days
/// in coral, days unwell in amber.
class _EffortChart extends StatelessWidget {
  const _EffortChart({required this.review});

  final WeeklyReview review;

  static const _height = 80.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final usual = review.usualCapacity;
    final top =
        [
          for (final d in review.days) d.effort ?? 0,
          ?usual,
          50.0,
        ].reduce(math.max) *
        1.1;
    return Column(
      children: [
        SizedBox(
          height: _height,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in review.days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          height: math.max(3, _height * (d.effort ?? 0) / top),
                          decoration: BoxDecoration(
                            color: d.sick
                                ? _amber.withValues(alpha: .7)
                                : d.heavy
                                ? _coral.withValues(alpha: .75)
                                : _purple.withValues(alpha: .55),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                              bottom: Radius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (usual != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _height * usual / top,
                  child: Container(height: 1.5, color: _teal),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final d in review.days)
              Expanded(
                child: Text(
                  'MTWTFSS'[DateTime.parse(d.day).weekday - 1],
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Bars: Effort · line: your usual Capacity · coral: heavy · '
          'amber: unwell',
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// "Anything else going on": chips and a short note, saved with the review
/// for Vivordo AI and mentioned in next week's.
class _ContextPicker extends StatefulWidget {
  const _ContextPicker({required this.review});

  final WeeklyReview review;

  @override
  State<_ContextPicker> createState() => _ContextPickerState();
}

class _ContextPickerState extends State<_ContextPicker> {
  late final Set<String> _chosen = {...widget.review.context};
  late final _note = TextEditingController(text: widget.review.note ?? '');
  late bool _other = widget.review.note?.isNotEmpty ?? false;
  late List<String> _savedContext = widget.review.context;
  late String _savedNote = widget.review.note ?? '';
  bool _saving = false;

  bool get _dirty =>
      !_sameSet(_chosen, _savedContext.toSet()) ||
      (_other ? _note.text.trim() : '') != _savedNote;

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final context = [
      for (final o in weeklyReviewContextOptions)
        if (_chosen.contains(o)) o,
    ];
    final note = _other ? _note.text.trim() : '';
    try {
      await WeeklyReviewService.saveContext(
        widget.review.weekStart,
        context,
        note,
      );
      _savedContext = context;
      _savedNote = note;
      if (mounted) FocusScope.of(this.context).unfocus();
    } catch (_) {
      if (mounted) {
        showToast(
          this.context,
          'Couldn’t save that. Try again.',
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    Widget chip(String label, bool selected, VoidCallback onTap) => FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(onTap),
      selectedColor: _purple.withValues(alpha: .18),
      backgroundColor: colors.card,
      side: BorderSide(color: selected ? _purple : colors.border),
      labelStyle: TextStyle(
        fontSize: 13,
        color: selected ? _purple : colors.textPrimary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vivordo AI keeps it in mind, and next week\'s review mentions it.',
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in weeklyReviewContextOptions)
              chip(
                option,
                _chosen.contains(option),
                () => _chosen.contains(option)
                    ? _chosen.remove(option)
                    : _chosen.add(option),
              ),
            chip('Something else…', _other, () => _other = !_other),
          ],
        ),
        if (_other) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            maxLength: _noteLimit,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            // The Save button is under the keyboard: Done saves too.
            onSubmitted: (_) {
              if (_dirty && !_saving) _save();
            },
            decoration: const InputDecoration(
              hintText: 'e.g. Moving apartments',
            ),
          ),
        ],
        if (_dirty) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: _purple),
              child: const Text('Save'),
            ),
          ),
        ],
      ],
    );
  }
}
