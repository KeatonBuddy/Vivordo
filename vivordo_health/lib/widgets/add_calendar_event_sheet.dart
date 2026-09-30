import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/src/utils/event_repeat.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/vivordo_time_picker.dart';

const _purple = Color(0xFF6254F4);

Color _calendarColor(String? hex) {
  final value = hex?.replaceFirst('#', '');
  if (value == null || value.length != 6) return _purple;
  return Color(int.parse('FF$value', radix: 16));
}

class CalendarEventDraft {
  const CalendarEventDraft({
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.isAllDay,
    required this.recurrence,
    required this.calendarId,
  });

  final String title;
  final DateTime date;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final bool isAllDay;
  final String recurrence;
  final String calendarId;

  DateTime get start => DateTime(
    date.year,
    date.month,
    date.day,
    isAllDay ? 0 : startTime.hour,
    isAllDay ? 0 : startTime.minute,
  );

  DateTime get end {
    if (isAllDay) return DateUtils.dateOnly(date).add(const Duration(days: 1));
    var value = DateTime(
      date.year,
      date.month,
      date.day,
      endTime.hour,
      endTime.minute,
    );
    if (!value.isAfter(start)) value = value.add(const Duration(days: 1));
    return value;
  }
}

enum CalendarEventEditAction { save, delete }

/// Which part of a repeating event a change applies to.
enum EventScope { thisEvent, allEvents }

class CalendarEventEditResult {
  const CalendarEventEditResult.save(
    this.draft, {
    required this.recurrenceChanged,
    this.scope = EventScope.thisEvent,
  }) : action = CalendarEventEditAction.save;

  const CalendarEventEditResult.delete({this.scope = EventScope.thisEvent})
    : action = CalendarEventEditAction.delete,
      draft = null,
      recurrenceChanged = false;

  final CalendarEventEditAction action;
  final CalendarEventDraft? draft;
  final bool recurrenceChanged;
  final EventScope scope;
}

/// Asks whether a change to one occurrence of a repeating event applies to it
/// alone or to the whole series. Without [allowSingle] only the series can
/// change, e.g. for a new repeat rule. Null means cancel.
Future<EventScope?> askEventScope(
  BuildContext context, {
  required String title,
  required String message,
  bool allowSingle = true,
  bool destructive = false,
}) => showDialog<EventScope>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Cancel'),
      ),
      if (allowSingle)
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, EventScope.thisEvent),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: Colors.red)
              : null,
          child: const Text('This event'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, EventScope.allEvents),
        style: destructive
            ? TextButton.styleFrom(foregroundColor: Colors.red)
            : null,
        child: const Text('All events'),
      ),
    ],
  ),
);

/// Confirms deleting [title]. A [repeating] occurrence asks which part of
/// the series to delete. Null means cancel.
Future<EventScope?> confirmEventDelete(
  BuildContext context, {
  required String title,
  required bool repeating,
}) async {
  if (repeating) {
    return askEventScope(
      context,
      title: 'Delete repeating event?',
      message: 'Delete only this “$title”, or every event in the series?',
      destructive: true,
    );
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete event?'),
      content: Text('This will delete “$title” from Google Calendar.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true ? EventScope.thisEvent : null;
}

Future<CalendarEventDraft?> showAddCalendarEventSheet(
  BuildContext context, {
  required DateTime initialStart,
  DateTime? initialEnd,
}) => showModalBottomSheet<CalendarEventDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .68),
  builder: (_) => _AddCalendarEventSheet(
    initialStart: initialStart,
    initialEnd: initialEnd ?? initialStart.add(const Duration(hours: 1)),
  ),
);

/// The add form for hosting in another sheet; [header] replaces the title.
/// Saving pops a [CalendarEventDraft].
Widget addCalendarEventForm({
  required DateTime initialStart,
  required DateTime initialEnd,
  Widget? header,
}) => _AddCalendarEventSheet(
  initialStart: initialStart,
  initialEnd: initialEnd,
  header: header,
);

