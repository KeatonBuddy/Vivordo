import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/day_key.dart';
import '../src/utils/training_load_view.dart';
import 'contextual_insight_bar.dart';

const _teal = Color(0xFF1D9E75);
const _amber = Color(0xFFEF9F27);
const _coral = Color(0xFFE24B4A);
const _purple = Color(0xFF7F77DD);

/// [_stateColor] for text, dark enough to read in light mode.
Color _stateTextColor(VivordoColors colors, String state) => switch (state) {
  'high' || 'strained' => colors.danger,
  'building' => colors.warning,
  'lighter' => colors.textSecondary,
  _ => colors.success,
};

Color _stateColor(String state) => switch (state) {
  'high' || 'strained' => _coral,
  'building' => _amber,
  'lighter' => _purple,
  _ => _teal,
};

/// The latest training load: it's calculated with Capacity each morning, so
/// look back a few days for a morning nothing synced.
Stream<TrainingLoadView?> watchTrainingLoad(DateTime day) =>
    watchTrainingLoadRecord(day).map((r) => r?.view);

/// The latest record in the last 3 days, read as a view, or while it's
/// still learning as the days until there's a usual week (null when that
/// isn't a matter of time, e.g. too little activity).
Stream<({TrainingLoadView? view, int? learningDaysToGo})?>
watchTrainingLoadRecord(DateTime day) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('scores_daily')
      .where(
        FieldPath.documentId,
        isGreaterThanOrEqualTo: localDayKey(
          DateTime(day.year, day.month, day.day - 3),
        ),
      )
      .where(FieldPath.documentId, isLessThanOrEqualTo: localDayKey(day))
      .snapshots()
      .map((snapshot) {
        for (final doc in snapshot.docs.reversed) {
          final raw = doc.data()['trainingLoad'];
          if (raw == null) continue;
          return (
            view: TrainingLoadView.fromMap(raw, doc.id),
            learningDaysToGo: raw is Map && raw['state'] == 'learning'
                ? (raw['daysToGo'] as num?)?.toInt()
                : null,
          );
        }
        return null;
      });
}

/// Opens Vivordo AI to plan an easier week; null where there's no chat.
VoidCallback? _planner(BuildContext context, TrainingLoadView view) {
  final ask = vivordoAiAsker(context);
  if (ask == null) return null;
  return () => ask(
    ScreenInsight(
      'training_load',
      'Training load',
      '${view.headline}. ${view.summary}',
      context: view.chatContext,
    ),
  );
}

/// This week against the usual one: headline, the 7 days, and the rows
/// behind the state. On Fitness, and in the details sheet.
class TrainingLoadCard extends StatelessWidget {
  const TrainingLoadCard({
    super.key,
    required this.view,
    this.onTap,
    this.daysLabel = 'Last 7 days',
  });

  final TrainingLoadView view;
  final VoidCallback? onTap;

