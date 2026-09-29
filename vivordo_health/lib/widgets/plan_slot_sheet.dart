import 'package:flutter/material.dart';

import '../theme/vivordo_theme.dart';
import 'add_calendar_event_sheet.dart';
import 'add_priority_sheet.dart';

/// Plans an open slot as a priority or a calendar event. Returns a
/// [PriorityDraft], a [CalendarEventDraft], or null when dismissed.
Future<Object?> showPlanSlotSheet(
  BuildContext context, {
  required DateTime start,
  DateTime? end,
}) => showModalBottomSheet<Object>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .68),
  builder: (_) => _PlanSlotSheet(start: start, end: end),
);

class _PlanSlotSheet extends StatefulWidget {
  const _PlanSlotSheet({required this.start, this.end});

  final DateTime start;
  final DateTime? end;

  @override
  State<_PlanSlotSheet> createState() => _PlanSlotSheetState();
}

class _PlanSlotSheetState extends State<_PlanSlotSheet> {
  bool _event = false;

  @override
  Widget build(BuildContext context) {
    final toggle = PlanSlotToggle(
      event: _event,
      onChanged: (value) => setState(() => _event = value),
    );
    final hour = widget.start.add(const Duration(hours: 1));
    final end = widget.end;
    // ponytail: switching starts the other form fresh; carry the typed title
    // across if people switch mid-entry.
    return _event
        ? addCalendarEventForm(
            initialStart: widget.start,
            initialEnd: end != null && end.isBefore(hour) ? end : hour,
            header: toggle,
          )
        : addPriorityForm(at: widget.start, header: toggle);
  }
}

/// Priority / Event switch with a sliding thumb.
class PlanSlotToggle extends StatelessWidget {
  const PlanSlotToggle({
    super.key,
    required this.event,
    required this.onChanged,
  });

  final bool event;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    Widget segment(String label, bool value) => Expanded(
      child: Semantics(
        button: true,
        selected: event == value,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: event == value ? Colors.white : colors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFamily: 'DMSans',
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.input,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: event ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: .5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: VivordoTheme.brand,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          Row(children: [segment('Priority', false), segment('Event', true)]),
        ],
      ),
    );
  }
}
