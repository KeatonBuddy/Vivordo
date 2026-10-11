import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import 'apple_ui.dart';
import 'daily_tags.dart';

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

/// "Good morning", "Good afternoon" or "Good evening": Home's header and the
/// check-in sheet, which can be opened from the row at any time of day.
String timeOfDayGreeting(DateTime now) => now.hour < 12
    ? 'Good morning'
    : now.hour < 17
    ? 'Good afternoon'
    : 'Good evening';

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

/// The daily check-in on Home as one line, under the stress card: shown
/// from 5 AM until both questions are answered or it's put off for the day.
/// Tapping opens the check-in sheet.
class CheckInRow extends StatelessWidget {
  const CheckInRow({super.key, required this.left, required this.onTap});

  /// Questions still unanswered: 1 or 2.
  final int left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withValues(alpha: .07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Color(0xFF7F77DD),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Daily check-in',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                left > 1 ? '2 taps' : '1 left',
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

/// Sleep, last night's tags and feel: the check-in sheet's questions.
class _CheckInQuestions extends StatelessWidget {
  const _CheckInQuestions({
    required this.feel,
    required this.sleep,
    required this.sleepHours,
    required this.tags,
    required this.onFeel,
    required this.onSleep,
    required this.onTags,
  });

  final String? feel, sleep;
  final double? sleepHours;
  final Set<String> tags;
  final ValueChanged<String> onFeel, onSleep;
  final ValueChanged<Set<String>> onTags;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final minutes = ((sleepHours ?? 0) * 60).round();
    Widget label(String text, [String? aside]) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (aside != null)
              TextSpan(
                text: ' · $aside',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
          ],
        ),
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label(
          'How did you sleep?',
          minutes > 0 ? '${minutes ~/ 60} h ${minutes % 60} m recorded' : null,
        ),
        _CheckInOptions(
          labels: sleepCheckInScores.keys.toList(),
          icons: _sleepIcons,
          selected: sleep,
          onSelect: onSleep,
        ),
        label('Anything from last night?', 'optional'),
        DailyTagChips(selected: tags, onChanged: onTags),
        label('How do you feel?'),
        _CheckInOptions(
          labels: feelCheckInLabels,
          icons: _feelIcons,
          selected: feel,
          onSelect: onFeel,
        ),
      ],
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

/// The check-in as a sheet on the first morning open: sleep, last night's
/// tags and feel on one screen. Once both questions are answered it waits a
/// moment (any tap restarts the wait, so a last tag still lands), shows
/// "You're set" and closes. Answers and tags are saved as they're tapped.
/// [sleepHours] is live, so the recorded sleep appears if it syncs while the
/// sheet is open. True when both got answered, false for "Not today", null
/// when swiped away.
Future<bool?> showMorningCheckInSheet(
  BuildContext context, {
  required String? feel,
  required String? sleep,
  required ValueListenable<double?> sleepHours,
  required Set<String> tags,
  required ValueChanged<String> onFeel,
  required ValueChanged<String> onSleep,
  required ValueChanged<Set<String>> onTags,
}) => showAppleSheet<bool>(
  context,
  builder: (_) => _CheckInSheet(
    feel: feel,
    sleep: sleep,
    sleepHours: sleepHours,
    tags: tags,
    onFeel: onFeel,
    onSleep: onSleep,
    onTags: onTags,
  ),
);

class _CheckInSheet extends StatefulWidget {
  const _CheckInSheet({
    required this.feel,
    required this.sleep,
    required this.sleepHours,
    required this.tags,
    required this.onFeel,
    required this.onSleep,
    required this.onTags,
  });

  final String? feel, sleep;
  final ValueListenable<double?> sleepHours;
  final Set<String> tags;
  final ValueChanged<String> onFeel, onSleep;
  final ValueChanged<Set<String>> onTags;

  @override
  State<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends State<_CheckInSheet> {
  late String? _feel = widget.feel;
  late String? _sleep = widget.sleep;
  late Set<String> _tags = widget.tags;
  bool _closing = false;
  Timer? _settle;

  /// Starts (or restarts) the pause before closing, once both are answered.
  void _touched() {
    _settle?.cancel();
    if (_feel == null || _sleep == null) return;
    _settle = Timer(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      setState(() => _closing = true);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final Widget body;
    if (_closing) {
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
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Tagged ${dailyTagsPhrase(_tags)}',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
          const SizedBox(height: 20),
        ],
      );
    } else {
      body = Column(
        key: const ValueKey('questions'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeOfDayGreeting(DateTime.now()),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            "Two taps. It sharpens today's Capacity.",
            style: TextStyle(color: colors.textSecondary),
          ),
          ValueListenableBuilder<double?>(
            valueListenable: widget.sleepHours,
            builder: (context, hours, _) => _CheckInQuestions(
              feel: _feel,
              sleep: _sleep,
              sleepHours: hours,
              tags: _tags,
              onSleep: (label) {
                widget.onSleep(label);
                setState(() => _sleep = label);
                _touched();
              },
              onFeel: (label) {
                widget.onFeel(label);
                setState(() => _feel = label);
                _touched();
              },
              onTags: (tags) {
                widget.onTags(tags);
                setState(() => _tags = tags);
                _touched();
              },
            ),
          ),
          const SizedBox(height: 14),
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
            if (!_closing)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not today'),
                ),
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
