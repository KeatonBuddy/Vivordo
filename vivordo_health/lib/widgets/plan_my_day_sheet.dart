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
Future<PlanChoice?> showPlanMyDaySheet(
  BuildContext context, {
  required DayPlan plan,
}) => showAppleSheet<PlanChoice>(
  context,
  builder: (sheetContext) => _PlanMyDaySheet(plan: plan),
);

class _PlanMyDaySheet extends StatefulWidget {
  const _PlanMyDaySheet({required this.plan});

  final DayPlan plan;

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

  /// Times you set yourself, offered beside the suggestions.
  final _own = <String, PlannedSlot>{};
  final _tomorrow = <String>{};

  List<PlannedSlot> _optionsFor(PlanTask task) {
    final options = {
      for (final o in widget.plan.options[task.id] ?? const <PlannedSlot>[])
        o.start: o,
    };
    for (final extra in [_picked[task.id], _own[task.id]]) {
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

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Plan for today',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pick a time for each, or leave it for later. Times fit '
                'around your events, heavy ones in your peak. Only in '
                'Vivordo; your calendar isn\'t changed.',
                style: TextStyle(fontSize: 15, color: colors.textSecondary),
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
                        ? reasons[task.id] ?? 'No room before your wrap-up'
                        : options.every(_clashes)
                        ? 'Its open times are taken by your other picks'
                        : 'No time yet';
                    return Container(
                      // Full width, so the line above spans the sheet.
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: colors.border, width: .5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
                                for (final option in options)
                                  chip(
                                    time(option.start),
                                    selected: picked?.start == option.start,
                                    onTap: _clashes(option)
                                        ? null
                                        : () => _pick(task, option),
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
