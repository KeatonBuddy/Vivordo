import 'back_to_back_events.dart';
import 'daily_brief_analysis.dart';

/// Uses already-loaded My Day data; never treats missing data as an empty plan.
String myDayPlanningInsight({
  required DateTime now,
  required List<BriefCommitment> events,
  required List<BriefPriority> priorities,
  required bool calendarReady,
  required bool prioritiesReady,
  int allDayEvents = 0,
}) {
  if (!calendarReady || !prioritiesReady) {
    final missing = !calendarReady && !prioritiesReady
        ? 'calendar and priorities'
        : !calendarReady
        ? 'calendar'
        : 'priorities';
    return 'Your $missing ${!calendarReady && prioritiesReady ? 'is' : 'are'} not fully available yet. Refresh your plan so I can help you prioritize or find a break.';
  }
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final remaining = events
      .where(
        (e) =>
            e.end.isAfter(now) &&
            e.start.isBefore(tomorrow) &&
            e.end.isAfter(e.start),
      )
      .toList();
  final unfinished = priorities.where((p) => !p.completed).toList();
  final keys = events.map((e) => e.key).toSet();
  final unlinked = unfinished.where((p) => p.eventKey == null).toList();
  final linked = unfinished
      .where((p) => p.eventKey != null && keys.contains(p.eventKey))
      .length;
  final minutes = unlinked.fold<int>(
    0,
    (sum, p) =>
        sum +
        ((p.minutes != null && p.minutes! > 0 && p.minutes! <= 1440)
            ? p.minutes!
            : 0),
  );
  final missingEstimates = unlinked.any(
    (p) => p.minutes == null || p.minutes! <= 0 || p.minutes! > 1440,
  );
  final count = remaining.length + allDayEvents;
  if (count == 0 && unfinished.isEmpty) {
    return 'No calendar events remain and you have no unfinished priorities today. Want help making a simple plan?';
  }
  final summary =
      'You have $count calendar ${count == 1 ? 'event' : 'events'} remaining${allDayEvents > 0 ? ' (including $allDayEvents all-day)' : ''} and ${unfinished.length} unfinished ${unfinished.length == 1 ? 'priority' : 'priorities'} today.';
  final workload = minutes > 0
      ? ' ${missingEstimates ? 'At least ' : ''}$minutes minutes of estimated priority work are not linked to calendar events.'
      : '';
  final linkNote = linked > 0
      ? ' $linked ${linked == 1 ? 'priority is' : 'priorities are'} already linked to your calendar.'
      : '';
  final block = findNextBackToBackEventBlock(
    remaining.map(
      (e) => ScheduledEventWindow(title: e.title, start: e.start, end: e.end),
    ),
    now: now,
  );
  final help = block != null
      ? ' You have back-to-back tasks ahead. Want help choosing what to fit in or finding a break?'
      : unfinished.isNotEmpty
      ? ' Want help deciding what to tackle first${count > 0 ? ' and where it fits' : ''}?'
      : ' Want help reviewing your schedule or finding a break?';
  return '$summary$workload$linkNote$help';
}
