import 'dart:async';
import '../widgets/contextual_insight_bar.dart';
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
import '../src/utils/daily_brief_metrics.dart';
import '../src/utils/daily_brief_analysis.dart';
import '../src/utils/my_day_planning_insight.dart';
import '../src/utils/home_metrics_summary.dart';
import '../widgets/add_calendar_event_sheet.dart';
import '../widgets/add_priority_sheet.dart';
import 'journal_screen.dart';
import 'month_calendar_screen.dart';
import 'all_priorities_screen.dart';
import '../widgets/tomorrow_preview.dart';
import '../widgets/daily_brief_card.dart';
import '../src/utils/owned_stream_snapshot.dart';

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
  List<_CalendarEvent> _tomorrowEvents = const [];
  String? _calendarLoadError;
  int _loadGeneration = 0;
  bool _isLoading = true;
  DateTime? _calendarLoadedAt;
  Timer? _clockTimer;
  bool _screenActive = false;
  late DateTime _priorityDay;
  final _briefSnapshot = OwnedStreamSnapshot<DailyBriefMetricsSummary>();
  DailyBriefMetrics? _briefMetrics;

  void _connectBriefMetrics(DateTime day) {
    _briefMetrics = null;
    final stream = _metricsStreamFor(day);
    _briefSnapshot.connect(
      (stream ?? const Stream<QuerySnapshot<Map<String, dynamic>>>.empty()).map(
        (snapshot) {
          final metrics = DailyBriefMetrics(
            snapshot.docs
                .map((d) => MetricDayEntry(dayKey: d.id, data: d.data()))
                .toList(),
            isFromCache: snapshot.metadata.isFromCache,
          );
          _briefMetrics = metrics;
          return metrics.summarize(DateTime.now());
        },
      ),
    );
  }

  void _refreshBriefClock() {
    final metrics = _briefMetrics;
    if (metrics == null || _briefSnapshot.value.hasError) return;
    final summary = metrics.summarize(DateTime.now());
    if (!identical(summary, _briefSnapshot.value.data)) {
      _briefSnapshot.value = AsyncSnapshot.withData(
        _briefSnapshot.value.connectionState,
        summary,
      );
    }
  }

  final _prioritySnapshot = OwnedStreamSnapshot<List<DailyPriority>>();
  final _tomorrowPrioritySnapshot = OwnedStreamSnapshot<List<DailyPriority>>();
  DateTime get _tomorrow =>
      DateTime(_priorityDay.year, _priorityDay.month, _priorityDay.day + 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _priorityDay = DateUtils.dateOnly(DateTime.now());
    _connectBriefMetrics(_priorityDay);
    _prioritySnapshot.connect(DailyPriorityService.watch(_priorityDay));
    _tomorrowPrioritySnapshot.connect(DailyPriorityService.watch(_tomorrow));
    _loadTodayEvents();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    _briefSnapshot.setActive(active);
    _prioritySnapshot.setActive(active);
    _tomorrowPrioritySnapshot.setActive(active);
    if (_screenActive == active) return;
    _screenActive = active;
    _clockTimer?.cancel();
    if (!active) return;
    if (!_handleDayRollover()) _refreshBriefClock();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (!_handleDayRollover()) {
        _refreshBriefClock();
        setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _screenActive) {
      if (!_handleDayRollover()) _refreshBriefClock();
    }
  }

  bool _handleDayRollover() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (DateUtils.isSameDay(today, _priorityDay)) return false;

    setState(() {
      _priorityDay = today;
      _connectBriefMetrics(today);
      _prioritySnapshot.connect(DailyPriorityService.watch(today));
      _tomorrowPrioritySnapshot.connect(DailyPriorityService.watch(_tomorrow));
    });
    unawaited(_loadTodayEvents());
    return true;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? _metricsStreamFor(DateTime day) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final period = DateFormat('yyyy-MM-dd').format(day);
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics_daily')
        .where(
          FieldPath.documentId,
          isGreaterThanOrEqualTo: DateFormat(
            'yyyy-MM-dd',
          ).format(DateTime(day.year, day.month, day.day - 28)),
        )
        .where(FieldPath.documentId, isLessThanOrEqualTo: period)
        .orderBy(FieldPath.documentId)
        .snapshots();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _briefSnapshot.dispose();
    _prioritySnapshot.dispose();
    _tomorrowPrioritySnapshot.dispose();
    super.dispose();
  }

  /// [forceRefresh] bypasses the shared calendar cache. Used by pull-to-refresh
  /// and after the user edits an event, where reusing a cached range would
  /// show them what they just changed away from.
  Future<void> _loadTodayEvents({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    if (mounted) setState(() => _isLoading = true);
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = DateTime(now.year, now.month, now.day + 1);
    final tomorrowEnd = DateTime(now.year, now.month, now.day + 2);

    late List<dynamic> results;
    try {
      results = await Future.wait([
        CalendarService.getEventsBetween(
          dayStart,
          tomorrowEnd,
          forceRefresh: forceRefresh,
        ).timeout(const Duration(seconds: 8)),
        OutlookCalendarService.getEventsBetween(
          dayStart,
          tomorrowEnd,
          forceRefresh: forceRefresh,
        ).timeout(const Duration(seconds: 8)),
      ]);
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isLoading = false;
          _calendarLoadError =
              'Could not refresh the schedule. Pull down to retry.';
        });
      }
      return;
    }

    final googleEvents = results[0] as List<gcal.Event>;
    final outlookEvents = results[1] as List<OutlookEvent>;
    final allEvents = <_CalendarEvent>[
      ...googleEvents
          .map(_CalendarEvent.fromGoogle)
          .whereType<_CalendarEvent>(),
      ...outlookEvents.map(_CalendarEvent.fromOutlook),
    ].toList()..sort((a, b) => a.start.compareTo(b.start));
    final events = allEvents
        .where((e) => e.start.isBefore(dayEnd) && e.end.isAfter(dayStart))
        .toList();
    final tomorrowEvents = allEvents
        .where((e) => e.start.isBefore(tomorrowEnd) && e.end.isAfter(dayEnd))
        .toList();

    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _calendarLoadedAt = DateTime.now();
      _events = events;
      _tomorrowEvents = tomorrowEvents;
      _calendarLoadError = null;
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
      await DailyPriorityService.materializeRecurring(dayEnd);
      await DailyPriorityService.seedFromCalendar(
        dayEnd,
        tomorrowEvents
            .where((e) => !e.isPriorityLinked)
            .map((e) => e.priorityCandidate),
      );
    } catch (error) {
      debugPrint('Could not generate daily priorities: $error');
    }
  }

  Future<void> _handleEventTap(_CalendarEvent event) async {
    final googleEvent = event.googleEvent;
    if (!mounted) return;
    final action = await showModalBottomSheet<_EventSummaryAction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EventSummarySheet(event: event),
    );
    if (googleEvent == null || !mounted) return;
    switch (action) {
      case _EventSummaryAction.edit:
        await _editGoogleEvent(googleEvent);
        return;
      case _EventSummaryAction.delete:
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
      setState(() => _isLoading = true);
      await CalendarService.deleteEvent(event);
      await _loadTodayEvents();
      _showMessage('Event deleted.');
    } catch (error) {
      if (mounted) setState(() => _isLoading = false);
      _showMessage('Could not delete event: $error');
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
    final longestOpening = gaps.isEmpty
        ? Duration.zero
        : gaps.first.$2.difference(gaps.first.$1);

    if (_isLoading) {
      return _DayInsight(
        title: 'Analyzing today’s calendar',
        detail: 'Looking for open windows and heavier calendar blocks.',
        longestOpening: longestOpening,
      );
    }

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
        longestOpening: longestOpening,
      );
    }

    if (gaps.isNotEmpty) {
      final longest = gaps.first;
      final gapDuration = longest.$2.difference(longest.$1);
      if (gapDuration.inMinutes >= 30) {
        return _DayInsight(
          title: 'Protect your longest opening',
          detail:
              'Your ${range(longest.$1, longest.$2)} window is the longest open block in today’s calendar (${duration(gapDuration)}). Consider using it for focused work, movement, or recovery.',
          longestOpening: longestOpening,
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
      longestOpening: longestOpening,
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
          onRefresh: () => _loadTodayEvents(forceRefresh: true),
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
              Row(
                children: [
                  const Expanded(child: _SectionLabel("TODAY'S PRIORITIES")),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AllPrioritiesScreen(
                          onAdd: (sheetContext) =>
                              _addManualPriority(sheetContext: sheetContext),
                          onEdit: (sheetContext, priority) => _editPriority(
                            priority,
                            sheetContext: sheetContext,
                          ),
                        ),
                      ),
                    ),
                    child: const Text('View all'),
                  ),
                ],
              ),
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
              const SizedBox(height: 24),
              ValueListenableBuilder<AsyncSnapshot<List<DailyPriority>>>(
                valueListenable: _tomorrowPrioritySnapshot,
                builder: (context, snapshot, _) => TomorrowPreview(
                  day: _tomorrow,
                  loading:
                      _isLoading ||
                      snapshot.connectionState == ConnectionState.waiting,
                  error:
                      _calendarLoadError ??
                      (snapshot.hasError
                          ? 'Could not load tomorrow’s priorities.'
                          : null),
                  events: _tomorrowEvents
                      .map(
                        (e) => TomorrowPreviewEvent(
                          title: e.title,
                          start: e.start,
                          end: e.end,
                          allDay: e.isAllDay,
                          onTap: () => _handleEventTap(e),
                        ),
                      )
                      .toList(),
                  priorities: snapshot.data ?? const [],
                  onEdit: _editPriority,
                  onToggle: _togglePriority,
                  onViewDay: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            MonthCalendarScreen(initialDay: _tomorrow),
                      ),
                    );
                    if (mounted) await _loadTodayEvents();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayOutlookCard({
    required List<_CalendarEvent> timedEvents,
  }) => ValueListenableBuilder<AsyncSnapshot<DailyBriefMetricsSummary>>(
    valueListenable: _briefSnapshot,
    builder: (context, snapshot, _) {
      final summary = snapshot.data;
      final sleep = summary?.sleep;
      final usualSleep = summary?.usualSleep;
      final capacity = summary?.capacity;
      final capacityNote =
          summary?.capacityNote ?? 'Building your capacity baseline';
      final stale = summary?.stale ?? true;
      final stressTime = summary?.stressTime;
      final healthTime = summary?.healthTime;
      final now = DateTime.now();
      final calendarReady = !_isLoading && _calendarLoadError == null;
      return ValueListenableBuilder<AsyncSnapshot<List<DailyPriority>>>(
        valueListenable: _prioritySnapshot,
        builder: (context, priorities, _) {
          final briefEvents = timedEvents
              .map(
                (e) =>
                    BriefCommitment(e.sourceEventKey, e.title, e.start, e.end),
              )
              .toList();
          final briefPriorities = (priorities.data ?? [])
              .map(
                (p) => BriefPriority(
                  id: p.id,
                  completed: p.completed,
                  start: p.isAllDay ? null : p.sourceStart,
                  plannedDay: DateTime.tryParse(
                    p.planning['plannedDay'] as String? ?? '',
                  ),
                  minutes: (p.planning['minutes'] as num?)?.toInt(),
                  effort: p.planning['effort'] as String?,
                  eventKey: _linkedKey(p),
                ),
              )
              .toList();
          final plan = analyzeBriefPlan(now, briefEvents, briefPriorities);
          final ready =
              calendarReady && priorities.hasData && !priorities.hasError;
          final headline = capacity?.score == null
              ? 'Make space for your day'
              : capacity!.score! < 40 || (ready && plan.score >= 65)
              ? 'Give yourself a little more room today'
              : 'Find a steady rhythm today';
          final calendarText = ready
              ? plan.observation
              : 'Your plan is not fully available yet.';
          final estimateText = plan.missingEstimates > 0
              ? ' ${plan.missingEstimates} priorities need estimates or calendar details.'
              : '';
          String timeLabel(DateTime? t) =>
              t == null ? 'unknown' : DateFormat('MMM d, h:mm a').format(t);
          return DailyBriefCard(
            headline: headline,
            summary:
                '${sleepComparison(sleep, usualSleep)} $calendarText$estimateText',
            capacityScore: capacity?.score,
            capacityLabel: capacity?.score == null
                ? 'Needs health data'
                : capacityNote,
            scheduleScore: ready ? plan.score : null,
            scheduleLabel: !ready
                ? 'Plan unavailable'
                : 'Remaining demand${plan.missingEstimates > 0 ? ' · partial' : ''}',
            footer:
                '${stale || !ready || plan.missingEstimates > 0 ? 'Limited data' : 'Available data'} · View data freshness',
            onDetails: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Daily Brief data'),
                content: SingleChildScrollView(
                  child: Text(
                    'Calendar loaded: ${timeLabel(_calendarLoadedAt)} (may use a short-lived cache).\n'
                    'Heart rate measured: ${timeLabel(healthTime)}.\n'
                    'Stress calculated: ${timeLabel(stressTime)}.\n'
                    '${summary?.isFromCache == true ? 'Health data is from the local cache.\n' : ''}'
                    'Sleep baseline: ${summary?.priorNights ?? 0} prior nights in the last 28 days; at least 7 required.\n'
                    'Capacity uses sleep and stress, not raw heart rate. Comparisons require 7 days with matching inputs and stress readings at a similar time of day. These are wellness estimates, not clinical assessments.\n'
                    'Remaining demand includes unfinished planned priorities and upcoming events. Openings use a 9 AM–5 PM planning window. Untimed work does not block a specific opening.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ).withScreenInsight(
            ScreenInsight(
              'my_day',
              'Your day',
              myDayPlanningInsight(
                now: now,
                events: briefEvents,
                priorities: briefPriorities,
                calendarReady: calendarReady,
                prioritiesReady: priorities.hasData && !priorities.hasError,
                allDayEvents: _events
                    .where((e) => e.isAllDay && e.end.isAfter(now))
                    .length,
              ),
            ),
          );
        },
      );
    },
  );

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
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.circle, color: Color(0xFF89CF68), size: 18),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Free now',
                    style: TextStyle(
                      color: context.vivordoColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'No more events scheduled today.',
                    style: TextStyle(
                      color: context.vivordoColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  Widget _buildPriorities() =>
      ValueListenableBuilder<AsyncSnapshot<List<DailyPriority>>>(
        valueListenable: _prioritySnapshot,
        builder: (context, snapshot, _) {
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
                  key: ValueKey(priorities[index].reference.path),
                  priority: priorities[index],
                  onToggle: () => _togglePriority(priorities[index]),
                  onDelete: () => _deletePriority(priorities[index]),
                  onEdit: () => _editPriority(priorities[index]),
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

  Future<void> _editPriority(
    DailyPriority priority, {
    BuildContext? sheetContext,
  }) async {
    final result = await showEditPrioritySheet(
      sheetContext ?? context,
      priority,
    );
    if (result == null || !mounted) return;
    try {
      if (result.deleteRequested) {
        await DailyPriorityService.delete(priority);
        return;
      }
      final destination = await DailyPriorityService.editPriority(
        priority,
        title: result.title,
        planning: result.planning,
        date: result.date,
        scheduledAt: result.scheduledAt,
        completed: result.completed,
        reminderMinutes: result.reminderMinutes,
        reminderTimeMinutes: result.reminderTimeMinutes,
        recurrence: result.recurrence,
        selectedWeekdays: result.selectedWeekdays,
        recurrenceEnd: result.repeatEnd,
      );
      final linkedKey = _linkedKey(priority);
      if (linkedKey != null && linkedKey.startsWith('google:')) {
        final linked = _events
            .where((e) => e.sourceEventKey == linkedKey)
            .firstOrNull;
        if (linked?.googleEvent != null) {
          final start = result.scheduledAt ?? DateUtils.dateOnly(result.date);
          await CalendarService.updateEvent(
            linked!.googleEvent!,
            title: result.title,
            start: start,
            end: result.scheduledAt == null
                ? start.add(const Duration(days: 1))
                : start.add(
                    Duration(
                      minutes:
                          (result.planning['minutes'] as num?)?.toInt() ??
                          linked.end.difference(linked.start).inMinutes,
                    ),
                  ),
            isAllDay: result.scheduledAt == null,
          );
          await _loadTodayEvents(forceRefresh: true);
        } else {
          _showMessage(
            'Priority saved. Its linked calendar event was not available to update.',
          );
        }
      } else if (result.addToCalendar &&
          linkedKey == null &&
          destination != null) {
        await _addPriorityCalendarEvent(result, reference: destination);
      }
    } catch (error) {
      if (sheetContext != null && sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(content: Text('Could not update priority: $error')),
        );
      } else {
        _showMessage('Could not update priority: $error');
      }
    }
  }

  Future<void> _addManualPriority({BuildContext? sheetContext}) async {
    final draft = await showAddPrioritySheet(sheetContext ?? context);
    if (draft == null || !mounted) return;

    try {
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
      );
      if (draft.addToCalendar && reference != null) {
        await _addPriorityCalendarEvent(draft, reference: reference);
      }
    } catch (error) {
      _showMessage('Could not add priority: $error');
      return;
    }
  }

  Future<void> _addPriorityCalendarEvent(
    PriorityDraft draft, {
    required DocumentReference<Map<String, dynamic>> reference,
  }) async {
    final start = draft.scheduledAt ?? DateUtils.dateOnly(draft.date);
    final end = draft.scheduledAt == null
        ? start.add(const Duration(days: 1))
        : start.add(
            Duration(
              minutes: (draft.planning['minutes'] as num?)?.toInt() ?? 60,
            ),
          );
    try {
      final event = await CalendarService.createEvent(
        title: draft.title,
        start: start,
        end: end,
        recurrence: draft.calendarRecurrence,
        isAllDay: draft.scheduledAt == null,
        isPriority: true,
        priorityReference: reference.path,
      );
      await reference.update({
        'sourceEventKey': 'google:${event.id}',
        'linkedCalendarId': 'primary',
        'sourceEnd': Timestamp.fromDate(end),
      });
      final saved = (await reference.get()).data();
      final templateId = saved?['templateId'] as String?;
      if (templateId != null) {
        await reference.parent.parent!.parent.parent!
            .collection('priority_templates')
            .doc(templateId)
            .update({'sourceEventKey': 'google:${event.id}'});
      }
      if (mounted) await _loadTodayEvents(forceRefresh: true);
    } catch (error) {
      _showMessage(
        'Priority saved, but the calendar event could not be added: $error',
      );
      if (mounted) await _loadTodayEvents(forceRefresh: true);
    }
  }

  String? _linkedKey(DailyPriority priority) {
    for (final event in _events) {
      final google = event.googleEvent;
      if (event.sourceEventKey == priority.sourceEventKey ||
          (google?.recurringEventId != null &&
              'google:${google!.recurringEventId}' ==
                  priority.sourceEventKey) ||
          google?.extendedProperties?.private?['vivordoPriorityReference'] ==
              priority.reference.path) {
        return event.sourceEventKey;
      }
    }
    if (priority.sourceEventKey == null &&
        _events.any(
          (event) =>
              event.isPriorityLinked &&
              event.title.trim().toLowerCase() ==
                  priority.title.trim().toLowerCase() &&
              event.start == priority.sourceStart,
        )) {
      // Old exports have no stable backlink. Exclude ambiguous extra work and
      // disclose the unresolved link rather than counting the same task twice.
      return 'unresolved:${priority.id}';
    }
    return priority.sourceEventKey;
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
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.black.withValues(alpha: .07)),
    ),
    child: child,
  );
}

