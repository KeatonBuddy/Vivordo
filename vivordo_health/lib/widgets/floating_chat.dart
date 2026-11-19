import 'package:flutter/material.dart';

/// Where a floating box may sit on an unfolded iPhone Duo: anywhere on
/// screen, but wholly on one half, so nothing lies across the hinge.
///
/// [screen] is the window, [rail] the tab strip's width on the right edge,
/// [top] the status area. Sizes keep to [minSize] or more.
class FloatingBoxBounds {
  const FloatingBoxBounds({
    required this.screen,
    this.rail = 0,
    this.top = 0,
    this.bottom = 0,
  });

  final Size screen;
  final double rail;
  final double top;

  /// The keyboard, when it is up.
  final double bottom;

  static const margin = 8.0;
  static const hingeGap = 12.0;
  static const minSize = Size(260, 260);

  double get _hinge => screen.width / 2;
  double get _leftMax => _hinge - hingeGap - margin;
  double get _rightMax => screen.width - rail - margin - (_hinge + hingeGap);

  /// [box] moved, and shrunk if it must be, to lie on the half its centre
  /// is over and clear of the keyboard.
  Rect settle(Rect box) {
    final onLeft = box.center.dx < _hinge;
    final width = box.width.clamp(minSize.width, onLeft ? _leftMax : _rightMax);
    final floor = screen.height - bottom - margin;
    final height = box.height.clamp(
      minSize.height < floor - top - margin
          ? minSize.height
          : floor - top - margin,
      floor - top - margin,
    );
    final minX = onLeft ? margin : _hinge + hingeGap;
    final maxX = onLeft
        ? _hinge - hingeGap - width
        : screen.width - rail - margin - width;
    return Rect.fromLTWH(
      box.left.clamp(minX, maxX),
      box.top.clamp(top + margin, floor - height),
      width,
      height,
    );
  }

  /// [box] while a finger is moving it: on screen, but free to cross the
  /// hinge until it is let go.
  Rect follow(Rect box) => Rect.fromLTWH(
    box.left.clamp(margin, screen.width - rail - margin - box.width),
    box.top.clamp(top + margin, screen.height - margin - box.height),
    box.width,
    box.height,
  );

  /// [box] with its bottom-right corner dragged by [delta]; the far edge
  /// stops at the hinge or the rail, and the bottom at the screen's.
  Rect resize(Rect box, Offset delta) {
    final onLeft = box.center.dx < _hinge;
    final maxRight = onLeft ? _hinge - hingeGap : screen.width - rail - margin;
    return Rect.fromLTWH(
      box.left,
      box.top,
      (box.width + delta.dx).clamp(minSize.width, maxRight - box.left),
      (box.height + delta.dy).clamp(
        minSize.height,
        screen.height - margin - box.top,
      ),
    );
  }
}

/// How the box looks part way through opening: pulled out of the robot
/// button as a bubble that swells into the window, the way a minimised
/// window leaves the Dock. [t] runs 0 (the button) to 1 (the box).
///
/// [offset] moves the box's centre, [scaleX] and [scaleY] size it, and
/// [radius] is its corner on screen: a circle the button's size at first.
({Offset offset, double scaleX, double scaleY, double radius}) chatMorph({
  required double t,
  required Rect box,
  required Offset origin,
  double button = 62,
}) {
  final p = t.clamp(0.0, 1.0);
  // It reaches out sideways first, then fills out downwards.
  final across = Curves.easeOutCubic.transform(p);
  final down = Curves.easeInOutCubic.transform(p);
  final startX = (button / box.width).clamp(0.0, 1.0);
  final startY = (button / box.height).clamp(0.0, 1.0);
  return (
    offset: Offset(
      (origin.dx - box.center.dx) * (1 - across),
      (origin.dy - box.center.dy) * (1 - down),
    ),
    scaleX: startX + (1 - startX) * across,
    scaleY: startY + (1 - startY) * down,
    radius: button / 2 + (26 - button / 2) * p,
  );
}

