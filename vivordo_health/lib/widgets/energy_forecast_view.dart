import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/energy_factors.dart';
import '../src/utils/energy_fit.dart';
import '../src/utils/energy_forecast.dart';
import '../src/utils/sleep_schedule.dart';
import 'daily_tags.dart';

/// The energy forecast's colours: green when you're at your best, amber in
/// the dip, muted while groggy, purple while winding down.
const energyHigh = Color(0xFF1D9E75);
const energyLow = Color(0xFFEF9F27);
const _energyGroggy = Color(0xFF8A879A);
const _energyWindDown = Color(0xFF7F77DD);

Color energyPhaseColor(EnergyPhase phase) => switch (phase) {
  EnergyPhase.peak || EnergyPhase.secondWind => energyHigh,
  EnergyPhase.dip => energyLow,
  EnergyPhase.groggy => _energyGroggy,
  EnergyPhase.windDown => _energyWindDown,
};

String energyPhaseName(EnergyPhase phase) => switch (phase) {
  EnergyPhase.groggy => 'Groggy',
  EnergyPhase.peak => 'Peak',
  EnergyPhase.dip => 'Dip',
  EnergyPhase.secondWind => 'Second wind',
  EnergyPhase.windDown => 'Wind-down',
};

/// "the afternoon dip", "your peak"… for sentences.
String energyPhasePhrase(EnergyPhase phase) => switch (phase) {
  EnergyPhase.groggy => 'your groggy start',
  EnergyPhase.peak => 'your peak',
  EnergyPhase.dip => 'your afternoon dip',
  EnergyPhase.secondWind => 'your second wind',
  EnergyPhase.windDown => 'your wind-down',
};

/// "9–11 AM", "1:30–4 PM", "11 AM–1 PM".
String energyWindowText(EnergyWindow window) {
  String time(DateTime t, {required bool marker}) {
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minutes = t.minute == 0
        ? ''
        : ':${t.minute.toString().padLeft(2, '0')}';
    return marker
        ? '$hour$minutes ${t.hour < 12 ? 'AM' : 'PM'}'
        : '$hour$minutes';
  }

  final sameHalf = (window.start.hour < 12) == (window.end.hour < 12);
  return '${time(window.start, marker: !sameHalf)}–${time(window.end, marker: true)}';
}

/// "6 h 40", "45 min".
/// Sleep that fits between [night]'s bed-by and when you wake: your need,
/// or less when your usual wake comes sooner; "8 h of sleep" while the need
/// is the placeholder.
String _bedByHours(EnergyForecast night) {
  final fits = night.wakeTarget.difference(night.bedBy).inMinutes / 60;
  final hours = fits > 0 && fits < night.sleepNeedHours
      ? fits
      : night.sleepNeedHours;
  return '${hoursMinutes(hours)}${night.needIsDefault ? ' of sleep' : ''}';
}

/// The peak, dip and second wind as chips. Taps open the "why" sheet.
/// Last night on Home's Your Day: time asleep against your need, and the
/// night's tags. Nothing when last night isn't tracked and nothing's tagged.
class EnergySleepLine extends StatelessWidget {
  const EnergySleepLine({super.key, required this.forecast, this.onTap});

