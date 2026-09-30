import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/vivordo_theme.dart';

class WorkoutRestTimer extends StatefulWidget {
  const WorkoutRestTimer({
    super.key,
    this.now = DateTime.now,
    this.onDeadlineChanged,
  });
  final DateTime Function() now;
  final Future<void> Function(DateTime?)? onDeadlineChanged;

  @override
  State<WorkoutRestTimer> createState() => _WorkoutRestTimerState();
}

class _WorkoutRestTimerState extends State<WorkoutRestTimer>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  int _preset = 75;
  int _remaining = 75;
  DateTime? _deadline;
  Timer? _ticker;

  int get _seconds => _deadline == null
      ? _remaining
      : ((_deadline!.difference(widget.now()).inMilliseconds / 1000).ceil())
            .clamp(0, 3600);

  void _tick() {
    if (!mounted) return;
    if (_seconds == 0) {
      _ticker?.cancel();
      _deadline = null;
      _remaining = 0;
      unawaited(HapticFeedback.mediumImpact());
    }
    setState(() {});
  }

  void _toggle() {
    setState(() {
      if (_deadline != null) {
        _remaining = _seconds;
        _deadline = null;
        _ticker?.cancel();
      } else {
        if (_remaining == 0) _remaining = _preset;
        _deadline = widget.now().add(Duration(seconds: _remaining));
        _ticker = Timer.periodic(
          const Duration(milliseconds: 250),
          (_) => _tick(),
        );
      }
    });
    _updateNotification();
  }

  void _adjust(int delta) {
    setState(() {
      final running = _deadline != null;
      _remaining = (_seconds + delta).clamp(15, 3600);
      if (running) {
        _deadline = widget.now().add(Duration(seconds: _remaining));
      } else {
        _preset = _remaining;
      }
    });
    _updateNotification();
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _deadline = null;
      _remaining = _preset;
    });
    _updateNotification();
  }

  void _updateNotification() {
    final update = widget.onDeadlineChanged;
    if (update != null) {
      unawaited(
        update(_deadline).catchError((Object error) {
          debugPrint('Could not update rest timer notification: $error');
        }),
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _deadline = null;
    _updateNotification();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.vivordoColors;
    final seconds = _seconds;
    final label =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    const purple = Color(0xFF6B5CE7);
    final running = _deadline != null;
    final adjustStyle = IconButton.styleFrom(
      foregroundColor: purple,
      side: BorderSide(color: purple.withValues(alpha: .45)),
      minimumSize: const Size(40, 40),
    );
    return Material(
      color: colors.card,
      shape: Border(top: BorderSide(color: colors.border)),
      child: SafeArea(
        top: false,
        child: Padding(
          // The app-wide assistant bubble floats over the bottom-right
          // corner of every screen; keep the controls clear of it.
          padding: const EdgeInsets.fromLTRB(18, 8, 84, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      seconds == 0 ? 'Rest complete' : 'Rest',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: 'Subtract 15 seconds',
                onPressed: () => _adjust(-15),
                icon: const Icon(Icons.remove),
                style: adjustStyle,
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Rest timer, $label',
                button: true,
                child: IconButton.filled(
                  tooltip: running ? 'Pause rest timer' : 'Start rest timer',
                  onPressed: _toggle,
                  icon: Icon(
                    running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  iconSize: 28,
                  style: IconButton.styleFrom(
                    backgroundColor: purple,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(52, 52),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Add 15 seconds',
                onPressed: () => _adjust(15),
                icon: const Icon(Icons.add),
                style: adjustStyle,
              ),
              TextButton(
                onPressed: _reset,
                style: TextButton.styleFrom(foregroundColor: purple),
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
