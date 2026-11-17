import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'vivordo_robot.dart';

/// How Vivordo AI opens from the robot button: iOS's no-bounce spring, about
/// half a second to settle.
final chatRevealSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 195,
  ratio: 1,
);

const _glowColors = [
  Color(0xFF7B6CFF),
  Color(0xFFC36CFF),
  Color(0xFFFF8FB8),
  Color(0xFFFFC48A),
  Color(0xFF6FD0FF),
  Color(0xFF7B6CFF),
];

/// The chat growing out of the robot button in a circle. Inside it the chat
/// settles in from slightly larger, a glowing ring rides the circle's edge
/// and the robot lifts from the button into the header. Dragging the header
/// down shrinks it back.
///
/// [progress] is the raw spring value (0 closed, 1 open). [robotKey] marks
/// the header robot, which [robotHidden] hides while its copy is in flight.
class CircleChatReveal extends StatefulWidget {
  const CircleChatReveal({
    super.key,
    required this.progress,
    required this.origin,
    required this.robotKey,
    required this.robotHidden,
    required this.onDrag,
    required this.onDragEnd,
    required this.child,
  });

  final Animation<double> progress;
  final Offset origin;
  final GlobalKey robotKey;
  final ValueNotifier<bool> robotHidden;

  /// A header drag moved by this many points (positive is down).
  final ValueChanged<double> onDrag;

  /// The drag ended at this speed in points per second (positive is down).
  final ValueChanged<double> onDragEnd;
  final Widget child;

  /// How far a header drag must go to close the chat fully.
  static const dragDistance = 520.0;

  @override
  State<CircleChatReveal> createState() => _CircleChatRevealState();
}

class _CircleChatRevealState extends State<CircleChatReveal>
    with TickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    widget.progress.addListener(_onProgress);
  }

  @override
  void didUpdateWidget(covariant CircleChatReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) {
      oldWidget.progress.removeListener(_onProgress);
      widget.progress.addListener(_onProgress);
    }
  }

  @override
  void dispose() {
    widget.progress.removeListener(_onProgress);
    _spin.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _onProgress() {
    final p = widget.progress.value;
    final moving = p > 0 && p < 1;
    if (moving && !_spin.isAnimating && !_reduceMotion) _spin.repeat();
    if (!moving && _spin.isAnimating) _spin.stop();
    // The header robot shows only while its copy isn't flying.
    final hide = moving && !_reduceMotion;
    if (widget.robotHidden.value != hide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.robotHidden.value =
            widget.progress.value > 0 &&
            widget.progress.value < 1 &&
            !_reduceMotion;
      });
    }
  }

  /// The header robot's box in this widget's coordinates, if laid out.
  Rect? _robotEnd() {
    final robot = widget.robotKey.currentContext?.findRenderObject();
    final self = context.findRenderObject();
    if (robot is! RenderBox || self is! RenderBox) return null;
    if (!robot.hasSize || !robot.attached || !self.attached) return null;
    final topLeft = self.globalToLocal(robot.localToGlobal(Offset.zero));
    final bottomRight = self.globalToLocal(
      robot.localToGlobal(robot.size.bottomRight(Offset.zero)),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  @override
  Widget build(BuildContext context) {
    final headerHeight = MediaQuery.paddingOf(context).top + 64;
    final drag = Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: headerHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: (d) =>
            widget.onDragEnd(d.velocity.pixelsPerSecond.dy),
      ),
    );
    final reduce = _reduceMotion;
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        final o = widget.origin;
        final maxRadius =
            math.sqrt(
              math.pow(math.max(o.dx, size.width - o.dx), 2) +
                  math.pow(math.max(o.dy, size.height - o.dy), 2),
            ) +
            18;
        return AnimatedBuilder(
          animation: Listenable.merge([widget.progress, _spin]),
          child: widget.child,
          builder: (context, child) {
            final p = widget.progress.value.clamp(0.0, 1.0);
            if (reduce) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(opacity: p, child: child),
                  drag,
                ],
              );
            }
            final radius = maxRadius * p;
            final turn = _spin.value * 2 * math.pi;
            final end = p > 0 && p < 1 ? _robotEnd() : null;
            return Stack(
              fit: StackFit.expand,
              children: [
                ClipPath(
                  clipper: _CircleClipper(o, radius),
                  child: Opacity(
                    opacity: .55 + .45 * (p * 1.4).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 1.035 - .035 * p,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                ),
                if (p > 0 && p < 1)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _RingPainter(
                        center: o,
                        radius: radius,
                        turn: turn,
                        opacity: math.min(p * 6, (1 - p) * 8).clamp(0.0, 1.0),
                      ),
                    ),
                  ),
                if (end != null) _flyingRobot(o, end, p),
                drag,
              ],
            );
          },
        );
      },
    );
  }

  /// The robot on its way from the button (46 pt, centred on it) to the
  /// header, on a slight upward arc.
  Widget _flyingRobot(Offset origin, Rect end, double p) {
    final start = Rect.fromCenter(
      center: origin + const Offset(0, 1),
      width: 46,
      height: 46,
    );
    final rect = Rect.lerp(
      start,
      end,
      p,
    )!.shift(Offset(0, -math.sin(math.pi * p) * 26));
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: FittedBox(child: VivordoRobot(size: end.height)),
      ),
    );
  }
}

class _CircleClipper extends CustomClipper<Path> {
  const _CircleClipper(this.center, this.radius);
  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleClipper old) =>
      old.center != center || old.radius != radius;
}

/// A soft ring in Vivordo's colours on the circle's edge.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.center,
    required this.radius,
    required this.turn,
    required this.opacity,
  });
  final Offset center;
  final double radius;
  final double turn;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || radius <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final shader = SweepGradient(
      colors: [for (final c in _glowColors) c.withValues(alpha: opacity)],
      transform: GradientRotation(turn),
    ).createShader(rect);
    canvas.drawCircle(
      center,
      radius - 5,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.radius != radius || old.turn != turn || old.opacity != opacity;
}
