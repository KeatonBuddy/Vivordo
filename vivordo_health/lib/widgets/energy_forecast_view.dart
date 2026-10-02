import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/energy_forecast.dart';

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
String _hoursText(double hours) {
  final minutes = (hours * 60).round();
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0
      ? '${minutes ~/ 60} h'
      : '${minutes ~/ 60} h ${rest.toString().padLeft(2, '0')}';
}

/// The peak, dip and second wind as chips. Taps open the "why" sheet.
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
class EnergyCurve extends StatelessWidget {
  const EnergyCurve({
    super.key,
    required this.forecast,
    required this.from,
    required this.until,
    this.shadeWindows = true,
  });

  final EnergyForecast forecast;
  final DateTime from;
  final DateTime until;
  final bool shadeWindows;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      size: Size.infinite,
      painter: _EnergyCurvePainter(forecast, from, until, shadeWindows),
    ),
  );
}

class _EnergyCurvePainter extends CustomPainter {
  _EnergyCurvePainter(this.forecast, this.from, this.until, this.shade);

  final EnergyForecast forecast;
  final DateTime from;
  final DateTime until;
  final bool shade;

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
            ..color = energyPhaseColor(window.phase).withValues(alpha: .10),
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
    canvas.drawPath(
      path,
      Paint()
        ..color = energyHigh
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_EnergyCurvePainter old) =>
      !identical(old.forecast, forecast) ||
      old.from != from ||
      old.until != until ||
      old.shade != shade;
}

/// "Your energy today": the curve and plain-language reasons.
Future<void> showEnergyForecastSheet(
  BuildContext context,
  EnergyForecast forecast,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: context.vivordoColors.card,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                          fontSize: 14,
                          height: 1.35,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Built on research into sleep pressure and body clocks. It '
              "doesn't learn your own patterns yet.",
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
      Icons.bedtime_rounded,
      forecast.estimated
          ? "Last night's sleep hasn't synced yet, so this uses your usual "
                'pattern.'
          : short >= 0.5
          ? 'You slept ${_hoursText(forecast.sleptHours)}, '
                '${_hoursText(short)} under your need, so today\'s peak is a '
                'little lower and the dip a little deeper.'
          : 'You slept ${_hoursText(forecast.sleptHours)}, about what you '
                'need.',
    ),
    if (groggy != null)
      (
        Icons.wb_twilight_rounded,
        '${forecast.estimated ? 'You usually wake' : 'You woke'} at '
            '${DateFormat.jm().format(forecast.wake)}. Expect some grogginess '
            'until about ${DateFormat.jm().format(groggy.end)}.',
      ),
    (
      Icons.schedule_rounded,
      'Your body clock runs '
          '${mid < 2.5
              ? 'early'
              : mid > 4.5
              ? 'late'
              : 'about average'} '
          '(you sleep around a midpoint of $midTime).',
    ),
    if (forecast.sleepDebtHours >= 1)
      (
        Icons.hourglass_bottom_rounded,
        "You're carrying about ${_hoursText(forecast.sleepDebtHours)} of "
            'sleep debt from the last week.',
      ),
    if (peak != null)
      (
        Icons.lightbulb_outline_rounded,
        'Best for focus: ${energyWindowText(peak)}.'
            '${dip == null ? '' : ' Save routine tasks for ${energyWindowText(dip)}.'}',
      ),
  ];
}

/// The evening card on My Day: when to wind down, bed-by for tomorrow's
/// first event, sleep debt and tomorrow's forecast if you're in bed by then.
class EnergyEveningCard extends StatelessWidget {
  const EnergyEveningCard({
    super.key,
    required this.tonight,
    required this.tomorrow,
    this.firstEventTitle,
    this.firstEventStart,
    this.onTap,
  });

  /// Today's forecast, with bed-by from tomorrow's first event.
  final EnergyForecast tonight;

  /// Tomorrow's forecast, assuming bed at [tonight]'s bed-by.
  final EnergyForecast tomorrow;
  final String? firstEventTitle;
  final DateTime? firstEventStart;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final windDown = tonight.window(EnergyPhase.windDown);
    final wakeBy = tonight.bedBy.add(
      Duration(minutes: (tonight.sleepNeedHours * 60).round()),
    );
    Widget tile(String label, String value, String detail, Color color) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.cardMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ],
            ),
          ),
        );
    return Material(
      color: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.black.withValues(alpha: .07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TONIGHT',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                windDown == null
                    ? 'Bed by ${DateFormat.jm().format(tonight.bedBy)}'
                    : 'Wind down from ${DateFormat.jm().format(windDown.start)}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  'Your body clock starts winding down around then.',
                  if (firstEventTitle != null && firstEventStart != null)
                    'Tomorrow starts with $firstEventTitle at '
                        '${DateFormat.jm().format(firstEventStart!)}.',
                ].join(' '),
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  tile(
                    'Bed by',
                    DateFormat.jm().format(tonight.bedBy),
                    '${_hoursText(tonight.sleepNeedHours)} before '
                        '${DateFormat.jm().format(wakeBy)}',
                    const Color(0xFF7F77DD),
                  ),
                  const SizedBox(width: 8),
                  tile(
                    'Sleep debt',
                    tonight.sleepDebtHours < 0.25
                        ? 'None'
                        : _hoursText(tonight.sleepDebtHours),
                    'over 7 nights',
                    tonight.sleepDebtHours >= 1
                        ? energyLow
                        : colors.textPrimary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                "TOMORROW'S FORECAST",
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .8,
                  fontWeight: FontWeight.w700,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              EnergyChips(forecast: tomorrow),
              const SizedBox(height: 6),
              Text(
                "If you're in bed by ${DateFormat.jm().format(tonight.bedBy)}.",
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tomorrow's forecast if you sleep from [tonight]'s bed-by for your full
/// sleep need, added to the nights you've had.
EnergyForecast tomorrowEnergyForecast({
  required EnergyForecast tonight,
  required DateTime today,
  required List<SleepPeriod> nights,
}) {
  final start = tonight.bedBy;
  final end = start.add(
    Duration(minutes: (tonight.sleepNeedHours * 60).round()),
  );
  return forecastEnergy(
    day: DateTime(today.year, today.month, today.day + 1),
    nights: [...nights, (start: start, end: end)],
    sleepNeedHours: tonight.sleepNeedHours,
  );
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
