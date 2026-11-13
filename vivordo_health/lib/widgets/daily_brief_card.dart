import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../src/utils/day_effort.dart';

/// Where the brief's sun sits at [time], as fractions of the landscape: it
/// rises bottom-left at 6 AM, peaks around 1 PM and sets bottom-right at
/// 8 PM. Null at night, when no sun is drawn.
Offset? briefSunPosition(DateTime time) {
  final minutes = time.hour * 60 + time.minute;
  if (minutes < 6 * 60 || minutes > 20 * 60) return null;
  final t = (minutes - 6 * 60) / (14 * 60);
  return Offset(.12 + .76 * t, .62 - .40 * math.sin(math.pi * t));
}

/// A local, data-backed brief. Scores retain their existing 0–100 meaning.
class DailyBriefCard extends StatelessWidget {
  const DailyBriefCard({
    super.key,
    required this.headline,
    required this.summary,
    required this.capacityScore,
    required this.capacityLabel,
    required this.scheduleScore,
    required this.scheduleLabel,
    required this.footer,
    this.onDetails,
    this.now,
    this.words,
    this.action,
    this.capacityEmptyIcon,
    this.scheduleEmptyIcon,
    this.onCapacityTap,
    this.onScheduleTap,
    this.capacityLeft,
    this.evening,
  });

  /// Today's Capacity as it stands, during the day: one ring split into
  /// what's free, booked and spent, in place of the Capacity and Demand
  /// rings (which the evening keeps for tomorrow).
  final CapacityLeft? capacityLeft;

  /// After the day ends: today's ring as it ended beside a dashed one for
  /// tomorrow's Demand against your usual Capacity, in place of the
  /// Capacity and Demand rings, so Capacity never looks refilled.
  final BriefEvening? evening;

  /// Under the summary: the day's top fix, and in the evening tonight's
  /// wind-down.
  final Widget? action;

  final String headline, summary, capacityLabel, scheduleLabel, footer;
  final int? capacityScore, scheduleScore;

  /// Inside the Capacity ring while it's empty (capacityEmptyState).
  final IconData? capacityEmptyIcon;

  /// Inside the Demand ring while the plan is loading or didn't load.
  final IconData? scheduleEmptyIcon;

  /// Open why Capacity and Demand are what they are (score_breakdown).
  final VoidCallback? onCapacityTap, onScheduleTap;

