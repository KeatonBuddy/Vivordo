import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/plan_my_day.dart';
import 'apple_ui.dart';
import 'vivordo_time_picker.dart';

/// What the person kept from a plan: the slots to set (with any times they
/// changed) and the tasks to move to tomorrow. Null when dismissed.
typedef PlanChoice = ({List<PlannedSlot> slots, List<PlanTask> tomorrow});

/// "Plan my day": each priority with every time it could go today, the
/// suggested one picked. Pick another, your own time, tomorrow, or none
/// (tap the picked one again); a time taken by another priority can't be
/// picked. Times stay in Vivordo; the calendar isn't changed.
/// With [from] and [until] (now and the wrap-up time) the rest of the day
/// is drawn across the top: what's already [busy], and each pick as it
/// lands.
Future<PlanChoice?> showPlanMyDaySheet(
  BuildContext context, {
  required DayPlan plan,
  DateTime? from,
  DateTime? until,
  List<DateTimeRange> busy = const [],
}) => showAppleSheet<PlanChoice>(
  context,
  builder: (sheetContext) =>
      _PlanMyDaySheet(plan: plan, from: from, until: until, busy: busy),
);

class _PlanMyDaySheet extends StatefulWidget {
  const _PlanMyDaySheet({
    required this.plan,
    required this.from,
    required this.until,
    required this.busy,
  });

  final DayPlan plan;
  final DateTime? from, until;
  final List<DateTimeRange> busy;

  @override
  State<_PlanMyDaySheet> createState() => _PlanMyDaySheetState();
}

class _PlanMyDaySheetState extends State<_PlanMyDaySheet> {
  // Suggested first, in time order, then what didn't fit.
  late final List<PlanTask> _tasks = [
    for (final slot in widget.plan.placed) slot.task,
    for (final (:task, reason: _) in widget.plan.unplaced) task,
  ];
  late final Map<String, PlannedSlot> _picked = {
    for (final slot in widget.plan.placed) slot.task.id: slot,
  };

  late final Map<String, PlannedSlot> _suggested = {
    for (final slot in widget.plan.placed) slot.task.id: slot,
  };

  /// Times you set yourself, offered beside the suggestions.
  final _own = <String, PlannedSlot>{};
  final _tomorrow = <String>{};

  List<PlannedSlot> _optionsFor(PlanTask task) {
    final options = {
      for (final o in widget.plan.options[task.id] ?? const <PlannedSlot>[])
        o.start: o,
    };
    // The suggested time stays on offer after it's unpicked: it can differ
    // from the plan's listed options, and would otherwise vanish.
    for (final extra in [
      _suggested[task.id],
      _picked[task.id],
      _own[task.id],
    ]) {
      if (extra != null) options[extra.start] = extra;
    }
    return options.values.toList()..sort((a, b) => a.start.compareTo(b.start));
  }

  bool _clashes(PlannedSlot option) => _picked.values.any(
    (p) =>
        p.task.id != option.task.id &&
        option.start.isBefore(p.end) &&
        p.start.isBefore(option.end),
  );

  void _pick(PlanTask task, PlannedSlot slot) => setState(() {
    _tomorrow.remove(task.id);
    if (_picked[task.id]?.start == slot.start) {
      _picked.remove(task.id);
    } else {
      _picked[task.id] = slot;
    }
  });

