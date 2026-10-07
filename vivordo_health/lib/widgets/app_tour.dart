import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/vivordo_theme.dart';
import 'vivordo_robot.dart';

/// Each screen's tour runs once, the first time that screen is shown. The
/// user document keeps `tours: {screen: version}`; bump this to run them all
/// again.
const kTourVersion = 1;

/// Whether [screen]'s tour still needs to run for these saved versions.
bool needsTour(Map<String, dynamic>? seenTours, String screen) =>
    ((seenTours?[screen] as num?) ?? 0) < kTourVersion;

DocumentReference<Map<String, dynamic>>? get _userRef {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instance.collection('users').doc(uid);
}

Future<void> markTourSeen(String screen) async => _userRef?.set({
  'tours': {screen: kTourVersion},
  'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));

/// Forgets every tour, so each runs again on its next visit.
Future<void> resetTours() async => _userRef?.set({
  'tours': FieldValue.delete(),
  'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));

class TourStep {
  const TourStep(this.text, {this.tab, this.target, this.crop, this.pose});
  final String text;

  /// Tab to switch to before this step.
  final int? tab;

  /// Widget the step spotlights.
  final GlobalKey? target;

  /// Narrows the spotlight to part of [target].
  final Rect Function(Rect target)? crop;

  /// Overrides the pose picked from where the target sits.
  final RobotPose? pose;
}

/// Vivordo AI flies around the live app, spotlighting one thing per step.
/// Everything under it is dimmed and inert; tapping the spotlight or Next
/// moves on. The robot enters from and leaves into [home], the chat button.
class AppTour extends StatefulWidget {
  const AppTour({
    super.key,
    required this.steps,
    required this.onSelectTab,
    required this.onFinished,
    this.onStepChanged,
    this.home,
  });
  final List<TourStep> steps;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onFinished;

  /// Reports each step's index as it starts.
  final ValueChanged<int>? onStepChanged;
  final GlobalKey? home;

  /// Set from Settings to run the tour again; main navigation listens.
  static final replayRequested = ValueNotifier<bool>(false);

  @override
  State<AppTour> createState() => _AppTourState();
}

class _AppTourState extends State<AppTour> with SingleTickerProviderStateMixin {
  static const _robotHeight = 150.0;
  static const _robotWidth = _robotHeight * VivordoRobotRig.aspect;
  static const _homeScale = 64 / _robotHeight;
  static const _gap = 20.0;

  late final _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  double _scale = _homeScale;
  Rect? _hole;
  RobotPose _pose = RobotPose.idle;
  int _index = -1;
  int _shown = 0;
  Timer? _typing;
  bool _leaving = false;
  // One of these is set: the bubble's distance from the top or bottom.
  double? _bubbleTop;
  double? _bubbleBottom;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);
  TourStep? get _step =>
      _index >= 0 && _index < widget.steps.length ? widget.steps[_index] : null;
  bool get _talking => _step != null && _shown < _step!.text.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final size = MediaQuery.sizeOf(context);
      final home = _homeRect(size);
      _from = _to = home.center - const Offset(_robotWidth, _robotHeight) / 2;
      _scale = _homeScale;
      _hole = Rect.fromCenter(center: home.center, width: 0, height: 0);
      setState(() {});
      await _go(0);
    });
  }

  @override
  void dispose() {
    _fly.dispose();
    _typing?.cancel();
    super.dispose();
  }

  /// The chat button's rect, or where it would be.
  Rect _homeRect(Size size) =>
      _rectOf(widget.home) ??
      Rect.fromLTWH(size.width - 94, size.height - 180, 64, 64);

  Rect? _rectOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    final self = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || self == null) return null;
    final topLeft = self.globalToLocal(box.localToGlobal(Offset.zero));
    return topLeft & box.size;
  }

  Future<void> _go(int index) async {
    _typing?.cancel();
    if (index >= widget.steps.length) return _leave();
    final step = widget.steps[index];
    widget.onStepChanged?.call(index);
    if (step.tab != null) widget.onSelectTab(step.tab!);
    // Let the tab switch lay out before measuring its widgets.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final topZone = padding.top + 56;
    // The floating nav bar sits in the bottom 110pt.
    const navZone = 110.0;
    // Rough bubble height, from the line count at the bubble's width.
    final bubbleEstimate = 110.0 + 24 * (step.text.length / 36).ceil();

    // A target further down the screen scrolls into view first. A tall one
    // goes to the top, so as much of it as possible stays uncovered.
    final targetContext = step.target?.currentContext;
    final targetBox = targetContext?.findRenderObject() as RenderBox?;
    final tall =
        targetBox != null &&
        targetBox.hasSize &&
        targetBox.size.height >
            size.height - topZone - navZone - _robotHeight - _gap * 2;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: tall ? 0 : .2,
        duration: _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    var target = _rectOf(step.target);
    if (target != null && step.crop != null) target = step.crop!(target);
    // A target scrolled off screen gets no spotlight; the robot just talks.
    if (target != null && !(Offset.zero & size).overlaps(target)) target = null;

    Offset robot;
    RobotPose pose;
    var scale = 1.0;
    if (target == null) {
      robot = _clampRobot(
        Offset(
          (size.width - _robotWidth) / 2,
          size.height * .36 - _robotHeight / 2,
        ),
        size,
        topZone,
        navZone,
      );
      pose = step.pose ?? (index == 0 ? RobotPose.wave : RobotPose.idle);
      _bubbleTop = robot.dy + _robotHeight + 12;
      _bubbleBottom = null;
    } else {
      final needed = _robotHeight + _gap + bubbleEstimate;
      final freeAbove = target.top - topZone;
      final freeBelow = size.height - navZone - target.bottom;
      final leftOfTarget = target.center.dx > size.width / 2;
      final above = freeAbove > freeBelow;
      final x = leftOfTarget
          ? target.left - _robotWidth - _gap
          : target.right + _gap;
      if (freeBelow >= needed || freeAbove >= needed) {
        // Room on one side: robot beside the target, bubble beyond it.
        robot = Offset(
          x,
          above ? target.top - _robotHeight - _gap : target.bottom + _gap,
        );
        robot = _clampRobot(robot, size, topZone, navZone);
        _bubbleTop = above ? null : robot.dy + _robotHeight + 12;
        _bubbleBottom = above ? size.height - robot.dy + 12 : null;
      } else {
        // Tight screen: the bubble takes the roomier zone against the
        // screen edge, and a smaller robot stands between it and the
        // target, over the target's edge if it must. The robot shrinks
        // about its feet, so its drawn top sits 45pt below its layout top.
        scale = .7;
        const shrink = _robotHeight * .3;
        if (above) {
          _bubbleTop = topZone;
          _bubbleBottom = null;
          robot = Offset(x, topZone + bubbleEstimate + 8 - shrink);
        } else {
          _bubbleTop = null;
          _bubbleBottom = navZone + 8;
          robot = Offset(
            x,
            size.height - navZone - 16 - bubbleEstimate - _robotHeight,
          );
        }
        robot = Offset(
          robot.dx.clamp(16.0, size.width - _robotWidth - 16),
          robot.dy,
        );
      }
      pose =
          step.pose ??
          (leftOfTarget ? RobotPose.pointRight : RobotPose.pointLeft);
    }

    setState(() {
      _index = index;
      _shown = 0;
      _pose = pose;
      _scale = scale;
      _hole =
          target ??
          Rect.fromCenter(
            center: robot + const Offset(_robotWidth, _robotHeight) / 2,
            width: 0,
            height: 0,
          );
      _moveTo(robot);
    });
    _type(step.text);
  }

  Offset _clampRobot(Offset robot, Size size, double topZone, double navZone) =>
      Offset(
        robot.dx.clamp(16.0, size.width - _robotWidth - 16),
        robot.dy.clamp(topZone, size.height - _robotHeight - navZone),
      );

  void _moveTo(Offset to) {
    _from = _position;
    _to = to;
    _fly.duration = _reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 650);
    _fly.forward(from: 0);
  }

  /// Where the robot is right now, on its arc between [_from] and [_to].
  Offset get _position {
    final t = Curves.easeInOutCubic.transform(_fly.value);
    final arc = _reduceMotion ? 0.0 : math.sin(math.pi * _fly.value) * 48;
    return Offset.lerp(_from, _to, t)! - Offset(0, arc);
  }

  void _type(String text) {
    if (_reduceMotion) {
      setState(() => _shown = text.length);
      return;
    }
    _typing = Timer.periodic(const Duration(milliseconds: 24), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _shown = math.min(_shown + 1, text.length));
      if (_shown == text.length) timer.cancel();
    });
  }

  void _next() {
    if (_leaving) return;
    if (_talking) {
      _typing?.cancel();
      setState(() => _shown = _step!.text.length);
      return;
    }
    _go(_index + 1);
  }

  Future<void> _leave() async {
    if (_leaving) return;
    final size = MediaQuery.sizeOf(context);
    final home = _homeRect(size);
    setState(() {
      _leaving = true;
      _pose = RobotPose.idle;
      _scale = _homeScale;
      _hole = Rect.fromCenter(center: home.center, width: 0, height: 0);
      _moveTo(home.center - const Offset(_robotWidth, _robotHeight) / 2);
    });
    await _fly.forward(from: 0);
    if (mounted) widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final step = _step;
    final last = _index == widget.steps.length - 1;
    final motion = _reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 650);
    return Stack(
      children: [
        Positioned.fill(
          child: TweenAnimationBuilder<Rect?>(
            tween: RectTween(end: _hole ?? Rect.zero),
            duration: motion,
            curve: Curves.easeInOutCubic,
            builder: (context, hole, _) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (hole != null && hole.contains(details.localPosition)) {
                  _next();
                }
              },
              child: CustomPaint(painter: _ScrimPainter(hole ?? Rect.zero)),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _fly,
          builder: (context, child) {
            final pos = _position;
            return Positioned(left: pos.dx, top: pos.dy, child: child!);
          },
          child: AnimatedScale(
            scale: _scale,
            alignment: Alignment.bottomCenter,
            duration: motion,
            curve: Curves.easeInOutCubic,
            child: AnimatedOpacity(
              opacity: _leaving ? 0 : 1,
              duration: motion,
              curve: Curves.easeIn,
              child: VivordoRobotRig(
                size: _robotHeight,
                pose: _pose,
                talking: _talking,
              ),
            ),
          ),
        ),
        if (step != null && !_leaving)
          AnimatedPositioned(
            duration: motion,
            curve: Curves.easeInOutCubic,
            left: 20,
            right: 20,
            top: _bubbleTop,
            bottom: _bubbleBottom,
            child: Material(
              color: colors.card,
              elevation: 12,
              shadowColor: Colors.black.withValues(alpha: .4),
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      step.text.substring(0, _shown),
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.4,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '${_index + 1} of ${widget.steps.length}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        if (!last)
                          TextButton(
                            onPressed: _leave,
                            style: TextButton.styleFrom(
                              foregroundColor: colors.textSecondary,
                            ),
                            child: const Text('Skip tour'),
                          ),
                        FilledButton(
                          // While typing, the first tap shows the whole line.
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: VivordoTheme.brand,
                            shape: const StadiumBorder(),
                          ),
                          child: Text(last ? 'Done' : 'Next'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.hole);
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final spot = RRect.fromRectAndRadius(
      hole.inflate(8),
      const Radius.circular(22),
    );
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(spot),
    );
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: .6));
    if (hole.isEmpty) return;
    canvas.drawRRect(
      spot,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = VivordoTheme.brand,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}
