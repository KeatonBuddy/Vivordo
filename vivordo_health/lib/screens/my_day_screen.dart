import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:intl/intl.dart';

import '../src/services/calendar_service.dart';
import '../src/services/daily_priority_service.dart';
import '../src/services/outlook_calendar_service.dart';
import '../src/utils/back_to_back_events.dart';
import '../src/utils/daily_outlook_score.dart';
import '../src/utils/latest_heart_rate.dart';
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
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _todayMetricsStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _priorityDay = DateUtils.dateOnly(DateTime.now());
    _priorityStream = DailyPriorityService.watch(_priorityDay);
    _todayMetricsStream = _metricsStreamFor(_priorityDay);
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
      _todayMetricsStream = _metricsStreamFor(today);
    });
    unawaited(_loadTodayEvents());
    return true;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>>? _metricsStreamFor(
    DateTime day,
  ) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final period = DateFormat('yyyy-MM-dd').format(day);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .doc(period)
        .snapshots();
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
    if (!mounted) return;
    final shouldEdit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EventSummarySheet(event: event),
    );
    if (shouldEdit == true && googleEvent != null && mounted) {
      await _editGoogleEvent(googleEvent);
    }
  }

  Future<void> _editGoogleEvent(gcal.Event event) async {
    final result = await showEditCalendarEventSheet(context, event: event);
    if (result == null || !mounted) return;

    try {
      setState(() => _isLoading = true);
      if (result.action == CalendarEventEditAction.delete) {
        await CalendarService.deleteEvent(event);
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
        );
      }
      await _loadTodayEvents();
      _showMessage(
        result.action == CalendarEventEditAction.delete
            ? 'Event deleted.'
            : 'Event updated.',
      );
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      _showMessage('Could not save event: $error');
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
              _buildDayOutlookCard(timedEvents: timedEvents),
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

  Widget _buildDayOutlookCard({
    required List<_CalendarEvent> timedEvents,
  }) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _todayMetricsStream,
    builder: (context, snapshot) {
      final data = snapshot.data?.data();
      final sleep = ((data?['sleep'] as Map?)?['avg'] as num?)?.toDouble();
      final stressMap = data?['stress'] as Map?;
      final hrvMap = data?['hrv'] as Map?;
      final stress =
          (stressMap?['current'] as num?)?.toDouble() ??
          (stressMap?['avg'] as num?)?.toDouble() ??
          (hrvMap?['stressScore'] as num?)?.toDouble();
      final latestHeartRate = data == null
          ? null
          : latestHeartRateReadingFromMetricDays([data]);
      final heartRate = latestHeartRate?.bpm.toDouble();
      final capacity = calculateDailyCapacity(
        sleepHours: sleep,
        stressScore: stress,
        heartRate: heartRate,
      );
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final schedule = calculateScheduleDemand(
        events: timedEvents.map(
          (event) => DailyScheduleEvent(
            title: event.title,
            start: event.start,
            end: event.end,
          ),
        ),
        dayStart: dayStart,
        dayEnd: dayStart.add(const Duration(days: 1)),
      );
      final signals = <_OutlookSignal>[
        if (sleep != null)
          _OutlookSignal(
            icon: Icons.bedtime_outlined,
            label: 'Sleep ${sleep.toStringAsFixed(1)}h',
          ),
        if (stress != null)
          _OutlookSignal(
            icon: Icons.monitor_heart_outlined,
            label: 'Stress ${stress.round()}',
          ),
        if (heartRate != null)
          _OutlookSignal(
            icon: Icons.favorite_border_rounded,
            label: 'Heart ${heartRate.round()}',
          ),
        _OutlookSignal(
          icon: Icons.schedule_rounded,
          label:
              '${_shortDuration(Duration(minutes: schedule.unscheduledMinutes))} unscheduled today',
        ),
      ];
      final signalCount = capacity.availableSignals + (_isLoading ? 0 : 1);
      final confidence = signalCount >= 4
          ? 'High confidence'
          : signalCount >= 2
          ? 'Moderate confidence'
          : 'Limited data';

      return _DayOutlookCard(
        capacityScore: capacity.score,
        capacityLabel: capacity.score == null ? 'Needs data' : capacity.label,
        scheduleScore: _isLoading ? null : schedule.score,
        scheduleLabel: _isLoading ? 'Analyzing' : schedule.label,
        signals: signals,
        footer:
            '$confidence · $signalCount ${signalCount == 1 ? 'signal' : 'signals'} available',
      );
    },
  );

  String _shortDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) return '${minutes}m';
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  Widget _buildWatchItem(BackToBackEventBlock block) {
    final count = block.events.length;
    final last = block.events.last;
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
            'These events run back to back.',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isReset ? const Color(0xFF169B62) : MyDayScreen.purple;
    final fill = isReset
        ? isDark
              ? context.vivordoColors.cardMuted
              : const Color(0xFFEAF8F0)
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

class _DayOutlookCard extends StatelessWidget {
  const _DayOutlookCard({
    required this.capacityScore,
    required this.capacityLabel,
    required this.scheduleScore,
    required this.scheduleLabel,
    required this.signals,
    required this.footer,
  });

  final int? capacityScore;
  final String capacityLabel;
  final int? scheduleScore;
  final String scheduleLabel;
  final List<_OutlookSignal> signals;
  final String footer;

  @override
  Widget build(BuildContext context) {
    final headline = capacityScore == null
        ? 'Daily Capacity needs health data · $scheduleLabel schedule demand'
        : '$capacityLabel daily capacity · $scheduleLabel schedule demand';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5848D8), Color(0xFF3020A9)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3422B8).withValues(alpha: .24),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _OutlookHeaderIcon(),
              SizedBox(width: 10),
              Text(
                'DAY OUTLOOK',
                style: TextStyle(
                  color: Color(0xFFE7E3FF),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            headline,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              height: 1.18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _OutlookScoreRing(
                  title: 'Daily Capacity',
                  score: capacityScore,
                  label: capacityLabel,
                ),
              ),
              Container(width: 1, height: 118, color: Colors.white24),
              Expanded(
                child: _OutlookScoreRing(
                  title: 'Schedule',
                  score: scheduleScore,
                  label: scheduleLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final signal in signals) _OutlookSignalChip(signal),
              ],
            ),
          ),
          const SizedBox(height: 13),
          Center(
            child: Text(
              footer,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE7E3FF),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlookHeaderIcon extends StatelessWidget {
  const _OutlookHeaderIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .16),
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.show_chart_rounded, color: Colors.white, size: 23),
  );
}

