import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';

import '../src/services/calendar_service.dart';
import '../src/services/daily_priority_service.dart';
import '../src/services/outlook_calendar_service.dart';
import '../src/utils/back_to_back_events.dart';
import '../widgets/add_calendar_event_sheet.dart';
import '../widgets/add_priority_sheet.dart';
import 'journal_screen.dart';
import 'month_calendar_screen.dart';

class MyDayScreen extends StatefulWidget {
  const MyDayScreen({super.key});

  static const purple = Color(0xFF6B5CE7);
  static const background = Color(0xFFF2F2F7);
  static const ink = Color(0xFF17172B);
  static const muted = Color(0xFF85859B);

  @override
  State<MyDayScreen> createState() => _MyDayScreenState();
}

class _MyDayScreenState extends State<MyDayScreen> with WidgetsBindingObserver {
  List<_CalendarEvent> _events = const [];
  bool _isLoading = true;
  Timer? _clockTimer;
  late DateTime _priorityDay;
  late Stream<List<DailyPriority>> _priorityStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _priorityDay = DateUtils.dateOnly(DateTime.now());
    _priorityStream = DailyPriorityService.watch(_priorityDay);
    _loadTodayEvents();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (!_handleDayRollover()) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _handleDayRollover();
    }
  }

  bool _handleDayRollover() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (DateUtils.isSameDay(today, _priorityDay)) return false;

    setState(() {
      _priorityDay = today;
      _priorityStream = DailyPriorityService.watch(today);
    });
    unawaited(_loadTodayEvents());
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    super.dispose();
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
    try {
      await DailyPriorityService.materializeRecurring(dayStart);
      await DailyPriorityService.seedFromCalendar(
        dayStart,
        events
            .where((event) => !event.isPriorityLinked)
            .map((event) => event.priorityCandidate),
      );
    } catch (error) {
      debugPrint('Could not generate daily priorities: $error');
    }
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

  Future<void> _createGoogleEvent() async {
    final now = DateTime.now();
    final initialStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.minute < 30 ? now.hour : now.hour + 1,
      now.minute < 30 ? 30 : 0,
    );
    final draft = await showAddCalendarEventSheet(
      context,
      initialStart: initialStart,
      initialEnd: initialStart.add(const Duration(hours: 1)),
    );
    if (draft == null || !mounted) return;

    try {
      setState(() => _isLoading = true);
      await CalendarService.createEvent(
        title: draft.title,
        start: draft.start,
        end: draft.end,
        recurrence: draft.recurrence,
        isAllDay: draft.isAllDay,
        calendarId: draft.calendarId,
      );
      await _loadTodayEvents();
      _showMessage('Event added to Google Calendar.');
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      _showMessage('Could not create event: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  _DayInsight _calculateDayInsight() {
    if (_isLoading) {
      return const _DayInsight(
        title: 'Analyzing today’s calendar',
        detail: 'Looking for open windows and heavier calendar blocks.',
      );
    }

    final now = DateTime.now();
    final workStart = DateTime(now.year, now.month, now.day, 9);
    final workEnd = DateTime(now.year, now.month, now.day, 17);
    final timedEvents =
        _events
            .where(
              (event) =>
                  !event.isAllDay &&
                  event.end.isAfter(workStart) &&
                  event.start.isBefore(workEnd),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));

    String range(DateTime start, DateTime end) =>
        '${DateFormat('h:mm a').format(start)}–${DateFormat('h:mm a').format(end)}';
    String duration(Duration value) {
      final minutes = value.inMinutes;
      if (minutes < 60) return '$minutes minutes';
      final hours = minutes ~/ 60;
      final remainder = minutes % 60;
      return remainder == 0
          ? '$hours ${hours == 1 ? 'hour' : 'hours'}'
          : '${hours}h ${remainder}m';
    }

    if (timedEvents.isEmpty) {
      final allDayCount = _events.where((event) => event.isAllDay).length;
      return _DayInsight(
        title: 'Your workday is open',
        detail: allDayCount == 0
            ? 'No timed events are scheduled between 9:00 AM and 5:00 PM. You have a large window for focused work, movement, or recovery.'
            : 'You have $allDayCount all-day ${allDayCount == 1 ? 'event' : 'events'}, but no timed events between 9:00 AM and 5:00 PM.',
      );
    }

    final gaps = <(DateTime, DateTime)>[];
    var cursor = workStart;
    for (final event in timedEvents) {
      final start = event.start.isBefore(workStart) ? workStart : event.start;
      final end = event.end.isAfter(workEnd) ? workEnd : event.end;
      if (start.isAfter(cursor)) gaps.add((cursor, start));
      if (end.isAfter(cursor)) cursor = end;
    }
    if (cursor.isBefore(workEnd)) gaps.add((cursor, workEnd));
    gaps.sort((a, b) => b.$2.difference(b.$1).compareTo(a.$2.difference(a.$1)));

    if (gaps.isNotEmpty) {
      final longest = gaps.first;
      final gapDuration = longest.$2.difference(longest.$1);
      if (gapDuration.inMinutes >= 30) {
        return _DayInsight(
          title: 'Protect your longest opening',
          detail:
              'Your ${range(longest.$1, longest.$2)} window is the longest open block in today’s calendar (${duration(gapDuration)}). Consider using it for focused work, movement, or recovery.',
        );
      }
    }

    final longestEvent = timedEvents.reduce(
      (current, event) =>
          event.end.difference(event.start) >
              current.end.difference(current.start)
          ? event
          : current,
    );
    return _DayInsight(
      title: 'Your calendar is tightly packed',
      detail:
          'You have ${timedEvents.length} timed ${timedEvents.length == 1 ? 'event' : 'events'} during the workday. “${longestEvent.title}” is the longest block (${range(longestEvent.start, longestEvent.end)}), so leave recovery time around it if possible.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final timedEvents = _events.where((event) => !event.isAllDay).toList();
    final scheduled = timedEvents.fold<Duration>(
      Duration.zero,
      (total, event) => total + event.end.difference(event.start),
    );
    final longestOpening = _longestOpening();
    final load = scheduled.inHours >= 6
        ? 'High'
        : scheduled.inHours >= 3
        ? 'Moderate'
        : 'Low';
    final dayInsight = _calculateDayInsight();
    final watchItem = findNextBackToBackEventBlock(
      _events
          .where((event) => !event.isAllDay)
          .map(
            (event) => ScheduledEventWindow(
              title: event.title,
              start: event.start,
              end: event.end,
            ),
          ),
    );

    return Scaffold(
      backgroundColor: context.vivordoColors.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadTodayEvents,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 140),
            children: [
              Text(
                'My Day',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: context.vivordoColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE, MMMM d').format(DateTime.now()),
                style: const TextStyle(color: MyDayScreen.muted),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5848E8), Color(0xFF3422B8)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 62,
                          height: 62,
                          child: Icon(
                            Icons.speed_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "TODAY'S SCHEDULE LOAD",
                                style: TextStyle(
                                  color: Color(0xFFE1DDFF),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                load,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${_events.length} ${_events.length == 1 ? 'event' : 'events'} · ${load == 'Low' ? 'Balanced focus time' : 'A structured day'}',
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
                    const Divider(height: 24, color: Color(0x55FFFFFF)),
                    Row(
                      children: [
                        Expanded(
                          child: _LoadMetric(
                            icon: Icons.schedule_rounded,
                            value: _shortDuration(longestOpening),
                            label: 'longest opening',
                          ),
                        ),
                        Container(width: 1, height: 38, color: Colors.white24),
                        Expanded(
                          child: _LoadMetric(
                            icon: Icons.calendar_month_rounded,
                            value: _shortDuration(scheduled),
                            label: 'scheduled',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('NOW & NEXT'),
              const SizedBox(height: 10),
              _SectionCard(child: _buildNowAndNext()),
              const SizedBox(height: 24),
              const _SectionLabel('VIVORDO INSIGHT'),
              const SizedBox(height: 10),
              _SectionCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: MyDayScreen.purple,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dayInsight.title,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: context.vivordoColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dayInsight.detail,
                              style: const TextStyle(
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
              ),
              if (watchItem != null) ...[
                const SizedBox(height: 24),
                _buildWatchItem(watchItem),
              ],
              const SizedBox(height: 24),
              const _SectionLabel("TODAY'S PRIORITIES"),
              const SizedBox(height: 10),
              _SectionCard(child: _buildPriorities()),
              const SizedBox(height: 24),
              const _SectionLabel('JOURNAL'),
              const SizedBox(height: 10),
              _buildJournalTile(),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: _SectionLabel("TODAY'S TIMELINE")),
                  IconButton(
                    onPressed: _isLoading ? null : _createGoogleEvent,
                    tooltip: 'Add event',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.add_rounded,
                      color: MyDayScreen.purple,
                    ),
                  ),
                  TextButton(
                    onPressed: _openCalendar,
                    child: const Text('View Calendar'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _SectionCard(child: _buildTimeline()),
            ],
          ),
        ),
      ),
    );
  }

  Duration _longestOpening() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9);
    final end = DateTime(now.year, now.month, now.day, 17);
    final events =
        _events
            .where(
              (e) =>
                  !e.isAllDay && e.end.isAfter(start) && e.start.isBefore(end),
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    var cursor = start;
    var longest = Duration.zero;
    for (final event in events) {
      if (event.start.isAfter(cursor)) {
        final gap = event.start.difference(cursor);
        if (gap > longest) longest = gap;
      }
      if (event.end.isAfter(cursor)) cursor = event.end;
    }
    if (cursor.isBefore(end) && end.difference(cursor) > longest) {
      return end.difference(cursor);
    }
    return longest;
  }

  String _shortDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  Widget _buildWatchItem(BackToBackEventBlock block) {
    final count = block.events.length;
    final last = block.events.last;
    final countLabel = switch (count) {
      2 => 'Two',
      3 => 'Three',
      4 => 'Four',
      5 => 'Five',
      _ => '$count',
    };
    final period = block.start.hour >= 12
        ? 'after lunch'
        : block.end.hour <= 12
        ? 'this morning'
        : 'today';
    final resetEnd = block.end.add(const Duration(minutes: 10));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: context.vivordoColors.cardMuted,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: MyDayScreen.purple.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: context.vivordoColors.shadow,
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: MyDayScreen.purple,
                size: 23,
              ),
              SizedBox(width: 8),
              Text(
                'WATCH ITEM',
                style: TextStyle(
                  color: MyDayScreen.purple,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$countLabel meetings run back-to-back $period.',
            style: TextStyle(
              color: context.vivordoColors.textPrimary,
              fontSize: 19,
              height: 1.15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Protect a 10-minute reset after ${last.title}.',
            style: TextStyle(
              color: context.vivordoColors.textSecondary,
              fontSize: 13,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final timelineWidth = math.max(
                constraints.maxWidth,
                (count + 1) * 88.0,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: timelineWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < count; index++)
                        Expanded(
                          child: _WatchTimelineSegment(
                            title: block.events[index].title,
                            start: block.events[index].start,
                            end: block.events[index].end,
                            icon: switch (index % 3) {
                              0 => Icons.groups_rounded,
                              1 => Icons.chat_bubble_rounded,
                              _ => Icons.assessment_rounded,
                            },
                            isFirst: index == 0,
                          ),
                        ),
                      Expanded(
                        child: _WatchTimelineSegment(
                          title: 'Reset',
                          start: block.end,
                          end: resetEnd,
                          icon: Icons.eco_rounded,
                          isReset: true,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openCalendar() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MonthCalendarScreen()),
    );
    if (mounted) await _loadTodayEvents();
  }

  Widget _buildNowAndNext() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final now = DateTime.now();
    final timedEvents = _events.where((event) => !event.isAllDay).toList();
    final isBusy = timedEvents.any(
      (event) => !event.start.isAfter(now) && event.end.isAfter(now),
    );
    final futureEvents = timedEvents
        .where((event) => event.start.isAfter(now))
        .toList();
    final nextEvent = futureEvents.isEmpty ? null : futureEvents.first;
    final freeDuration = nextEvent?.start.difference(now);
    final showFreeUntil =
        !isBusy && freeDuration != null && freeDuration.inMinutes >= 1;
    final upcoming = _events
        .where((event) => event.end.isAfter(now))
        .take(showFreeUntil ? 2 : 3)
        .toList();
    if (upcoming.isEmpty && !showFreeUntil) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Nothing else scheduled today',
            style: TextStyle(color: MyDayScreen.muted),
          ),
        ),
      );
    }
    return Column(
      children: [
        if (showFreeUntil) ...[
          _FreeUntilRow(until: nextEvent!.start, duration: freeDuration),
          if (upcoming.isNotEmpty) const Divider(height: 1, indent: 66),
        ],
        for (var i = 0; i < upcoming.length; i++) ...[
          _DayEvent(upcoming[i], onTap: () => _handleEventTap(upcoming[i])),
          if (i < upcoming.length - 1) const Divider(height: 1, indent: 66),
        ],
      ],
    );
  }

  Widget _buildPriorities() => StreamBuilder<List<DailyPriority>>(
    stream: _priorityStream,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return const SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Could not load today’s priorities',
            textAlign: TextAlign.center,
            style: TextStyle(color: MyDayScreen.muted),
          ),
        );
      }
      final priorities = snapshot.data ?? const <DailyPriority>[];
      return Column(
        children: [
          if (priorities.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 20, 18, 12),
              child: Text(
                'No calendar events qualify as priorities yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: MyDayScreen.muted, fontSize: 12),
              ),
            ),
          for (var index = 0; index < priorities.length; index++) ...[
            _PriorityRow(
              key: ValueKey(priorities[index].id),
              priority: priorities[index],
              onToggle: () => _togglePriority(priorities[index]),
              onDelete: () => _deletePriority(priorities[index]),
            ),
            if (index < priorities.length - 1)
              const Divider(height: 1, indent: 58, endIndent: 16),
          ],
          if (priorities.isNotEmpty) const Divider(height: 1),
          TextButton.icon(
            onPressed: _addManualPriority,
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text('Add priority'),
          ),
          const SizedBox(height: 4),
        ],
      );
    },
  );

  Future<void> _togglePriority(DailyPriority priority) async {
    try {
      await DailyPriorityService.setCompleted(priority, !priority.completed);
    } catch (error) {
      _showMessage('Could not update priority: $error');
    }
  }

  Future<void> _deletePriority(DailyPriority priority) async {
    try {
      await DailyPriorityService.delete(priority);
    } catch (error) {
      _showMessage('Could not delete priority: $error');
    }
  }

  Future<void> _addManualPriority() async {
    final draft = await showAddPrioritySheet(context);
    if (draft == null || !mounted) return;

    try {
      await DailyPriorityService.createManual(
        title: draft.title,
        date: draft.date,
        scheduledAt: draft.scheduledAt,
        recurrence: draft.recurrence,
        selectedWeekdays: draft.selectedWeekdays,
        recurrenceEnd: draft.repeatEnd,
      );
    } catch (error) {
      _showMessage('Could not add priority: $error');
      return;
    }

    if (!draft.addToCalendar) return;
    final start = draft.scheduledAt ?? DateUtils.dateOnly(draft.date);
    final end = draft.scheduledAt == null
        ? start.add(const Duration(days: 1))
        : start.add(const Duration(hours: 1));
    try {
      await CalendarService.createEvent(
        title: draft.title,
        start: start,
        end: end,
        recurrence: draft.calendarRecurrence,
        isAllDay: draft.scheduledAt == null,
        isPriority: true,
      );
      if (mounted) await _loadTodayEvents();
    } catch (error) {
      _showMessage(
        'Priority saved, but the calendar event could not be added: $error',
      );
    }
  }

  Widget _buildJournalTile() => Material(
    color: context.vivordoColors.card,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const JournalScreen())),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: .07)),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFF2EDFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: MyDayScreen.purple,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's Journal",
                    style: TextStyle(
                      color: context.vivordoColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your space to write, reflect, or record your day.',
                    style: TextStyle(color: MyDayScreen.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF2EDFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.edit_rounded, color: MyDayScreen.purple, size: 15),
                  SizedBox(width: 5),
                  Text(
                    'Write entry',
                    style: TextStyle(
                      color: MyDayScreen.purple,
                      fontWeight: FontWeight.w800,
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
  );

  Widget _buildTimeline() {
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
            'Your timeline is open today',
            style: TextStyle(color: MyDayScreen.muted),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          for (var index = 0; index < _events.length; index++)
            _TimelineEvent(
              event: _events[index],
              isFirst: index == 0,
              isLast: index == _events.length - 1,
              onTap: () => _handleEventTap(_events[index]),
            ),
        ],
      ),
    );
  }
}

