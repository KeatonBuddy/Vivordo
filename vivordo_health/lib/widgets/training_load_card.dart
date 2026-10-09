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

Color _stateColor(String state) => switch (state) {
  'high' || 'strained' => _coral,
  'building' => _amber,
  'lighter' => _purple,
  _ => _teal,
};

/// The latest training load: it's calculated with Capacity each morning, so
/// look back a few days for a morning nothing synced.
Stream<TrainingLoadView?> watchTrainingLoad(DateTime day) {
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
          if (raw != null) return TrainingLoadView.fromMap(raw, doc.id);
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
  const TrainingLoadCard({super.key, required this.view, this.onTap});

  final TrainingLoadView view;
  final VoidCallback? onTap;

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
          Text(
            value,
            style: off ? secondary.copyWith(color: _coral) : secondary,
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
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _WeekChart(view: view),
              const SizedBox(height: 4),
              row(
                'Last 7 days',
                view.vsUsual,
                off: view.alert && view.percent >= 5,
              ),
              row('Hard days', '${view.hardDays} of 7'),
              for (final body in view.bodyRows)
                row(body.label, body.value, off: body.off),
              const SizedBox(height: 12),
              Text(
                '${view.measuredBy} · line: your average day',
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
                'TRAINING LOAD · ${view.label.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
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
                'TRAINING LOAD',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              TrainingLoadCard(view: view),
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
              const SizedBox(height: 22),
              Text(
                'HOW THIS WORKS',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Each morning Vivordo adds up your last 7 days of activity '
                'and compares it with your usual week, the 4 weeks before. '
                'Each day is measured against an ordinary active day for '
                'you: by heart rate when your watch was worn, by active '
                'minutes otherwise. A hard day is one and a half times an '
                'ordinary one or more.\n\n'
                '• Steady: around your usual week\n'
                '• Lighter: under 80% of it\n'
                '• Building: 30% or more above it\n'
                '• High: 50% or more above it, with 3 or more hard days\n'
                '• Strained: High, and your HRV or resting heart rate agrees '
                'on 2 of the last 3 mornings\n\n'
                'High stays on until your week drops back under 30% above '
                'usual, so one rest day doesn\'t switch it off.',
                style: secondary,
              ),
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
