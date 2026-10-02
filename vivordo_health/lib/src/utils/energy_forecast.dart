import 'dart:math' as math;

/// One night's sleep, from falling asleep to waking.
typedef SleepPeriod = ({DateTime start, DateTime end});

enum EnergyPhase { groggy, peak, dip, secondWind, windDown }

class EnergyWindow {
  const EnergyWindow(this.phase, this.start, this.end);

  final EnergyPhase phase;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime time) => !time.isBefore(start) && time.isBefore(end);
}

/// The day's predicted energy (docs/scores.md §8): a forecast from sleep and
/// body clock, not a measurement.
class EnergyForecast {
  const EnergyForecast({
    required this.wake,
    required this.usualBedtime,
    required this.bedBy,
    required this.curve,
    required this.windows,
    required this.sleptHours,
    required this.sleepNeedHours,
    required this.sleepDebtHours,
    required this.midSleepHours,
    required this.estimated,
  });

  final DateTime wake;

  /// Tonight's bedtime by your usual pattern.
  final DateTime usualBedtime;

  /// Tonight's bedtime for a full night before tomorrow's first event, no
  /// later than [usualBedtime].
  final DateTime bedBy;

  /// Energy 0–1 every 15 minutes from [wake] to [usualBedtime].
  final List<(DateTime, double)> curve;
  final List<EnergyWindow> windows;
  final double sleptHours;
  final double sleepNeedHours;
  final double sleepDebtHours;

  /// Your usual sleep midpoint, in hours after midnight (chronotype).
  final double midSleepHours;

  /// True when last night's sleep is missing and your usual pattern was used.
  final bool estimated;

  /// Energy at [time], or null outside the waking day.
  double? at(DateTime time) {
    if (curve.isEmpty ||
        time.isBefore(curve.first.$1) ||
        time.isAfter(curve.last.$1)) {
      return null;
    }
    final index = time.difference(curve.first.$1).inMinutes ~/ _stepMinutes;
    if (index >= curve.length - 1) return curve.last.$2;
    final (t0, e0) = curve[index];
    final (_, e1) = curve[index + 1];
    final f = time.difference(t0).inSeconds / (_stepMinutes * 60);
    return e0 + (e1 - e0) * f;
  }

  EnergyWindow? window(EnergyPhase phase) =>
      windows.where((w) => w.phase == phase).firstOrNull;

  EnergyPhase? phaseAt(DateTime time) =>
      windows.where((w) => w.contains(time)).firstOrNull?.phase;
}

// ── Model constants ──────────────────────────────────────────────────────────
// A two-process model (sleep pressure + body clock) plus sleep inertia, the
// same family Rise and most alertness models use. The weights and phases are
// product choices fitted to the textbook day of someone sleeping 11 PM–7 AM:
// groggy until ~8, peak ~9–11, dip ~2:30–4, a second wind ~6–7:30, then down.
// Tune them against real "How's your energy?" answers later (phase 6).

const _stepMinutes = 15;
const _defaultMidSleepHours = 3.5;
const _defaultNeedHours = 8.0;

/// Nights needed before your own pattern replaces the defaults.
const _minNights = 5;

/// Body clock: a 24-hour wave peaking 11 h after your sleep midpoint, plus a
/// 12-hour wave peaking 5.5 h after it (the morning peak and the dip).
const _clock24PeakHours = 11.0;
const _clock12PeakHours = 5.5;
const _clock12Weight = 0.7;
const _clockWeight = 0.2;

/// Sleep pressure rises towards 1 while awake (time constant 18.2 h, the
/// classic Borbély value) from a start that's higher after a short night.
const _pressureRiseHours = 18.2;
const _pressureWeight = 0.4;
const _pressureRested = 0.2;
const _pressurePerMissingNight = 0.5;
const _pressurePerDebtHour = 0.03;
const _pressureMax = 0.75;

/// Sleep inertia: grogginess that fades over the first ~70 minutes.
const _inertiaStart = 0.5;
const _inertiaFadeHours = 0.75;
const _inertiaGone = 0.1;

const _base = 0.7;

/// How close to the extreme a time must be to belong to a window.
const _peakBand = 0.03;
const _dipBand = 0.02;
const _secondWindBand = 0.015;
const _maxWindowHours = 3.0;

/// A dip or second wind must stand out by this much to be named at all.
const _minDipDepth = 0.08;
const _minSecondWindRise = 0.04;

/// Time to get ready between waking and tomorrow's first event.
const _morningPrep = Duration(minutes: 60);
const _windDown = Duration(minutes: 60);
const _debtDays = 7;
const _maxDebtHours = 10.0;

