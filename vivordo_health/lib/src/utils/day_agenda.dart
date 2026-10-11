/// One row of the My Day timeline: an item, an opening, or a short break.
sealed class AgendaEntry<T> {
  const AgendaEntry();
}

class AgendaItem<T> extends AgendaEntry<T> {
  const AgendaItem(this.item, this.start, this.end);
  final T item;
  final DateTime start, end;
}

/// A plannable gap of at least [openingMinutes]. [end] is null for the rest
/// of the day.
class AgendaOpening<T> extends AgendaEntry<T> {
  const AgendaOpening(this.start, this.end);
  final DateTime start;
  final DateTime? end;
}

class AgendaBreak<T> extends AgendaEntry<T> {
  const AgendaBreak(this.minutes);
  final int minutes;
}

const openingMinutes = 30;
const breakMinutes = 10;

/// Upcoming timed items interleaved with the gaps between them, from [now] to
/// midnight, or to the last item when [openEnded] is false. Gaps are measured
/// from the latest end so far, so overlapping items never create a false
/// opening. Items already over are left out.
List<AgendaEntry<T>> buildDayAgenda<T>(
  DateTime now,
  Iterable<AgendaItem<T>> items, {
  bool openEnded = true,
}) {
  final dayEnd = DateTime(now.year, now.month, now.day + 1);
  final upcoming =
      items.where((i) => i.end.isAfter(now) || !i.start.isBefore(now)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final entries = <AgendaEntry<T>>[];
  var cursor = now;
  for (final item in upcoming) {
    final gap = item.start.difference(cursor).inMinutes;
    if (gap >= openingMinutes) {
      entries.add(AgendaOpening(cursor, item.start));
    } else if (gap >= breakMinutes) {
      entries.add(AgendaBreak(gap));
    }
    entries.add(item);
    if (item.end.isAfter(cursor)) cursor = item.end;
  }
  if (openEnded && dayEnd.difference(cursor).inMinutes >= openingMinutes) {
    entries.add(AgendaOpening(cursor, null));
  }
  return entries;
}
