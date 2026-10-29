import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:vivordo_health/src/utils/home_stress_card_logic.dart';
import 'package:vivordo_health/src/utils/stress_view.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/whoop_source_badge.dart';

class HomeStressCard extends StatefulWidget {
  const HomeStressCard({
    super.key,
    required this.score,
    required this.updatedAt,
    required this.usual,
    required this.drivers,
    required this.steps,
    required this.loading,
    required this.updating,
    required this.revealScore,
    required this.onInfoTap,
    this.showWhoopBadge = false,
    this.showNumbers = true,
    this.onScanTap,
  });

  final double? score;
  final DateTime? updatedAt;

  /// The person's usual (the stress service's anchor), as on Stress detail.
  final double usual;
  final List<HomeStressDriver> drivers;
  final int steps;
  final bool loading;
  final bool updating;
  final bool revealScore;
  final VoidCallback onInfoTap;
  final bool showWhoopBadge;

  /// False in words mode: a sentence and a level chip instead of the ring
  /// and percentage.
  final bool showNumbers;

  /// Opens a heart scan: offered when there's no reading at all.
  final VoidCallback? onScanTap;

  @override
  State<HomeStressCard> createState() => _HomeStressCardState();
}

class _HomeStressCardState extends State<HomeStressCard>
    with SingleTickerProviderStateMixin {
  static const _palePurple = Color(0xFFC5BCFF);
  // Reads on both the light and dark gradients.
  static const _label = Color(0xD9FFFFFF);
  late final AnimationController _controller;
  late Animation<double> _scoreAnimation;
  late double _targetScore;
  Widget? _cachedCard;
  Brightness? _brightness;

  double get _visibleScore => widget.revealScore ? widget.score ?? 0 : 0;

  /// No reading and no usual to stand in for one: no watch heart data yet.
  bool get _noReading => widget.score == null && !widget.loading;

  @override
  void initState() {
    super.initState();
    _targetScore = _visibleScore;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _scoreAnimation = Tween<double>(
      begin: 0,
      end: _targetScore,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (_targetScore > 0) _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness == brightness && _cachedCard != null) return;
    _brightness = brightness;
    _cachedCard = _buildCard(brightness);
  }

  @override
  void didUpdateWidget(covariant HomeStressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contentChanged =
        widget.score != oldWidget.score ||
        widget.updatedAt != oldWidget.updatedAt ||
        widget.usual != oldWidget.usual ||
        !_sameDrivers(widget.drivers, oldWidget.drivers) ||
        widget.steps != oldWidget.steps ||
        widget.loading != oldWidget.loading ||
        widget.updating != oldWidget.updating ||
        widget.revealScore != oldWidget.revealScore ||
        widget.showWhoopBadge != oldWidget.showWhoopBadge ||
        widget.showNumbers != oldWidget.showNumbers;
    final nextScore = _visibleScore;
    if (nextScore != _targetScore) {
      final currentScore = _scoreAnimation.value;
      _targetScore = nextScore;
      _scoreAnimation = Tween<double>(begin: currentScore, end: nextScore)
          .animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          );
      _controller.forward(from: 0);
    }
    if (contentChanged && _brightness != null) {
      _cachedCard = _buildCard(_brightness!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _cachedCard!;

  Widget _buildCard(Brightness brightness) {
    final displayedScore = widget.revealScore ? widget.score : null;
    final lightMode = brightness == Brightness.light;
    final gradientColors = lightMode
        ? const [Color(0xFF8D78F4), Color(0xFF7664DC), Color(0xFF6054BE)]
        : const [Color(0xFF4327EC), Color(0xFF282078), Color(0xFF181445)];
    final action = homeStressAction(
      score: widget.score,
      drivers: widget.drivers,
      steps: widget.steps,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
            stops: [0, 0.58, 1],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: lightMode
                ? const Color(0xFFA99AF7)
                : const Color(0xFF6253EF),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3C2AD4).withValues(alpha: 0.24),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -70,
              right: -55,
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.035),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // The header's 44 pt info target takes 10 pt from the padding
            // above and the gap below it, so nothing moves.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  if (!widget.showNumbers)
                    _summary(displayedScore)
                  else
                    Row(
                      children: [
                        RepaintBoundary(
                          child: SizedBox(
                            width: 104,
                            height: 104,
                            child: AnimatedBuilder(
                              animation: _scoreAnimation,
                              child: _ringCenter(displayedScore),
                              builder: (context, child) => CustomPaint(
                                painter: _StressRingPainter(
                                  progress: _scoreAnimation.value / 100,
                                ),
                                child: child,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: _summary(displayedScore)),
                      ],
                    ),
                  if (!_noReading) ...[
                    const SizedBox(height: 14),
                    _action(action),
                  ] else if (widget.onScanTap case final onScan?) ...[
                    const SizedBox(height: 14),
                    _scanButton(onScan),
                  ],
                  const SizedBox(height: 12),
                  _footer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _sameDrivers(
    List<HomeStressDriver> current,
    List<HomeStressDriver> previous,
  ) {
    if (identical(current, previous)) return true;
    if (current.length != previous.length) return false;
    for (var index = 0; index < current.length; index++) {
      if (current[index].label != previous[index].label ||
          current[index].type != previous[index].type) {
        return false;
      }
    }
    return true;
  }

  Widget _header() => Row(
    children: [
      const Text(
        'RIGHT NOW',
        style: TextStyle(
          color: _label,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
      const Spacer(),
      Semantics(
        button: true,
        label: 'About your stress score',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onInfoTap,
          child: const SizedBox.square(
            dimension: 44,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.all(3),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: _palePurple,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _ringCenter(double? displayedScore) => Center(
    child: widget.loading
        ? const SizedBox(
            width: 26,
            height: 26,
            child: CupertinoActivityIndicator(color: Colors.white, radius: 13),
          )
        : _noReading
        ? const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.monitor_heart_outlined, color: Colors.white, size: 28),
              SizedBox(height: 4),
              Text(
                'NO READING',
                style: TextStyle(
                  color: _label,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayedScore == null ? '--' : '${displayedScore.round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'STRESS',
                style: TextStyle(
                  color: _label,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
  );

  Widget _summary(double? displayedScore) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (!widget.showNumbers && widget.loading)
        const SizedBox(
          width: 22,
          height: 22,
          child: CupertinoActivityIndicator(color: Colors.white, radius: 11),
        )
      else
        Text(
          (widget.showNumbers
                  ? homeStressLevel(displayedScore)
                  : homeStressSentence(displayedScore, usual: widget.usual)) ??
              'No stress reading yet',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      const SizedBox(height: 3),
      Row(
        children: [
          Icon(
            _noReading ? Icons.watch_outlined : _comparisonIcon(),
            color: _palePurple,
            size: 16,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              switch (widget.score) {
                null =>
                  'Wear a watch or ring that syncs heart rate, or take a '
                      'heart scan.',
                final score when widget.showNumbers => stressUsualHeadline(
                  score,
                  widget.usual,
                ),
                final score => stressUsualHeadlineWords(score, widget.usual),
              },
              style: const TextStyle(
                color: Color(0xFFDCD6FF),
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
      if (!widget.showNumbers)
        if (homeStressLevel(displayedScore) case final level?) ...[
          const SizedBox(height: 8),
          StressLevelChip(level),
        ],
      if (widget.drivers.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final driver in widget.drivers) _driverChip(driver)],
        ),
      ],
    ],
  );

  Widget _action(String action) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF171344).withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.directions_walk_rounded,
          color: Color(0xFF69E987),
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            action,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _scanButton(VoidCallback onScan) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onScan,
      borderRadius: BorderRadius.circular(16),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fingerprint_rounded, color: Color(0xFF3C3489), size: 18),
            SizedBox(width: 8),
            Text(
              'Take a heart scan',
              style: TextStyle(
                color: Color(0xFF3C3489),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _footer() => Row(
    children: [
      if (widget.updating) ...[
        SizedBox(
          width: 12,
          height: 12,
          child: CupertinoActivityIndicator(
            color: Colors.white.withValues(alpha: 0.72),
            radius: 6,
          ),
        ),
        const SizedBox(width: 6),
      ],
      Text(
        _updatedLabel(),
        style: const TextStyle(
          color: _label,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      const Spacer(),
      // The dark badge keeps the white WHOOP mark legible on the gradient.
      if (widget.showWhoopBadge)
        Theme(
          data: VivordoTheme.dark,
          child: const WhoopSourceBadge(compact: true),
        ),
    ],
  );

  String _updatedLabel() {
    if (widget.updating) return 'Updating';
    final updatedAt = widget.updatedAt;
    if (updatedAt == null) {
      return _noReading
          ? 'Readings come from your heart rate and HRV'
          : 'Waiting for data';
    }
    final elapsed = DateTime.now().difference(updatedAt);
    if (elapsed.isNegative || elapsed.inMinutes < 1) return 'Updated now';
    if (elapsed.inMinutes < 60) return 'Updated ${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return 'Updated ${elapsed.inHours}h ago';
    return 'Updated ${updatedAt.month}/${updatedAt.day}';
  }

  IconData _comparisonIcon() {
    final score = widget.score;
    final usual = widget.usual;
    // Flat whenever the text says "About usual".
    if (score == null ||
        (widget.showNumbers
            ? (score - usual).round().abs() <= 1
            : (score - usual).abs() < 5)) {
      return Icons.trending_flat_rounded;
    }
    return score < usual
        ? Icons.trending_down_rounded
        : Icons.trending_up_rounded;
  }

  Widget _driverChip(HomeStressDriver driver) {
    final (icon, color) = switch (driver.type) {
      HomeStressDriverType.sleep => (
        Icons.dark_mode_rounded,
        const Color(0xFF9B8CFF),
      ),
      HomeStressDriverType.heartRate => (
        Icons.favorite_rounded,
        const Color(0xFFFF6BAE),
      ),
      HomeStressDriverType.hrv => (
        Icons.monitor_heart_rounded,
        const Color(0xFFFF6BAE),
      ),
      HomeStressDriverType.activity => (
        Icons.directions_walk_rounded,
        const Color(0xFF69E987),
      ),
      HomeStressDriverType.mood => (
        Icons.mood_rounded,
        const Color(0xFFFFA44D),
      ),
      HomeStressDriverType.other => (
        Icons.insights_rounded,
        const Color(0xFF9B8CFF),
      ),
      HomeStressDriverType.calendar => (
        Icons.calendar_month_rounded,
        const Color(0xFF9B8CFF),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              driver.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StressRingPainter extends CustomPainter {
  const _StressRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 9.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final value = progress.clamp(0.0, 1.0);
    const startAngle = -math.pi / 2;
    const segmentCount = 4;
    const gapAngle = 0.20;
    const segmentSweep = (math.pi * 2 - segmentCount * gapAngle) / segmentCount;
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [Color(0xFF65E47D), Color(0xFFB0F29C)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (var segment = 0; segment < segmentCount; segment++) {
      final angle =
          startAngle + gapAngle / 2 + segment * (segmentSweep + gapAngle);
      canvas.drawArc(rect, angle, segmentSweep, false, trackPaint);
    }

    var remainingSweep = value * segmentSweep * segmentCount;
    for (
      var segment = 0;
      segment < segmentCount && remainingSweep > 0;
      segment++
    ) {
      final angle =
          startAngle + gapAngle / 2 + segment * (segmentSweep + gapAngle);
      final paintedSweep = math.min(segmentSweep, remainingSweep);
      canvas.drawArc(rect, angle, paintedSweep, false, progressPaint);
      remainingSweep -= paintedSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _StressRingPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

/// Words mode's stress colour for a level ("Low"…"High"): light enough for
/// a chip, with its text colour.
(Color, Color) stressLevelColors(String level) => switch (level) {
  'Low' => (const Color(0xFFE1F5EE), const Color(0xFF085041)),
  'Moderate' => (const Color(0xFFFAEEDA), const Color(0xFF633806)),
  'Elevated' => (const Color(0xFFFAECE7), const Color(0xFF712B13)),
  _ => (const Color(0xFFFCEBEB), const Color(0xFF791F1F)),
};

/// Words mode's stress level as a coloured chip, on Home and the stress
/// detail.
class StressLevelChip extends StatelessWidget {
  const StressLevelChip(this.level, {super.key});

  final String level;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = stressLevelColors(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        level,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
