import 'day_effort.dart';
import 'energy_forecast.dart';

/// Categories that need you at your sharpest (calendar_cognitive_load).
const _hardCategories = {'focused-work', 'high-consequence'};

/// A priority rated at least this (demanding is 75, moderate 45) counts as
/// hard work too.
const _hardPriorityScore = 55;

/// Routine items, and priorities rated at most this (light is 20), suit a
/// dip.
const _lightPriorityScore = 20;

/// Phases where hard work is a poor fit.
const _lowPhases = {EnergyPhase.groggy, EnergyPhase.dip, EnergyPhase.windDown};
const _highPhases = {EnergyPhase.peak, EnergyPhase.secondWind};

/// At most this many clashes a day, hardest first, so My Day doesn't nag.
const _maxClashes = 2;

const _slotStep = Duration(minutes: 15);

/// How soon from now a suggested slot may start.
const _leadTime = Duration(minutes: 15);

enum EnergyFitKind {
  /// Hard work planned for a low-energy window.
  clash,

  /// Hard work in a peak or second wind, or routine work in a dip.
  goodFit,
}

class EnergyFit {
  const EnergyFit({
    required this.item,
    required this.kind,
    required this.phase,
    required this.movable,
    this.suggestedStart,
  });

  final EffortItem item;
  final EnergyFitKind kind;

  /// The window the item falls in.
  final EnergyPhase phase;

  /// Whether Vivordo may move it: a timed priority, or a calendar event with
  /// no other guests. Events with other people only get the note.
  final bool movable;

  /// For a movable clash: the earliest free start where the whole item fits
  /// in your peak or second wind, ending before wind-down and not already
  /// offered to another clash. Null when there's none.
  final DateTime? suggestedStart;

  String get id => item.event.id;
}

/// How [items] (the day's events and timed priorities, as for Your Day)
/// fit [forecast]: clashes first (hardest first, at most [_maxClashes]),
/// then good fits. Only items still ahead of [now] are judged. Items that
/// fit neither way are left out.
List<EnergyFit> fitDayToEnergy({
  required EnergyForecast forecast,
  required List<EffortItem> items,
  required DateTime now,
}) {
  final busy = [
    for (final i in items)
      if (_counts(i)) i,
  ];
  final clashes = <EnergyFit>[];
  final good = <EnergyFit>[];
  // Slots already offered, so two clashes aren't sent to the same time.
  final offered = <({DateTime start, DateTime end})>[];
  for (final item in busy) {
    if (item.done || !item.event.start.isAfter(now)) continue;
    final phase = forecast.phaseAt(_judgedAt(item));
    if (phase == null) continue;
    final hard = _isHard(item);
    if (hard && _lowPhases.contains(phase)) {
      final movable = _isMovable(item);
      final slot = movable
          ? _suggestSlot(forecast, item, busy, offered, now)
          : null;
      if (slot != null) {
        offered.add((
          start: slot,
          end: slot.add(item.event.end.difference(item.event.start)),
        ));
      }
      clashes.add(
        EnergyFit(
          item: item,
          kind: EnergyFitKind.clash,
          phase: phase,
          movable: movable,
          suggestedStart: slot,
        ),
      );
    } else if ((hard && _highPhases.contains(phase)) ||
        (_isLight(item) && phase == EnergyPhase.dip)) {
      good.add(
        EnergyFit(
          item: item,
          kind: EnergyFitKind.goodFit,
          phase: phase,
          movable: _isMovable(item),
        ),
      );
    }
  }
  clashes.sort((a, b) {
    final byScore = b.item.score.score.compareTo(a.item.score.score);
    return byScore != 0
        ? byScore
        : a.item.event.start.compareTo(b.item.event.start);
  });
  return [...clashes.take(_maxClashes), ...good];
}

/// Items that take up time (CalendarCognitiveEvent.contributesToSchedule).
bool _counts(EffortItem i) => i.event.contributesToSchedule;

bool _isPriority(EffortItem i) => i.score.category == 'priority';

bool _isHard(EffortItem i) => _isPriority(i)
    ? i.score.score >= _hardPriorityScore
    : _hardCategories.contains(i.score.category);

bool _isLight(EffortItem i) => _isPriority(i)
    ? i.score.score <= _lightPriorityScore
    : i.score.category == 'routine';

/// A timed priority, or an event with nobody else invited.
// ponytail: recurring events aren't known here; the move sheet (phase 3)
// must offer "this event" only.
bool _isMovable(EffortItem i) => _isPriority(i) || i.event.attendeeCount <= 1;

/// Where an item is judged: half an hour in, or its middle if it's shorter,
/// so a meeting that starts just before the dip still counts as in it.
DateTime _judgedAt(EffortItem i) {
  final length = i.event.end.difference(i.event.start);
  const halfHour = Duration(minutes: 30);
  return i.event.start.add(length < halfHour * 2 ? length ~/ 2 : halfHour);
}

DateTime? _suggestSlot(
  EnergyForecast forecast,
  EffortItem item,
  List<EffortItem> busy,
  List<({DateTime start, DateTime end})> offered,
  DateTime now,
) {
  final length = item.event.end.difference(item.event.start);
  final windDown = forecast.window(EnergyPhase.windDown)?.start;
  final earliest = now.add(_leadTime);
  bool free(DateTime start) {
    final end = start.add(length);
    if (start.isBefore(earliest)) return false;
    if (windDown != null && end.isAfter(windDown)) return false;
    bool overlaps(DateTime from, DateTime to) =>
        from.isBefore(end) && to.isAfter(start);
    return !busy.any(
          (other) =>
              other.event.id != item.event.id &&
              overlaps(other.event.start, other.event.end),
        ) &&
        !offered.any((slot) => overlaps(slot.start, slot.end));
  }

  final windows =
      forecast.windows.where((w) => _highPhases.contains(w.phase)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  for (final window in windows) {
    for (
      var start = window.start;
      !start.add(length).isAfter(window.end);
      start = start.add(_slotStep)
    ) {
      if (free(start)) return start;
    }
  }
  return null;
}
