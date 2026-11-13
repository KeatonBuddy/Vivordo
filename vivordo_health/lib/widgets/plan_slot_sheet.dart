import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../src/services/calendar_service.dart';
import '../src/services/daily_priority_service.dart';
import '../src/services/event_invite_service.dart';
import '../src/utils/priority_schedule.dart';
import '../theme/vivordo_theme.dart';
import 'add_calendar_event_sheet.dart';
import 'add_priority_sheet.dart';

/// A waiting priority picked for an open slot, and when it starts.
typedef SlotPick = ({DailyPriority priority, DateTime start});

/// How long [p] takes when planning: its estimate, or half an hour.
int slotMinutes(DailyPriority p) =>
    switch ((p.planning['minutes'] as num?)?.toInt()) {
      final minutes? when minutes > 0 => minutes,
      _ => 30,
    };

/// Plans an open slot. The [waiting] priorities (no time yet) that fit it
/// come first, one tap each; under them, or straight away when none fit, a
/// new priority or calendar event. Returns a [SlotPick], a [PriorityDraft],
/// a [CalendarEventDraft], or null when dismissed.
Future<Object?> showPlanSlotSheet(
  BuildContext context, {
  required DateTime start,
  DateTime? end,
  List<DailyPriority> waiting = const [],
}) => showModalBottomSheet<Object>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .68),
  builder: (_) => _PlanSlotSheet(start: start, end: end, waiting: waiting),
);

/// Creates [draft]'s priority, then its calendar event when asked. Throws
/// when the priority itself could not be saved; returns a warning when only
/// the calendar event failed.
Future<String?> savePriorityDraft(PriorityDraft draft) async {
  final reference = await DailyPriorityService.createManual(
    title: draft.title,
    planning: draft.planning,
    date: draft.date,
    scheduledAt: draft.scheduledAt,
    recurrence: draft.recurrence,
    selectedWeekdays: draft.selectedWeekdays,
    recurrenceEnd: draft.repeatEnd,
    reminderMinutes: draft.reminderMinutes,
    reminderTimeMinutes: draft.reminderTimeMinutes,
    habit: draft.habit,
    target: draft.target,
  );
  if (!draft.addToCalendar || reference == null) return null;
  return addPriorityCalendarEvent(draft, reference: reference);
}

/// Adds [draft]'s calendar event and links it back to the priority at
/// [reference]. Returns a warning when the event could not be added.
Future<String?> addPriorityCalendarEvent(
  PriorityDraft draft, {
  required DocumentReference<Map<String, dynamic>> reference,
}) async {
  final start = draft.scheduledAt ?? DateUtils.dateOnly(draft.date);
  final end = draft.scheduledAt == null
      ? start.add(const Duration(days: 1))
      : start.add(
          Duration(minutes: (draft.planning['minutes'] as num?)?.toInt() ?? 60),
        );
  try {
    final calendarId = await CalendarService.defaultCalendarId();
    final event = await CalendarService.createEvent(
      title: draft.title,
      start: start,
      end: end,
      recurrence: draft.calendarRecurrence,
      isAllDay: draft.scheduledAt == null,
      calendarId: calendarId,
      isPriority: true,
      priorityReference: reference.path,
    );
    await reference.update({
      'sourceEventKey': CalendarService.eventKey(event),
      'linkedCalendarId': calendarId,
      'sourceEnd': Timestamp.fromDate(end),
    });
    final saved = (await reference.get()).data();
    final templateId = saved?['templateId'] as String?;
    if (templateId != null) {
      await reference.parent.parent!.parent.parent!
          .collection('priority_templates')
          .doc(templateId)
          .update({'sourceEventKey': CalendarService.eventKey(event)});
    }
    return null;
  } catch (error) {
    return 'Priority saved, but the calendar event could not be added: $error';
  }
}

