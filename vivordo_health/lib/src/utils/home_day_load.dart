import '../services/calendar_cognitive_load_service.dart';
import 'day_agenda.dart';

/// Bar levels on Home's day-load card, on the same 30/60 cut points as
/// `CognitiveLoadScore.level`.
enum DayLoadLevel { none, light, focused, heavy }

DayLoadLevel dayLoadLevel(num? score) => score == null || score <= 0
    ? DayLoadLevel.none
    : score >= 60
    ? DayLoadLevel.heavy
    : score >= 30
    ? DayLoadLevel.focused
    : DayLoadLevel.light;

/// The hours Home's day-load bars cover: 7 AM, or the whole hour of anything
/// that starts earlier that day, to midnight, so the whole evening shows.
({DateTime from, DateTime until}) dayLoadRange(
  DateTime day,
  Iterable<({DateTime start, DateTime end})> items,
) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = DateTime(day.year, day.month, day.day + 1);
  var from = DateTime(day.year, day.month, day.day, 7);
  for (final item in items) {
    if (!item.end.isAfter(dayStart) || !item.start.isBefore(dayEnd)) continue;
    if (item.start.isBefore(from)) {
      from = item.start.isBefore(dayStart)
          ? dayStart
          : DateTime(day.year, day.month, day.day, item.start.hour);
    }
  }
  return (from: from, until: dayEnd);
}

/// Rating a timed priority gets from its effort. An unrated priority
/// counts as focused work.
int priorityLoad(Object? effort) => switch (effort) {
  'light' => 20,
  'demanding' => 75,
  _ => 45,
};

/// A timed priority as calendar-load input, rated by its effort, so it is
/// weighted by its minutes and adds overlap and back-to-back pressure
/// exactly like a calendar event.
({CalendarCognitiveEvent event, CognitiveLoadScore score}) priorityLoadInput({
  required String id,
  required String title,
  required DateTime start,
  required DateTime end,
  Object? effort,
}) => (
  event: CalendarCognitiveEvent(id: id, title: title, start: start, end: end),
  score: CognitiveLoadScore(
    eventId: id,
    score: priorityLoad(effort),
    category: 'priority',
    reason: 'Priority effort',
    usedAi: false,
    confidence: 1,
  ),
);

/// The first opening left today and the title of what follows it. Null
/// when no opening of [openingMinutes] or more is left.
({DateTime start, DateTime? end, String? next})? nextDayOpening(
  DateTime now,
  Iterable<AgendaItem<String>> items,
) {
  final agenda = buildDayAgenda(now, items);
  for (var i = 0; i < agenda.length; i++) {
    if (agenda[i] case AgendaOpening(:final start, :final end)) {
      final following = agenda.skip(i + 1).whereType<AgendaItem<String>>();
      return (start: start, end: end, next: following.firstOrNull?.item);
    }
  }
  return null;
}
