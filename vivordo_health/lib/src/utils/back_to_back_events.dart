class ScheduledEventWindow {
  const ScheduledEventWindow({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final DateTime start;
  final DateTime end;
}

class BackToBackEventBlock {
  const BackToBackEventBlock(this.events);

  final List<ScheduledEventWindow> events;

  DateTime get start => events.first.start;
  DateTime get end => events.fold<DateTime>(
    events.first.end,
    (latest, event) => event.end.isAfter(latest) ? event.end : latest,
  );
}

/// Finds the next active or upcoming block containing at least two events that
/// touch or overlap. Identical events from multiple calendar providers are
/// collapsed before matching.
BackToBackEventBlock? findNextBackToBackEventBlock(
  Iterable<ScheduledEventWindow> source, {
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final seen = <String>{};
  final events = source.where((event) {
    if (!event.end.isAfter(currentTime) || !event.end.isAfter(event.start)) {
      return false;
    }
    final key =
        '${event.title.trim().toLowerCase()}|'
        '${event.start.millisecondsSinceEpoch}|${event.end.millisecondsSinceEpoch}';
    return seen.add(key);
  }).toList()..sort((a, b) => a.start.compareTo(b.start));

  for (var index = 0; index < events.length - 1; index++) {
    final block = <ScheduledEventWindow>[events[index]];
    var blockEnd = events[index].end;
    var nextIndex = index + 1;
    while (nextIndex < events.length &&
        !events[nextIndex].start.isAfter(blockEnd)) {
      block.add(events[nextIndex]);
      if (events[nextIndex].end.isAfter(blockEnd)) {
        blockEnd = events[nextIndex].end;
      }
      nextIndex++;
    }
    if (block.length >= 2) return BackToBackEventBlock(block);
  }
  return null;
}
