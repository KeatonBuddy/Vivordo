import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/day_fixes.dart';

const _green = Color(0xFF1D9E75);
const _amber = Color(0xFFBA7517);

String _time(DateTime t) => DateFormat.jm().format(t).replaceAll(':00', '');

/// "2 h", "1 h 45".
String _runText(int minutes) => minutes % 60 == 0
    ? '${minutes ~/ 60} h'
    : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';

/// "Ways to lighten today" under My Day's brief when Demand outruns Capacity
/// (docs/scores.md §2). The X hides it until tomorrow.
class DayFixesCard extends StatelessWidget {
  const DayFixesCard({
    super.key,
    required this.fixes,
    required this.onOpen,
    required this.onHide,
  });

  final List<DayFix> fixes;
  final ValueChanged<DayFix> onOpen;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 8),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: .07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'WAYS TO LIGHTEN TODAY',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hide until tomorrow',
                visualDensity: VisualDensity.compact,
                onPressed: onHide,
                icon: Icon(Icons.close_rounded, color: colors.textSecondary),
              ),
            ],
          ),
          for (final fix in fixes) _FixRow(fix: fix, onTap: () => onOpen(fix)),
        ],
      ),
    );
  }
}

class _FixRow extends StatelessWidget {
  const _FixRow({required this.fix, required this.onTap});

  final DayFix fix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final (icon, tint, title, detail) = switch (fix.kind) {
      DayFixKind.movePriority => (
        Icons.event_repeat_rounded,
        VivordoTheme.brand,
        'Move "${fix.title}"',
        'To a lighter day this week',
      ),
      DayFixKind.buffer => (
        Icons.more_time_rounded,
        const Color(0xFF378ADD),
        '15-min buffer before ${fix.title}',
        'Ends the back-to-back after ${fix.after}',
      ),
      DayFixKind.energySlot => (
        Icons.bolt_rounded,
        _green,
        '${fix.title} at ${_time(fix.newStart!)}',
        'Out of a low-energy window, into your best time',
      ),
      DayFixKind.addBreak => (
        Icons.self_improvement_rounded,
        const Color(0xFF0F6E56),
        '15-min break at ${_time(fix.newStart!)}',
        '${fix.beforeRun ? 'Before' : 'After'} ${_runText(fix.runMinutes)} '
            'of back-to-back',
      ),
    };
    final saved = fix.demandSaved.round();
    // Fixes that don't take Demand off say what they do instead.
    final label = saved >= 1
        ? null
        : fix.kind == DayFixKind.addBreak
        ? 'Breather'
        : 'Fits peak';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    detail,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (label == null ? _green : VivordoTheme.brand).withValues(
                  alpha: .12,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label ?? '−$saved',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: label == null ? _green : VivordoTheme.brand,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The confirm sheet for moving an item to a new time (a buffer or a better
/// energy slot): before and after, today's Demand, and any guest warning.
/// Returns true when the person confirms.
Future<bool> showDayFixTimeSheet(
  BuildContext context, {
  required DayFix fix,
  required double demandNow,
  bool recurring = false,
}) async {
  final colors = context.vivordoColors;
  final start = fix.start!, end = fix.end!;
  final newStart = fix.newStart!, newEnd = fix.newEnd!;
  String range(DateTime a, DateTime b) =>
      '${DateFormat.jm().format(a)} – ${DateFormat.jm().format(b)}';
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: colors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        // Clears the floating Vivordo AI button.
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 84),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              switch (fix.kind) {
                DayFixKind.buffer => 'Add 15 minutes before ${fix.title}',
                DayFixKind.addBreak => 'Add a 15-min break',
                _ => 'Move ${fix.title} to ${_time(newStart)}',
              },
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(switch (fix.kind) {
              DayFixKind.buffer =>
                'A breather after ${fix.after}, so the run of meetings '
                    'gets a gap.',
              DayFixKind.addBreak =>
                'A "Break" in your Google Calendar '
                    '${fix.beforeRun ? 'before' : 'after'} ${fix.after}, so '
                    'the time stays free. Breaks don\'t count towards '
                    'Demand or Effort.',
              _ =>
                'Hard work lands in a low-energy window now. '
                    '${_time(newStart)} is in your peak or second wind.',
            }, style: TextStyle(color: colors.textSecondary)),
            const SizedBox(height: 16),
            if (fix.kind == DayFixKind.addBreak)
              _BeforeAfter(before: null, after: range(newStart, newEnd))
            else
              _BeforeAfter(
                before: range(start, end),
                after: range(newStart, newEnd),
              ),
            if (fix.guests > 0 || recurring) ...[
              const SizedBox(height: 12),
              _Warning(
                [
                  if (fix.guests > 0)
                    'You organised this, so ${fix.guests} '
                        '${fix.guests == 1 ? 'guest' : 'guests'} will get the '
                        'new time.',
                  if (recurring) 'Only this occurrence moves.',
                ].join(' '),
              ),
            ],
            if (fix.demandSaved >= 0.5) ...[
              const SizedBox(height: 14),
              _DemandChange(from: demandNow, to: demandNow - fix.demandSaved),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: VivordoTheme.brand,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(sheetContext, true),
                child: Text(
                  fix.kind == DayFixKind.addBreak
                      ? 'Add break'
                      : 'Move to ${_time(newStart)}',
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return confirmed == true;
}

/// The confirm sheet for moving a priority: the next few days with how full
/// each is ([days], expected Demand), the lightest picked. Returns the
/// chosen day, or null.
Future<DateTime?> showMovePrioritySheet(
  BuildContext context, {
  required DayFix fix,
  required double demandNow,
  required Future<List<({DateTime day, double demand})>> days,
}) {
  final colors = context.vivordoColors;
  return showModalBottomSheet<DateTime>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: colors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 84),
        child: FutureBuilder<List<({DateTime day, double demand})>>(
          future: days,
          builder: (context, snapshot) {
            final options = snapshot.data;
            return _DayPicker(
              fix: fix,
              demandNow: demandNow,
              options: options,
              failed: snapshot.hasError,
              onPick: (day) => Navigator.pop(sheetContext, day),
              onCancel: () => Navigator.pop(sheetContext),
            );
          },
        ),
      ),
    ),
  );
}

