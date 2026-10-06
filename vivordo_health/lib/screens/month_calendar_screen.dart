import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/calendar_service.dart';
import '../src/services/outlook_calendar_service.dart';
import '../src/utils/day_agenda.dart';
import '../widgets/add_calendar_event_sheet.dart';
import '../widgets/add_priority_sheet.dart';
import '../widgets/apple_ui.dart';
import '../widgets/calendar_event_summary_sheet.dart';
import '../widgets/day_timeline.dart';
import '../widgets/plan_slot_sheet.dart';

class MonthCalendarScreen extends StatefulWidget {
  const MonthCalendarScreen({super.key, this.initialDay});
  final DateTime? initialDay;

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
  String? _loadError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(widget.initialDay ?? DateTime.now());
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDay = today;
    _loadEvents();
  }

  DateTime get _gridStart {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    return first.subtract(Duration(days: first.weekday % 7));
  }

  /// Only as many week rows as the visible month needs (5 or 6, rarely 4).
  int get _gridDays {
    final lead = DateTime(_visibleMonth.year, _visibleMonth.month).weekday % 7;
    final length = DateUtils.getDaysInMonth(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    return ((lead + length + 6) ~/ 7) * 7;
  }

  /// [forceRefresh] bypasses the shared calendar cache for pull-to-refresh.
  Future<void> _loadEvents({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    if (mounted) setState(() => _loading = true);
    final start = _gridStart;
    final end = start.add(Duration(days: _gridDays));

    final List<Object> results;
    try {
      results = await Future.wait<Object>([
        CalendarService.getEventsBetween(
          start,
          end,
          forceRefresh: forceRefresh,
        ).timeout(const Duration(seconds: 10)),
        OutlookCalendarService.getEventsBetween(
          start,
          end,
          forceRefresh: forceRefresh,
        ).timeout(const Duration(seconds: 10)),
      ]);
    } catch (error) {
      // A failed load must not look like an empty calendar.
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load your calendar. Pull down to retry.';
        });
      }
      return;
    }

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
      _loadError = null;
    });
  }

  void _changeMonth(int offset) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() {
      _visibleMonth = next;
      _selectedDay = today.year == next.year && today.month == next.month
          ? today
          : next;
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
    final end = DateTime(start.year, start.month, start.day + 1);
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
    final action = await showCalendarEventSummarySheet(
      context,
      event: CalendarEventSummaryData(
        title: event.title,
        start: event.start,
        end: event.end,
        isAllDay: event.isAllDay,
        isRecurring:
            googleEvent?.recurringEventId != null ||
            googleEvent?.recurrence?.isNotEmpty == true,
        color: event.color,
        calendarName: googleEvent == null ? 'Outlook' : 'Google Calendar',
        canEdit: googleEvent != null,
      ),
    );
    if (googleEvent == null || !mounted) return;
    switch (action) {
      case CalendarEventSummaryAction.edit:
        await _editGoogleEvent(googleEvent);
        return;
      case CalendarEventSummaryAction.delete:
        await _deleteGoogleEvent(googleEvent);
        return;
      case null:
        return;
    }
  }

  Future<void> _editGoogleEvent(gcal.Event event) async {
    final result = await showEditCalendarEventSheet(context, event: event);
    if (result == null || !mounted) return;

    try {
      setState(() => _loading = true);
      final allEvents = result.scope == EventScope.allEvents;
      if (result.action == CalendarEventEditAction.delete) {
        await CalendarService.deleteEvent(event, scope: result.scope);
      } else {
        final draft = result.draft!;
        await CalendarService.updateEvent(
          event,
          title: draft.title,
          start: draft.start,
          end: draft.end,
          recurrence: result.recurrenceChanged ? draft.recurrence : null,
          calendarId: draft.calendarId,
          isAllDay: draft.isAllDay,
          allEvents: allEvents,
        );
      }
      await _loadEvents();
      _showMessage(
        result.action == CalendarEventEditAction.delete
            ? 'Event deleted.'
            : 'Event updated.',
      );
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      debugPrint('Save calendar event failed: $error');
      _showMessage("Couldn't save the event. Try again.", error: true);
    }
  }

  Future<void> _deleteGoogleEvent(gcal.Event event) async {
    final scope = await confirmEventDelete(
      context,
      title: event.summary ?? 'Untitled event',
      repeating: event.recurringEventId != null,
    );
    if (scope == null || !mounted) return;

    try {
      setState(() => _loading = true);
      await CalendarService.deleteEvent(event, scope: scope);
      await _loadEvents();
      _showMessage('Event deleted.');
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      debugPrint('Delete calendar event failed: $error');
      _showMessage("Couldn't delete the event. Try again.", error: true);
    }
  }

  /// The header "+": the next half hour today, 9 AM on any other day.
  Future<void> _addForSelectedDay() {
    final now = DateTime.now();
    final start = DateUtils.isSameDay(_selectedDay, now)
        ? DateTime(
            now.year,
            now.month,
            now.day,
            now.minute < 30 ? now.hour : now.hour + 1,
            now.minute < 30 ? 30 : 0,
          )
        : DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 9);
    return _planSlot(start);
  }

  /// Opens the Priority / Event sheet for a slot starting at [start].
  Future<void> _planSlot(DateTime start, [DateTime? end]) async {
    final result = await showPlanSlotSheet(context, start: start, end: end);
    if (!mounted) return;
    switch (result) {
      case PriorityDraft draft:
        final String? warning;
        try {
          warning = await savePriorityDraft(draft);
        } catch (error) {
          debugPrint('Add priority failed: $error');
          _showMessage("Couldn't add the priority. Try again.", error: true);
          return;
        }
        _showMessage(warning ?? 'Priority added.');
        if (draft.addToCalendar && mounted) {
          await _loadEvents(forceRefresh: true);
        }
      case CalendarEventDraft draft:
        try {
          setState(() => _loading = true);
          await saveEventDraft(draft);
          if (!mounted) return;
          setState(() {
            _visibleMonth = DateTime(draft.date.year, draft.date.month);
            _selectedDay = DateUtils.dateOnly(draft.date);
          });
          await _loadEvents(forceRefresh: true);
          _showMessage('Event added to Google Calendar.');
        } catch (error) {
          if (mounted) setState(() => _loading = false);
          debugPrint('Create calendar event failed: $error');
          _showMessage("Couldn't add the event. Try again.", error: true);
        }
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    showToast(context, message, kind: error ? ToastKind.error : ToastKind.info);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final start = _gridStart;
    final days = [
      for (var i = 0; i < _gridDays; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
    final now = DateTime.now();
    final hasGoogle = _events.any((e) => e.googleEvent != null);
    final hasOutlook = _events.any((e) => e.googleEvent == null);

    return Scaffold(
      backgroundColor: colors.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadEvents(forceRefresh: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      size: 30,
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TimelinePill(
                    'Today',
                    color: VivordoTheme.brand,
                    onTap: _goToToday,
                  ),
                  IconButton(
                    onPressed: _loading ? null : _addForSelectedDay,
                    tooltip: 'Add',
                    icon: const Icon(
                      Icons.add_rounded,
                      color: VivordoTheme.brand,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 0, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: DateFormat('MMMM').format(_visibleMonth),
                              style: TextStyle(color: colors.textPrimary),
                            ),
                            TextSpan(
                              text: ' ${_visibleMonth.year}',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ],
                        ),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () => _changeMonth(-1),
                      icon: Icon(
                        Icons.chevron_left_rounded,
                        color: colors.textSecondary,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: () => _changeMonth(1),
                      icon: Icon(
                        Icons.chevron_right_rounded,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 16,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _loadError!,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              GestureDetector(
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() > 250) _changeMonth(velocity < 0 ? 1 : -1);
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          for (final label in const [
                            'S',
                            'M',
                            'T',
                            'W',
                            'T',
                            'F',
                            'S',
                          ])
                            Expanded(
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (var week = 0; week < days.length; week += 7)
                        Row(
                          children: [
                            for (final day in days.sublist(week, week + 7))
                              Expanded(
                                child: _CalendarDayCell(
                                  day: day,
                                  events: _eventsFor(day),
                                  inMonth: day.month == _visibleMonth.month,
                                  selected: DateUtils.isSameDay(
                                    day,
                                    _selectedDay,
                                  ),
                                  today: DateUtils.isSameDay(day, now),
                                  onTap: () => _selectDay(day),
                                ),
                              ),
                          ],
                        ),
                      if (hasGoogle && hasOutlook) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _LegendDot(color: _googleBlue, label: 'Google'),
                            const SizedBox(width: 14),
                            _LegendDot(color: _outlookOrange, label: 'Outlook'),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _buildSelectedDay(now),
            ],
          ),
        ),
      ),
    );
  }

  /// Today runs from now to the end of the day, like My Day. Other future
  /// days run from their first event to their last. Past days list events.
  Widget _buildSelectedDay(DateTime now) {
    final colors = context.vivordoColors;
    final day = _selectedDay;
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    final events = _eventsFor(day);
    final allDay = events.where((e) => e.isAllDay).toList();
    final items = [
      for (final e in events.where((e) => !e.isAllDay))
        AgendaItem(
          e,
          e.start.isBefore(day) ? day : e.start,
          e.end.isAfter(dayEnd) ? dayEnd : e.end,
        ),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final isToday = DateUtils.isSameDay(day, now);
    final isPast = !isToday && day.isBefore(now);
    final earlier = isToday
        ? items
              .where((i) => !i.end.isAfter(now) && i.start.isBefore(now))
              .toList()
        : const <AgendaItem<_MonthEvent>>[];
    final List<AgendaEntry<_MonthEvent>> agenda = isToday
        ? buildDayAgenda(now, items)
        : isPast || items.isEmpty
        ? items
        : buildDayAgenda(items.first.start, items, openEnded: false);
    final openMinutes = agenda.fold<int>(
      0,
      (sum, entry) => entry is AgendaOpening<_MonthEvent> && entry.end != null
          ? sum + entry.end!.difference(entry.start).inMinutes
          : sum,
    );
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final summary = [
      if (isToday) 'Today',
      if (DateUtils.isSameDay(day, tomorrow)) 'Tomorrow',
      if (DateUtils.isSameDay(day, yesterday)) 'Yesterday',
      if (!_loading)
        events.isEmpty
            ? 'No events'
            : '${events.length} ${events.length == 1 ? 'event' : 'events'}',
      if (!_loading && openMinutes > 0)
        '${formatSpan(Duration(minutes: openMinutes))} open',
    ].join(' · ');

    Widget row(AgendaItem<_MonthEvent> entry, {bool past = false}) =>
        TimelineRow(
          start: entry.start,
          title: entry.item.title,
          detail: [
            formatSpan(entry.end.difference(entry.start)),
            if (entry.item.googleEvent == null) 'Outlook',
          ].join(' · '),
          color: entry.item.color,
          past: past,
          onTap: () => _handleEventTap(entry.item),
        );

    final Widget body;
    if (_loading && events.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (earlier.isEmpty && agenda.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No events scheduled',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            for (final entry in earlier) row(entry, past: true),
            if (isToday) TimelineNowLine(now),
            for (final entry in agenda)
              switch (entry) {
                AgendaItem<_MonthEvent>() => row(entry, past: isPast),
                AgendaOpening<_MonthEvent>(:final start, :final end) =>
                  TimelineOpeningRow(
                    start: start,
                    label: end == null
                        ? 'Open · rest of day'
                        : 'Open · ${formatSpan(end.difference(start))}',
                    onPlan: () => _planSlot(start, end),
                  ),
                AgendaBreak<_MonthEvent>(:final minutes) => TimelineBreakRow(
                  minutes,
                ),
              },
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, MMM d').format(day),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  summary,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        if (allDay.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final event in allDay)
                TimelinePill(
                  'All day · ${event.title}',
                  color: event.color,
                  onTap: () => _handleEventTap(event),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border),
          ),
          child: body,
        ),
      ],
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
    required this.onTap,
  });

  final DateTime day;
  final List<_MonthEvent> events;
  final bool inMonth;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${DateFormat('EEEE, MMMM d').format(day)}, ${events.isEmpty ? 'no events' : '${events.length} ${events.length == 1 ? 'event' : 'events'}'}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 46,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: selected
                  ? VivordoTheme.brand.withValues(alpha: .16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: today ? VivordoTheme.brand : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: today
                          ? Colors.white
                          : inMonth
                          ? colors.textPrimary
                          : colors.textSecondary.withValues(alpha: .45),
                      fontSize: 14,
                      fontWeight: today || selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 5,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final event in events.take(3))
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: event.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
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

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(
          color: context.vivordoColors.textSecondary,
          fontSize: 11,
        ),
      ),
    ],
  );
}

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
}
