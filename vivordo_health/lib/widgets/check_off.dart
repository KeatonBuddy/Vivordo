import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Plays a priority's check-off before it is saved. Saving moves the row to
/// "completed" at once, so the row used to leave the list in the frame it
/// was tapped, before its tick could show. Here the tick fills and the title
/// strikes through ([builder]'s `checked`), it holds, the row closes, and
/// only then [onToggle] saves. A second tap during the hold takes it back.
/// Unchecking, and Reduce Motion, go straight to [onToggle].
class CheckOff extends StatefulWidget {
  const CheckOff({
    super.key,
    required this.completed,
    required this.onToggle,
    required this.builder,
  });

  /// Whether the priority is saved as done.
  final bool completed;
  final Future<void> Function() onToggle;
  final Widget Function(BuildContext context, bool checked, VoidCallback toggle)
  builder;

  static const hold = Duration(milliseconds: 550);
  static const close = Duration(milliseconds: 250);

  @override
  State<CheckOff> createState() => _CheckOffState();
}

class _CheckOffState extends State<CheckOff> {
  var _checked = false;
  var _closing = false;

  /// Checked here but not yet saved.
  var _pending = false;
  var _run = 0;

  Future<void> _toggle() async {
    if (_closing) return;
    if (_checked) {
      // Tapped again during the hold: a mis-tap, nothing was saved.
      _run++;
      _pending = false;
      setState(() => _checked = false);
      return;
    }
    if (widget.completed || MediaQuery.disableAnimationsOf(context)) {
      return widget.onToggle();
    }
    final run = ++_run;
    unawaited(HapticFeedback.lightImpact());
    _pending = true;
    setState(() => _checked = true);
    await Future<void>.delayed(CheckOff.hold);
    if (!mounted || run != _run) return;
    setState(() => _closing = true);
    await Future<void>.delayed(CheckOff.close);
    if (!mounted || run != _run) return;
    _pending = false;
    await widget.onToggle();
    // Still here: the save failed, or the row stays in this list when done.
    if (mounted) {
      setState(() {
        _checked = false;
        _closing = false;
      });
    }
  }

  @override
  void dispose() {
    // Scrolled or navigated away mid-animation: the check still counts.
    if (_pending) unawaited(widget.onToggle());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: _closing ? 0 : 1),
    // Reopening (a failed save) is not animated.
    duration: _closing ? CheckOff.close : Duration.zero,
    curve: Curves.easeInOut,
    // The row fades as its space closes.
    builder: (context, open, child) => ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: open,
        child: Opacity(opacity: open, child: child),
      ),
    ),
    child: widget.builder(context, _checked || widget.completed, _toggle),
  );
}