class _OutlookScoreRing extends StatelessWidget {
  const _OutlookScoreRing({
    required this.title,
    required this.score,
    required this.label,
  });

  final String title;
  final int? score;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: score == null ? 0 : score! / 100,
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.white.withValues(alpha: .22),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFDCD7FF)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: title == 'Daily Capacity' ? 10 : 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  score?.toString() ?? '—',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    height: 1.05,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFFE7E3FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _OutlookSignal {
  const _OutlookSignal({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _OutlookSignalChip extends StatelessWidget {
  const _OutlookSignalChip(this.signal);

  final _OutlookSignal signal;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: Colors.white.withValues(alpha: .24)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(signal.icon, color: Colors.white, size: 18),
        const SizedBox(width: 6),
        Text(
          signal.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
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

class _EventSummarySheet extends StatelessWidget {
  const _EventSummarySheet({required this.event});

  final _CalendarEvent event;

  (String, Color) get _status {
    final now = DateTime.now();
    if (!now.isBefore(event.end)) {
      return ('COMPLETED', const Color(0xFF20A968));
    }
    if (!now.isBefore(event.start)) {
      return ('IN PROGRESS', const Color(0xFFFF9F0A));
    }
    return ('UPCOMING', MyDayScreen.purple);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final status = _status;
    final time = event.isAllDay
        ? 'All day'
        : '${DateFormat('h:mm a').format(event.start)} – ${DateFormat('h:mm a').format(event.end)}';

    return FractionallySizedBox(
      heightFactor: .9,
      child: Material(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      'Event Summary',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.cardMuted,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: MyDayScreen.purple.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.calendar_month_rounded,
                              color: MyDayScreen.purple,
                              size: 36,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: status.$2.withValues(alpha: .16),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    status.$1,
                                    style: TextStyle(
                                      color: status.$2,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _SummarySectionLabel('DETAILS'),
                    const SizedBox(height: 10),
                    _SummarySurface(
                      children: [
                        _SummaryDetailRow(
                          icon: Icons.calendar_today_rounded,
                          label: 'Date',
                          value: DateFormat('MMMM d, y').format(event.start),
                        ),
                        _SummaryDetailRow(
                          icon: Icons.schedule_rounded,
                          label: 'Time',
                          value: time,
                        ),
                        _SummaryDetailRow(
                          icon: Icons.hourglass_bottom_rounded,
                          label: 'Duration',
                          value: event.durationLabel,
                        ),
                        _SummaryDetailRow(
                          icon: Icons.repeat_rounded,
                          label: 'Repeats',
                          value: event.isRecurring
                              ? 'Recurring event'
                              : 'Does not repeat',
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const _SummarySectionLabel('CALENDAR'),
                    const SizedBox(height: 10),
                    _SummarySurface(
                      children: [
                        _SummaryDetailRow(
                          icon: Icons.calendar_month_rounded,
                          label: 'Calendar',
                          value: event.googleEvent == null
                              ? 'Outlook'
                              : 'Google Calendar',
                          valueDotColor: event.color,
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: event.googleEvent == null
                            ? null
                            : () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: MyDayScreen.purple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          event.googleEvent == null
                              ? 'Outlook event · Read only'
                              : 'Edit Event',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (event.googleEvent == null) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Outlook events are currently read-only in Vivordo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
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

class _SummarySectionLabel extends StatelessWidget {
  const _SummarySectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: MyDayScreen.purple,
      fontSize: 12,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.2,
    ),
  );
}

class _SummarySurface extends StatelessWidget {
  const _SummarySurface({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: context.vivordoColors.cardMuted,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Column(children: children),
  );
}

class _SummaryDetailRow extends StatelessWidget {
  const _SummaryDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueDotColor,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueDotColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: MyDayScreen.purple, size: 23),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(color: colors.textPrimary, fontSize: 15),
              ),
              const Spacer(),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (valueDotColor != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: valueDotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: colors.border),
      ],
    );
  }
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