  /// "Those 7 days" for an earlier week in the details sheet.
  final String daysLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final color = _stateColor(view.state);
    final secondary = TextStyle(fontSize: 13, color: colors.textSecondary);
    Widget row(String label, String value, {bool off = false}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: off ? secondary.copyWith(color: colors.danger) : secondary,
            ),
          ),
        ],
      ),
    );
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      view.headline,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      view.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _stateTextColor(colors, view.state),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _WeekChart(view: view),
              const SizedBox(height: 4),
              row(
                daysLabel,
                view.vsUsual,
                off: view.alert && view.percent >= 5,
              ),
              row('Hard days', '${view.hardDays} of 7'),
              for (final body in view.bodyRows)
                row(body.label, body.value, off: body.off),
              const SizedBox(height: 12),
              Text(
                '${view.measuredBy} · line: your average day over '
                '${view.usualSpan}',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 7 days as bars, hard days in coral, with the usual week's average
/// day as a line.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.view});

  final TrainingLoadView view;

  static const _height = 72.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final top =
        [
          ...view.days.map((d) => d.value),
          TrainingLoadView.hardDay,
          view.usualDay,
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
                  for (final d in view.days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          height: math.max(3, _height * d.value / top),
                          decoration: BoxDecoration(
                            color: d.value >= TrainingLoadView.hardDay
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
              Positioned(
                left: 0,
                right: 0,
                bottom: _height * view.usualDay / top,
                child: Container(height: 1.5, color: _teal),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final d in view.days)
              Expanded(
                child: Text(
                  'MTWTFSS'[DateTime.parse(d.day).weekday - 1],
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// My Day at High or Strained: what's going on, with a way to act.
class TrainingLoadAlert extends StatelessWidget {
  const TrainingLoadAlert({super.key, required this.view});

  final TrainingLoadView view;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final plan = _planner(context, view);
    TextButton button(String label, VoidCallback onPressed) => TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: _coral,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
    return Material(
      color: Color.alphaBlend(_coral.withValues(alpha: .10), colors.card),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _coral.withValues(alpha: .45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showTrainingLoadDetails(context, view),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Training load · ${view.label}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _coral,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'You\'ve trained a lot more than usual',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                view.summary,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (plan != null) button('Plan an easier week', plan),
                  const Spacer(),
                  button(
                    'Details ›',
                    () => showTrainingLoadDetails(context, view),
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

/// The card, how it works, and (at High or Strained) planning an easier
/// week with Vivordo AI.
Future<void> showTrainingLoadDetails(
  BuildContext context,
  TrainingLoadView view,
) {
  // Looked up here: the sheet below sits outside the tabs.
  final plan = view.alert ? _planner(context, view) : null;
  final colors = context.vivordoColors;
  final secondary = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: colors.textSecondary,
  );
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: colors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          // Clears the floating Vivordo AI button.
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Training load',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              _TrainingLoadWeeks(latest: view, secondary: secondary),
              if (view.alert) ...[
                const SizedBox(height: 14),
                Text(
                  'A lighter few days usually brings this back to steady.',
                  style: secondary,
                ),
              ],
              if (plan != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    plan();
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('Plan an easier week'),
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
              const SizedBox(height: 20),
              Text(
                'A wellness signal, not a diagnosis. If something hurts or '
                'feels wrong, rest and talk to a professional.',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The details sheet's week: [latest] first, then up to 11 weeks before it
/// (TrainingLoadView.weeks), changed by swiping the card, the arrows, or
/// picking from the dates. The alert and the easier-week plan below it
/// stay about the latest week.
class _TrainingLoadWeeks extends StatefulWidget {
  const _TrainingLoadWeeks({required this.latest, required this.secondary});

  final TrainingLoadView latest;
  final TextStyle secondary;

  @override
  State<_TrainingLoadWeeks> createState() => _TrainingLoadWeeksState();
}

class _TrainingLoadWeeksState extends State<_TrainingLoadWeeks> {
  late var _weeks = [widget.latest];

  /// Into _weeks; 0 is the latest.
  var _index = 0;

  /// The last move went to an earlier week, so the card slides right.
  var _older = true;

  /// Training load began at the oldest week (a learning record before it).
  var _startsHere = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final day = DateTime.parse(widget.latest.dayKey);
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scores_daily')
          .where(
            FieldPath.documentId,
            isGreaterThanOrEqualTo: localDayKey(
              DateTime(
                day.year,
                day.month,
                day.day - 7 * TrainingLoadView.historyWeeks - 3,
              ),
            ),
          )
          .where(FieldPath.documentId, isLessThan: widget.latest.dayKey)
          .get();
      final records = {
        for (final doc in snapshot.docs) doc.id: doc.data()['trainingLoad'],
      };
      final weeks = TrainingLoadView.weeks(widget.latest, records);
      if (!mounted) return;
      setState(() {
        _weeks = weeks;
        _startsHere =
            weeks.length < TrainingLoadView.historyWeeks &&
            records.entries.any(
              (e) =>
                  e.key.compareTo(weeks.last.dayKey) < 0 &&
                  e.value is Map &&
                  (e.value as Map)['state'] == 'learning',
            );
      });
    } catch (error) {
      // Firebase isn't set up in widget tests; the latest week still shows.
      debugPrint('Training load history: $error');
    }
  }

  void _go(int index) {
    if (index < 0 || index >= _weeks.length || index == _index) return;
    setState(() {
      _older = index > _index;
      _index = index;
    });
  }

  String _ago(TrainingLoadView week) {
    if (identical(week, widget.latest)) return 'Last 7 days';
    final weeks =
        (DateTime.parse(
                  widget.latest.dayKey,
                ).difference(DateTime.parse(week.dayKey)).inDays /
                7)
            .round();
    return weeks == 1 ? '1 week ago' : '$weeks weeks ago';
  }

  /// "+62%", or "about usual" within 5%.
  static String _change(TrainingLoadView week) => week.percent.abs() < 5
      ? 'about usual'
      : '${week.percent > 0 ? '+' : '−'}${week.percent.abs()}%';

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final week = _weeks[_index];
    Widget arrow(IconData icon, String tooltip, int to) {
      final enabled = to >= 0 && to < _weeks.length;
      return IconButton(
        onPressed: enabled ? () => _go(to) : null,
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        color: _purple,
        disabledColor: colors.border,
        style: IconButton.styleFrom(
          backgroundColor: enabled ? _purple.withValues(alpha: .14) : null,
          minimumSize: const Size(36, 36),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            arrow(Icons.chevron_left_rounded, 'Earlier week', _index + 1),
            Expanded(
              // A dropdown of the weeks, as wide as the space between the
              // arrows.
              child: LayoutBuilder(
                builder: (context, constraints) => MenuAnchor(
                  alignmentOffset: const Offset(0, 6),
                  style: MenuStyle(
                    backgroundColor: WidgetStatePropertyAll(colors.card),
                    surfaceTintColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    elevation: const WidgetStatePropertyAll(12),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(vertical: 6),
                    ),
                    minimumSize: WidgetStatePropertyAll(
                      Size(constraints.maxWidth, 0),
                    ),
                    maximumSize: WidgetStatePropertyAll(
                      Size(constraints.maxWidth, double.infinity),
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: colors.border),
                      ),
                    ),
                  ),
                  menuChildren: [
                    for (final (i, option) in _weeks.indexed)
                      MenuItemButton(
                        onPressed: () => _go(i),
                        style: MenuItemButton.styleFrom(
                          backgroundColor: i == _index
                              ? _purple.withValues(alpha: .14)
                              : null,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size.fromHeight(44),
                        ),
                        leadingIcon: SizedBox(
                          width: 18,
                          child: i == _index
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: _purple,
                                )
                              : null,
                        ),
                        trailingIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _stateColor(option.state),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${option.label} · ${_change(option)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        child: Text(
                          option.dateRange,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                  builder: (context, controller, _) => Semantics(
                    button: _weeks.length > 1,
                    label: 'Choose a week',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _weeks.length < 2
                          ? null
                          : controller.isOpen
                          ? controller.close
                          : controller.open,
                      child: Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                week.dateRange,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (_weeks.length > 1)
                                Icon(
                                  controller.isOpen
                                      ? Icons.expand_less_rounded
                                      : Icons.expand_more_rounded,
                                  size: 18,
                                  color: _purple,
                                ),
                            ],
                          ),
                          Text(
                            _ago(week),
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            arrow(Icons.chevron_right_rounded, 'Later week', _index - 1),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          // Swipe right for the week before, as if paging back in time.
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity > 200) _go(_index + 1);
            if (velocity < -200) _go(_index - 1);
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, animation) {
              final incoming = child.key == ValueKey(_index);
              final side = (_older ? 1.0 : -1.0) * (incoming ? -.25 : .25);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: Offset(side, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: TrainingLoadCard(
              key: ValueKey(_index),
              view: week,
              daysLabel: _index == 0 ? 'Last 7 days' : 'Those 7 days',
            ),
          ),
        ),
        if (_weeks.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Oldest on the left, like the arrows.
              for (var i = _weeks.length - 1; i >= 0; i--)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 2.5),
                  width: i == _index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _index ? _purple : colors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
        ],
        if (_startsHere && _index == _weeks.length - 1) ...[
          const SizedBox(height: 12),
          Text(
            'Training load starts here. Before this, Vivordo was still '
            'learning your usual week.',
            style: widget.secondary,
          ),
        ],
        if (week.bodyExplanation case final explanation?) ...[
          const SizedBox(height: 22),
          Text(
            'What your body is saying',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(explanation, style: widget.secondary),
        ],
      ],
    );
  }
}
