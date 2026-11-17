import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../theme/vivordo_theme.dart';
import 'duo_layout.dart';

/// One event or timed priority on the [DayGrid].
class DayGridBlock {
  const DayGridBlock({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.color,
    this.onTap,
    this.resizable = false,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final Color color;
  final VoidCallback? onTap;

  /// Its bottom edge can be dragged to change how long it is.
  final bool resizable;
}

/// A priority being dragged onto the [DayGrid].
class DayGridDrag {
  const DayGridDrag({required this.id, required this.title, this.minutes = 30});

  final String id;
  final String title;
  final int minutes;
}

/// The grid's arithmetic: minutes of the day against points down the page.
class DayGridScale {
  const DayGridScale(this.hourHeight);

  /// Points per hour. Pinching moves it between [min] and [max].
  final double hourHeight;

  static const min = 26.0;
  static const max = 170.0;

  /// The step times snap to: 15 minutes, or 5 once zoomed far in.
  int get step => hourHeight >= 100 ? 5 : 15;

  double offsetOf(int minutes) => minutes / 60 * hourHeight;

  /// The minute of the day at [dy] points down, snapped to [step] and kept
  /// so [length] minutes still end by midnight.
  int minutesAt(double dy, {int length = 0}) {
    final raw = dy / hourHeight * 60;
    final snapped = (raw / step).round() * step;
    return snapped.clamp(0, 24 * 60 - length);
  }

  /// A length of [minutes] plus [dy] points of dragging, snapped, and at
  /// least one step long.
  int resized(int minutes, double dy) {
    final snapped = ((minutes + dy / hourHeight * 60) / step).round() * step;
    return math.max(step, snapped);
  }

  /// [hourHeight] after a pinch that spread the fingers by [ratio].
  static double zoomed(double hourHeight, double ratio) =>
      (hourHeight * ratio).clamp(min, max);
}

/// Today as a full day by the hour, for an unfolded iPhone Duo: pinch to
/// zoom in to 30, 15 and 5 minute steps, drop a priority on a time, and
/// drag a priority's bottom edge to change its length.
class DayGrid extends StatefulWidget {
  const DayGrid({
    super.key,
    required this.day,
    required this.now,
    required this.blocks,
    required this.onDrop,
    required this.onResize,
    this.height = 420,
  });

  /// Midnight of the day shown.
  final DateTime day;
  final DateTime now;
  final List<DayGridBlock> blocks;
  final void Function(DayGridDrag drag, DateTime start) onDrop;
  final void Function(String id, int minutes) onResize;
  final double height;

  @override
  State<DayGrid> createState() => _DayGridState();
}

class _DayGridState extends State<DayGrid> with SingleTickerProviderStateMixin {
  static const _gutter = 58.0;
  // The zoom last used, kept for the life of the app.
  static double _hourHeight = 46;

  late final ScrollController _scroll = ScrollController(
    // Opens just above now.
    initialScrollOffset: math.max(
      0,
      DayGridScale(_hourHeight).offsetOf(_minutesOf(widget.now)) -
          1.6 * _hourHeight,
    ),
  );
  final _content = GlobalKey();
  final _pointers = <int, Offset>{};
  ({double distance, double hourHeight, double anchor, double focal})? _pinch;

  /// Where a dragged priority would land, in minutes of the day.
  ({int start, DayGridDrag drag})? _ghost;

  /// A block being resized and its length so far.
  ({String id, int minutes, double dy, int from})? _resize;

  // Just after an unfold the grid opens out: it waits out iOS's fade, then
  // grows from a short card with the hours packed tight.
  late final _opening = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );
  late final _grow = CurvedAnimation(
    parent: _opening,
    curve: const Interval(.3, 1, curve: Curves.easeOutCubic),
  );
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    if (DuoUnfold.justNow && !MediaQuery.disableAnimationsOf(context)) {
      _opening
        ..addListener(() => setState(() {}))
        ..forward(from: 0);
    }
  }

