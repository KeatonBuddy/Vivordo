import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:foldable/foldable.dart';

export 'package:foldable/foldable.dart' show HingeStatus;

/// The hinge, from package:foldable. [status] stays null off a Duo, so every
/// other phone reads as "no hinge" without asking the platform again.
class DuoHinge {
  static final status = ValueNotifier<HingeStatus?>(null);
  static StreamSubscription<HingeStatus>? _subscription;

  /// Call once at launch; a no-op anywhere but a Duo.
  static Future<void> start() async {
    if (_subscription != null || !await Foldable.isFoldable) return;
    status.value = await Foldable.hingeStatus;
    _subscription = Foldable.hingeStatusStream.listen(
      (next) => status.value = next,
    );
  }

  /// Tabletop: the inner display held upright with the hinge part way open,
  /// so one half lies flat and the other stands. Listen to [status] to
  /// rebuild when it changes.
  static bool tabletopOf(BuildContext context) =>
      status.value == HingeStatus.partiallyOpen &&
      DuoPose.of(context) == DuoPose.openPortrait;
}

/// Where the app is on an iPhone Duo, read from the window size alone.
///
/// Both Duo displays are about 1:1.42 and at least 466 pt across, while every
/// other iPhone is over 2:1, so no plugin is needed to tell them apart.
/// Outer display 466×678; inner display 890×626 opened flat like a book
/// (hinge vertical) or 626×890 turned upright (hinge horizontal).
enum DuoPose {
  /// Not a Duo: the usual phone layout.
  none,

  /// The outer display, closed.
  closed,

  /// Opened like a book, hinge vertical.
  openLandscape,

  /// Opened and turned upright, hinge horizontal.
  openPortrait;

  static DuoPose of(BuildContext context) =>
      fromSize(MediaQuery.sizeOf(context));

  static DuoPose fromSize(Size size) {
    final short = size.shortestSide;
    final long = size.longestSide;
    // ponytail: size heuristic; swap for the hinge API (package:foldable)
    // when the tabletop pose needs the angle.
    if (short < 440 || long / short > 1.6) return none;
    if (short < 600) return closed;
    return size.width > size.height ? openLandscape : openPortrait;
  }

  /// iOS 27.1 puts tab bars in a strip on the trailing edge on the outer
  /// display and on the inner one in landscape; upright it is a bottom bar.
  bool get trailingTabBar => this == closed || this == openLandscape;

  /// Room for two panes, one each side of the hinge.
  bool get twoPane => this == openLandscape;
}

/// Two columns with the gutter on the hinge, so nothing sits on the crease.
///
/// [leftInset] is how far this widget's left edge is from the window's
/// left edge (the page padding), which places the hinge at the window centre.
class DuoPanes extends StatelessWidget {
  const DuoPanes({
    super.key,
    required this.left,
    required this.right,
    this.leftInset = 0,
    this.gutter = 32,
  });

  final Widget left;
  final Widget right;
  final double leftInset;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final hinge = MediaQuery.sizeOf(context).width / 2 - leftInset;
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftWidth = (hinge - gutter / 2).clamp(0.0, constraints.maxWidth);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: leftWidth, child: left),
            SizedBox(width: gutter),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}
