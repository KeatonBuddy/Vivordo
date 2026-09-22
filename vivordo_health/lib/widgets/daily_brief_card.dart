import 'package:flutter/material.dart';

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
  });

  final String headline, summary, capacityLabel, scheduleLabel, footer;
  final int? capacityScore, scheduleScore;
  final VoidCallback? onDetails;

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
        const Positioned(
          right: 0,
          top: 0,
          width: 210,
          height: 180,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: CustomPaint(painter: _BriefLandscape()),
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
                  fontSize: 27,
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
                    title: 'DAILY CAPACITY',
                    score: capacityScore,
                    label: capacityLabel,
                  );
                  final schedule = _BriefScore(
                    title: 'SCHEDULE DEMAND',
                    score: scheduleScore,
                    label: scheduleLabel,
                  );
                  if (constraints.maxWidth < 270 ||
                      MediaQuery.textScalerOf(context).scale(12) > 19) {
                    return Column(
                      children: [
                        capacity,
                        const SizedBox(height: 20),
                        schedule,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: capacity),
                      Container(
                        width: 1,
                        height: 140,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: Colors.white24,
                      ),
                      Expanded(child: schedule),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              InkWell(
                onTap: onDetails,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    footer,
                    style: const TextStyle(
                      color: Color(0xFFE8E0FF),
                      fontSize: 12,
                      height: 1.4,
                    ),
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
    required this.score,
    required this.label,
  });
  final String title, label;
  final int? score;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$title: ${score == null ? "unavailable" : "$score out of 100"}. $label',
    child: ExcludeSemantics(
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 82,
            height: 82,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: score == null ? 0 : score!.clamp(0, 100) / 100,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0xFF8270DB),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFD0A5FF)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: FittedBox(
                    child: Text(
                      score == null ? '—' : '$score%',
                      style: const TextStyle(color: Colors.white, fontSize: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ],
      ),
    ),
  );
}

class _BriefLandscape extends CustomPainter {
  const _BriefLandscape();

  @override
  void paint(Canvas canvas, Size size) {
    final sun = Offset(size.width * .72, size.height * .42);
    canvas.drawCircle(
      sun,
      85,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x55FFBCE8), Color(0x00FFBCE8)],
        ).createShader(Rect.fromCircle(center: sun, radius: 85)),
    );
    canvas.drawCircle(sun, 25, Paint()..color = const Color(0x55FFD5EC));
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
  bool shouldRepaint(_BriefLandscape oldDelegate) => false;
}