  int _minutesOf(DateTime t) => t.difference(widget.day).inMinutes;
  DayGridScale get _scale => DayGridScale(
    _opening.isCompleted ? _hourHeight : 20 + (_hourHeight - 20) * _grow.value,
  );
  double get _height => _opening.isCompleted
      ? widget.height
      : 150 + (widget.height - 150) * _grow.value;

  @override
  void dispose() {
    _grow.dispose();
    _opening.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Pinch to zoom, keeping the time under the fingers where it is ──────

  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length != 2) return;
    final [a, b] = _pointers.values.toList();
    final focal = (a.dy + b.dy) / 2;
    setState(
      () => _pinch = (
        distance: math.max(1, (a - b).distance),
        hourHeight: _hourHeight,
        anchor: (_scroll.offset + focal) / _hourHeight,
        focal: focal,
      ),
    );
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final pinch = _pinch;
    if (pinch == null || _pointers.length != 2) return;
    final [a, b] = _pointers.values.toList();
    setState(
      () => _hourHeight = DayGridScale.zoomed(
        pinch.hourHeight,
        (a - b).distance / pinch.distance,
      ),
    );
    final max = 24 * _hourHeight + 24 - widget.height;
    _scroll.jumpTo(
      (pinch.anchor * _hourHeight - pinch.focal).clamp(0, math.max(0, max)),
    );
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pinch != null && _pointers.length < 2) setState(() => _pinch = null);
  }

  // ── Dropping a priority on a time ───────────────────────────────────────

  int? _dropMinutes(Offset global, DayGridDrag drag) {
    final box = _content.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return _scale.minutesAt(box.globalToLocal(global).dy, length: drag.minutes);
  }

  void _dragMoved(DragTargetDetails<DayGridDrag> details) {
    final start = _dropMinutes(details.offset, details.data);
    if (start == null) return;
    if (_ghost?.start != start) {
      setState(() => _ghost = (start: start, drag: details.data));
    }
    // Near the top or bottom edge the day scrolls under the finger.
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final y = box.globalToLocal(details.offset).dy;
    final nudge = y < 36
        ? -14.0
        : y > widget.height - 36
        ? 14.0
        : 0.0;
    if (nudge != 0) {
      _scroll.jumpTo(
        (_scroll.offset + nudge).clamp(0, _scroll.position.maxScrollExtent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final scale = _scale;
    final time = DateFormat('h:mm a');
    return Container(
      height: _height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: DragTarget<DayGridDrag>(
        onMove: _dragMoved,
        onLeave: (_) => setState(() => _ghost = null),
        onAcceptWithDetails: (details) {
          final start = _dropMinutes(details.offset, details.data);
          setState(() => _ghost = null);
          if (start != null) {
            widget.onDrop(
              details.data,
              widget.day.add(Duration(minutes: start)),
            );
          }
        },
        builder: (context, _, _) => Listener(
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: _pointerUp,
          child: SingleChildScrollView(
            controller: _scroll,
            // Two fingers zoom; they must not scroll as well.
            physics: _pinch != null
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              key: _content,
              height: 24 * scale.hourHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GridPainter(
                        scale: scale,
                        gutter: _gutter,
                        line: colors.border,
                        label: colors.textSecondary,
                        textScaler: MediaQuery.textScalerOf(
                          context,
                        ).clamp(maxScaleFactor: 1.3),
                      ),
                    ),
                  ),
                  for (final block in widget.blocks) _block(block, scale, time),
                  // Now, across the whole day.
                  Positioned(
                    top: scale.offsetOf(_minutesOf(widget.now)) - 1,
                    left: _gutter - 6,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(height: 2, color: colors.danger),
                    ),
                  ),
                  if (_ghost case final ghost?)
                    Positioned(
                      top: scale.offsetOf(ghost.start),
                      left: _gutter,
                      right: 8,
                      height: math.max(22, scale.offsetOf(ghost.drag.minutes)),
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: VivordoTheme.brand.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: VivordoTheme.brand,
                              width: 2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                time.format(
                                  widget.day.add(
                                    Duration(minutes: ghost.start),
                                  ),
                                ),
                                maxLines: 1,
                                style: const TextStyle(
                                  color: VivordoTheme.brand,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
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
      ),
    );
  }

  Widget _block(DayGridBlock block, DayGridScale scale, DateFormat time) {
    final start = _minutesOf(block.start).clamp(0, 24 * 60);
    final resizing = _resize?.id == block.id ? _resize : null;
    final minutes =
        resizing?.minutes ?? (_minutesOf(block.end).clamp(0, 24 * 60) - start);
    final end = widget.day.add(Duration(minutes: start + minutes));
    final height = math.max(22.0, scale.offsetOf(minutes));
    return Positioned(
      top: scale.offsetOf(start),
      left: _gutter,
      right: 8,
      height: height,
      child: Semantics(
        button: block.onTap != null,
        label:
            '${block.title}, ${time.format(block.start)} to ${time.format(end)}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: block.onTap,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: block.color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: block.color, width: 4)),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                  child: Text(
                    height < 38
                        ? block.title
                        : '${block.title}\n${time.format(block.start)} – ${time.format(end)}',
                    maxLines: height < 38 ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.vivordoColors.textPrimary,
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (block.resizable)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 16,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) => setState(
                        () => _resize = (
                          id: block.id,
                          minutes: minutes,
                          dy: 0,
                          from: minutes,
                        ),
                      ),
                      onVerticalDragUpdate: (d) {
                        final r = _resize;
                        if (r == null) return;
                        final dy = r.dy + d.delta.dy;
                        setState(
                          () => _resize = (
                            id: r.id,
                            minutes: math.min(
                              24 * 60 - start,
                              scale.resized(r.from, dy),
                            ),
                            dy: dy,
                            from: r.from,
                          ),
                        );
                      },
                      onVerticalDragEnd: (_) {
                        final r = _resize;
                        setState(() => _resize = null);
                        if (r != null && r.minutes != r.from) {
                          widget.onResize(r.id, r.minutes);
                        }
                      },
                      onVerticalDragCancel: () =>
                          setState(() => _resize = null),
                      child: Center(
                        child: Container(
                          width: 28,
                          height: 3,
                          decoration: BoxDecoration(
                            color: block.color.withValues(alpha: .7),
                            borderRadius: BorderRadius.circular(2),
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
}

/// Hour lines and labels, with half and quarter hours once zoomed in.
class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.scale,
    required this.gutter,
    required this.line,
    required this.label,
    required this.textScaler,
  });

  final DayGridScale scale;
  final double gutter;
  final Color line;
  final Color label;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final hh = scale.hourHeight;
    // Labels every hour; every half hour from 50 pt; every quarter from 100.
    final step = hh >= 100
        ? 15
        : hh >= 50
        ? 30
        : 60;
    final paint = Paint()..strokeWidth = 1;
    for (var m = 0; m <= 24 * 60; m += step) {
      final y = scale.offsetOf(m);
      final hour = m % 60 == 0;
      paint.color = line.withValues(alpha: hour ? 1 : .5);
      canvas.drawLine(Offset(gutter - 6, y), Offset(size.width, y), paint);
      if (m == 24 * 60) continue;
      final h = m ~/ 60, min = m % 60;
      final text = hour
          ? '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}'
          : '${h % 12 == 0 ? 12 : h % 12}:${min.toString().padLeft(2, '0')}';
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: label.withValues(alpha: hour ? 1 : .7),
            fontSize: hour ? 11 : 10,
            fontWeight: hour ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        // Numerals and AM/PM read left to right in every locale.
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout(maxWidth: gutter - 10);
      painter.paint(
        canvas,
        Offset(gutter - 10 - painter.width, y - painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.scale.hourHeight != scale.hourHeight ||
      old.line != line ||
      old.label != label ||
      old.textScaler != textScaler;
}
