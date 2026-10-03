import '../services/calendar_cognitive_load_service.dart';
import 'day_effort.dart';
import 'energy_fit.dart';

/// One-tap fixes for a day with more planned than you've got (docs/scores.md
/// §2, "Ways to lighten today"). Each is priced by re-running Demand with the
/// change made, so the saving shown is real.
enum DayFixKind {
  /// Move an open priority of your own to a lighter day.
  movePriority,

  /// Push an event so a back-to-back run gets a 15-minute gap.
  buffer,

  /// Move hard work out of a low-energy window into the peak or second wind.
  energySlot,

  /// Add a 15-minute Break event next to a long back-to-back run, so the
  /// time stays free. Breaks take no part in Demand, so it saves nothing on
  /// paper; it protects recovery.
  addBreak,
}

class DayFix {
  const DayFix({
    required this.kind,
    required this.id,
    required this.title,
    required this.demandSaved,
    this.start,
    this.end,
    this.newStart,
    this.after,
    this.guests = 0,
    this.runMinutes = 0,
    this.beforeRun = false,
  });

  final DayFixKind kind;

  /// The item's id: an event's sourceEventKey, `priority:<path>` for a
  /// timed priority, or an untimed priority's id ([DayFixPriority.id]).
  final String id;
  final String title;

  /// Demand points the fix takes off today.
  final double demandSaved;

  /// The item's current times; null for an untimed priority.
  final DateTime? start, end;

  /// Buffer and energy slot: where the item moves to.
  final DateTime? newStart;

  /// Buffer: the item the new gap opens after.
  final String? after;

  /// Other guests who'd get the new time.
  final int guests;

  /// Add a break: how long the back-to-back run is, and whether the break
  /// goes before it (no room after).
  final int runMinutes;
  final bool beforeRun;

  DateTime? get newEnd => newStart == null || start == null || end == null
      ? null
      : newStart!.add(end!.difference(start!));
}

/// An open priority with no time today, as it counts towards Demand.
typedef DayFixPriority = ({String id, String title, Object? effort});

/// A back-to-back gap: shorter than this and the next item starts "straight
/// after" (hourly_calendar_load.dart).
const _buffer = Duration(minutes: 15);

/// Fixes worth less than this aren't offered.
const _minSaving = 0.5;

/// A back-to-back run this long earns a break.
const _longRun = Duration(minutes: 90);

/// Up to [max] fixes for today: the best priority to move, the best buffer,
/// then a better energy slot, then a break after the longest run. [items] and [untimed] are today's, as for
/// Demand; [demandOf] prices a version of the day. [canMove] says which items
/// the app may change (Google events not linked to a priority, and one-off
/// priorities of your own); events with other guests also need you to be
/// the organiser.
List<DayFix> findDayFixes({
  required DateTime now,
  required List<EffortItem> items,
  required List<DayFixPriority> untimed,
  required double Function(List<EffortItem> items, List<Object?> untimed)
  demandOf,
  required bool Function(EffortItem item) canMove,
  List<EnergyFit> fits = const [],
  int max = 3,
}) {
  final efforts = [for (final p in untimed) p.effort];
  final base = demandOf(items, efforts);
  bool own(EffortItem i) =>
      _isPriority(i) || i.event.attendeeCount <= 1 || i.event.isOrganizer;
  bool movable(EffortItem i) =>
      !i.done && i.event.start.isAfter(now) && own(i) && canMove(i);
  int guests(EffortItem i) =>
      _isPriority(i) ? 0 : (i.event.attendeeCount - 1).clamp(0, 999);

  final ranked = <DayFix>[];

  // Move a priority: whichever saves most.
  DayFix? priorityFix;
  for (final item in items) {
    if (!_isPriority(item) || !movable(item)) continue;
    final saved =
        base -
        demandOf([
          for (final i in items)
            if (i != item) i,
        ], efforts);
    if (saved >= _minSaving && saved > (priorityFix?.demandSaved ?? 0)) {
      priorityFix = DayFix(
        kind: DayFixKind.movePriority,
        id: item.event.id,
        title: item.event.title,
        demandSaved: saved,
        start: item.event.start,
        end: item.event.end,
      );
    }
  }
  for (final p in untimed) {
    final saved =
        base -
        demandOf(items, [
          for (final other in untimed)
            if (other != p) other.effort,
        ]);
    if (saved >= _minSaving && saved > (priorityFix?.demandSaved ?? 0)) {
      priorityFix = DayFix(
        kind: DayFixKind.movePriority,
        id: p.id,
        title: p.title,
        demandSaved: saved,
      );
    }
  }
  if (priorityFix != null) ranked.add(priorityFix);

  // Buffer: push an event that starts straight after another so there's a
  // 15-minute gap, if it then fits before whatever comes next.
  final busy = [
    for (final i in items)
      if (i.event.contributesToSchedule && !i.done) i,
  ]..sort((a, b) => a.event.start.compareTo(b.event.start));
  DayFix? bufferFix;
  for (final item in busy) {
    if (_isPriority(item) || !movable(item)) continue;
    final start = item.event.start;
    final before = busy
        .where(
          (o) =>
              o != item &&
              !o.event.end.isAfter(start) &&
              start.difference(o.event.end) < _buffer,
        )
        .fold<EffortItem?>(
          null,
          (latest, o) => latest == null || o.event.end.isAfter(latest.event.end)
              ? o
              : latest,
        );
    if (before == null) continue;
    final newStart = before.event.end.add(_buffer);
    final newEnd = newStart.add(item.event.end.difference(start));
    final clashes = busy.any(
      (o) =>
          o != item &&
          o.event.start.isBefore(newEnd) &&
          o.event.end.isAfter(newStart),
    );
    if (clashes || newEnd.day != start.day) continue;
    final saved =
        base -
        demandOf([
          for (final i in items) i == item ? _moved(i, newStart) : i,
        ], efforts);
    if (saved >= _minSaving && saved > (bufferFix?.demandSaved ?? 0)) {
      bufferFix = DayFix(
        kind: DayFixKind.buffer,
        id: item.event.id,
        title: item.event.title,
        demandSaved: saved,
        start: start,
        end: item.event.end,
        newStart: newStart,
        after: before.event.title,
        guests: guests(item),
      );
    }
  }
  if (bufferFix != null) ranked.add(bufferFix);
  ranked.sort((a, b) => b.demandSaved.compareTo(a.demandSaved));

  // A better energy slot: the hardest movable clash with somewhere to go.
  for (final fit in fits) {
    final to = fit.suggestedStart;
    if (fit.kind != EnergyFitKind.clash ||
        to == null ||
        !movable(fit.item) ||
        ranked.any((f) => f.id == fit.id)) {
      continue;
    }
    ranked.add(
      DayFix(
        kind: DayFixKind.energySlot,
        id: fit.id,
        title: fit.item.event.title,
        demandSaved:
            (base -
                    demandOf([
                      for (final i in items)
                        i.event.id == fit.id ? _moved(i, to) : i,
                    ], efforts))
                .clamp(0, double.infinity)
                .toDouble(),
        start: fit.item.event.start,
        end: fit.item.event.end,
        newStart: to,
        guests: guests(fit.item),
      ),
    );
    break;
  }
  if (_breakFix(now, busy) case final fix?) ranked.add(fix);
  return ranked.take(max).toList();
}

