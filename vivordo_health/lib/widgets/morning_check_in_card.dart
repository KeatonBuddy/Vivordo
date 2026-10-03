import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

/// "How did you sleep?" answers and their Capacity sub-scores
/// (docs/scores.md §4).
const sleepCheckInScores = {
  'Awful': 0,
  'Poor': 25,
  'Okay': 50,
  'Good': 75,
  'Great': 100,
};

/// "How do you feel?" uses the mood check-in labels, so the answer is also
/// today's mood (scored by MetricsService.moodScoreForLabel).
/// The check-in is asked from 5 AM until midnight, until it's answered.
/// Before 5 AM most people are still up from the night before and haven't
/// slept yet, and an answer would be saved to a day that hasn't really
/// started.
bool morningCheckInOpen(DateTime now) => now.hour >= 5;

/// Whether Home shows the check-in: today's answers are loaded ([checkIn]
/// is null until then), it's open, not dismissed, and a question is still
/// unanswered.
bool checkInDue(Map? checkIn, DateTime now) =>
    checkIn != null &&
    morningCheckInOpen(now) &&
    checkIn['dismissed'] != true &&
    !(checkIn['feel'] is num && checkIn['sleep'] is num);

const feelCheckInLabels = ['Awful', 'Down', 'Okay', 'Good', 'Great'];

const _feelIcons = [
  Icons.sentiment_very_dissatisfied_rounded,
  Icons.sentiment_dissatisfied_rounded,
  Icons.sentiment_neutral_rounded,
  Icons.sentiment_satisfied_rounded,
  Icons.sentiment_very_satisfied_rounded,
];

const _sleepIcons = [
  Icons.bedtime_off_outlined,
  Icons.bedtime_outlined,
  Icons.bedtime_outlined,
  Icons.bedtime_rounded,
  Icons.bedtime_rounded,
];

/// The optional daily check-in on Home, under the stress card. Shown from
/// 5 AM until both questions are answered or it's dismissed.
class MorningCheckInCard extends StatelessWidget {
  const MorningCheckInCard({
    super.key,
    required this.feel,
    required this.sleep,
    required this.sleepHours,
    required this.onFeel,
    required this.onSleep,
    required this.onDismiss,
  });

  /// Saved answers (labels), or null when unanswered.
  final String? feel, sleep;

  /// Last night's recorded sleep, shown next to the sleep question.
  final double? sleepHours;
  final ValueChanged<String> onFeel, onSleep;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final minutes = ((sleepHours ?? 0) * 60).round();
    final recorded = minutes <= 0
        ? ''
        : ' · ${minutes ~/ 60}h ${minutes % 60}m recorded';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DAILY CHECK-IN',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        letterSpacing: .7,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Two quick questions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: Icon(Icons.close_rounded, color: colors.textSecondary),
              ),
            ],
          ),
          _question(
            context,
            'How do you feel?',
            feelCheckInLabels,
            _feelIcons,
            feel,
            onFeel,
          ),
          _question(
            context,
            'How did you sleep?$recorded',
            sleepCheckInScores.keys.toList(),
            _sleepIcons,
            sleep,
            onSleep,
          ),
        ],
      ),
    );
  }

  Widget _question(
    BuildContext context,
    String title,
    List<String> labels,
    List<IconData> icons,
    String? selected,
    ValueChanged<String> onSelect,
  ) {
    final colors = context.vivordoColors;
    const purple = Color(0xFF534AB7);
    return Padding(
      padding: const EdgeInsets.only(top: 12, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: labels[i] == selected,
                    child: Material(
                      color: labels[i] == selected
                          ? purple
                          : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: labels[i] == selected ? purple : colors.border,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onSelect(labels[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Icon(
                                icons[i],
                                size: 22,
                                color: labels[i] == selected
                                    ? Colors.white
                                    : null,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: labels[i] == selected
                                      ? Colors.white
                                      : colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
