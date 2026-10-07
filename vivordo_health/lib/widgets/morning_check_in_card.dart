import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import 'apple_ui.dart';

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

/// After this many dismissals in a row the pop-up stops; the card stays.
const checkInPopupDismissLimit = 3;

/// Whether the check-in pops up as a sheet: once a day ([checkIn] has no
/// `prompted`), in the morning (5 AM – noon), while it's still due, and
/// unless it was dismissed [dismissedInARow] times running.
bool checkInPopupDue(Map? checkIn, DateTime now, int dismissedInARow) =>
    checkInDue(checkIn, now) &&
    now.hour < 12 &&
    checkIn!['prompted'] != true &&
    dismissedInARow < checkInPopupDismissLimit;

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
          _CheckInOptions(
            labels: labels,
            icons: icons,
            selected: selected,
            onSelect: onSelect,
          ),
        ],
      ),
    );
  }
}

/// The five answer buttons, shared by the card and the pop-up.
class _CheckInOptions extends StatelessWidget {
  const _CheckInOptions({
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final List<IconData> icons;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    const purple = Color(0xFF534AB7);
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              button: true,
              selected: labels[i] == selected,
              child: Material(
                color: labels[i] == selected ? purple : Colors.transparent,
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
                          color: labels[i] == selected ? Colors.white : null,
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
    );
  }
}

/// The check-in as a sheet on the first morning open: sleep, then feel,
/// then a moment of "You're set" before it closes. Answers are saved as
/// they're tapped ([onSleep], [onFeel]); already-answered questions are
/// skipped. True when both got answered, false when dismissed.
Future<bool> showMorningCheckInSheet(
  BuildContext context, {
  required String? feel,
  required String? sleep,
  required double? sleepHours,
  required ValueChanged<String> onFeel,
  required ValueChanged<String> onSleep,
}) async =>
    await showAppleSheet<bool>(
      context,
      builder: (_) => _CheckInSheet(
        feel: feel,
        sleep: sleep,
        sleepHours: sleepHours,
        onFeel: onFeel,
        onSleep: onSleep,
      ),
    ) ??
    false;

class _CheckInSheet extends StatefulWidget {
  const _CheckInSheet({
    required this.feel,
    required this.sleep,
    required this.sleepHours,
    required this.onFeel,
    required this.onSleep,
  });

  final String? feel, sleep;
  final double? sleepHours;
  final ValueChanged<String> onFeel, onSleep;

  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  late String? _feel = widget.feel;
  late String? _sleep = widget.sleep;

  bool get _done => _feel != null && _sleep != null;

  void _answerSleep(String label) {
    widget.onSleep(label);
    setState(() => _sleep = label);
    _finishIfDone();
  }

  void _answerFeel(String label) {
    widget.onFeel(label);
    setState(() => _feel = label);
    _finishIfDone();
  }

  Future<void> _finishIfDone() async {
    if (!_done) return;
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    const purple = Color(0xFF534AB7);
    final minutes = ((widget.sleepHours ?? 0) * 60).round();
    final askSleep = _sleep == null;
    Widget body;
    if (_done) {
      body = Column(
        key: const ValueKey('done'),
        children: [
          const SizedBox(height: 8),
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFFE1F5EE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Color(0xFF0F6E56),
              size: 30,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "You're set for today",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Slept ${_sleep!.toLowerCase()} · feeling ${_feel!.toLowerCase()}',
            style: TextStyle(color: colors.textSecondary),
          ),
          const SizedBox(height: 20),
        ],
      );
    } else {
      body = Column(
        key: ValueKey(askSleep),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!askSleep && widget.sleep == null)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE1F5EE),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'Slept ${_sleep!.toLowerCase()}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF085041)),
              ),
            ),
          Text(
            askSleep ? 'How did you sleep?' : 'How do you feel?',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            askSleep
                ? "Two taps. It sharpens today's Capacity."
                : "Counts as today's mood check-in.",
            style: TextStyle(color: colors.textSecondary),
          ),
          if (askSleep && minutes > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bedtime_rounded, color: purple, size: 20),
                  const SizedBox(width: 10),
                  Text('${minutes ~/ 60} h ${minutes % 60} m recorded'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          askSleep
              ? _CheckInOptions(
                  labels: sleepCheckInScores.keys.toList(),
                  icons: _sleepIcons,
                  selected: null,
                  onSelect: _answerSleep,
                )
              : _CheckInOptions(
                  labels: feelCheckInLabels,
                  icons: _feelIcons,
                  selected: null,
                  onSelect: _answerFeel,
                ),
          const SizedBox(height: 12),
          Text(
            'Swipe down to finish later on Home.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(top: 6, bottom: 8),
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Row(
              children: [
                // Which of the two questions this is.
                if (!_done)
                  for (final on in [askSleep, !askSleep])
                    Container(
                      width: on ? 14 : 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: on ? purple : colors.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                const Spacer(),
                if (!_done)
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not today'),
                  ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: body,
            ),
          ],
        ),
      ),
    );
  }
}