@visibleForTesting
Widget priorityRowForTesting({
  required DailyPriority priority,
  required Future<void> Function() onDelete,
  VoidCallback? onEdit,
}) => _PriorityRow(
  priority: priority,
  onToggle: () {},
  onDelete: onDelete,
  onEdit: onEdit,
);

class _PriorityRow extends StatefulWidget {
  const _PriorityRow({
    super.key,
    required this.priority,
    required this.onToggle,
    required this.onDelete,
    this.onEdit,
  });

  final DailyPriority priority;
  final VoidCallback onToggle;
  final Future<void> Function() onDelete;
  final VoidCallback? onEdit;

  @override
  State<_PriorityRow> createState() => _PriorityRowState();
}

class _PriorityRowState extends State<_PriorityRow> {
  static const _actionWidth = 88.0;
  double _dragOffset = 0;
  bool _dragging = false;
  bool _deleting = false;
  bool _confirmingDelete = false;

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
            // Let taps in the revealed action area reach the Delete button.
            behavior: HitTestBehavior.deferToChild,
            onTap: widget.onEdit,
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
    if (_deleting || _confirmingDelete) return;
    _confirmingDelete = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete priority?'),
          content: Text(
            'Remove “${priority.title}” from your priorities?'
            '${priority.source == 'manual' ? '' : '\n\nThis will not delete the original calendar event or recurring schedule.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        setState(() => _deleting = true);
        await widget.onDelete();
      }
    } finally {
      _confirmingDelete = false;
      if (mounted) {
        setState(() {
          _deleting = false;
          _dragOffset = 0;
        });
      }
    }
  }
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

enum _EventSummaryAction { edit, delete }

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
                    onPressed: () => Navigator.pop(context),
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
                            : () => Navigator.pop(
                                context,
                                _EventSummaryAction.edit,
                              ),
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
                    if (event.googleEvent != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => Navigator.pop(
                            context,
                            _EventSummaryAction.delete,
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFF453A),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('Delete'),
                        ),
                      ),
                    ],
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
              SizedBox(
                width: 92,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(color: colors.textPrimary, fontSize: 15),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (valueDotColor != null) ...[
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: valueDotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
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
  const _DayInsight({
    required this.title,
    required this.detail,
    required this.longestOpening,
  });

  final String title;
  final String detail;
  final Duration longestOpening;
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