bool _isRest(EffortItem i) => i.score.category == 'rest';

/// A 15-minute break right after the longest back-to-back run of at least
/// [_longRun] still to come (or just before it when there's no room after),
/// unless a break is already there.
DayFix? _breakFix(DateTime now, List<EffortItem> busy) {
  final work = [
    for (final i in busy)
      if (!_isRest(i)) i,
  ];
  ({DateTime start, DateTime end, EffortItem first, EffortItem last})? longest;
  ({DateTime start, DateTime end, EffortItem first, EffortItem last})? run;
  for (final item in work) {
    final current = run;
    if (current != null && item.event.start.difference(current.end) < _buffer) {
      run = (
        start: current.start,
        first: current.first,
        end: item.event.end.isAfter(current.end) ? item.event.end : current.end,
        last: item.event.end.isAfter(current.end) ? item : current.last,
      );
    } else {
      run = (
        start: item.event.start,
        end: item.event.end,
        first: item,
        last: item,
      );
    }
    final candidate = run;
    if (candidate.end.difference(candidate.start) >= _longRun &&
        candidate.end.isAfter(now) &&
        (longest == null ||
            candidate.end.difference(candidate.start) >
                longest.end.difference(longest.start))) {
      longest = candidate;
    }
  }
  final found = longest;
  if (found == null) return null;
  bool free(DateTime start) {
    final end = start.add(_buffer);
    return !start.isBefore(now) &&
        // Never into the next day (a run can end at midnight).
        !end.isAfter(
          DateTime(found.start.year, found.start.month, found.start.day + 1),
        ) &&
        !busy.any(
          (o) => o.event.start.isBefore(end) && o.event.end.isAfter(start),
        );
  }

  // Already resting right around it.
  if (busy.any(
    (o) =>
        _isRest(o) &&
        o.event.start.isBefore(found.end.add(_buffer * 2)) &&
        o.event.end.isAfter(found.start.subtract(_buffer * 2)),
  )) {
    return null;
  }
  final before = found.start.subtract(_buffer);
  final at = free(found.end)
      ? found.end
      : free(before)
      ? before
      : null;
  if (at == null) return null;
  return DayFix(
    kind: DayFixKind.addBreak,
    id: 'break:${at.toIso8601String()}',
    title: 'Break',
    demandSaved: 0,
    start: at,
    end: at.add(_buffer),
    newStart: at,
    after: (at == before ? found.first : found.last).event.title,
    runMinutes: found.end.difference(found.start).inMinutes,
    beforeRun: at == before,
  );
}

bool _isPriority(EffortItem i) => i.score.category == 'priority';

EffortItem _moved(EffortItem i, DateTime start) {
  final e = i.event;
  return (
    event: CalendarCognitiveEvent(
      id: e.id,
      title: e.title,
      description: e.description,
      start: start,
      end: start.add(e.end.difference(e.start)),
      attendeeCount: e.attendeeCount,
      isOrganizer: e.isOrganizer,
      isOptional: e.isOptional,
      isOnlineMeeting: e.isOnlineMeeting,
      showsAsFree: e.showsAsFree,
      isCancelled: e.isCancelled,
      isDeclined: e.isDeclined,
      isAllDay: e.isAllDay,
    ),
    score: i.score,
    done: i.done,
    open: i.open,
  );
}
