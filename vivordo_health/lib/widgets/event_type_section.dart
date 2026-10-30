import 'package:flutter/cupertino.dart'
    show CupertinoActivityIndicator, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/calendar_cognitive_load_service.dart';
import '../src/services/calendar_service.dart';
import '../src/services/day_record_service.dart';
import 'apple_ui.dart';

const _purple = Color(0xFF6B5CE7);

/// The types someone can pick, heaviest first, in the app's words.
const eventTypeLabels = {
  'high-consequence': 'High stakes',
  'focused-work': 'Focused work',
  'collaboration': 'Meeting or class',
  'social': 'Social',
  'routine': 'Errands and routine',
  'rest': 'Break',
};

/// How much a type adds to Demand and Effort (docs/scores.md §1), in
/// My Day's "load" words.
String eventTypeWeight(String category) => switch (category) {
  'high-consequence' => 'Heaviest load on your day',
  'focused-work' => 'Heavy load on your day',
  'collaboration' => 'Medium load on your day',
  'unknown' => 'Medium load until you choose',
  'rest' => "Doesn't add to your day",
  _ => 'Light load on your day',
};

/// Where the type came from, then how much it adds. A [free] event (Free
/// in the calendar) only counts once the person picks its type.
String eventTypeCaption(CognitiveLoadScore score, {bool free = false}) {
  if (free && !score.chosen) {
    return "Marked Free in your calendar, so it isn't counted. "
        'Choose a type to count it.';
  }
  final from = score.chosen
      ? 'Set by you'
      : score.category == 'unknown'
      ? "Vivordo can't tell"
      : score.usedAi
      ? 'Sorted by Vivordo AI'
      : "Vivordo's guess";
  return '$from · ${eventTypeWeight(score.category)}';
}

/// "EVENT TYPE" on an event's details: its type, which sets how much it
/// adds to Demand and Effort. Changing it changes every event with the same
/// title, and the day reloads.
/// Asks what kind of event [event] is and saves the answer for every event
/// with its title. Returns the new score, or null when nothing changed.
Future<CognitiveLoadScore?> changeEventType(
  BuildContext context,
  CalendarCognitiveEvent event,
  CognitiveLoadScore score,
) async {
  final title = event.title.trim();
  final picked = await showAppleActionSheet<String>(
    context,
    title: 'What kind of event is this?',
    message:
        'Applies to all events called "${title.isEmpty ? 'Untitled' : title}". '
        'Heavier types count more towards your day.'
        '${event.showsAsFree && !score.chosen ? " It's marked Free in your calendar, so choosing a type also counts it." : ''}',
    actions: [
      for (final MapEntry(key: category, value: label)
          in eventTypeLabels.entries)
        AppleSheetAction(label, category, selected: category == score.category),
      if (score.chosen) const AppleSheetAction("Use Vivordo's guess", ''),
    ],
  );
  if (picked == null || !context.mounted) return null;
  if (score.chosen && picked == score.category) return null;
  try {
    await CalendarCognitiveLoadService.setType(
      event.title,
      picked.isEmpty ? null : picked,
    );
    // Home, My Day and today's day record (for Effort) re-sort.
    CalendarService.invalidateEventCache();
    DayRecordService.syncSoon();
    return (await CalendarCognitiveLoadService.scoreEvents([
      event,
    ], allowAi: true)).first;
  } catch (error) {
    debugPrint('Event type change failed: $error');
    if (context.mounted) {
      showToast(
        context,
        "Couldn't change the type. Try again.",
        kind: ToastKind.error,
      );
    }
    return null;
  }
}

class EventTypeSection extends StatefulWidget {
  const EventTypeSection({super.key, required this.event});

  final CalendarCognitiveEvent event;

  @override
  State<EventTypeSection> createState() => _EventTypeSectionState();
}

class _EventTypeSectionState extends State<EventTypeSection> {
  CognitiveLoadScore? _score;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scores = await CalendarCognitiveLoadService.scoreEvents([
      widget.event,
    ], allowAi: true);
    if (mounted) setState(() => _score = scores.first);
  }

  Future<void> _change() async {
    final score = _score;
    if (score == null || _busy) return;
    setState(() => _busy = true);
    final changed = await changeEventType(context, widget.event, score);
    if (!mounted) return;
    setState(() {
      _score = changed ?? _score;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final score = _score;
    final value = score == null
        ? ''
        : score.category == 'unknown'
        ? 'Not sure'
        : eventTypeLabels[score.category] ?? 'Not sure';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Event type',
          style: TextStyle(
            color: _purple,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: colors.cardMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: score == null || _busy ? null : _change,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, color: _purple, size: 23),
                  const SizedBox(width: 14),
                  Text(
                    'Type',
                    style: TextStyle(color: colors.textPrimary, fontSize: 15),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: score?.category == 'unknown' && !score!.chosen
                            ? _purple
                            : colors.textSecondary,
                        fontSize: 14,
                        fontWeight: score?.category == 'unknown'
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (score == null || _busy)
                    const SizedBox.square(
                      dimension: 16,
                      child: CupertinoActivityIndicator(radius: 8),
                    )
                  else
                    Icon(
                      CupertinoIcons.chevron_right,
                      color: colors.textSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (score != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              eventTypeCaption(score, free: widget.event.showsAsFree),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