  static Widget _tappable(Widget child, VoidCallback? onTap) => onTap == null
      ? child
      : InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: child,
        );

  /// Words mode: state rows instead of the score rings.
  final BriefWords? words;
  final VoidCallback? onDetails;

  /// The time the sun is drawn for; defaults to now. My Day rebuilds every
  /// minute, so the sun moves through the day.
  final DateTime? now;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFAA91FF).withValues(alpha: .6)),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF5844ED), Color(0xFF3529AD)],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: 0,
          top: 0,
          width: 210,
          height: 180,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _BriefLandscape(
                  briefSunPosition(now ?? DateTime.now()),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your daily brief',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                summary,
                style: const TextStyle(
                  color: Color(0xFFF1ECFF),
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              if (action case final action?) ...[
                const SizedBox(height: 12),
                action,
              ],
              const SizedBox(height: 16),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 16),
              if (words case final words?)
                Column(
                  children: [
                    _tappable(
                      _BriefStateRow('Energy', words.energy),
                      onCapacityTap,
                    ),
                    const SizedBox(height: 8),
                    _tappable(
                      _BriefStateRow(words.loadTitle, words.load),
                      onScheduleTap,
                    ),
                  ],
                )
              else if (capacityLeft case final live?)
                _tappable(_CapacityLeftRow(live), onCapacityTap)
              else if (evening case final evening?)
                _EveningRow(
                  evening,
                  onTodayTap: onCapacityTap,
                  onTomorrowTap: onScheduleTap,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final capacity = _tappable(
                      _BriefScore(
                        title: 'Capacity',
                        semanticTitle: 'Daily capacity',
                        score: capacityScore,
                        label: capacityLabel,
                        emptyIcon: capacityEmptyIcon,
                      ),
                      onCapacityTap,
                    );
                    final schedule = _tappable(
                      _BriefScore(
                        title: 'Demand',
                        semanticTitle: 'Schedule demand',
                        score: scheduleScore,
                        label: scheduleLabel,
                        emptyIcon: scheduleEmptyIcon,
                      ),
                      onScheduleTap,
                    );
                    if (constraints.maxWidth < 280 ||
                        MediaQuery.textScalerOf(context).scale(12) > 19) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          capacity,
                          const SizedBox(height: 12),
                          schedule,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: capacity),
                        const SizedBox(width: 10),
                        Expanded(child: schedule),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 12),
              InkWell(
                onTap: onDetails,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.info,
                        color: Color(0xFFE8E0FF),
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          footer,
                          style: const TextStyle(
                            color: Color(0xFFE8E0FF),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

enum BriefTone { good, usual, low }

/// Why today's Capacity is empty, and what fills it: the icon in its ring,
/// the label beside it, the words-mode word and the brief's data footer.
({IconData icon, String label, String word, String footer}) capacityEmptyState({
  required bool beforeSleep,
  required bool sleepRecorded,
  required bool tracksSleep,
}) => beforeSleep
    ? (
        icon: CupertinoIcons.moon_fill,
        label: 'Ready after you sleep',
        word: 'After you sleep',
        footer: "Today's sleep is still ahead",
      )
    : sleepRecorded
    // Last night arrived; the server's Capacity follows in a moment.
    ? (
        icon: CupertinoIcons.hourglass,
        label: 'Working it out',
        word: 'Working it out',
        footer: "Updating with last night's sleep",
      )
    : tracksSleep
    ? (
        icon: CupertinoIcons.arrow_2_circlepath,
        label: 'Waiting for sleep · check in now',
        word: 'Waiting for sleep',
        footer: "Waiting for last night's sleep",
      )
    : (
        icon: CupertinoIcons.heart,
        label: 'Connect Health or check in',
        word: 'Connect Health',
        footer: 'No health data yet',
      );

typedef BriefState = ({String word, BriefTone tone});

/// A state chip's background and text colours.
(Color, Color) briefToneColors(BriefTone tone) => switch (tone) {
  BriefTone.good => (const Color(0xFFE1F5EE), const Color(0xFF085041)),
  BriefTone.low => (const Color(0xFFFAEEDA), const Color(0xFF633806)),
  BriefTone.usual => (const Color(0xFFEEEDFE), const Color(0xFF3C3489)),
};

/// Words mode's brief: Energy and today's (or tomorrow's) load as states.
typedef BriefWords = ({BriefState energy, String loadTitle, BriefState load});

/// Today's Capacity as a state: against your usual when known (8 points
/// either way, as the weekly review's low days), else by its own bands.
BriefState briefEnergyState({
  required int? capacity,
  required int? usual,
  required bool recovering,
  String? emptyWord,
}) {
  if (capacity == null) {
    return (word: emptyWord ?? 'Needs health data', tone: BriefTone.usual);
  }
  if (recovering) return (word: 'Recovering', tone: BriefTone.low);
  if (usual != null) {
    return capacity <= usual - 8
        ? (word: 'Lower than usual', tone: BriefTone.low)
        : capacity >= usual + 8
        ? (word: 'Higher than usual', tone: BriefTone.good)
        : (word: 'Your usual', tone: BriefTone.usual);
  }
  return capacity >= 80
      ? (word: 'High', tone: BriefTone.good)
      : capacity >= 50
      ? (word: 'Moderate', tone: BriefTone.usual)
      : (word: 'Low', tone: BriefTone.low);
}

/// Words mode's live Capacity: what's left against the plan still ahead
/// ([CapacityLeft.fit]). With [easy] (an alert is showing under the brief),
/// room left isn't called plenty.
BriefState capacityLeftWords(CapacityLeft live, {bool easy = false}) =>
    switch (live.fit) {
      DemandFit.roomToSpare when easy => (
        word: 'Go easy',
        tone: BriefTone.usual,
      ),
      DemandFit.roomToSpare => (word: 'Plenty left', tone: BriefTone.good),
      DemandFit.full => (word: 'Some room', tone: BriefTone.usual),
      DemandFit.over => (word: 'Short today', tone: BriefTone.low),
    };

/// Demand against the Capacity it's set beside, as the headline
/// ([demandFit]).
BriefState briefLoadState({
  required double? demand,
  required int? capacity,
  bool planFailed = false,
}) {
  if (demand == null) {
    return (
      word: planFailed ? "Didn't load" : 'Loading',
      tone: BriefTone.usual,
    );
  }
  if (capacity == null) {
    return (word: demand < 40 ? 'Light' : 'Full', tone: BriefTone.usual);
  }
  return switch (demandFit(demand, capacity)) {
    DemandFit.roomToSpare => (word: 'Light', tone: BriefTone.good),
    DemandFit.over => (word: 'Heavy', tone: BriefTone.low),
    DemandFit.full => (word: 'Full', tone: BriefTone.usual),
  };
}

class _BriefStateRow extends StatelessWidget {
  const _BriefStateRow(this.title, this.state);

  final String title;
  final BriefState state;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = briefToneColors(state.tone);
    return Semantics(
      label: '$title: ${state.word}',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              state.word,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BriefScore extends StatelessWidget {
  const _BriefScore({
    required this.title,
    required this.semanticTitle,
    required this.score,
    required this.label,
    this.emptyIcon,
  });
  final String title, semanticTitle, label;
  final int? score;
  final IconData? emptyIcon;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$semanticTitle: ${score == null ? "unavailable" : "$score out of 100"}. $label',
    child: ExcludeSemantics(
      child: Row(
        children: [
          // A changed score glides from the old one. A score arriving where
          // there was none shows as is (a fresh builder starts at its end),
          // so nothing counts up from zero at launch.
          TweenAnimationBuilder<double>(
            key: ValueKey(score == null),
            tween: Tween(end: (score ?? 0).clamp(0, 100).toDouble()),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, shown, _) => SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: shown / 100,
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      backgroundColor: const Color(0xFF8270DB),
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFFD0A5FF),
                      ),
                    ),
                  ),
                  if (score == null && emptyIcon != null)
                    Icon(emptyIcon, color: Colors.white, size: 20)
                  else
                    Padding(
                      padding: const EdgeInsets.all(9),
                      child: FittedBox(
                        child: Text(
                          score == null ? '—' : '${shown.round()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFE8E0FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _BriefLandscape extends CustomPainter {
  const _BriefLandscape(this.sunAt);

  /// Fractions of the canvas; null at night.
  final Offset? sunAt;

  @override
  void paint(Canvas canvas, Size size) {
    final sunAt = this.sunAt;
    if (sunAt != null) {
      // Drawn before the hills, so it rises and sets behind them.
      final sun = Offset(size.width * sunAt.dx, size.height * sunAt.dy);
      canvas.drawCircle(
        sun,
        85,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x55FFBCE8), Color(0x00FFBCE8)],
          ).createShader(Rect.fromCircle(center: sun, radius: 85)),
      );
      canvas.drawCircle(sun, 25, Paint()..color = const Color(0x55FFD5EC));
    }
    final back = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(
        size.width * .15,
        size.height * .45,
        size.width * .48,
        size.height * .70,
      )
      ..quadraticBezierTo(
        size.width * .8,
        size.height * .28,
        size.width,
        size.height * .42,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0x557D5CF0));
    final front = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(
        size.width * .5,
        size.height * .65,
        size.width,
        size.height * .78,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0x554332CA));
  }

  @override
  bool shouldRepaint(_BriefLandscape oldDelegate) => oldDelegate.sunAt != sunAt;
}

/// The brief's live Capacity: [live] as one ring on this morning's Capacity,
/// free (white), booked (lilac) and spent (the track), with the numbers
/// beside it. Booked turns amber when the plan needs more than is left.
class _CapacityLeftRow extends StatelessWidget {
  const _CapacityLeftRow(this.live);

  final CapacityLeft live;

  static const _free = Colors.white;
  static const _booked = Color(0xFFD0A5FF);
  static const _over = Color(0xFFFFB547);
  static const _spent = Color(0xFF8270DB);

  @override
  Widget build(BuildContext context) {
    final left = math.max(0, live.left.round());
    final booked = live.booked.round();
    final spent = live.spent.round();
    final tonight = live.byTonight.round();
    final short = tonight < 0;
    final rows = <(Color?, String)>[
      if (short) ...[
        (_over, '$booked booked'),
        (null, 'Short by ${-tonight}'),
      ] else ...[
        (_free, '$tonight free by tonight'),
        (_booked, '$booked booked'),
      ],
      (_spent, '$spent spent'),
    ];
    return Semantics(
      label:
          'Capacity: $left left, started today at ${live.morning}. '
          '${short ? '$booked booked, short by ${-tonight}' : '$booked booked, $tonight free by tonight'}. '
          '$spent spent.',
      child: ExcludeSemantics(
        child: Row(
          children: [
            // Glides when Effort or the plan moves it; the first value
            // shows as is.
            TweenAnimationBuilder<double>(
              tween: Tween(end: math.max(0, live.left).toDouble()),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (context, shownLeft, _) => SizedBox(
                width: 76,
                height: 76,
                child: CustomPaint(
                  painter: _CapacityRingPainter(
                    morning: live.morning.toDouble(),
                    left: shownLeft,
                    booked: live.booked,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${shownLeft.round()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const Text(
                          'left',
                          style: TextStyle(
                            color: Color(0xFFE8E0FF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Capacity',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'started today at ${live.morning}',
                    style: const TextStyle(
                      color: Color(0xFFE8E0FF),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (color, text) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          // No dot: the line under it goes on.
                          Container(
                            width: 8,
                            height: 8,
                            decoration: color == null
                                ? null
                                : BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: color == _spent
                                        ? Border.all(
                                            color: Colors.white.withValues(
                                              alpha: .5,
                                            ),
                                          )
                                        : null,
                                  ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              text,
                              style: TextStyle(
                                color: color == null ? _over : Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The evening row's numbers: how today ended and what tomorrow asks.
typedef BriefEvening = ({
  CapacityLeft today,
  double tomorrowDemand,
  int tomorrowCapacity,
});

/// Today's ring as it ended (white what's left, the track what was spent)
/// and tomorrow's dashed, not yet begun, filled with its Demand.
class _EveningRow extends StatelessWidget {
  const _EveningRow(this.evening, {this.onTodayTap, this.onTomorrowTap});

  final BriefEvening evening;
  final VoidCallback? onTodayTap, onTomorrowTap;

  @override
  Widget build(BuildContext context) {
    final today = evening.today;
    final left = math.max(0, today.left.round());
    final demand = evening.tomorrowDemand.round();
    final usual = evening.tomorrowCapacity;
    final over = demand > usual;
    Widget half(
      CustomPainter painter,
      int number,
      String title,
      String note,
      String label,
      VoidCallback? onTap, {
      Color noteColor = const Color(0xFFE8E0FF),
    }) => DailyBriefCard._tappable(
      Semantics(
        label: label,
        child: ExcludeSemantics(
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CustomPaint(
                  painter: painter,
                  child: Center(
                    child: Text(
                      '$number',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      note,
                      style: TextStyle(color: noteColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      onTap,
    );
    final todayHalf = half(
      _CapacityRingPainter(
        morning: today.morning.toDouble(),
        left: left.toDouble(),
        booked: 0,
      ),
      left,
      'Today',
      '$left left of ${today.morning}',
      'Today: $left Capacity left of ${today.morning}.',
      onTodayTap,
    );
    final tomorrowHalf = half(
      _TomorrowRingPainter(demand: evening.tomorrowDemand, usual: usual),
      demand,
      'Tomorrow',
      over
          ? '$demand booked, more than a usual $usual'
          : '$demand booked of a usual $usual',
      'Tomorrow: $demand Demand booked against a usual Capacity of $usual.',
      onTomorrowTap,
      noteColor: over ? _CapacityLeftRow._over : const Color(0xFFE8E0FF),
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth < 280 ||
              MediaQuery.textScalerOf(context).scale(12) > 19
          ? Column(
              children: [todayHalf, const SizedBox(height: 12), tomorrowHalf],
            )
          : Row(
              children: [
                Expanded(child: todayHalf),
                const SizedBox(width: 10),
                Expanded(child: tomorrowHalf),
              ],
            ),
    );
  }
}

/// Tomorrow: a dashed ring for a day not yet begun, filled lilac with its
/// Demand as a share of your usual Capacity (amber when it's more).
class _TomorrowRingPainter extends CustomPainter {
  const _TomorrowRingPainter({required this.demand, required this.usual});

  final double demand;
  final int usual;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0, dashes = 24;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const step = math.pi * 2 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        rect,
        i * step,
        step / 2,
        false,
        arc(Colors.white.withValues(alpha: .35)),
      );
    }
    if (usual <= 0 || demand <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      (demand / usual).clamp(0.0, 1.0) * math.pi * 2,
      false,
      arc(demand > usual ? _CapacityLeftRow._over : _CapacityLeftRow._booked),
    );
  }

  @override
  bool shouldRepaint(_TomorrowRingPainter old) =>
      old.demand != demand || old.usual != usual;
}

class _CapacityRingPainter extends CustomPainter {
  const _CapacityRingPainter({
    required this.morning,
    required this.left,
    required this.booked,
  });

  final double morning, left, booked;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    // Flat ends, so one share doesn't spill into the next.
    canvas.drawArc(rect, 0, math.pi * 2, false, arc(_CapacityLeftRow._spent));
    if (morning <= 0 || left <= 0) return;
    final leftShare = (left / morning).clamp(0.0, 1.0);
    final bookedShare = (math.min(booked, left) / morning).clamp(0.0, 1.0);
    final freeShare = leftShare - bookedShare;
    const top = -math.pi / 2;
    final short = booked > left;
    // Free first from the top, then what's booked; past the end is spent.
    if (freeShare > 0) {
      canvas.drawArc(
        rect,
        top,
        freeShare * math.pi * 2,
        false,
        arc(_CapacityLeftRow._free),
      );
    }
    if (bookedShare > 0) {
      canvas.drawArc(
        rect,
        top + freeShare * math.pi * 2,
        bookedShare * math.pi * 2,
        false,
        arc(short ? _CapacityLeftRow._over : _CapacityLeftRow._booked),
      );
    }
  }

  @override
  bool shouldRepaint(_CapacityRingPainter old) =>
      old.morning != morning || old.left != left || old.booked != booked;
}