/// Forecasts [day]'s energy from recent [nights] (any order, including last
/// night). [sleepNeedHours] is Capacity's sleep need; [tomorrowFirstEvent]
/// sets tonight's bed-by time.
EnergyForecast forecastEnergy({
  required DateTime day,
  required List<SleepPeriod> nights,
  double? sleepNeedHours,
  DateTime? tomorrowFirstEvent,
}) {
  final date = DateTime(day.year, day.month, day.day);
  final need = sleepNeedHours ?? _defaultNeedHours;
  final valid = [
    for (final n in nights)
      if (n.end.isAfter(n.start) && !n.end.isAfter(date.add(_oneDay))) n,
  ]..sort((a, b) => b.end.compareTo(a.end));
  final recent = valid.take(14).toList();
  final lastNight = recent.where((n) => _sameDay(n.end, date)).firstOrNull;

  // Chronotype: the median sleep midpoint, measured from midnight of the day
  // each night ended, preferring free days (weekends) when there are enough.
  // ponytail: plain median, not circular; fine for steady patterns, but a
  // mix of day and night sleeps averages to a meaningless midpoint.
  double midOf(SleepPeriod n) {
    final mid = n.start.add(n.end.difference(n.start) ~/ 2);
    return mid.difference(_midnight(n.end)).inMinutes / 60;
  }

  final free = recent.where((n) => n.end.weekday >= DateTime.saturday);
  final history = recent.length >= _minNights;
  final midSleep = history
      ? _median([for (final n in free.length >= 2 ? free : recent) midOf(n)])
      : lastNight != null
      ? midOf(lastNight)
      : _defaultMidSleepHours;
  final usualHours = history
      ? _median([for (final n in recent) _hours(n.end.difference(n.start))])
      : need;

  final anchor = date.add(_fromHours(midSleep));
  final wake = lastNight?.end ?? anchor.add(_fromHours(usualHours / 2));
  final slept = lastNight == null
      ? need
      : _hours(lastNight.end.difference(lastNight.start));
  final usualBedtime = anchor.add(_fromHours(24 - usualHours / 2));

  final debt = math.min(
    _maxDebtHours,
    [
      for (final n in recent)
        if (n.end.isAfter(date.subtract(const Duration(days: _debtDays - 1))))
          math.max(0.0, need - _hours(n.end.difference(n.start))),
    ].fold(0.0, (a, b) => a + b),
  );

  final pressureAtWake = math.min(
    _pressureMax,
    _pressureRested +
        _pressurePerMissingNight * math.max(0, 1 - slept / need) +
        _pressurePerDebtHour * debt,
  );
  double energy(DateTime t) {
    final phase = _hours(t.difference(anchor));
    final clock =
        math.cos(2 * math.pi * (phase - _clock24PeakHours) / 24) +
        _clock12Weight *
            math.cos(2 * math.pi * (phase - _clock12PeakHours) / 12);
    final awake = math.max(0.0, _hours(t.difference(wake)));
    final pressure =
        1 - (1 - pressureAtWake) * math.exp(-awake / _pressureRiseHours);
    final inertia = _inertiaStart * math.exp(-awake / _inertiaFadeHours);
    return (_base + _clockWeight * clock - _pressureWeight * pressure - inertia)
        .clamp(0.0, 1.0);
  }

  final curve = <(DateTime, double)>[
    for (
      var t = wake;
      !t.isAfter(usualBedtime);
      t = t.add(const Duration(minutes: _stepMinutes))
    )
      (t, energy(t)),
  ];

  final fromPrep = tomorrowFirstEvent
      ?.subtract(_morningPrep)
      .subtract(_fromHours(need));
  final bedBy = fromPrep != null && fromPrep.isBefore(usualBedtime)
      ? fromPrep
      : usualBedtime;

  return EnergyForecast(
    wake: wake,
    usualBedtime: usualBedtime,
    bedBy: bedBy,
    curve: curve,
    windows: _windows(curve, wake, bedBy),
    sleptHours: slept,
    sleepNeedHours: need,
    sleepDebtHours: debt,
    midSleepHours: midSleep,
    estimated: lastNight == null,
  );
}