class _WatchTimelineSegment extends StatelessWidget {
  const _WatchTimelineSegment({
    required this.title,
    required this.start,
    required this.end,
    required this.icon,
    this.isFirst = false,
    this.isReset = false,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final IconData icon;
  final bool isFirst;
  final bool isReset;

  @override
  Widget build(BuildContext context) {
    final accent = isReset ? const Color(0xFF169B62) : MyDayScreen.purple;
    final fill = isReset
        ? const Color(0xFFEAF8F0)
        : MyDayScreen.purple.withValues(alpha: .07);
    final border = isReset
        ? const Color(0xFF9DDDBD)
        : MyDayScreen.purple.withValues(alpha: .28);
    final time = DateFormat('h:mm a');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 7),
          child: Text(
            time.format(start),
            style: TextStyle(
              color: isReset
                  ? const Color(0xFF087A49)
                  : context.vivordoColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Container(
          height: 112,
          width: double.infinity,
          margin: EdgeInsets.only(left: isFirst ? 0 : 2),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accent, size: 21),
              const SizedBox(height: 7),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${time.format(start)}–${time.format(end)}',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.3,
      color: MyDayScreen.muted,
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.black.withValues(alpha: .07)),
    ),
    child: child,
  );
}

class _PriorityRow extends StatefulWidget {
  const _PriorityRow({
    super.key,
    required this.priority,
    required this.onToggle,
    required this.onDelete,
  });

