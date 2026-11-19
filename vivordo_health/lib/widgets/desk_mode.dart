import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../src/utils/desk_glance.dart';
import '../src/utils/home_stress_card_logic.dart' show homeStressLevel;
import '../theme/vivordo_theme.dart';

/// Desk mode: an iPhone Duo propped like a tent shows a dark glance screen
/// on its outer display instead of the tabs: Stress, capacity left, the
/// clock, what is still ahead today and the next event.
class DeskMode extends StatefulWidget {
  const DeskMode({super.key});

  @override
  State<DeskMode> createState() => _DeskModeState();
}

class _DeskModeState extends State<DeskMode> {
  static const _ink = Color(0xFF0B0A14);
  static const _card = Color(0xFF17152A);
  static const _soft = Color(0xFFA9A4C8);

  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(
      const Duration(seconds: 20),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ColoredBox(
      color: _ink,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: ListenableBuilder(
              listenable: Listenable.merge([
                DeskGlance.stress,
                DeskGlance.capacityLeft,
                DeskGlance.capacity,
                DeskGlance.events,
              ]),
              builder: (context, _) {
                final stress = DeskGlance.stress.value;
                final left = DeskGlance.capacityLeft.value;
                final capacity = DeskGlance.capacity.value;
                final ahead = deskAhead(DeskGlance.events.value, now);
                final next = ahead
                    .where((e) => e.start.isAfter(now))
                    .firstOrNull;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _StressRing(score: stress),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Right now',
                                style: TextStyle(
                                  color: _soft,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                homeStressLevel(stress) ?? 'No reading yet',
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                ),
                              ),
                              if (left != null || capacity != null)
                                Text(
                                  // What's left once My Day has worked it
                                  // out; until then, today's Capacity.
                                  left != null
                                      ? '$left capacity left'
                                      : 'Capacity $capacity today',
                                  style: const TextStyle(
                                    color: _soft,
                                    fontSize: 15,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat('h:mm').format(now),
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w600,
                                height: 1,
                              ),
                            ),
                            Text(
                              DateFormat('EEE, MMM d').format(now),
                              style: const TextStyle(
                                color: _soft,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _panel(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ahead.isEmpty
                                  ? 'Nothing else on your calendar today'
                                  : 'Still ahead · ${ahead.length} ${ahead.length == 1 ? 'event' : 'events'}',
                              style: const TextStyle(
                                color: _soft,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Expanded(
                              child: CustomPaint(
                                size: Size.infinite,
                                painter: _StripPainter(now: now, events: ahead),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _panel(
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              next == null ? 'Nothing next' : next.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (next != null)
                            Text(
                              'Next · ${DateFormat('h:mm a').format(next.start)}',
                              style: const TextStyle(
                                color: _soft,
                                fontSize: 14,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class _StressRing extends StatelessWidget {
  const _StressRing({required this.score});

  final double? score;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 104,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: CircularProgressIndicator(
            value: (score ?? 0) / 100,
            strokeWidth: 12,
            strokeCap: StrokeCap.round,
            backgroundColor: Colors.white.withValues(alpha: .14),
            color: const Color(0xFF7CF0B2),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              score == null ? '–' : '${score!.round()}',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
            ),
            const Text(
              'Stress',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    ),
  );
}

/// What is still ahead as a strip: a capsule for each event, named where
/// it fits, with a gap between neighbours and the hours marked underneath.
class _StripPainter extends CustomPainter {
  _StripPainter({required this.now, required this.events});

  final DateTime now;
  final List<DeskEvent> events;

  static const _soft = Color(0xFFA9A4C8);

  TextPainter _text(String text, TextStyle style, double maxWidth) =>
      TextPainter(
        text: TextSpan(text: text, style: style),
        // Titles follow the app's language; times read left to right.
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, maxWidth));

  @override
  void paint(Canvas canvas, Size size) {
    final window = deskWindow(events, now);
    final span = math.max(1, window.end.difference(window.start).inMinutes);
    double x(DateTime t) =>
        (t.difference(window.start).inMinutes / span).clamp(0.0, 1.0) *
        size.width;

    const labels = 18.0;
    final lane = Rect.fromLTWH(0, 0, size.width, size.height - labels - 6);
    final barHeight = math.min(lane.height, 54.0);
    final top = lane.center.dy - barHeight / 2;

    // Hours: a faint line through the lane and a label under it.
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: .08)
      ..strokeWidth = 1;
    final every = span > 8 * 60 ? 2 : 1;
    var hour = DateTime(
      window.start.year,
      window.start.month,
      window.start.day,
      window.start.hour + 1,
    );
    while (hour.isBefore(window.end)) {
      if (hour.hour % every == 0) {
        final hx = x(hour);
        canvas.drawLine(Offset(hx, 0), Offset(hx, lane.bottom), tick);
        final label = _text(
          DateFormat('j').format(hour),
          const TextStyle(color: _soft, fontSize: 11),
          60,
        );
        final lx = (hx - label.width / 2).clamp(0.0, size.width - label.width);
        label.paint(canvas, Offset(lx, size.height - labels));
      }
      hour = hour.add(const Duration(hours: 1));
    }

    for (final e in events) {
      // A hair of space each side, so back-to-back events read as separate.
      final left = x(e.start) + 2;
      final right = math.max(x(e.end) - 2, left + 10);
      final under = !e.start.isAfter(now);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, top, right, top + barHeight),
          const Radius.circular(12),
        ),
        Paint()..color = VivordoTheme.brand.withValues(alpha: under ? 1 : .78),
      );
      final width = right - left - 16;
      if (width < 34) continue;
      final title = _text(
        e.title,
        const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        width,
      );
      final time = _text(
        DateFormat('h:mm').format(e.start),
        TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 11),
        width,
      );
      final stacked = barHeight >= 40;
      final textTop =
          top + (barHeight - title.height - (stacked ? time.height : 0)) / 2;
      title.paint(canvas, Offset(left + 8, textTop));
      if (stacked) time.paint(canvas, Offset(left + 8, textTop + title.height));
    }

    // Now, while it is on the strip.
    if (!now.isBefore(window.start)) {
      final nx = x(now);
      canvas.drawLine(
        Offset(nx, 0),
        Offset(nx, lane.bottom),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2,
      );
      canvas.drawCircle(Offset(nx, 0), 4, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.now.minute != now.minute || old.events != events;
}