  final EnergyForecast forecast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lines = energySleepLines(forecast);
    if (lines.sleep == null && lines.tags == null) {
      return const SizedBox.shrink();
    }
    final colors = context.vivordoColors;
    return Material(
      color: _energyWindDown.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Icon(CupertinoIcons.moon, size: 18, color: _energyWindDown),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (lines.sleep case final sleep?)
                      Text(
                        sleep,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    if (lines.tags case final tags?)
                      Text(
                        tags,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// In the sleep line's place when there's no sleep and no usual sleep
/// times, so nothing draws the energy line yet.
class EnergyLineInvite extends StatelessWidget {
  const EnergyLineInvite({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Material(
      color: _energyWindDown.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Icon(CupertinoIcons.moon, size: 18, color: _energyWindDown),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add your usual sleep times to see your energy through '
                  'the day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.chevron_right,
                size: 18,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "5 h 18 asleep · 2 h 10 under your need" and "Alcohol last night".
@visibleForTesting
({String? sleep, String? tags}) energySleepLines(EnergyForecast forecast) {
  final short = forecast.sleepNeedHours - forecast.sleptHours;
  final tags = {
    for (final f in forecast.factors)
      if (f.id != hardTrainingFactor) f.id,
  };
  final phrase = dailyTagsPhrase(tags);
  return (
    sleep: forecast.estimated
        ? null
        : forecast.needIsDefault
        ? '${hoursMinutes(forecast.sleptHours)} asleep'
        : '${hoursMinutes(forecast.sleptHours)} asleep · '
              '${short >= 0.25
                  ? '${hoursMinutes(short)} under your need'
                  : short <= -0.25
                  ? '${hoursMinutes(-short)} over your need'
                  : 'about your need'}',
    tags: phrase.isEmpty
        ? null
        : '${phrase[0].toUpperCase()}${phrase.substring(1)} last night',
  );
}

class EnergyChips extends StatelessWidget {
  const EnergyChips({super.key, required this.forecast, this.onTap});

  final EnergyForecast forecast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final windows = [
      for (final phase in const [
        EnergyPhase.peak,
        EnergyPhase.dip,
        EnergyPhase.secondWind,
      ])
        ?forecast.window(phase),
    ];
    if (windows.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final window in windows)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: energyPhaseColor(window.phase).withValues(alpha: .14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${energyPhaseName(window.phase)} ${energyWindowText(window)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: energyPhaseColor(window.phase),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The energy curve from [from] to [until], with the peak and dip shaded,
/// drawn over another chart (Home's Your Day bars) or on its own.
class EnergyCurve extends StatefulWidget {
  const EnergyCurve({
    super.key,
    required this.forecast,
    required this.from,
    required this.until,
    this.shadeWindows = true,
    this.drawIn = false,
    this.now,
  });

  final EnergyForecast forecast;
  final DateTime from;
  final DateTime until;
  final bool shadeWindows;

  /// Home's chart: the line draws along the day the first time it scrolls
  /// into view each day, rather than at load, when it's below the fold.
  final bool drawIn;

  /// Marks this moment on the line with a dot that breathes: the one live
  /// point on a forecast.
  final DateTime? now;

  @override
  State<EnergyCurve> createState() => _EnergyCurveState();
}

class _EnergyCurveState extends State<EnergyCurve>
    with TickerProviderStateMixin {
  // ponytail: in memory, so a cold start the same day draws it again;
  // persist the day if that turns out to be too often.
  static String? _drawnOn;

  late final _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    value: 1,
  );
  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  late final _drawCurve = CurvedAnimation(
    parent: _draw,
    curve: Curves.easeInOut,
  );
  late final _breathCurve = CurvedAnimation(
    parent: _breath,
    curve: Curves.easeInOut,
  );
  ScrollPosition? _scroll;

  EnergyForecast get forecast => widget.forecast;
  DateTime get from => widget.from;
  DateTime get until => widget.until;

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (widget.now != null && !still) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
      _breath.value = 0;
    }
    if (!widget.drawIn || still || _drawnOn == _today()) return;
    // Hidden until it's on screen, then drawn once.
    if (_scroll == null) _draw.value = 0;
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != _scroll) {
      _scroll?.removeListener(_drawWhenSeen);
      _scroll = scroll?..addListener(_drawWhenSeen);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _drawWhenSeen());
  }

  void _drawWhenSeen() {
    if (!mounted || _drawnOn == _today()) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final middle = box.localToGlobal(box.size.center(Offset.zero)).dy;
    final screen = MediaQuery.sizeOf(context).height;
    // Clear of the navigation bar above and the tab bar below.
    if (middle < 100 || middle > screen - 110) return;
    _drawnOn = _today();
    _scroll?.removeListener(_drawWhenSeen);
    _draw.forward(from: 0);
  }

  @override
  void dispose() {
    _scroll?.removeListener(_drawWhenSeen);
    _drawCurve.dispose();
    _breathCurve.dispose();
    _draw.dispose();
    _breath.dispose();
    super.dispose();
  }

  /// What the curve shows, for VoiceOver: the windows it shades.
  String get _summary {
    final windows = [
      for (final phase in const [
        EnergyPhase.peak,
        EnergyPhase.dip,
        EnergyPhase.secondWind,
      ])
        if (forecast.window(phase) case final w?
            when w.end.isAfter(from) && w.start.isBefore(until))
          '${energyPhaseName(w.phase)} ${energyWindowText(w)}',
    ];
    return windows.isEmpty
        ? 'Energy forecast curve.'
        : 'Energy forecast: ${windows.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: _summary,
    child: ExcludeSemantics(
      child: IgnorePointer(
        // Its own layer: the breathing dot repaints only this.
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _EnergyCurvePainter(
              forecast,
              from,
              until,
              widget.shadeWindows,
              now: widget.now,
              draw: _drawCurve,
              breath: _breathCurve,
            ),
          ),
        ),
      ),
    ),
  );
}

class _EnergyCurvePainter extends CustomPainter {
  _EnergyCurvePainter(
    this.forecast,
    this.from,
    this.until,
    this.shade, {
    required this.now,
    required this.draw,
    required this.breath,
  }) : super(repaint: Listenable.merge([draw, breath]));

  final EnergyForecast forecast;
  final DateTime from;
  final DateTime until;
  final bool shade;
  final DateTime? now;

  /// 0 → 1 as the line is drawn along the day; 0 ↔ 1 as the now dot breathes.
  final Animation<double> draw, breath;

  @override
  void paint(Canvas canvas, Size size) {
    final span = until.difference(from).inMinutes;
    if (span <= 0 || forecast.curve.length < 2) return;
    double x(DateTime t) =>
        size.width * (t.difference(from).inMinutes / span).clamp(0.0, 1.0);
    // The day's own range fills the height, so its shape shows even when
    // energy only moves a little; a margin keeps the line off the edges.
    final shown = [
      for (final (time, energy) in forecast.curve)
        if (!time.isBefore(from) && !time.isAfter(until)) energy,
    ];
    if (shown.length < 2) return;
    final low = shown.reduce((a, b) => a < b ? a : b);
    final high = shown.reduce((a, b) => a > b ? a : b);
    final range = high - low < 0.05 ? 0.05 : high - low;
    double y(double energy) =>
        size.height * (1 - (0.12 + (energy - low) / range * 0.76));

    if (shade) {
      for (final window in forecast.windows) {
        if (window.phase != EnergyPhase.peak &&
            window.phase != EnergyPhase.dip) {
          continue;
        }
        canvas.drawRect(
          Rect.fromLTRB(x(window.start), 0, x(window.end), size.height),
          Paint()
            ..color = energyPhaseColor(
              window.phase,
            ).withValues(alpha: .10 * draw.value),
        );
      }
    }

    final path = Path();
    var started = false;
    for (final (time, energy) in forecast.curve) {
      if (time.isBefore(from) || time.isAfter(until)) continue;
      final point = Offset(x(time), y(energy));
      if (!started) {
        path.moveTo(point.dx, point.dy);
        started = true;
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    var line = path;
    if (draw.value < 1) {
      // Only as much of the line as has been drawn so far.
      line = Path();
      for (final metric in path.computeMetrics()) {
        line.addPath(
          metric.extractPath(0, metric.length * draw.value),
          Offset.zero,
        );
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = energyHigh
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Now, on the line, once the line has reached it.
    final at = now;
    if (at == null || at.isBefore(from) || at.isAfter(until)) return;
    final nowX = x(at);
    if (nowX > size.width * draw.value) return;
    (DateTime, double)? before, after;
    for (final point in forecast.curve) {
      if (!point.$1.isAfter(at)) before = point;
      if (after == null && !point.$1.isBefore(at)) after = point;
    }
    final a = before ?? after, b = after ?? before;
    if (a == null || b == null) return;
    final gap = b.$1.difference(a.$1).inSeconds;
    final energy = gap <= 0
        ? a.$2
        : a.$2 + (b.$2 - a.$2) * at.difference(a.$1).inSeconds / gap;
    final dot = Offset(nowX, y(energy));
    canvas.drawCircle(
      dot,
      5 + 6 * breath.value,
      Paint()..color = energyHigh.withValues(alpha: .30 * (1 - breath.value)),
    );
    canvas.drawCircle(dot, 4, Paint()..color = energyHigh);
  }

  @override
  bool shouldRepaint(_EnergyCurvePainter old) =>
      !identical(old.forecast, forecast) ||
      old.from != from ||
      old.until != until ||
      old.shade != shade ||
      old.now != now;
}

/// "Your energy today": the curve and plain-language reasons.
Future<void> showEnergyForecastSheet(
  BuildContext context,
  EnergyForecast forecast,
) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  backgroundColor: context.vivordoColors.card,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => _EnergyForecastSheet(forecast: forecast),
);

class _EnergyForecastSheet extends StatelessWidget {
  const _EnergyForecastSheet({required this.forecast});

  final EnergyForecast forecast;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final reasons = energyReasons(forecast);
    return SafeArea(
      child: SingleChildScrollView(
        // Bottom room keeps the note clear of the assistant bubble.
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 84),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Your energy today',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'A forecast from your sleep and body clock, not a measurement.',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
            const SizedBox(height: 14),
            Container(
              height: 110,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: colors.cardMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: EnergyCurve(
                forecast: forecast,
                from: forecast.wake,
                until: forecast.usualBedtime,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final text in [
                  'Woke ${DateFormat.jm().format(forecast.wake)}',
                  'Bed ${DateFormat.jm().format(forecast.usualBedtime)}',
                ])
                  Text(
                    text,
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            EnergyChips(forecast: forecast),
            const SizedBox(height: 16),
            for (final (icon, text) in reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: const Color(0xFF7F77DD)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Built on research into sleep pressure and body clocks. Night '
              'tags use your own mornings once you have tagged a few nights.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// The plain-language reasons behind [forecast], for the "why" sheet.
@visibleForTesting
List<(IconData, String)> energyReasons(EnergyForecast forecast) {
  final short = forecast.sleepNeedHours - forecast.sleptHours;
  final groggy = forecast.window(EnergyPhase.groggy);
  final peak = forecast.window(EnergyPhase.peak);
  final dip = forecast.window(EnergyPhase.dip);
  final mid = forecast.midSleepHours;
  final midTime = DateFormat.jm().format(
    DateTime(2000).add(Duration(minutes: ((mid % 24) * 60).round())),
  );
  return [
    (
      CupertinoIcons.moon_fill,
      forecast.estimated && forecast.usesSchedule
          ? "No sleep is tracked for last night, so this uses your usual "
                'sleep times. You can change them on the Sleep screen.'
          : forecast.estimated
          ? "Last night's sleep hasn't synced yet, so this uses your usual "
                'pattern.'
          : forecast.needIsDefault
          ? 'You slept ${hoursMinutes(forecast.sleptHours)}.'
          : short >= 0.5
          ? 'You slept ${hoursMinutes(forecast.sleptHours)}, '
                '${hoursMinutes(short)} under your need, so today\'s peak is a '
                'little lower and the dip a little deeper.'
          : short <= -0.5
          ? 'You slept ${hoursMinutes(forecast.sleptHours)}, '
                '${hoursMinutes(-short)} over your need.'
                '${forecast.shortNights > 0 ? ' Longer nights like this make up for short ones.' : ''}'
          : 'You slept ${hoursMinutes(forecast.sleptHours)}, about what you '
                'need.',
    ),
    if (shortNightsText(forecast) case final text?)
      (CupertinoIcons.hourglass_bottomhalf_fill, text),
    for (final f in forecast.factors)
      (
        f.id == hardTrainingFactor
            ? Icons.fitness_center_rounded
            : CupertinoIcons.moon,
        f.reason,
      ),
    if (groggy != null)
      (
        CupertinoIcons.sunset_fill,
        '${forecast.estimated ? 'You usually wake' : 'You woke'} at '
            '${DateFormat.jm().format(forecast.wake)}. Expect some grogginess '
            'until about ${DateFormat.jm().format(groggy.end)}'
            '${switch (forecast.heavyGrogginess) {
              HeavyGrogginess.sleepDebt when !forecast.needIsDefault => ", longer than usual since you've been short on sleep this "
                  'week',
              HeavyGrogginess.earlyWake => ', longer than usual since you woke earlier than you '
                  'usually do',
              _ => '',
            }}.',
      ),
    (
      CupertinoIcons.clock,
      'Your body clock runs '
          '${mid < 2.5
              ? 'early'
              : mid > 4.5
              ? 'late'
              : 'about average'} '
          '(you sleep around a midpoint of $midTime).',
    ),
    if (peak != null)
      (
        CupertinoIcons.lightbulb,
        'Best for focus: ${energyWindowText(peak)}.'
            '${dip == null ? '' : ' Save routine tasks for ${energyWindowText(dip)}.'}',
      ),
  ];
}

/// Recent short nights, as a count rather than hours owed (how lost sleep
/// adds up isn't precise enough to count): still weighing on today, or
/// mostly made up by longer nights since. Null under 3 short nights.
String? shortNightsText(EnergyForecast forecast) {
  final short = forecast.shortNights;
  if (forecast.needIsDefault || short < 3) return null;
  final of = 'of your last ${forecast.recentNights} nights';
  if (forecast.sleepDebtHours < 1) {
    return 'You were short on $short $of, but longer nights since have made '
        'up for most of it.';
  }
  final week = forecast.shortNightsThisWeek;
  return "You've been short on sleep $short $of"
      '${week == short
          ? ', all this week'
          : week > 0
          ? ', $week of them this week'
          : ''}. The recent ones weigh most on today.';
}

/// Tomorrow's forecast if you sleep from [tonight]'s bed-by for your full
/// sleep need, added to the nights you've had.
EnergyForecast tomorrowEnergyForecast({
  required EnergyForecast tonight,
  required DateTime today,
  required List<SleepPeriod> nights,
  SleepSchedule? schedule,
}) {
  final start = tonight.bedBy;
  final end = start.add(
    Duration(minutes: (tonight.sleepNeedHours * 60).round()),
  );
  return forecastEnergy(
    day: DateTime(today.year, today.month, today.day + 1),
    nights: [...nights, (start: start, end: end, asleepHours: null)],
    sleepNeedHours: tonight.sleepNeedHours,
    schedule: schedule,
  );
}

/// The wind-down reminders for tonight and the following nights: each at
/// the start of that night's wind-down, with bed-by and the next day's peak.
/// Only tonight knows tomorrow's first event; later nights use your usual
/// bedtime until the app reschedules them.
List<({DateTime at, String body})> windDownReminders({
  required DateTime today,
  required List<SleepPeriod> nights,
  double? sleepNeedHours,
  SleepSchedule? schedule,
  DateTime? tomorrowFirstEvent,
  int count = 7,
}) {
  final reminders = <({DateTime at, String body})>[];
  for (var i = 0; i < count; i++) {
    final day = DateTime(today.year, today.month, today.day + i);
    final night = forecastEnergy(
      day: day,
      nights: nights,
      sleepNeedHours: sleepNeedHours,
      tomorrowFirstEvent: i == 0 ? tomorrowFirstEvent : null,
      schedule: schedule,
    );
    final windDown = night.window(EnergyPhase.windDown);
    if (windDown == null) continue;
    final peak = tomorrowEnergyForecast(
      tonight: night,
      today: day,
      nights: nights,
      schedule: schedule,
    ).window(EnergyPhase.peak);
    reminders.add((
      at: windDown.start,
      body: [
        'Bed by ${DateFormat.jm().format(night.bedBy)} for '
            '${_bedByHours(night)} before you wake at '
            '${DateFormat.jm().format(night.wakeTarget)}.',
        if (peak != null) "Tomorrow's peak is ${energyWindowText(peak)}.",
      ].join(' '),
    ));
  }
  return reminders;
}

/// The forecast Home or My Day last showed, for Vivordo AI's ENERGY context
/// (docs/scores.md §8, phase 5): only the phone can calculate it.
({String text, DateTime at})? latestEnergy;

/// ENERGY for Vivordo AI: today's windows and bed-by, last night against
/// need, sleep debt, the clashes still ahead (from [fits]) and, in the
/// evening, [tomorrow]'s windows.
String energyContext({
  required EnergyForecast today,
  List<EnergyFit> fits = const [],
  EnergyForecast? tomorrow,
}) {
  final time = DateFormat.jm();
  String windows(EnergyForecast f) => [
    for (final w in f.windows)
      if (w.phase != EnergyPhase.groggy)
        '${energyPhaseName(w.phase).toLowerCase()} ${energyWindowText(w)}',
  ].join('; ');
  final groggy = today.window(EnergyPhase.groggy);
  final clashes = [
    for (final fit in fits)
      if (fit.kind == EnergyFitKind.clash)
        energyClashText(
              title: fit.item.event.title,
              start: fit.item.event.start,
              phase: fit.phase,
            ) +
            (!fit.movable
                ? ' It has other guests, so it stays put.'
                : fit.suggestedStart == null
                ? ' It could move, but the peak and second wind are full.'
                : ' It could move to ${time.format(fit.suggestedStart!)}.'),
  ];
  return [
    'Today'
        '${today.usesSchedule && today.estimated
            ? ' (estimated from usual sleep times; no sleep tracked)'
            : today.estimated
            ? " (last night's sleep hasn't synced; from the usual pattern)"
            : ''}: '
        '${today.estimated ? 'usually wakes' : 'woke'} '
        '${time.format(today.wake)}'
        '${groggy == null ? '' : ', groggy until ${time.format(groggy.end)}'}; '
        '${windows(today)}. Bed by ${time.format(today.bedBy)}.',
    if (!today.estimated)
      'Last night: slept ${hoursMinutes(today.sleptHours)} '
          '(needs ${hoursMinutes(today.sleepNeedHours)}).',
    ?shortNightsText(today),
    clashes.isEmpty
        ? 'No hard work still ahead lands in a low-energy window.'
        : 'Clashes: ${clashes.join(' ')}',
    if (tomorrow != null)
      'Tomorrow, if in bed by ${time.format(today.bedBy)}: '
          '${windows(tomorrow)}.',
  ].join('\n');
}

/// The first clash's sentence, e.g. "Your 2 PM Q4 budget review lands in
/// your afternoon dip."
String energyClashText({
  required String title,
  required DateTime start,
  required EnergyPhase phase,
}) =>
    'Your ${DateFormat.jm().format(start).replaceAll(':00', '')} '
    '$title lands in ${energyPhasePhrase(phase)}.';

/// A short hint for a clash's suggested time, e.g. "Try 10 AM, in your
/// peak".
String energyMoveHint(DateTime start, EnergyForecast forecast) {
  final phase = forecast.phaseAt(start);
  final time = DateFormat.jm().format(start).replaceAll(':00', '');
  return phase == null
      ? 'Try $time'
      : 'Try $time, in ${energyPhasePhrase(phase)}';
}
