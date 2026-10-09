import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  });

  final String headline, summary, capacityLabel, scheduleLabel, footer;
  final int? capacityScore, scheduleScore;
  final VoidCallback? onDetails;

  /// The time the sun is drawn for; defaults to now. My Day rebuilds every
  /// minute, so the sun moves through the day.
  final DateTime? now;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
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
                'YOUR DAILY BRIEF',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
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
              const SizedBox(height: 16),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final capacity = _BriefScore(
                    title: 'CAPACITY',
                    semanticTitle: 'Daily capacity',
                    score: capacityScore,
                    label: capacityLabel,
                  );
                  final schedule = _BriefScore(
                    title: 'DEMAND',
                    semanticTitle: 'Schedule demand',
                    score: scheduleScore,
                    label: scheduleLabel,
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
                        Icons.info_outline_rounded,
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

class _BriefScore extends StatelessWidget {
  const _BriefScore({
    required this.title,
    required this.semanticTitle,
    required this.score,
    required this.label,
  });
  final String title, semanticTitle, label;
  final int? score;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$semanticTitle: ${score == null ? "unavailable" : "$score out of 100"}. $label',
    child: ExcludeSemantics(
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: score == null ? 0 : score!.clamp(0, 100) / 100,
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0xFF8270DB),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFD0A5FF)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(9),
                  child: FittedBox(
                    child: Text(
                      score == null ? '—' : '$score',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
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
                    fontSize: 10,
                    letterSpacing: 1.4,
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