Future<CalendarEventEditResult?> showEditCalendarEventSheet(
  BuildContext context, {
  required gcal.Event event,
}) async {
  final start =
      event.start?.dateTime?.toLocal() ?? event.start?.date?.toLocal();
  final end = event.end?.dateTime?.toLocal() ?? event.end?.date?.toLocal();
  if (start == null || end == null) return null;
  final repeating = event.recurringEventId != null;
  gcal.Event? series;
  if (repeating) {
    try {
      series = await CalendarService.seriesFor(event);
    } catch (_) {
      // Without the series the form still edits this occurrence.
    }
    if (!context.mounted) return null;
  }

  return showModalBottomSheet<CalendarEventEditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .72),
    builder: (_) => _AddCalendarEventSheet(
      initialStart: start,
      initialEnd: end,
      initialTitle: event.summary ?? '',
      initialIsAllDay: event.start?.dateTime == null,
      initialRepeat: EventRepeat.parse(series?.recurrence ?? event.recurrence),
      repeating: repeating,
      initialCalendarId: CalendarService.calendarIdForEvent(event),
      isEditing: true,
    ),
  );
}

enum _RepeatOption {
  none,
  daily,
  weekly,
  monthly,
  yearly,
  selectedDays,
  custom,
}

const _repeatOptions = [
  (_RepeatOption.none, 'Does not repeat'),
  (_RepeatOption.daily, 'Every day'),
  (_RepeatOption.weekly, 'Every week'),
  (_RepeatOption.monthly, 'Every month'),
  (_RepeatOption.yearly, 'Every year'),
  (_RepeatOption.selectedDays, 'Selected days'),
  (_RepeatOption.custom, 'Custom…'),
];

/// Which menu entry [repeat] is: anything beyond a plain preset is Custom.
_RepeatOption _optionFor(EventRepeat repeat) {
  final unit = repeat.unit;
  if (unit == null) return _RepeatOption.none;
  if (repeat.interval != 1 || repeat.until != null) return _RepeatOption.custom;
  if (unit == RepeatUnit.week && repeat.weekdays.isNotEmpty) {
    return _RepeatOption.selectedDays;
  }
  return switch (unit) {
    RepeatUnit.day => _RepeatOption.daily,
    RepeatUnit.week => _RepeatOption.weekly,
    RepeatUnit.month => _RepeatOption.monthly,
    RepeatUnit.year => _RepeatOption.yearly,
  };
}

class _AddCalendarEventSheet extends StatefulWidget {
  const _AddCalendarEventSheet({
    required this.initialStart,
    required this.initialEnd,
    this.initialTitle = '',
    this.initialIsAllDay = false,
    this.initialRepeat = const EventRepeat(),
    this.initialCalendarId,
    this.isEditing = false,
    this.repeating = false,
    this.header,
  });

  final Widget? header;

  /// Editing one occurrence of a repeating event.
  final bool repeating;
  final DateTime initialStart;
  final DateTime initialEnd;
  final String initialTitle;
  final bool initialIsAllDay;
  final EventRepeat initialRepeat;
  final String? initialCalendarId;
  final bool isEditing;

  @override
  State<_AddCalendarEventSheet> createState() => _AddCalendarEventSheetState();
}