/// Creates the calendar event in [draft], in Google or Outlook, then
/// invites its friends. Returns the message to show.
Future<String> saveEventDraft(CalendarEventDraft draft) async {
  final event = await CalendarService.createEvent(
    title: draft.title,
    start: draft.start,
    end: draft.end,
    recurrence: draft.recurrence,
    isAllDay: draft.isAllDay,
    calendarId: draft.calendarId,
  );
  final invitees = draft.inviteeUids;
  if (invitees.isEmpty) return 'Event added to your calendar.';
  try {
    await EventInviteService.send(
      title: draft.title,
      start: draft.start,
      end: draft.end,
      allDay: draft.isAllDay,
      recipientUids: invitees,
      senderEventId: event.id,
      recurrence: draft.recurrence == 'none' ? null : draft.recurrence,
    );
    return invitees.length == 1
        ? 'Event added and your friend invited.'
        : 'Event added and ${invitees.length} friends invited.';
  } catch (error) {
    debugPrint('Event invites not sent: $error');
    return "Event added, but the invites couldn't be sent.";
  }
}

class _PlanSlotSheet extends StatefulWidget {
  const _PlanSlotSheet({required this.start, this.end, required this.waiting});

  final DateTime start;
  final DateTime? end;
  final List<DailyPriority> waiting;

  @override
  State<_PlanSlotSheet> createState() => _PlanSlotSheetState();
}

class _PlanSlotSheetState extends State<_PlanSlotSheet> {
  bool _event = false;

  /// "Free now" starts mid-minute; plan from the next five minutes.
  late final _start = widget.start.add(
    Duration(
      minutes: (5 - widget.start.minute % 5) % 5,
      seconds: -widget.start.second,
      milliseconds: -widget.start.millisecond,
      microseconds: -widget.start.microsecond,
    ),
  );
  late final _fits = [
    for (final p in widget.waiting)
      if (widget.end == null ||
          !_start.add(Duration(minutes: slotMinutes(p))).isAfter(widget.end!))
        p,
  ];
  late bool _choosing = _fits.isNotEmpty;

  /// Shared by both forms, so a title typed under one survives switching.
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final toggle = PlanSlotToggle(
      event: _event,
      onChanged: (value) => setState(() => _event = value),
    );
    if (_choosing) return _chooser(context);
    final hour = _start.add(const Duration(hours: 1));
    final end = widget.end;
    return _event
        ? addCalendarEventForm(
            initialStart: _start,
            initialEnd: end != null && end.isBefore(hour) ? end : hour,
            header: toggle,
            titleController: _title,
          )
        : addPriorityForm(at: _start, header: toggle, titleController: _title);
  }

  Widget _chooser(BuildContext context) {
    final colors = context.vivordoColors;
    final time = DateFormat('h:mm a');
    Widget action({
      required Widget child,
      required VoidCallback onTap,
      String? trailing,
    }) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        child: Row(
          children: [
            Expanded(child: child),
            if (trailing != null)
              Text(
                trailing,
                style: const TextStyle(
                  color: VivordoTheme.brand,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
    Widget label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 2),
      child: Text(
        text,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: colors.textPrimary.withValues(alpha: .18)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 32)],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
              child: Text(
                'Open from ${time.format(_start)}',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 0),
              child: Text(
                widget.end == null
                    ? 'The rest of the day is free'
                    : 'Until ${time.format(widget.end!)}',
                style: TextStyle(color: colors.textSecondary, fontSize: 15),
              ),
            ),
            label('Waiting for a time'),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final p in _fits)
                      action(
                        onTap: () => Navigator.pop<Object>(context, (
                          priority: p,
                          start: _start,
                        )),
                        trailing: 'Put here',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.title,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${formatPriorityMinutes(slotMinutes(p))} · '
                              '${DateFormat('h:mm').format(_start)}–'
                              '${time.format(_start.add(Duration(minutes: slotMinutes(p))))}',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.border),
            action(
              onTap: () => setState(() => _choosing = false),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.add,
                    size: 20,
                    color: VivordoTheme.brand,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'New priority or event',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