  final DailyPriority priority;
  final VoidCallback onToggle;
  final Future<void> Function() onDelete;

  @override
  State<_PriorityRow> createState() => _PriorityRowState();
}

class _PriorityRowState extends State<_PriorityRow> {
  static const _actionWidth = 88.0;
  double _dragOffset = 0;
  bool _dragging = false;
  bool _deleting = false;

  DailyPriority get priority => widget.priority;

  String? get _timeLabel {
    final start = priority.sourceStart;
    final end = priority.sourceEnd;
    if (start == null) return null;
    if (priority.isAllDay) return 'All day';
    if (end == null) return DateFormat('h:mm a').format(start);
    return '${DateFormat('h:mm').format(start)}–${DateFormat('h:mm a').format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final timeLabel = _timeLabel;
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _actionWidth,
                child: Material(
                  color: const Color(0xFFE5484D),
                  child: InkWell(
                    onTap: _deleting ? null : _delete,
                    child: Center(
                      child: _deleting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: (details) {
              setState(() {
                _dragOffset = (_dragOffset + details.delta.dx).clamp(
                  -_actionWidth,
                  0,
                );
              });
            },
            onHorizontalDragEnd: (_) {
              setState(() {
                _dragging = false;
                _dragOffset = _dragOffset <= -_actionWidth * .35
                    ? -_actionWidth
                    : 0;
              });
            },
            onHorizontalDragCancel: () {
              setState(() {
                _dragging = false;
                _dragOffset = 0;
              });
            },
            child: AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(_dragOffset, 0, 0),
              color: colors.card,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onToggle,
                      customBorder: const CircleBorder(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: priority.completed
                              ? const Color(0xFF54C75B)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: priority.completed
                                ? const Color(0xFF54C75B)
                                : MyDayScreen.muted,
                            width: 2,
                          ),
                        ),
                        child: priority.completed
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      priority.title,
                      style: TextStyle(
                        color: priority.completed
                            ? colors.textSecondary
                            : colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: priority.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  if (timeLabel != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: MyDayScreen.purple.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        timeLabel,
                        style: const TextStyle(
                          color: MyDayScreen.purple,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    setState(() => _deleting = true);
    await widget.onDelete();
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _dragOffset = 0;
    });
  }
}

class _LoadMetric extends StatelessWidget {
  const _LoadMetric({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, color: const Color(0xFFD8D2FF), size: 23),
      const SizedBox(width: 9),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFD8D2FF), fontSize: 10),
          ),
        ],
      ),
    ],
  );
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({
    required this.event,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });
  final _CalendarEvent event;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              event.timeLabel,
              style: const TextStyle(fontSize: 11, color: MyDayScreen.muted),
            ),
          ),
          SizedBox(
            width: 10,
            height: 50,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: isFirst ? 25 : 0,
                  bottom: isLast ? 25 : 0,
                  left: 4.5,
                  child: Container(
                    width: 1,
                    color: MyDayScreen.muted.withValues(alpha: .65),
                  ),
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: DateTime.now().isBefore(event.end)
                        ? const Color(0xFF858594)
                        : const Color(0xFF3978F6),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.vivordoColors.card,
                      width: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: event.color.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: event.color, width: 2)),
              ),
              child: Text(
                '${event.title}  ·  ${event.durationLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.vivordoColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FreeUntilRow extends StatelessWidget {
  const _FreeUntilRow({required this.until, required this.duration});

  final DateTime until;
  final Duration duration;

  String get _durationLabel {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) return '$minutes min open';
    if (minutes == 0) return '${hours}h open';
    return '${hours}h ${minutes}m open';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(15),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFF65C65A).withValues(alpha: .13),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFF76D66A),
                shape: BoxShape.circle,
              ),
              child: SizedBox(width: 16, height: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Free until ${DateFormat('h:mm a').format(until)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: context.vivordoColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _durationLabel,
                style: const TextStyle(fontSize: 11, color: MyDayScreen.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
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
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: context.vivordoColors.textPrimary,
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

class _DayInsight {
  const _DayInsight({required this.title, required this.detail});

  final String title;
  final String detail;
}

class _CalendarEvent {
  const _CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.sourceEventKey,
    required this.isRecurring,
    required this.attendeeCount,
    required this.isPriorityLinked,
    required this.icon,
    required this.color,
    this.googleEvent,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final String sourceEventKey;
  final bool isRecurring;
  final int attendeeCount;
  final bool isPriorityLinked;
  final IconData icon;
  final Color color;
  final gcal.Event? googleEvent;

  static _CalendarEvent? fromGoogle(gcal.Event event) {
    if (event.status == 'cancelled') return null;
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
      sourceEventKey:
          'google:${event.id ?? event.iCalUID ?? '${event.summary}:$start'}',
      isRecurring:
          event.recurringEventId != null ||
          event.recurrence?.isNotEmpty == true,
      attendeeCount: event.attendees?.length ?? 0,
      isPriorityLinked:
          event.extendedProperties?.private?['vivordoPriority'] == 'true',
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
    sourceEventKey: 'outlook:${event.id}',
    isRecurring: false,
    attendeeCount: 0,
    isPriorityLinked: false,
    icon: Icons.event_rounded,
    color: MyDayScreen.purple,
  );

  String get timeLabel =>
      isAllDay ? 'All day' : DateFormat('h:mm a').format(start);

  CalendarPriorityCandidate get priorityCandidate => CalendarPriorityCandidate(
    sourceEventKey: sourceEventKey,
    title: title,
    start: start,
    end: end,
    isAllDay: isAllDay,
    isRecurring: isRecurring,
    attendeeCount: attendeeCount,
  );

  String get durationLabel {
    if (isAllDay) return 'All-day event';
    final minutes = end.difference(start).inMinutes;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }
}
