import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/utils/plan_my_day.dart';
import 'apple_ui.dart';
import 'vivordo_time_picker.dart';

/// What the person kept from a plan: the slots to set (with any times they
/// changed) and the tasks to move to tomorrow. Null when dismissed.
typedef PlanChoice = ({List<PlannedSlot> slots, List<PlanTask> tomorrow});

/// "Plan my day": the proposed times, each with why it's there. A slot can
/// be retimed (tap) or skipped; what didn't fit can go to tomorrow. Times
/// stay in Vivordo; the calendar isn't changed.
Future<PlanChoice?> showPlanMyDaySheet(
  BuildContext context, {
  required List<PlannedSlot> placed,
  required List<UnplacedTask> unplaced,
}) => showAppleSheet<PlanChoice>(
  context,
  builder: (sheetContext) =>
      _PlanMyDaySheet(placed: placed, unplaced: unplaced),
);

class _PlanMyDaySheet extends StatefulWidget {
  const _PlanMyDaySheet({required this.placed, required this.unplaced});

  final List<PlannedSlot> placed;
  final List<UnplacedTask> unplaced;

  @override
  State<_PlanMyDaySheet> createState() => _PlanMyDaySheetState();
}

class _PlanMyDaySheetState extends State<_PlanMyDaySheet> {
  late final List<PlannedSlot> _slots = [...widget.placed];
  final _skipped = <String>{};
  final _tomorrow = <String>{};

  Future<void> _retime(int index) async {
    final slot = _slots[index];
    final picked = await showVivordoTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(slot.start),
      title: slot.task.title,
      minuteInterval: 5,
    );
    if (picked == null || !mounted) return;
    final start = DateTime(
      slot.start.year,
      slot.start.month,
      slot.start.day,
      picked.hour,
      picked.minute,
    );
    setState(
      () => _slots[index] = (
        task: slot.task,
        start: start,
        end: start.add(slot.end.difference(slot.start)),
        reason: 'Your time',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final kept = [
      for (final slot in _slots)
        if (!_skipped.contains(slot.task.id)) slot,
    ];
    final secondary = TextStyle(fontSize: 12, color: colors.textSecondary);
    String time(DateTime t) => DateFormat.jm().format(t);
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
                _slots.isEmpty
                    ? 'There isn\'t room for these before your wrap-up.'
                    : 'Times for ${_slots.length == 1 ? 'a priority' : '${_slots.length} priorities'}, around your events, heavy ones in your peak. Only in Vivordo; your calendar isn\'t changed.',
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _slots.length; i++)
                Builder(
                  builder: (context) {
                    final slot = _slots[i];
                    final skipped = _skipped.contains(slot.task.id);
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: colors.border, width: .5),
                        ),
                      ),
                      child: InkWell(
                        onTap: skipped ? null : () => _retime(i),
                        child: Opacity(
                          opacity: skipped ? .45 : 1,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    time(slot.start),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: VivordoTheme.brand,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        slot.task.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        '${time(slot.start)}–${time(slot.end)} · ${slot.reason}',
                                        style: secondary,
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => setState(
                                    () => skipped
                                        ? _skipped.remove(slot.task.id)
                                        : _skipped.add(slot.task.id),
                                  ),
                                  child: Text(skipped ? 'Keep' : 'Skip'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (widget.unplaced.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  "Couldn't fit",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
                for (final (:task, :reason) in widget.unplaced)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: colors.border, width: .5),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
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
                                Text(reason, style: secondary),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(
                              () => _tomorrow.contains(task.id)
                                  ? _tomorrow.remove(task.id)
                                  : _tomorrow.add(task.id),
                            ),
                            child: Text(
                              _tomorrow.contains(task.id)
                                  ? 'Tomorrow ✓'
                                  : 'Tomorrow?',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop<PlanChoice>(context, (
                  slots: kept,
                  tomorrow: [
                    for (final (:task, reason: _) in widget.unplaced)
                      if (_tomorrow.contains(task.id)) task,
                  ],
                )),
                style: FilledButton.styleFrom(
                  backgroundColor: VivordoTheme.brand,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  kept.isEmpty && _tomorrow.isEmpty
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
