import 'package:intl/intl.dart';

import 'energy_forecast.dart';

typedef FitBlock = ({String title, DateTime start, DateTime end});

/// How an invite sits in your day: the stretch of calendar around it, what
/// it clashes with and a line saying whether it fits.
class InviteFit {
  const InviteFit({
    required this.windowStart,
    required this.windowEnd,
    required this.events,
    required this.clashes,
    required this.warning,
    required this.message,
  });

  /// The strip's span: a few hours either side of the invite.
  final DateTime windowStart;
  final DateTime windowEnd;

  /// Your timed events that show in the window.
  final List<FitBlock> events;

  /// Where the invite overlaps them, clipped to the overlap.
  final List<FitBlock> clashes;

  /// A clash or your usual dip: shown in amber rather than green.
  final bool warning;
  final String message;
}

String _time(DateTime t) => DateFormat.jm().format(t);

/// Compares the invite ([start]–[end]) with your timed events that day and
/// your forecast [dip], if one is known.
InviteFit inviteFit({
  required DateTime start,
  required DateTime end,
  required List<FitBlock> dayEvents,
  EnergyWindow? dip,
}) {
  final hour = DateTime(start.year, start.month, start.day, start.hour);
  final windowStart = hour.subtract(const Duration(hours: 2));
  final span = end.difference(hour) + const Duration(hours: 4);
  final windowEnd = windowStart.add(
    span > const Duration(hours: 7) ? span : const Duration(hours: 7),
  );
  final events = [
    for (final e in dayEvents)
      if (e.end.isAfter(windowStart) && e.start.isBefore(windowEnd)) e,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final clashes = [
    for (final e in dayEvents)
      if (e.end.isAfter(start) && e.start.isBefore(end))
        (
          title: e.title,
          start: e.start.isAfter(start) ? e.start : start,
          end: e.end.isBefore(end) ? e.end : end,
        ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final inDip =
      dip != null && dip.start.isBefore(end) && dip.end.isAfter(start);
  const dipNote = 'your usual afternoon dip';

  if (clashes.isNotEmpty) {
    final first = clashes.first;
    final more = clashes.length > 1 ? ' and ${clashes.length - 1} more' : '';
    return InviteFit(
      windowStart: windowStart,
      windowEnd: windowEnd,
      events: events,
      clashes: clashes,
      warning: true,
      message:
          'Clashes with ${first.title} from ${_time(first.start)} to '
          '${_time(first.end)}$more.'
          '${inDip ? ' It also lands in $dipNote.' : ''}',
    );
  }
  DateTime? freeFrom;
  DateTime? freeUntil;
  for (final e in dayEvents) {
    if (!e.end.isAfter(start) &&
        (freeFrom == null || e.end.isAfter(freeFrom))) {
      freeFrom = e.end;
    }
    if (!e.start.isBefore(end) &&
        (freeUntil == null || e.start.isBefore(freeUntil))) {
      freeUntil = e.start;
    }
  }
  final free = switch ((freeFrom, freeUntil)) {
    (final from?, final until?) =>
      "You're free from ${_time(from)} to ${_time(until)}.",
    (final from?, null) => "You're free from ${_time(from)} on.",
    (null, final until?) => "You're free until ${_time(until)}.",
    _ => 'Nothing else is on your calendar that day.',
  };
  return InviteFit(
    windowStart: windowStart,
    windowEnd: windowEnd,
    events: events,
    clashes: const [],
    warning: inDip,
    message: inDip ? '$free It lands in $dipNote, though.' : 'Fits well. $free',
  );
}
