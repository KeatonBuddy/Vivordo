import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';

import '../src/services/calendar_service.dart';
import '../src/services/outlook_calendar_service.dart';
import 'home_screen.dart' show WeeklyCalendar;

class MyDayScreen extends StatefulWidget {
  const MyDayScreen({super.key});

  static const purple = Color(0xFF6B5CE7);
  static const background = Color(0xFFF2F2F7);
  static const ink = Color(0xFF17172B);
  static const muted = Color(0xFF85859B);

  @override
  State<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends State<MyDayScreen> {
  List<_CalendarEvent> _events = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTodayEvents();
  }

  Future<void> _loadTodayEvents() async {
    if (mounted) setState(() => _isLoading = true);
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final results = await Future.wait([
      CalendarService.getEventsBetween(
        dayStart,
        dayEnd,
      ).timeout(const Duration(seconds: 8), onTimeout: () => <gcal.Event>[]),
      OutlookCalendarService.getEventsBetween(
        dayStart,
        dayEnd,
      ).timeout(const Duration(seconds: 8), onTimeout: () => <OutlookEvent>[]),
    ]);

    final googleEvents = results[0] as List<gcal.Event>;
    final outlookEvents = results[1] as List<OutlookEvent>;
    final events =
        <_CalendarEvent>[
              ...googleEvents
                  .map(_CalendarEvent.fromGoogle)
                  .whereType<_CalendarEvent>(),
              ...outlookEvents.map(_CalendarEvent.fromOutlook),
            ]
            .where(
              (event) =>
                  event.start.isBefore(dayEnd) && event.end.isAfter(dayStart),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    if (!mounted) return;
    setState(() {
      _events = events;
      _isLoading = false;
    });
  }

  Future<void> _handleEventTap(_CalendarEvent event) async {
    final googleEvent = event.googleEvent;
    if (googleEvent == null) {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text('${event.timeLabel} · ${event.durationLabel}'),
                const SizedBox(height: 18),
                const Text(
                  'Outlook events are read-only in Vivordo. Open Outlook to edit this event.',
                  style: TextStyle(color: MyDayScreen.muted),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    await _editGoogleEvent(googleEvent);
  }

  Future<void> _editGoogleEvent(gcal.Event event) async {
    final originalStart = event.start?.dateTime?.toLocal();
    final originalEnd = event.end?.dateTime?.toLocal();
    if (originalStart == null || originalEnd == null) {
      _showMessage('All-day events cannot be edited here yet.');
      return;
    }

    var title = event.summary ?? '';
    var date = DateUtils.dateOnly(originalStart);
    var startTime = TimeOfDay.fromDateTime(originalStart);
    var endTime = TimeOfDay.fromDateTime(originalEnd);

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
                TextFormField(
                  initialValue: title,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Event title',
                    prefixIcon: Icon(Icons.event_rounded),
                  ),
                  onChanged: (value) => title = value,
                ),
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
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
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
                    if (picked != null) setDialogState(() => endTime = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (shouldSave != true || !mounted) return;
    title = title.trim();
    if (title.isEmpty) {
      _showMessage('Enter an event title.');
      return;
    }

    final start = DateTime(
      date.year,
      date.month,
      date.day,
      startTime.hour,
      startTime.minute,
    );
    var end = DateTime(
      date.year,
      date.month,
      date.day,
      endTime.hour,
      endTime.minute,
    );
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

    try {
      await CalendarService.updateEvent(
        event,
        title: title,
        start: start,
        end: end,
      );
      await _loadTodayEvents();
      _showMessage('Event updated.');
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      _showMessage('Could not update event: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final load = _events.length >= 6
        ? 'High'
        : _events.length >= 3
        ? 'Moderate'
        : 'Low';

    return Scaffold(
      backgroundColor: MyDayScreen.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadTodayEvents,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 150),
            children: [
              const Text(
                'My Day',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: MyDayScreen.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE, MMMM d').format(DateTime.now()),
                style: const TextStyle(color: MyDayScreen.muted),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7667F4), Color(0xFF5845DF)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.speed_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "TODAY'S LOAD SCORE",
                            style: TextStyle(
                              color: Color(0xFFDCD6FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            load,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${_events.length} calendar events · Balanced focus time',
                            style: const TextStyle(
                              color: Color(0xFFE7E3FF),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "TODAY'S EVENTS",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: MyDayScreen.muted,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: .07),
                  ),
                ),
                child: _buildEvents(),
              ),
              const SizedBox(height: 28),
              const Text(
                'WEEKLY CALENDAR',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: MyDayScreen.muted,
                ),
              ),
              const SizedBox(height: 12),
              const WeeklyCalendar(),
              const SizedBox(height: 22),
              const Text(
                'DAY INSIGHT',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: MyDayScreen.muted,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: .07),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: MyDayScreen.purple),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Protect your afternoon opening',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: MyDayScreen.ink,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Your 2:30–4:30 PM window has the lowest cognitive load. It is a good time for recovery or focused individual work.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: MyDayScreen.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEvents() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No calendar events today',
            style: TextStyle(color: MyDayScreen.muted),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _events.length; i++) ...[
          _DayEvent(_events[i], onTap: () => _handleEventTap(_events[i])),
          if (i < _events.length - 1) const Divider(height: 1, indent: 74),
        ],
      ],
    );
  }
}

class _DayEvent extends StatelessWidget {
  const _DayEvent(this.event, {required this.onTap});

  final _CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: event.color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(event.icon, color: event.color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: MyDayScreen.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    event.durationLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: MyDayScreen.muted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              event.timeLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MyDayScreen.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CalendarEvent {
  const _CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.icon,
    required this.color,
    this.googleEvent,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final IconData icon;
  final Color color;
  final gcal.Event? googleEvent;

  static _CalendarEvent? fromGoogle(gcal.Event event) {
    final start =
        event.start?.dateTime?.toLocal() ?? event.start?.date?.toLocal();
    final end = event.end?.dateTime?.toLocal() ?? event.end?.date?.toLocal();
    if (start == null || end == null) return null;
    return _CalendarEvent(
      title: event.summary?.trim().isNotEmpty == true
          ? event.summary!.trim()
          : 'Untitled event',
      start: start,
      end: end,
      isAllDay: event.start?.dateTime == null,
      icon: Icons.event_rounded,
      color: const Color(0xFF3978F6),
      googleEvent: event,
    );
  }

  factory _CalendarEvent.fromOutlook(OutlookEvent event) => _CalendarEvent(
    title: event.subject.trim().isEmpty
        ? 'Untitled event'
        : event.subject.trim(),
    start: event.start.toLocal(),
    end: event.end.toLocal(),
    isAllDay: event.isAllDay,
    icon: Icons.event_rounded,
    color: MyDayScreen.purple,
  );

  String get timeLabel =>
      isAllDay ? 'All day' : DateFormat('h:mm a').format(start);

  String get durationLabel {
    if (isAllDay) return 'All-day event';
    final minutes = end.difference(start).inMinutes;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }
}