  Future<void> _ownTime(PlanTask task) async {
    final from = _picked[task.id]?.start ?? DateTime.now();
    final picked = await showVivordoTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(from),
      title: task.title,
      minuteInterval: 5,
    );
    if (picked == null || !mounted) return;
    final start = DateTime(
      from.year,
      from.month,
      from.day,
      picked.hour,
      picked.minute,
    );
    final PlannedSlot slot = (
      task: task,
      start: start,
      end: start.add(Duration(minutes: task.minutes)),
      reason: 'Your time',
    );
    _own[task.id] = slot;
    _picked.remove(task.id);
    _pick(task, slot);
  }

  /// The rest of the day, left to right: grey where it's already taken,
  /// purple for each pick. A pick fills its slot from the left as it's
  /// chosen (the suggested ones as the sheet opens) and drains when unpicked.
  Widget _dayStrip(BuildContext context, DateTime from, DateTime until) {
    final colors = context.vivordoColors;
    final span = until.difference(from).inSeconds;
    final still = MediaQuery.disableAnimationsOf(context);
    final label = TextStyle(fontSize: 11, color: colors.textSecondary);
    return ExcludeSemantics(
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 28,
              child: LayoutBuilder(
                builder: (context, box) {
                  Widget? block(
                    DateTime start,
                    DateTime end,
                    Color color, {
                    Key? key,
                    bool? on,
                  }) {
                    final a = start.isBefore(from) ? from : start;
                    final b = end.isAfter(until) ? until : end;
                    if (!b.isAfter(a)) return null;
                    final left =
                        box.maxWidth * a.difference(from).inSeconds / span;
                    final width =
                        box.maxWidth * b.difference(a).inSeconds / span;
                    final fill = Container(
                      margin: const EdgeInsets.only(right: 1),
                      color: color,
                    );
                    final w = width < 3 ? 3.0 : width;
                    if (on == null) {
                      return Positioned(
                        left: left,
                        width: w,
                        top: 0,
                        bottom: 0,
                        child: fill,
                      );
                    }
                    // No width on the Positioned: the Align sets it, from
                    // nothing to the slot's own as it fills.
                    return Positioned(
                      key: key,
                      left: left,
                      top: 0,
                      bottom: 0,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: on ? 1 : 0),
                        duration: still
                            ? Duration.zero
                            : const Duration(milliseconds: 380),
                        curve: Curves.easeOutCubic,
                        builder: (context, t, child) => ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: t,
                            child: child,
                          ),
                        ),
                        child: SizedBox(width: w, child: fill),
                      ),
                    );
                  }

                  return Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: colors.input)),
                      for (final b in widget.busy)
                        ?block(
                          b.start,
                          b.end,
                          colors.textSecondary.withValues(alpha: .35),
                        ),
                      // Every time on offer has its slot, filled while
                      // it's the pick, so picking and unpicking both move.
                      for (final task in _tasks)
                        for (final slot in _optionsFor(task))
                          ?block(
                            slot.start,
                            slot.end,
                            VivordoTheme.brand,
                            key: ValueKey('${task.id}@${slot.start}'),
                            on: _picked[task.id]?.start == slot.start,
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Now', style: label),
              Text(DateFormat.jm().format(until), style: label),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final from = widget.from, until = widget.until;
    final kept = [for (final task in _tasks) ?_picked[task.id]]
      ..sort((a, b) => a.start.compareTo(b.start));
    final tomorrow = [
      for (final task in _tasks)
        if (_tomorrow.contains(task.id)) task,
    ];
    final secondary = TextStyle(fontSize: 12, color: colors.textSecondary);
    String time(DateTime t) => DateFormat.jm().format(t);
    final reasons = {
      for (final (:task, :reason) in widget.plan.unplaced) task.id: reason,
    };

    Widget chip(String label, {required bool selected, VoidCallback? onTap}) =>
        Semantics(
          button: true,
          selected: selected,
          enabled: onTap != null,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? VivordoTheme.brand : null,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? VivordoTheme.brand : colors.border,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : onTap == null
                      ? colors.textSecondary.withValues(alpha: .45)
                      : colors.textPrimary,
                ),
              ),
            ),
          ),
        );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        // The title, the day and the button stay put; the priorities scroll.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      'Plan for today',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${kept.length} of ${_tasks.length} placed',
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ],
              ),
              if (from != null && until != null && until.isAfter(from)) ...[
                const SizedBox(height: 10),
                _dayStrip(context, from, until),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pick a time for each, or leave it for later. Times fit '
                        'around your events, heavy ones in your peak. Only in '
                        'Vivordo; your calendar isn\'t changed.',
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final task in _tasks)
                        Builder(
                          builder: (context) {
                            final picked = _picked[task.id];
                            final options = _optionsFor(task);
                            final note = picked != null
                                ? '${time(picked.start)}–${time(picked.end)} · ${picked.reason}'
                                : _tomorrow.contains(task.id)
                                ? 'Moves to tomorrow'
                                : options.isEmpty
                                ? reasons[task.id] ??
                                      'No room before your wrap-up'
                                : options.every(_clashes)
                                ? 'Its open times are taken by your other picks'
                                : 'No time yet';
                            return Container(
                              // Full width, so the line above spans the sheet.
                              width: double.infinity,
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: colors.border,
                                    width: .5,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                    Text(note, style: secondary),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        // A time another pick has taken isn't
                                        // offered; it comes back when that's undone.
                                        for (final option in options)
                                          if (!_clashes(option))
                                            chip(
                                              time(option.start),
                                              selected:
                                                  picked?.start == option.start,
                                              onTap: () => _pick(task, option),
                                            ),
                                        chip(
                                          'Other time',
                                          selected: false,
                                          onTap: () => _ownTime(task),
                                        ),
                                        chip(
                                          'Tomorrow',
                                          selected: _tomorrow.contains(task.id),
                                          onTap: () => setState(() {
                                            if (!_tomorrow.remove(task.id)) {
                                              _tomorrow.add(task.id);
                                              _picked.remove(task.id);
                                            }
                                          }),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop<PlanChoice>(context, (
                  slots: kept,
                  tomorrow: tomorrow,
                )),
                style: FilledButton.styleFrom(
                  backgroundColor: VivordoTheme.brand,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  kept.isEmpty && tomorrow.isEmpty
                      ? 'Close'
                      : kept.isEmpty
                      ? 'Move to tomorrow'
                      : kept.length == 1
                      ? 'Set this time'
                      : 'Set these times',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
