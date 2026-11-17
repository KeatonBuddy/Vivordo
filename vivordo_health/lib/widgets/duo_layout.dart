import 'dart:async';

import 'package:flutter/material.dart';
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

  /// Propped like a tent: the outer display on its side.
  // ponytail: read from the window alone, so a closed Duo turned sideways
  // in the hand counts too; add the hinge angle if that needs telling apart.
  static bool tentOf(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return fromSize(size) == closed && size.width > size.height;
  }

  /// Room for two panes, one each side of the hinge.
  bool get twoPane => this == openLandscape;
}

/// Two columns with the gutter on the hinge, so nothing sits on the crease.
///
/// Unfolding carries the outer display's screen to the right half, so
/// [cover] (what the closed phone was showing) takes the right pane and
/// [extra] (what the open phone adds) takes the left.
///
/// [leftInset] is how far this widget's left edge is from the window's
/// left edge (the page padding), which places the hinge at the window centre.
class DuoPanes extends StatelessWidget {
  const DuoPanes({
    super.key,
    required this.cover,
    required this.extra,
    this.leftInset = 0,
    this.gutter = 32,
    this.opens = true,
  });

  final Widget cover;
  final Widget extra;

  /// Plays the opening when the phone has just been unfolded. Off for
  /// screens that should hold still: a scan, a workout in progress.
  final bool opens;
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
            SizedBox(
              width: leftWidth,
              child: opens ? _DuoOpening(child: extra) : extra,
            ),
            SizedBox(width: gutter),
            Expanded(child: cover),
          ],
        );
      },
    );
  }
}

/// When the phone was last unfolded, so the panes that appear with it can
/// open from the fold instead of popping in.
class DuoUnfold {
  static DuoPose _last = DuoPose.none;
  static DateTime? _at;

  /// Counts unfolds. Parts of a screen that were already there when the
  /// phone opened (kept by a key as the layout changed) listen to this to
  /// play their opening.
  static final opened = ValueNotifier<int>(0);

  /// Call with the pose on every build of the app's root screen.
  static void track(DuoPose pose) {
    if (_last == DuoPose.closed && pose == DuoPose.openLandscape) {
      _at = DateTime.now();
      // After this build, which is still laying the panes out.
      WidgetsBinding.instance.addPostFrameCallback((_) => opened.value++);
    }
    _last = pose;
  }

  /// When the phone last opened, to tell one unfold from the next.
  static DateTime? get at => _at;

  /// True for a moment after the phone opens.
  static bool get justNow =>
      _at != null &&
      DateTime.now().difference(_at!) < const Duration(milliseconds: 1500);
}

/// The new pane's opening: it is revealed leftward from the fold while
/// what the closed phone showed stays put on the right. Plays once, when
/// the panes appear just after an unfold, and not with Reduce Motion.
class _DuoOpening extends StatefulWidget {
  const _DuoOpening({required this.child});

  final Widget child;

  @override
  State<_DuoOpening> createState() => _DuoOpeningState();
}

class _DuoOpeningState extends State<_DuoOpening>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );
  // Waits while iOS fades the display in, or the reveal plays unseen.
  late final _reveal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(.35, 1, curve: Curves.easeOutCubic),
  );
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    if (DuoUnfold.justNow && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      if (_controller.isCompleted) return child!;
      final t = _reveal.value;
      return ClipRect(
        clipper: _FromFold(t),
        child: Opacity(opacity: t, child: child),
      );
    },
  );
}

/// Shows the right-hand [shown] share of the pane, growing from the fold.
class _FromFold extends CustomClipper<Rect> {
  const _FromFold(this.shown);

  final double shown;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(size.width * (1 - shown), 0, size.width, size.height);

  @override
  bool shouldReclip(_FromFold old) => old.shown != shown;
}

/// A piece of a screen that animates in when the phone has just been
/// unfolded: a bar that fills from the left ([DuoUnfoldIn.wipe]) or rises
/// from its base ([DuoUnfoldIn.rise]). It waits out iOS's fade first, as
/// the panes do. At any other time, and with Reduce Motion, it is still.
class DuoUnfoldIn extends StatefulWidget {
  const DuoUnfoldIn.wipe({super.key, required this.child})
    : rises = false,
      order = 0;

  /// [order] runs 0 to 1 across a row of these, so they rise in turn.
  const DuoUnfoldIn.rise({super.key, required this.child, this.order = 0})
    : rises = true;

  final Widget child;
  final bool rises;
  final double order;

  @override
  State<DuoUnfoldIn> createState() => _DuoUnfoldInState();
}

class _DuoUnfoldInState extends State<DuoUnfoldIn>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
    value: 1,
  );
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    if (DuoUnfold.justNow) _play();
  }

  void _play() {
    if (mounted && !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void initState() {
    super.initState();
    DuoUnfold.opened.addListener(_play);
  }

  @override
  void dispose() {
    DuoUnfold.opened.removeListener(_play);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      if (_controller.isCompleted) return child!;
      // Still for the first quarter; then each takes about half the
      // run, later ones in a row starting later.
      final begin = .25 + .3 * widget.order.clamp(0.0, 1.0);
      final t = Curves.easeOutCubic.transform(
        ((_controller.value - begin) / .45).clamp(0.0, 1.0),
      );
      return widget.rises
          ? Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.diagonal3Values(1, t, 1),
              child: child,
            )
          : ClipRect(clipper: _FromLeft(t), child: child);
    },
  );
}

/// Shows the left-hand [shown] share of its child.
class _FromLeft extends CustomClipper<Rect> {
  const _FromLeft(this.shown);

  final double shown;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, 0, size.width * shown, size.height);

  @override
  bool shouldReclip(_FromLeft old) => old.shown != shown;
}

/// The pane across the hinge as a place to open screens: a list keeps the
/// right pane and what it opens takes the left, replacing what was there.
/// Off a Duo there is no [DuoDetail] above and screens are pushed as usual.
class DuoDetail extends InheritedWidget {
  const DuoDetail({super.key, required this.detail, required super.child});

  /// The screen open in the left pane, or null for its home.
  final ValueNotifier<Widget?> detail;

  static void open(BuildContext context, Widget screen) {
    final detail = context.getInheritedWidgetOfExactType<DuoDetail>()?.detail;
    if (detail == null) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => screen));
    } else {
      detail.value = screen;
    }
  }

  /// The left pane itself: [home] until something is opened over it. A
  /// navigator of its own, so the opened screen's back button returns here.
  static Widget pane(ValueNotifier<Widget?> detail, Widget home) =>
      ValueListenableBuilder<Widget?>(
        valueListenable: detail,
        builder: (context, screen, _) => Navigator(
          pages: [
            MaterialPage<void>(key: const ValueKey('home'), child: home),
            if (screen != null)
              MaterialPage<void>(key: ObjectKey(screen), child: screen),
          ],
          onDidRemovePage: (page) {
            // Replacing one screen with another also removes a page.
            if (page is MaterialPage && identical(page.child, detail.value)) {
              detail.value = null;
            }
          },
        ),
      );

  @override
  bool updateShouldNotify(DuoDetail oldWidget) => false;
}
