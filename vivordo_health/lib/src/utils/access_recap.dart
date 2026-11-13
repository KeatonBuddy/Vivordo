import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import 'day_key.dart';
import 'meeting_patterns.dart';

enum RecapIcon { capacity, focus, meetings, planned }

typedef RecapLine = ({RecapIcon icon, String title, String detail});

/// "What Vivordo learned this month": shown on the paywall when a trial or
/// subscription ends, in place of the feature list. Every line is something
/// only Vivordo knows, and shows only when it has a real number behind it.
class AccessRecap {
  const AccessRecap(this.heading, this.dates, this.lines);
  final String heading;
  final String dates;
  final List<RecapLine> lines;
}

/// The recap for access from [from] to [to].
///
/// [scores] and [fixDays] are scores_daily and day_fixes by day key.
/// [focus] is the energy forecast's peak, already worded ("9:45–11:45 AM"),
/// with [freeFocusDays] the weekdays a week it was free in the calendar.
/// [meeting] is the meeting kind or series that most raises heart rate,
/// [meetingName] its calendar title when known.
AccessRecap accessRecap({
  required DateTime from,
  required DateTime to,
  required Map<String, Map<String, dynamic>> scores,
  required Map<String, Map<String, dynamic>> fixDays,
  String? focus,
  int? freeFocusDays,
  MeetingPattern? meeting,
  String? meetingName,
}) {
  final start = localDayKey(from), end = localDayKey(to);
  bool inRange(String day) =>
      day.compareTo(start) >= 0 && day.compareTo(end) <= 0;
  final months = (to.difference(from).inDays / 30).round();
  final lines = <RecapLine>[];

  // Capacity: the median of the last 4 weeks, against the first month's
  // when there's a longer run to compare.
  final capacity = [
    for (final day in scores.keys.where(inRange).sorted())
      if ((scores[day]?['capacity'] as Map?)?['score'] case final num score)
        (day: day, score: score.toDouble()),
  ];
  if (capacity.length >= 7) {
    final recent = capacity.length > 28
        ? capacity.sublist(capacity.length - 28)
        : capacity;
    final usual = _median([for (final c in recent) c.score]).round();
    final firstMonth = DateTime.parse(
      capacity.first.day,
    ).add(const Duration(days: 30));
    final early = [
      for (final c in capacity)
        if (DateTime.parse(c.day).isBefore(firstMonth)) c.score,
    ];
    final was = months >= 2 && early.length >= 7
        ? _median(early).round()
        : null;
    final weeks = (recent.length / 7).round();
    lines.add((
      icon: RecapIcon.capacity,
      title: 'Your usual Capacity is $usual',
      detail: was != null && usual - was >= 2
          ? 'up from $was in your first month'
          : capacity.length < 14
          ? 'learned from your first ${capacity.length} days'
          : 'learned from $weeks weeks of your days',
    ));
  }

  if (focus != null) {
    final free = freeFocusDays ?? 0;
    lines.add((
      icon: RecapIcon.focus,
      title: 'Best focus: $focus',
      detail: free > 0
          ? "and it's free on $free ${free == 1 ? 'day' : 'days'} a week"
          : 'when your energy usually peaks',
    ));
  }

  if (meeting != null && meeting.high) {
    final name = meetingName ?? meeting.label;
    lines.add((
      icon: RecapIcon.meetings,
      title:
          '$name ${meeting.isSeries ? 'raises' : 'raise'} your heart rate most',
      detail: meeting.liftLabel,
    ));
  }

  // Days a fix was kept, Plan my day was kept or Vivordo AI was used.
  var fixed = false, planned = false, ai = false, days = 0;
  for (final day in fixDays.keys.where(inRange)) {
    final data = fixDays[day]!;
    final usedFix = (data['kinds'] as Map? ?? const {}).values.any(
      (k) => k is Map && k['used'] == true && k['undone'] != true,
    );
    final helped = data['helped'] as Map? ?? const {};
    final plan = helped['planMyDay'] == true,
        chat = helped['vivordoAi'] == true;
    if (!usedFix && !plan && !chat) continue;
    days++;
    fixed |= usedFix;
    planned |= plan;
    ai |= chat;
  }
  if (days > 0) {
    final how = [
      if (fixed) 'day fixes',
      if (planned) 'Plan my day',
      if (ai) 'Vivordo AI',
    ];
    lines.add((
      icon: RecapIcon.planned,
      title: days == 1
          ? 'Vivordo helped plan 1 of your days'
          : 'Vivordo helped plan $days of your days',
      detail:
          'with ${how.length == 1 ? how.single : '${how.take(how.length - 1).join(', ')} and ${how.last}'}',
    ));
  }

  final sameYear = from.year == to.year;
  return AccessRecap(
    months <= 1
        ? 'What Vivordo learned this month'
        : 'What Vivordo learned in $months months',
    months <= 1
        ? '${DateFormat('MMM d').format(from)} – ${DateFormat('MMM d').format(to)}'
        : sameYear
        ? '${DateFormat('MMM').format(from)} – ${DateFormat('MMM').format(to)}'
        : '${DateFormat('MMM y').format(from)} – ${DateFormat('MMM y').format(to)}',
    lines,
  );
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}