class _AddCalendarEventSheetState extends State<_AddCalendarEventSheet> {
  late final TextEditingController _titleController;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _isAllDay = false;
  late EventRepeat _repeat;
  List<WritableCalendar> _calendars = const [];
  WritableCalendar _selectedCalendar = const WritableCalendar(
    id: 'primary',
    name: 'Personal',
    isPrimary: true,
    colorHex: '#6254F4',
  );
  bool _loadingCalendars = true;
  bool _recurrenceChanged = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle)
      ..addListener(_titleChanged);
    _date = DateUtils.dateOnly(widget.initialStart);
    _startTime = TimeOfDay.fromDateTime(widget.initialStart);
    _endTime = TimeOfDay.fromDateTime(widget.initialEnd);
    _isAllDay = widget.initialIsAllDay;
    _repeat = widget.initialRepeat;
    _loadCalendars();
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_titleChanged)
      ..dispose();
    super.dispose();
  }

  void _titleChanged() => setState(() {});

  Future<void> _loadCalendars() async {
    try {
      final calendars = await CalendarService.getWritableCalendars();
      if (!mounted) return;
      setState(() {
        _calendars = calendars;
        if (calendars.isNotEmpty) {
          _selectedCalendar = calendars.firstWhere(
            (calendar) => calendar.id == widget.initialCalendarId,
            orElse: () => calendars.firstWhere(
              (calendar) => calendar.isPrimary,
              orElse: () => calendars.first,
            ),
          );
        }
        _loadingCalendars = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCalendars = false);
    }
  }

  Future<void> _pickCalendar() async {
    if (_loadingCalendars) return;
    if (_calendars.isEmpty) {
      setState(() => _loadingCalendars = true);
      await _loadCalendars();
      if (!mounted || _calendars.isNotEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load writable calendars.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<WritableCalendar>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .62,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Choose calendar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _calendars.length,
                  itemBuilder: (context, index) {
                    final calendar = _calendars[index];
                    final isSelected = calendar.id == _selectedCalendar.id;
                    return ListTile(
                      leading: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _calendarColor(calendar.colorHex),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 14, height: 14),
                      ),
                      title: Text(calendar.name),
                      subtitle: calendar.isPrimary
                          ? const Text('Primary calendar')
                          : null,
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded, color: _purple)
                          : null,
                      onTap: () => Navigator.pop(sheetContext, calendar),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedCalendar = selected);
    }
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _pickTime({required bool start}) async {
    final value = await showVivordoTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
      title: start ? 'Start Time' : 'End Time',
    );
    if (value == null) return;
    setState(() {
      if (start) {
        _startTime = value;
      } else {
        _endTime = value;
      }
    });
  }

  Future<void> _chooseRepeat(_RepeatOption option) async {
    final weekly = _repeat.unit == RepeatUnit.week;
    final next = switch (option) {
      _RepeatOption.none => const EventRepeat(),
      _RepeatOption.daily => const EventRepeat(unit: RepeatUnit.day),
      _RepeatOption.weekly => const EventRepeat(unit: RepeatUnit.week),
      _RepeatOption.monthly => const EventRepeat(unit: RepeatUnit.month),
      _RepeatOption.yearly => const EventRepeat(unit: RepeatUnit.year),
      _RepeatOption.selectedDays => EventRepeat(
        unit: RepeatUnit.week,
        weekdays: weekly && _repeat.weekdays.isNotEmpty
            ? _repeat.weekdays
            : {_date.weekday},
      ),
      _RepeatOption.custom => await _showCustomRepeatSheet(
        context,
        initial: _repeat.repeats
            ? _repeat
            : const EventRepeat(unit: RepeatUnit.week),
        start: _date,
      ),
    };
    if (next == null || !mounted) return;
    setState(() {
      _repeat = next;
      _recurrenceChanged = true;
    });
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final draft = CalendarEventDraft(
      title: title,
      date: _date,
      startTime: _startTime,
      endTime: _endTime,
      isAllDay: _isAllDay,
      recurrence: _repeat.recurrence(allDay: _isAllDay),
      calendarId: _selectedCalendar.id,
    );
    if (!widget.isEditing) {
      Navigator.pop(context, draft);
      return;
    }
    final scope = widget.repeating
        ? await askEventScope(
            context,
            title: 'Edit repeating event',
            message: _recurrenceChanged
                ? 'A new repeat rule applies to every event in the series.'
                : 'Apply your changes to only this event, or to every event in the series?',
            allowSingle: !_recurrenceChanged,
          )
        : EventScope.thisEvent;
    if (scope == null || !mounted) return;
    Navigator.pop(
      context,
      CalendarEventEditResult.save(
        draft,
        recurrenceChanged: _recurrenceChanged,
        scope: scope,
      ),
    );
  }

  Future<void> _delete() async {
    final title = _titleController.text.trim();
    final scope = await confirmEventDelete(
      context,
      title: title.isEmpty ? 'Untitled event' : title,
      repeating: widget.repeating,
    );
    if (scope != null && mounted) {
      Navigator.pop(context, CalendarEventEditResult.delete(scope: scope));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: colors.textPrimary.withValues(alpha: .18)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 32,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 14),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 14, 4),
              child: Row(
                children: [
                  const SizedBox(width: 42),
                  Expanded(
                    child:
                        widget.header ??
                        Text(
                          widget.isEditing ? 'Edit Event' : 'Add Event',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SheetLabel('EVENT'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _titleController,
                      autofocus: !widget.isEditing,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: colors.textPrimary, fontSize: 17),
                      decoration: InputDecoration(
                        hintText: 'Event title',
                        filled: true,
                        fillColor: colors.textPrimary.withValues(alpha: .045),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: colors.textPrimary.withValues(alpha: .14),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: colors.textPrimary.withValues(alpha: .14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const _SheetLabel('SCHEDULE'),
                    const SizedBox(height: 10),
                    _SheetCard(
                      children: [
                        _PickerRow(
                          icon: Icons.calendar_month_rounded,
                          label: 'Date',
                          value: DateFormat('MMMM d, y').format(_date),
                          onTap: _pickDate,
                        ),
                        _PickerRow(
                          icon: Icons.schedule_rounded,
                          label: 'Start time',
                          value: _startTime.format(context),
                          enabled: !_isAllDay,
                          onTap: () => _pickTime(start: true),
                        ),
                        _PickerRow(
                          icon: Icons.schedule_rounded,
                          label: 'End time',
                          value: _endTime.format(context),
                          enabled: !_isAllDay,
                          onTap: () => _pickTime(start: false),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'All-day event',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _isAllDay,
                                activeThumbColor: Colors.white,
                                activeTrackColor: _purple,
                                onChanged: (value) =>
                                    setState(() => _isAllDay = value),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    const _SheetLabel('REPEAT'),
                    const SizedBox(height: 10),
                    _SheetCard(
                      children: [
                        PopupMenuButton<_RepeatOption>(
                          tooltip: 'Repeat',
                          position: PopupMenuPosition.under,
                          color: colors.cardMuted,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          onSelected: _chooseRepeat,
                          itemBuilder: (_) => [
                            for (final (option, label) in _repeatOptions) ...[
                              if (option == _RepeatOption.custom)
                                const PopupMenuDivider(),
                              CheckedPopupMenuItem(
                                value: option,
                                checked: option == _optionFor(_repeat),
                                child: Text(label),
                              ),
                            ],
                          ],
                          // No onTap: the tap belongs to the menu button.
                          child: _PickerRow(
                            icon: Icons.repeat_rounded,
                            label: 'Repeat',
                            value: switch (_optionFor(_repeat)) {
                              _RepeatOption.custom => 'Custom',
                              _RepeatOption.selectedDays => 'Selected days',
                              _ => _repeat.describe(),
                            },
                          ),
                        ),
                      ],
                    ),
                    // Long rules would be cut off in the row, so spell them out.
                    if (_optionFor(_repeat) == _RepeatOption.custom) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _repeat.describe(),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                    if (_optionFor(_repeat) == _RepeatOption.selectedDays) ...[
                      const SizedBox(height: 12),
                      _WeekdaySelector(
                        selected: _repeat.weekdays,
                        onChanged: (days) => setState(() {
                          _repeat = _repeat.copyWith(weekdays: days);
                          _recurrenceChanged = true;
                        }),
                      ),
                    ],
                    const SizedBox(height: 26),
                    const _SheetLabel('CALENDAR'),
                    const SizedBox(height: 10),
                    _SheetCard(
                      children: [
                        _PickerRow(
                          icon: Icons.calendar_month_rounded,
                          label: 'Calendar',
                          value: _loadingCalendars
                              ? 'Loading…'
                              : _selectedCalendar.name,
                          calendarColor: _calendarColor(
                            _selectedCalendar.colorHex,
                          ),
                          enabled: !_loadingCalendars,
                          onTap: _pickCalendar,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4148F5), Color(0xFF5D45DC)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: FilledButton(
                          onPressed: _titleController.text.trim().isEmpty
                              ? null
                              : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            widget.isEditing ? 'Save Changes' : 'Add Event',
                            style: const TextStyle(fontSize: 17),
                          ),
                        ),
                      ),
                    ),
                    if (widget.isEditing) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: TextButton.icon(
                          onPressed: _delete,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFF574D),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Delete Event'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFFA9A7D8),
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
    ),
  );
}

class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colors.textPrimary.withValues(alpha: .13)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index < children.length - 1)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: colors.textPrimary.withValues(alpha: .09),
              ),
          ],
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.enabled = true,
    this.calendarColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? calendarColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Opacity(
      opacity: enabled ? 1 : .42,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Row(
            children: [
              Icon(icon, color: _purple, size: 23),
              const SizedBox(width: 16),
              SizedBox(
                width: 105,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textPrimary, fontSize: 16),
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (calendarColor != null) ...[
                      const SizedBox(width: 9),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: calendarColor,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 11, height: 11),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.choices,
    required this.onChanged,
  });
  final T value;
  final List<(T, String)> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colors.textPrimary.withValues(alpha: .13)),
      ),
      child: Row(
        children: [
          for (final choice in choices)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => onChanged(choice.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: value == choice.$1
                        ? const LinearGradient(
                            colors: [Color(0xFF494AF5), Color(0xFF6546E7)],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    choice.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: value == choice.$1
                          ? Colors.white
                          : colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekdaySelector extends StatelessWidget {
  const _WeekdaySelector({required this.selected, required this.onChanged});
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    const days = [
      (7, 'S'),
      (1, 'M'),
      (2, 'T'),
      (3, 'W'),
      (4, 'T'),
      (5, 'F'),
      (6, 'S'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final day in days)
          InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () {
              final updated = Set<int>.from(selected);
              if (updated.contains(day.$1)) {
                if (updated.length > 1) updated.remove(day.$1);
              } else {
                updated.add(day.$1);
              }
              onChanged(updated);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected.contains(day.$1)
                    ? _purple
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Text(
                day.$2,
                style: TextStyle(
                  color: selected.contains(day.$1)
                      ? Colors.white
                      : context.vivordoColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<EventRepeat?> _showCustomRepeatSheet(
  BuildContext context, {
  required EventRepeat initial,
  required DateTime start,
}) => showModalBottomSheet<EventRepeat>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _CustomRepeatSheet(initial: initial, start: start),
);

class _CustomRepeatSheet extends StatefulWidget {
  const _CustomRepeatSheet({required this.initial, required this.start});
  final EventRepeat initial;
  final DateTime start;

  @override
  State<_CustomRepeatSheet> createState() => _CustomRepeatSheetState();
}

class _CustomRepeatSheetState extends State<_CustomRepeatSheet> {
  late EventRepeat _repeat =
      widget.initial.unit == RepeatUnit.week && widget.initial.weekdays.isEmpty
      ? widget.initial.copyWith(weekdays: {widget.start.weekday})
      : widget.initial;

  void _setUnit(RepeatUnit unit) => setState(() {
    _repeat = EventRepeat(
      unit: unit,
      interval: _repeat.interval,
      weekdays: unit == RepeatUnit.week ? {widget.start.weekday} : const {},
      until: _repeat.until,
    );
  });

  Future<void> _pickUntil() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _repeat.until ?? widget.start.add(const Duration(days: 30)),
      firstDate: widget.start,
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _repeat = _repeat.copyWith(until: value));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final interval = _repeat.interval;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Custom repeat',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          const _SheetLabel('EVERY'),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Fewer',
                onPressed: interval > 1
                    ? () => setState(
                        () =>
                            _repeat = _repeat.copyWith(interval: interval - 1),
                      )
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '$interval',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'More',
                onPressed: interval < 99
                    ? () => setState(
                        () =>
                            _repeat = _repeat.copyWith(interval: interval + 1),
                      )
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Segmented(
            value: _repeat.unit!,
            choices: [
              for (final unit in RepeatUnit.values)
                (
                  unit,
                  '${unit.name[0].toUpperCase()}${unit.name.substring(1)}${interval == 1 ? '' : 's'}',
                ),
            ],
            onChanged: _setUnit,
          ),
          if (_repeat.unit == RepeatUnit.week) ...[
            const SizedBox(height: 20),
            const _SheetLabel('ON'),
            const SizedBox(height: 10),
            _WeekdaySelector(
              selected: _repeat.weekdays,
              onChanged: (days) =>
                  setState(() => _repeat = _repeat.copyWith(weekdays: days)),
            ),
          ],
          const SizedBox(height: 20),
          const _SheetLabel('ENDS'),
          const SizedBox(height: 10),
          _Segmented(
            value: _repeat.until != null,
            choices: const [(false, 'Never'), (true, 'On date')],
            onChanged: (onDate) {
              if (onDate) {
                _pickUntil();
              } else {
                setState(() => _repeat = _repeat.copyWith(clearUntil: true));
              }
            },
          ),
          if (_repeat.until != null) ...[
            const SizedBox(height: 10),
            _SheetCard(
              children: [
                _PickerRow(
                  icon: Icons.event_busy_rounded,
                  label: 'End date',
                  value: DateFormat('MMM d, y').format(_repeat.until!),
                  onTap: _pickUntil,
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Text(
            _repeat.describe(),
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _repeat),
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Done', style: TextStyle(fontSize: 17)),
            ),
          ),
        ],
      ),
    );
  }
}
