import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/burnout_view.dart';

const _teal = Color(0xFF1D9E75);
const _amber = Color(0xFFEF9F27);
const _coral = Color(0xFFE24B4A);
const _purple = Color(0xFF7F77DD);

Color _levelColor(String level) => switch (level) {
  'warning' => _coral,
  'watch' => _amber,
  'steady' => _teal,
  _ => _purple,
};

String _levelLabel(String level) => switch (level) {
  'warning' => 'BURNOUT CHECK · WARNING',
  'watch' => 'BURNOUT CHECK · WORTH WATCHING',
  _ => 'BURNOUT CHECK',
};

/// The nightly burnout check on My Day (docs/scores.md §6): a full card at
/// Watch or Warning, otherwise a one-line row. Tapping either opens the last
/// 2 weeks against the person's normal.
class BurnoutCard extends StatelessWidget {
  const BurnoutCard({super.key, required this.view});

  final BurnoutView view;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final color = _levelColor(view.level);
    final alert = view.level == 'warning' || view.level == 'watch';
    if (!alert) return _row(context);
    return Material(
      color: alert
          ? Color.alphaBlend(color.withValues(alpha: .10), colors.card)
          : colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: alert
              ? color.withValues(alpha: .45)
              : Colors.black.withValues(alpha: .07),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showBurnoutDetails(context, view),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (view.level == 'steady') ...[
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: _teal,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _levelLabel(view.level),
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: .8,
                        fontWeight: FontWeight.w600,
                        color: alert ? color : colors.textSecondary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                view.title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                view.body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: colors.textSecondary,
                ),
              ),
              if (view.learningProgress case final progress?) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: _purple,
                    backgroundColor: colors.cardMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Learning or Steady: "Burnout check · Steady ›" in one line.
  Widget _row(BuildContext context) {
    final colors = context.vivordoColors;
    // No day count: "14 of 42 days" reads as a long wait.
    final status = view.level == 'learning'
        ? 'Learning your normal'
        : view.early
        ? 'Steady · early check'
        : 'Steady';
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: .07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showBurnoutDetails(context, view),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: _levelColor(view.level),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Burnout check',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                status,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showBurnoutDetails(BuildContext context, BurnoutView view) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.vivordoColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => _BurnoutDetails(view: view),
    );

class _BurnoutDetails extends StatelessWidget {
  const _BurnoutDetails({required this.view});

  final BurnoutView view;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final color = _levelColor(view.level);
    TextStyle secondary([double size = 13]) =>
        TextStyle(fontSize: size, height: 1.45, color: colors.textSecondary);
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: .8,
          fontWeight: FontWeight.w600,
          color: colors.textSecondary,
        ),
      ),
    );
    return SafeArea(
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
                _levelLabel(view.level),
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w600,
                  color: view.level == 'learning'
                      ? colors.textSecondary
                      : color,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                view.level == 'learning'
                    ? 'How this works'
                    : view.early
                    ? 'Last week vs your first few'
                    : 'Last 2 weeks vs your normal',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              if (view.level == 'learning') ...[
                const SizedBox(height: 10),
                Text(
                  'Each night Vivordo compares your last 2 weeks with your '
                  'own normal (the 8 weeks before that), across three things:\n\n'
                  '• Capacity: the energy you start each day with\n'
                  '• Effort: how much your days take\n'
                  '• Mood: your check-ins\n\n'
                  'One area drifting is worth watching. It only warns you when '
                  'two agree for more than a week, so one bad day never sets '
                  'it off.\n\n'
                  'The first check comes after about 3 weeks, comparing your '
                  'last week with the weeks before. It gets sharper as it '
                  'learns your normal, and only warns from about 6 weeks.',
                  style: secondary(14),
                ),
              ] else ...[
                const SizedBox(height: 6),
                for (final area in view.areas)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: switch (area.state) {
                              'worse' =>
                                view.level == 'warning' ? _coral : _amber,
                              'slightly' => _amber,
                              'none' => colors.border,
                              _ => _teal,
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            area.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Text(area.word, style: secondary()),
                      ],
                    ),
                  ),
                if (view.drivers.isNotEmpty) ...[
                  section(
                    view.level == 'warning'
                        ? 'WHAT\'S DRIVING IT'
                        : 'BEHIND IT',
                  ),
                  for (final driver in view.drivers)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('• $driver', style: secondary(14)),
                    ),
                ],
                if (view.level == 'watch')
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      'Nothing to act on yet. If a second area starts '
                      'drifting too, this becomes a warning.',
                      style: secondary(),
                    ),
                  ),
                if (view.suggestions.isNotEmpty) ...[
                  section('SMALL THINGS THAT HELP'),
                  for (final suggestion in view.suggestions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('• $suggestion', style: secondary(14)),
                    ),
                ],
              ],
              const SizedBox(height: 20),
              Text(
                'A wellness signal, not a diagnosis. If you\'re struggling, '
                'talk to someone you trust or a professional.',
                style: secondary(11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