class _DayPicker extends StatefulWidget {
  const _DayPicker({
    required this.fix,
    required this.demandNow,
    required this.options,
    required this.failed,
    required this.onPick,
    required this.onCancel,
  });

  final DayFix fix;
  final double demandNow;
  final List<({DateTime day, double demand})>? options;
  final bool failed;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onCancel;

  @override
  State<_DayPicker> createState() => _DayPickerState();
}

class _DayPickerState extends State<_DayPicker> {
  DateTime? _chosen;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final options = widget.options;
    final lightest = options == null || options.isEmpty
        ? null
        : options.reduce((a, b) => b.demand < a.demand ? b : a).day;
    final chosen = _chosen ?? lightest;
    final most = (options ?? const []).fold<double>(
      1,
      (m, o) => o.demand > m ? o.demand : m,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Move "${widget.fix.title}"',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Pick a day. The bars show how full each one already is.',
          style: TextStyle(color: colors.textSecondary),
        ),
        const SizedBox(height: 16),
        if (options == null)
          SizedBox(
            height: 92,
            child: Center(
              child: widget.failed
                  ? Text(
                      "Couldn't load the next few days.",
                      style: TextStyle(color: colors.textSecondary),
                    )
                  : const CircularProgressIndicator(),
            ),
          )
        else
          Row(
            children: [
              for (final o in options) ...[
                if (o != options.first) const SizedBox(width: 6),
                Expanded(
                  child: _DayOption(
                    option: o,
                    fullness: o.demand / most,
                    selected: DateUtils.isSameDay(o.day, chosen),
                    onTap: () => setState(() => _chosen = o.day),
                  ),
                ),
              ],
            ],
          ),
        if (chosen != null && DateUtils.isSameDay(chosen, lightest)) ...[
          const SizedBox(height: 8),
          Text(
            'The lightest of the next ${options!.length} days.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
        const SizedBox(height: 14),
        _DemandChange(
          from: widget.demandNow,
          to: widget.demandNow - widget.fix.demandSaved,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: VivordoTheme.brand,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: chosen == null ? null : () => widget.onPick(chosen),
            child: Text(
              chosen == null
                  ? 'Move'
                  : 'Move to ${DateFormat('EEEE').format(chosen)}',
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: widget.onCancel,
            child: Text(
              'Cancel',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayOption extends StatelessWidget {
  const _DayOption({
    required this.option,
    required this.fullness,
    required this.selected,
    required this.onTap,
  });

  final ({DateTime day, double demand}) option;
  final double fullness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Material(
      color: selected
          ? VivordoTheme.brand.withValues(alpha: .1)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? VivordoTheme.brand : colors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(
                DateFormat('EEE').format(option.day),
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              SizedBox(
                height: 30,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 10,
                    height: 4 + 26 * fullness.clamp(0, 1),
                    decoration: BoxDecoration(
                      color: selected ? VivordoTheme.brand : colors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${option.demand.round()}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BeforeAfter extends StatelessWidget {
  const _BeforeAfter({required this.before, required this.after});

  /// Null for something new (a break): just the one time.
  final String? before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    Widget side(String label, String value, bool highlight) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: highlight
              ? VivordoTheme.brand.withValues(alpha: .08)
              : colors.cardMuted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: highlight ? VivordoTheme.brand : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
    final was = before;
    return Row(
      children: [
        if (was != null) ...[side('Now', was, false), const SizedBox(width: 8)],
        side(was == null ? 'When' : 'After', after, true),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: _amber.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, size: 18, color: _amber),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: _amber),
          ),
        ),
      ],
    ),
  );
}

class _DemandChange extends StatelessWidget {
  const _DemandChange({required this.from, required this.to});

  final double from, to;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            "Today's Demand",
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        Text(
          '${from.round()}',
          style: TextStyle(
            color: colors.textSecondary,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        Text(
          '  →  ${to.round()}',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
