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