/// Vivordo AI on an unfolded iPhone Duo: a box above both panes instead of
/// a full screen. Drag the header to move it and the bottom-right corner to
/// resize it; let go and it settles on one half.
///
/// [reveal] runs 0 (shut) to 1 (open). Place it in a [Stack].
class FloatingChat extends StatefulWidget {
  const FloatingChat({
    super.key,
    required this.reveal,
    required this.open,
    required this.rail,
    required this.child,
    this.origin,
  });

  /// The centre of the robot button the box opens out of and closes
  /// back into; without it the box grows from its own centre.
  final Offset? origin;

  final Animation<double> reveal;
  final bool open;
  final double rail;
  final Widget child;

  @override
  State<FloatingChat> createState() => _FloatingChatState();
}

class _FloatingChatState extends State<FloatingChat> {
  // Where it was last left; it starts on the left half, away from what the
  // closed phone was showing. Kept for the life of the app.
  static Rect _box = const Rect.fromLTWH(64, 120, 340, 440);
  bool _moving = false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bounds = FloatingBoxBounds(
      screen: media.size,
      rail: widget.rail,
      top: media.padding.top,
      bottom: media.viewInsets.bottom,
    );
    final box = _moving ? _box : bounds.settle(_box);
    final colors = Theme.of(context).colorScheme;
    return AnimatedPositioned.fromRect(
      rect: box,
      duration: _moving ? Duration.zero : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: TickerMode(
        enabled: widget.open,
        child: IgnorePointer(
          ignoring: !widget.open,
          child: AnimatedBuilder(
            animation: widget.reveal,
            builder: (context, child) {
              final t = widget.reveal.value.clamp(0.0, 1.0);
              final morph = chatMorph(
                t: MediaQuery.disableAnimationsOf(context) ? 1 : t,
                box: box,
                origin: widget.origin ?? box.center,
              );
              // The corner is set on screen, so undo the stretch for it.
              final corner = BorderRadius.all(
                Radius.elliptical(
                  morph.radius / morph.scaleX,
                  morph.radius / morph.scaleY,
                ),
              );
              return Opacity(
                // Solid almost at once, so it reads as one shape growing.
                opacity: (t * 4).clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: morph.offset,
                  child: Transform.scale(
                    scaleX: morph.scaleX,
                    scaleY: morph.scaleY,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: corner,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x4D14103C),
                            blurRadius: 50,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: ClipRRect(borderRadius: corner, child: child),
                    ),
                  ),
                ),
              );
            },
            child: Stack(
              children: [
                // The box has no status bar or keyboard of its own; it
                // moves clear of the keyboard instead.
                Positioned.fill(
                  child: MediaQuery(
                    data: media.copyWith(
                      padding: EdgeInsets.zero,
                      viewPadding: EdgeInsets.zero,
                      viewInsets: EdgeInsets.zero,
                    ),
                    child: widget.child,
                  ),
                ),
                // The header between its buttons moves the box.
                Positioned(
                  top: 0,
                  left: 52,
                  right: 110,
                  height: 56,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => setState(() => _moving = true),
                    onPanUpdate: (d) => setState(
                      () => _box = bounds.follow(_box.shift(d.delta)),
                    ),
                    onPanEnd: (_) => _letGo(bounds),
                    onPanCancel: () => _letGo(bounds),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  width: 30,
                  height: 30,
                  child: Semantics(
                    label: 'Resize Vivordo AI',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => setState(() => _moving = true),
                      onPanUpdate: (d) =>
                          setState(() => _box = bounds.resize(_box, d.delta)),
                      onPanEnd: (_) => _letGo(bounds),
                      onPanCancel: () => _letGo(bounds),
                      child: Align(
                        alignment: const Alignment(.3, .3),
                        child: Icon(
                          Icons.south_east_rounded,
                          size: 14,
                          color: colors.onSurface.withValues(alpha: .35),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _letGo(FloatingBoxBounds bounds) => setState(() {
    _moving = false;
    _box = bounds.settle(_box);
  });
}
