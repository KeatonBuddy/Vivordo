import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/calendar_service.dart';
import '../src/services/outlook_calendar_service.dart';
import '../widgets/add_calendar_event_sheet.dart';

class MonthCalendarScreen extends StatefulWidget {
  const MonthCalendarScreen({super.key});

  @override
  State<MonthCalendarScreen> createState() => _MonthCalendarScreenState();
}

class _MonthCalendarScreenState extends State<MonthCalendarScreen> {
  static const _googleBlue = Color(0xFF5B7DE8);
  static const _outlookOrange = Color(0xFFF4A62A);

  late DateTime _visibleMonth;
  late DateTime _selectedDay;
  List<_MonthEvent> _events = const [];
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDay = today;
    _loadEvents();
  }

  DateTime get _gridStart {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    return first.subtract(Duration(days: first.weekday % 7));
  }

  Future<void> _loadEvents() async {
    final generation = ++_loadGeneration;
    if (mounted) setState(() => _loading = true);
    final start = _gridStart;
    final end = start.add(const Duration(days: 42));

    final results = await Future.wait([
      CalendarService.getEventsBetween(
        start,
        end,
      ).timeout(const Duration(seconds: 10), onTimeout: () => <gcal.Event>[]),
      OutlookCalendarService.getEventsBetween(
        start,
        end,
      ).timeout(const Duration(seconds: 10), onTimeout: () => <OutlookEvent>[]),
    ]);

    if (!mounted || generation != _loadGeneration) return;
    final googleEvents = results[0] as List<gcal.Event>;
    final outlookEvents = results[1] as List<OutlookEvent>;
    final events = <_MonthEvent>[
      ...googleEvents.map(_MonthEvent.fromGoogle).whereType<_MonthEvent>(),
      ...outlookEvents.map(_MonthEvent.fromOutlook),
    ]..sort((a, b) => a.start.compareTo(b.start));

    setState(() {
      _events = events;
      _loading = false;
    });
  }

  void _changeMonth(int offset) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    setState(() {
      _visibleMonth = next;
      _selectedDay = DateTime(next.year, next.month, 1);
    });
    _loadEvents();
  }

  void _goToToday() {
    final today = DateUtils.dateOnly(DateTime.now());
    final monthChanged =
        today.year != _visibleMonth.year || today.month != _visibleMonth.month;
    setState(() {
      _visibleMonth = DateTime(today.year, today.month);
      _selectedDay = today;
    });
    if (monthChanged) _loadEvents();
  }

  List<_MonthEvent> _eventsFor(DateTime day) {
    final start = DateUtils.dateOnly(day);
    final end = start.add(const Duration(days: 1));
    return _events
        .where((event) => event.start.isBefore(end) && event.end.isAfter(start))
        .toList();
  }

  void _selectDay(DateTime day) {
    if (day.month != _visibleMonth.month || day.year != _visibleMonth.year) {
      setState(() {
        _visibleMonth = DateTime(day.year, day.month);
        _selectedDay = DateUtils.dateOnly(day);
      });
      _loadEvents();
      return;
    }
    setState(() => _selectedDay = DateUtils.dateOnly(day));
  }

  Future<void> _handleEventTap(_MonthEvent event) async {
    final googleEvent = event.googleEvent;
    if (googleEvent == null) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(event.timeLabel),
                const SizedBox(height: 18),
                const Text(
                  'Outlook events are read-only in Vivordo. Open Outlook to edit or delete this event.',
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    final action = await showModalBottomSheet<_EventAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: Theme.of(sheetContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(event.timeLabel),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Edit event'),
                onTap: () => Navigator.pop(sheetContext, _EventAction.edit),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                iconColor: Colors.red,
                textColor: Colors.red,
                title: const Text('Delete event'),
                onTap: () => Navigator.pop(sheetContext, _EventAction.delete),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    switch (action) {
      case _EventAction.edit:
        await _editGoogleEvent(googleEvent);
        return;
      case _EventAction.delete:
        await _deleteGoogleEvent(googleEvent);
        return;
      case null:
        return;
    }
  }

  Future<void> _editGoogleEvent(gcal.Event event) async {
    final originalStart =
        event.start?.dateTime?.toLocal() ?? event.start?.date?.toLocal();
    final originalEnd =
        event.end?.dateTime?.toLocal() ?? event.end?.date?.toLocal();
    if (originalStart == null || originalEnd == null) {
      _showMessage('This event does not have a valid date.');
      return;
    }

    final isAllDay = event.start?.dateTime == null;
    final titleController = TextEditingController(text: event.summary ?? '');
    var title = titleController.text.trim();
    var date = DateUtils.dateOnly(originalStart);
    var startTime = TimeOfDay.fromDateTime(originalStart);
    var endTime = TimeOfDay.fromDateTime(originalEnd);
    final allDayDuration = originalEnd.difference(originalStart);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Edit event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (value) {
                    setDialogState(() => title = value.trim());
                  },
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_rounded),
                  title: const Text('Date'),
                  subtitle: Text(DateFormat('MMMM d, y').format(date)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => date = picked);
                    }
                  },
                ),
                if (!isAllDay) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('Start time'),
                    trailing: Text(startTime.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: startTime,
                      );
                      if (picked != null) {
                        setDialogState(() => startTime = picked);
                      }
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('End time'),
                    trailing: Text(endTime.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: endTime,
                      );
                      if (picked != null) {
                        setDialogState(() => endTime = picked);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: title.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    title = titleController.text.trim();
    titleController.dispose();
    if (shouldSave != true || !mounted || title.isEmpty) return;

    late DateTime start;
    late DateTime end;
    if (isAllDay) {
      start = DateUtils.dateOnly(date);
      end = start.add(
        allDayDuration > Duration.zero
            ? allDayDuration
            : const Duration(days: 1),
      );
    } else {
      start = _withTime(date, startTime);
      end = _withTime(date, endTime);
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    }

    try {
      await CalendarService.updateEvent(
        event,
        title: title,
        start: start,
        end: end,
      );
      await _loadEvents();
      _showMessage('Event updated.');
    } catch (error) {
      _showMessage('Could not update event: $error');
    }
  }

  Future<void> _deleteGoogleEvent(gcal.Event event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text(
          'This will delete “${event.summary ?? 'Untitled event'}” from Google Calendar.',
        ),
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
    if (confirmed != true || !mounted) return;

    try {
      await CalendarService.deleteEvent(event);
      await _loadEvents();
      _showMessage('Event deleted.');
    } catch (error) {
      _showMessage('Could not delete event: $error');
    }
  }

  Future<void> _createGoogleEvent() async {
    final now = DateTime.now();
    final isToday = DateUtils.isSameDay(_selectedDay, now);
    final initialStart = isToday
        ? DateTime(
            now.year,
            now.month,
            now.day,
            now.minute < 30 ? now.hour : now.hour + 1,
            now.minute < 30 ? 30 : 0,
          )
        : DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 9);
    final draft = await showAddCalendarEventSheet(
      context,
      initialStart: initialStart,
      initialEnd: initialStart.add(const Duration(hours: 1)),
    );
    if (draft == null || !mounted) return;

    try {
      setState(() => _loading = true);
      await CalendarService.createEvent(
        title: draft.title,
        start: draft.start,
        end: draft.end,
        recurrence: draft.recurrence,
        isAllDay: draft.isAllDay,
        calendarId: draft.calendarId,
      );
      if (!mounted) return;
      setState(() {
        _visibleMonth = DateTime(draft.date.year, draft.date.month);
        _selectedDay = DateUtils.dateOnly(draft.date);
      });
      await _loadEvents();
      _showMessage('Event added to Google Calendar.');
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      _showMessage('Could not create event: $error');
    }
  }

  DateTime _withTime(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final start = _gridStart;
    final days = List.generate(42, (index) => start.add(Duration(days: index)));
    final selectedEvents = _eventsFor(_selectedDay);

    return Scaffold(
      backgroundColor: colors.page,
      appBar: AppBar(
        backgroundColor: colors.page,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        title: Text(
          'Calendar',
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loading ? null : _createGoogleEvent,
            tooltip: 'Add event',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded),
          ),
          TextButton(onPressed: _goToToday, child: const Text('Today')),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadEvents,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM y').format(_visibleMonth),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                  .map(
                    (label) => Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF85859B),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.card,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(20),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: days.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    // Month cells need enough vertical room for the date plus
                    // three compact event labels on narrow phones.
                    mainAxisExtent: 96,
                  ),
                  itemBuilder: (context, index) {
                    final day = days[index];
                    return _CalendarDayCell(
                      day: day,
                      events: _eventsFor(day),
                      inMonth: day.month == _visibleMonth.month,
                      selected: DateUtils.isSameDay(day, _selectedDay),
                      today: DateUtils.isSameDay(day, DateTime.now()),
                      loading: _loading,
                      onTap: () => _selectDay(day),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                DateFormat('EEEE, MMMM d').format(_selectedDay).toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF85859B),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (selectedEvents.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  'No events scheduled',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < selectedEvents.length; i++) ...[
                      _AgendaEventTile(
                        event: selectedEvents[i],
                        onTap: () => _handleEventTap(selectedEvents[i]),
                      ),
                      if (i != selectedEvents.length - 1)
                        Divider(height: 1, indent: 64, color: colors.border),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.events,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.loading,
    required this.onTap,
  });

  final DateTime day;
  final List<_MonthEvent> events;
  final bool inMonth;
  final bool selected;
  final bool today;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    // Busy days use the third row for the overflow summary instead of adding
    // an unbounded fourth row below the event chips.
    final visibleEventCount = events.length > 3 ? 2 : 3;
    final visibleEvents = events.take(visibleEventCount).toList();
    final hiddenEventCount = events.length - visibleEvents.length;
    return Material(
      color: selected
          ? const Color(0xFF6B5CE7).withValues(alpha: .08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: colors.border, width: .6),
              bottom: BorderSide(color: colors.border, width: .6),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(3, 5, 3, 3),
          child: Column(
            children: [
              Container(
                width: 25,
                height: 25,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: today
                      ? const Color(0xFF6B5CE7)
                      : selected
                      ? const Color(0xFFDCD7FF)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    color: today
                        ? Colors.white
                        : inMonth
                        ? colors.textPrimary
                        : colors.textSecondary.withValues(alpha: .5),
                    fontSize: 11,
                    fontWeight: today || selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (loading)
                Container(
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: colors.cardMuted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )
              else
                for (final event in visibleEvents)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: event.color.withValues(alpha: .85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 7.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              if (!loading && hiddenEventCount > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '+$hiddenEventCount more',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 7.5,
                      fontWeight: FontWeight.w700,
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

class _AgendaEventTile extends StatelessWidget {
  const _AgendaEventTile({required this.event, required this.onTap});

  final _MonthEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: event.color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.event_rounded, color: event.color, size: 20),
      ),
      title: Text(
        event.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.vivordoColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(event.timeLabel),
      trailing: const Icon(Icons.chevron_right_rounded),
    ),
  );
}

enum _EventAction { edit, delete }

class _MonthEvent {
  const _MonthEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.color,
    this.googleEvent,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final Color color;
  final gcal.Event? googleEvent;

  static _MonthEvent? fromGoogle(gcal.Event event) {
    final start =
        event.start?.dateTime?.toLocal() ?? event.start?.date?.toLocal();
    final end = event.end?.dateTime?.toLocal() ?? event.end?.date?.toLocal();
    if (start == null || end == null) return null;
    return _MonthEvent(
      title: event.summary?.trim().isNotEmpty == true
          ? event.summary!.trim()
          : 'Untitled event',
      start: start,
      end: end,
      isAllDay: event.start?.dateTime == null,
      color: _MonthCalendarScreenState._googleBlue,
      googleEvent: event,
    );
  }

  factory _MonthEvent.fromOutlook(OutlookEvent event) => _MonthEvent(
    title: event.subject.trim().isEmpty
        ? 'Untitled event'
        : event.subject.trim(),
    start: event.start.toLocal(),
    end: event.end.toLocal(),
    isAllDay: event.isAllDay,
    color: _MonthCalendarScreenState._outlookOrange,
  );

  String get timeLabel => isAllDay
      ? 'All day'
      : '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}';
}
