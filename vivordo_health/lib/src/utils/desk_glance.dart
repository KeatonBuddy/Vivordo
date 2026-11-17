import 'package:flutter/foundation.dart';

/// A timed event on Desk mode's day strip.
typedef DeskEvent = ({String title, DateTime start, DateTime end});

/// What Desk mode shows, kept in step with the widgets: these are set at
/// the same points the Stress, Capacity and calendar widgets are fed, so
/// the propped phone and the Home Screen never disagree.
class DeskGlance {
  static final stress = ValueNotifier<double?>(null);

  /// Live, from My Day; null until My Day has been on screen this launch.
  static final capacityLeft = ValueNotifier<int?>(null);

  /// Today's Capacity score, shown until [capacityLeft] is known.
  static final capacity = ValueNotifier<int?>(null);
  static final events = ValueNotifier<List<DeskEvent>>(const []);
}

/// Today's events that have not ended by [now], soonest first.
List<DeskEvent> deskAhead(List<DeskEvent> events, DateTime now) {
  final dayEnd = DateTime(now.year, now.month, now.day + 1);
  return [
    for (final e in events)
      if (e.end.isAfter(now) && e.start.isBefore(dayEnd)) e,
  ]..sort((a, b) => a.start.compareTo(b.start));
}

/// The stretch of today the day strip covers, so the events fill it rather
/// than huddling in a strip that runs to midnight: from shortly before the
/// first event (or now, once one is near or under way) to shortly after
/// the last, at least three hours, and never past midnight.
({DateTime start, DateTime end}) deskWindow(
  List<DeskEvent> ahead,
  DateTime now,
) {
  final midnight = DateTime(now.year, now.month, now.day + 1);
  if (ahead.isEmpty) {
    final end = now.add(const Duration(hours: 3));
    return (start: now, end: end.isAfter(midnight) ? midnight : end);
  }
  final lead = ahead.first.start.subtract(const Duration(minutes: 45));
  final start = lead.isAfter(now) ? lead : now;
  var end = ahead
      .map((e) => e.end)
      .reduce((a, b) => a.isAfter(b) ? a : b)
      .add(const Duration(minutes: 30));
  final shortest = start.add(const Duration(hours: 3));
  if (end.isBefore(shortest)) end = shortest;
  return (start: start, end: end.isAfter(midnight) ? midnight : end);
}