/// Names the day's windows from the curve: grogginess after waking, the
/// morning peak, the afternoon dip, an evening second wind if there is one,
/// and the hour before bed.
List<EnergyWindow> _windows(
  List<(DateTime, double)> curve,
  DateTime wake,
  DateTime bedBy,
) {
  if (curve.length < 8) return const [];
  final windows = <EnergyWindow>[];
  final groggyEnd = wake.add(
    _fromHours(_inertiaFadeHours * math.log(_inertiaStart / _inertiaGone)),
  );
  windows.add(EnergyWindow(EnergyPhase.groggy, wake, groggyEnd));

  final windDownStart = bedBy.subtract(_windDown);
  int indexOf(DateTime t) => math.max(
    0,
    math.min(curve.length - 1, t.difference(wake).inMinutes ~/ _stepMinutes),
  );
  final first = indexOf(groggyEnd);
  final middle = indexOf(wake.add(curve.last.$1.difference(wake) ~/ 2));
  final late = indexOf(windDownStart.subtract(const Duration(minutes: 30)));

  // Peak: the highest point in the first half of the waking day.
  final peak = _extreme(curve, first, middle, highest: true);
  if (peak == null) return windows;
  final peakRange = _band(curve, peak, curve[peak].$2 - _peakBand, above: true);
  windows.add(_window(EnergyPhase.peak, curve, peakRange));

  // Dip: the lowest point between the peak and the evening.
  // Dip: the lowest turning point between the peak and the evening, so the
  // slide into bedtime never counts as the dip.
  final dip = _extreme(
    curve,
    peakRange.$2 + 1,
    late,
    highest: false,
    turningPoint: true,
  );
  if (dip != null && curve[peak].$2 - curve[dip].$2 >= _minDipDepth) {
    final dipRange = _band(curve, dip, curve[dip].$2 + _dipBand, above: false);
    windows.add(_window(EnergyPhase.dip, curve, dipRange));

    // Second wind: a later local high that clearly beats the dip.
    final wind = _extreme(
      curve,
      dipRange.$2 + 1,
      late,
      highest: true,
      turningPoint: true,
    );
    if (wind != null &&
        curve[wind].$2 - curve[dip].$2 >= _minSecondWindRise &&
        wind > dipRange.$2 + 1) {
      final windRange = _band(
        curve,
        wind,
        curve[wind].$2 - _secondWindBand,
        above: true,
      );
      windows.add(_window(EnergyPhase.secondWind, curve, windRange));
    }
  }

  windows.add(EnergyWindow(EnergyPhase.windDown, windDownStart, bedBy));
  return windows;
}

/// The highest or lowest point in [from]..[to]. With [turningPoint], only
/// points that are at least as high (or low) as both neighbours count, so a
/// curve still rising or falling at the edge of the range has none.
int? _extreme(
  List<(DateTime, double)> curve,
  int from,
  int to, {
  required bool highest,
  bool turningPoint = false,
}) {
  bool turns(int i) =>
      i > 0 &&
      i < curve.length - 1 &&
      (highest
          ? curve[i].$2 >= curve[i - 1].$2 && curve[i].$2 >= curve[i + 1].$2
          : curve[i].$2 <= curve[i - 1].$2 && curve[i].$2 <= curve[i + 1].$2);
  int? best;
  for (var i = from; i <= to && i < curve.length; i++) {
    if (turningPoint && !turns(i)) continue;
    if (best == null ||
        (highest
            ? curve[i].$2 > curve[best].$2
            : curve[i].$2 < curve[best].$2)) {
      best = i;
    }
  }
  return best;
}

/// The run of points around [index] on the same side of [limit], capped at
/// [_maxWindowHours] and grown evenly in both directions.
(int, int) _band(
  List<(DateTime, double)> curve,
  int index,
  double limit, {
  required bool above,
}) {
  bool inside(int i) =>
      i >= 0 &&
      i < curve.length &&
      (above ? curve[i].$2 >= limit : curve[i].$2 <= limit);
  const maxPoints = _maxWindowHours * 60 ~/ _stepMinutes;
  var start = index, end = index;
  while (end - start + 1 < maxPoints) {
    final left = inside(start - 1), right = inside(end + 1);
    if (!left && !right) break;
    if (left) start--;
    if (right && end - start + 1 < maxPoints) end++;
  }
  return (start, end);
}

EnergyWindow _window(
  EnergyPhase phase,
  List<(DateTime, double)> curve,
  (int, int) range,
) => EnergyWindow(
  phase,
  curve[range.$1].$1,
  curve[range.$2].$1.add(const Duration(minutes: _stepMinutes)),
);

const _oneDay = Duration(days: 1);

DateTime _midnight(DateTime t) => DateTime(t.year, t.month, t.day);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

double _hours(Duration d) => d.inMinutes / 60;

Duration _fromHours(double hours) => Duration(minutes: (hours * 60).round());

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
