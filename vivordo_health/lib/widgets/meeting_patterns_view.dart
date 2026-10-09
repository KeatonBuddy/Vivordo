import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';

import '../screens/meeting_patterns_screen.dart';
import '../src/utils/body_reaction.dart';
import '../src/utils/meeting_patterns.dart';
import '../theme/vivordo_theme.dart';
import 'apple_ui.dart';
import 'body_reaction_view.dart';

/// Colours and words for a pattern, matching the per-event reaction chips.
({String tag, IconData icon, Color accent, Color fg, Color bg}) patternStyle(
  MeetingPattern p,
) {
  final s = bodyReactionStyle(
    p.high ? BodyReactionLevel.high : BodyReactionLevel.calm,
  )!;
  return (
    tag: p.high ? 'Heart rate usually up' : 'Heart rate usually lower',
    icon: s.icon,
    accent: s.accent,
    fg: s.fg,
    bg: s.bg,
  );
}

/// The pill under an upcoming event on My Day's timeline whose repeating
/// series has a pattern.
class MeetingPatternTag extends StatelessWidget {
  const MeetingPatternTag({super.key, required this.pattern, this.onTap});

  final MeetingPattern pattern;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = patternStyle(pattern);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? style.accent : style.fg;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: dark ? style.accent.withValues(alpha: .18) : style.bg,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 12, color: fg),
            const SizedBox(width: 4),
            Text(
              style.tag,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void openMeetingPatterns(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const MeetingPatternsScreen()));

/// One meeting's pattern: each measured time against your usual, how
/// consistent it was, and a way to all patterns.
Future<void> showMeetingPatternSheet(
  BuildContext context, {
  required String title,
  required MeetingPattern pattern,
}) {
  final style = patternStyle(pattern);
  final colors = context.vivordoColors;
  final top = pattern.events
      .map((e) => (e.liftBpm / e.usual * 100).abs())
      .fold<double>(10, (a, b) => b > a ? b : a);
  return showInfoSheet(
    context,
    icon: style.icon,
    title: title,
    summary: '${pattern.liftLabel} · ${pattern.countLabel}',
    body: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final e
                    in pattern.events.reversed.take(8).toList().reversed)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Container(
                        height:
                            4 + 60 * (e.liftBpm / e.usual * 100).abs() / top,
                        decoration: BoxDecoration(
                          color: (e.liftBpm > 0) == pattern.high
                              ? style.accent.withValues(alpha: .7)
                              : colors.border,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final d in [
                pattern.events.length > 8
                    ? pattern.events[pattern.events.length - 8].day
                    : pattern.events.first.day,
                pattern.events.last.day,
              ])
                Text(
                  DateFormat.MMMd().format(d),
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Your heart rate during this meeting against your usual at that '
            'time of day. A wellness estimate, not a measure of stress.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
          Builder(
            builder: (sheet) => Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(sheet);
                  openMeetingPatterns(context);
                },
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('All meeting patterns ›'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Home's Your Day: today's meetings with a pattern, in one row. Nothing
/// when none match; "learning" on Mondays for people with measured events.
class MeetingPatternsRow extends StatelessWidget {
  const MeetingPatternsRow({
    super.key,
    required this.patterns,
    required this.today,
    required this.now,
  });

  final MeetingPatterns patterns;

  /// Today's upcoming events with a pattern: title, start.
  final List<({String title, DateTime start, MeetingPattern pattern})> today;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final high = today.where((m) => m.pattern.high).toList();
    final shown = high.isNotEmpty ? high : today;
    final String title, subtitle;
    final IconData icon;
    final Color accent;
    VoidCallback? onTap;
    if (shown.isNotEmpty) {
      final first = shown.first;
      final style = patternStyle(first.pattern);
      icon = style.icon;
      accent = style.accent;
      if (shown.length == 1) {
        title = first.pattern.high
            ? '${first.title} usually raises your heart rate'
            : '${first.title} usually keeps your heart rate lower';
        subtitle =
            'Today at ${DateFormat(first.start.minute == 0 ? 'h a' : 'h:mm a').format(first.start)}'
            '${first.pattern.high ? ' · ${first.pattern.liftLabel}' : ''}';
        onTap = () => showMeetingPatternSheet(
          context,
          title: first.title,
          pattern: first.pattern,
        );
      } else {
        title = first.pattern.high
            ? '${shown.length} of today\'s meetings usually raise your heart rate'
            : '${shown.length} of today\'s meetings usually keep it lower';
        subtitle = shown.map((m) => m.title).join(', ');
        onTap = () => openMeetingPatterns(context);
      }
    } else if (patterns.learning &&
        patterns.measured > 0 &&
        now.weekday == DateTime.monday) {
      icon = Icons.insights_rounded;
      accent = const Color(0xFF7F77DD);
      title = 'Learning which meetings get to you';
      subtitle =
          '${patterns.measured} of about ${MeetingPatterns.learningTarget} '
          'events measured';
      onTap = () => openMeetingPatterns(context);
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
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
      ),
    );
  }
}

/// Timed Google events you'll actually be in, for [todaysPatternMeetings]:
/// cancelled, declined and "free" events are left out, as in Demand.
List<({String? series, String title, DateTime start})> patternEventsFrom(
  Iterable<gcal.Event> events,
) => [
  for (final e in events)
    if (e.status != 'cancelled' &&
        e.transparency != 'transparent' &&
        e.attendees?.any(
              (a) => a.self == true && a.responseStatus == 'declined',
            ) !=
            true)
      if (e.start?.dateTime?.toLocal() case final start?)
        (
          series: seriesKeyFor(e.recurringEventId),
          title: e.summary?.trim().isNotEmpty == true
              ? e.summary!.trim()
              : 'A meeting',
          start: start,
        ),
];

/// Today's events (Google) whose repeating series has a pattern, still to
/// come, earliest first.
List<({String title, DateTime start, MeetingPattern pattern})>
todaysPatternMeetings({
  required MeetingPatterns patterns,
  required Iterable<({String? series, String title, DateTime start})> events,
  required DateTime now,
}) => [
  for (final e in events)
    if (e.start.isAfter(now) &&
        DateUtils.isSameDay(e.start, now) &&
        patterns.bySeries[e.series] != null)
      (title: e.title, start: e.start, pattern: patterns.bySeries[e.series]!),
]..sort((a, b) => a.start.compareTo(b.start));
