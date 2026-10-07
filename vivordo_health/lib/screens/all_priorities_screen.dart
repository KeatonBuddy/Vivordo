import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../src/services/daily_priority_service.dart';
import '../src/utils/priority_schedule.dart';
import '../theme/vivordo_theme.dart';
import '../widgets/apple_ui.dart';
import '../widgets/swipe_to_delete.dart';

const _doneGreen = Color(0xFF54C75B);
const _overdueRed = Color(0xFFE5484D);

/// One row per recurring schedule, represented by today's or its next occurrence.
List<DailyPriority> distinctPriorities(List<DailyPriority> priorities) {
  final sorted = [...priorities]
    ..sort(
      (a, b) => (a.date ?? a.sourceStart ?? DateTime(2100)).compareTo(
        b.date ?? b.sourceStart ?? DateTime(2100),
      ),
    );
  final seen = <String>{};
  return sorted
      .where((p) => p.templateId == null || seen.add(p.templateId!))
      .toList();
}

enum _Tab { plan, repeating }

class AllPrioritiesScreen extends StatefulWidget {
  const AllPrioritiesScreen({
    super.key,
    required this.onAdd,
    required this.onEdit,
    this.onDelete,
    this.priorities,
  });
  final Future<void> Function(BuildContext) onAdd;
  final Future<void> Function(BuildContext, DailyPriority) onEdit;

  /// Defaults to [DailyPriorityService.delete].
  final Future<void> Function(DailyPriority)? onDelete;
  final Stream<List<DailyPriority>>? priorities;
  @override
  State<AllPrioritiesScreen> createState() => _AllPrioritiesScreenState();
}

class _AllPrioritiesScreenState extends State<AllPrioritiesScreen>
    with WidgetsBindingObserver {
  late DateTime _day;
  late Stream<List<DailyPriority>> _stream;
  Timer? _timer;
  StreamSubscription<Map<String, String>>? _labelsSubscription;
  Map<String, String> _labels = const {};
  _Tab _tab = _Tab.plan;
  bool _showCompleted = false;
  final _busy = <String>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _day = DateUtils.dateOnly(DateTime.now());
    _stream =
        widget.priorities ??
        DailyPriorityService.watch(_day, includeUpcoming: true);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _rollover());
    if (widget.priorities == null) {
      _labelsSubscription = DailyPriorityService.watchRecurrenceLabels().listen(
        (labels) {
          if (mounted) setState(() => _labels = labels);
        },
        onError: (Object error) {
          /* Dates remain usable without schedule labels. */
        },
      );
      DailyPriorityService.refreshReminders().catchError((Object error) {
        if (mounted) _message("Couldn't refresh repeating priorities.");
      });
    }
  }

  void _rollover() {
    final now = DateUtils.dateOnly(DateTime.now());
    if (now == _day || !mounted) return;
    setState(() {
      _day = now;
      _stream =
          widget.priorities ??
          DailyPriorityService.watch(now, includeUpcoming: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _rollover();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _labelsSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _message(String text) => showToast(context, text, kind: ToastKind.error);

  Future<void> _toggle(DailyPriority p) async {
    final key = p.reference.path;
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await DailyPriorityService.setCompleted(p, !p.completed);
    } catch (_) {
      if (mounted) _message("Couldn't update the priority. Try again.");
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _delete(DailyPriority p) async {
    try {
      await (widget.onDelete ?? DailyPriorityService.delete)(p);
    } catch (_) {
      if (mounted) _message("Couldn't delete the priority. Try again.");
    }
  }

  bool _recurring(DailyPriority p) => p.source == 'recurring_manual';

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      backgroundColor: colors.page,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<List<DailyPriority>>(
          stream: _stream,
          builder: (context, snapshot) {
            final all = snapshot.data ?? const <DailyPriority>[];
            final distinct = distinctPriorities(all);
            final schedules = distinct.where(_recurring).toList();
            final plan = _PlanGroups.from(distinct, _day);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
              children: [
                _header(plan),
                const SizedBox(height: 16),
                AppSegmented<_Tab>(
                  segments: {
                    _Tab.plan: 'Plan',
                    _Tab.repeating: schedules.isEmpty
                        ? 'Repeating'
                        : 'Repeating · ${schedules.length}',
                  },
                  value: _tab,
                  onChanged: (tab) => setState(() => _tab = tab),
                ),
                const SizedBox(height: 8),
                if (snapshot.hasError)
                  _note(
                    "Couldn't load your priorities. Check your connection and try again.",
                  )
                else if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_tab == _Tab.plan)
                  ..._planView(plan)
                else
                  ..._repeatingView(schedules, all),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(_PlanGroups plan) {
    final colors = context.vivordoColors;
    final minutes = plan.openToday.fold<int>(
      0,
      (sum, p) => sum + (priorityMinutes(p) ?? 0),
    );
    final left = plan.openToday.length;
    final total = left + plan.doneToday;
    final summary = total == 0
        ? 'Nothing planned for today'
        : left == 0
        ? 'All done for today'
        : [
            '$left left today',
            if (minutes > 0) 'about ${formatPriorityMinutes(minutes)} planned',
          ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
              icon: Icon(
                Icons.chevron_left_rounded,
                size: 32,
                color: colors.textPrimary,
              ),
            ),
            Expanded(
              child: Text(
                'Priorities',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton.filled(
              tooltip: 'Add priority',
              style: IconButton.styleFrom(
                backgroundColor: VivordoTheme.brand,
                foregroundColor: Colors.white,
              ),
              onPressed: () => widget.onAdd(context),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            summary,
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
        ),
        if (total > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: plan.doneToday / total,
              minHeight: 4,
              color: _doneGreen,
              backgroundColor: colors.border,
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _planView(_PlanGroups plan) {
    final tomorrow = DateTime(_day.year, _day.month, _day.day + 1);
    return [
      if (plan.overdue.isNotEmpty)
        _group('OVERDUE', plan.overdue, labelColor: _overdueRed),
      _group(
        plan.today.isEmpty
            ? 'TODAY'
            : 'TODAY · ${plan.doneToday} OF ${plan.today.length}',
        plan.today,
        empty: plan.overdue.isEmpty
            ? 'Nothing planned for today.'
            : 'Nothing else planned for today.',
      ),
      for (final entry in plan.later.entries)
        _group(
          DateUtils.isSameDay(entry.key, tomorrow)
              ? 'TOMORROW'
              : DateFormat('EEE, MMM d').format(entry.key).toUpperCase(),
          entry.value,
        ),
      Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Text(
          'Showing the next 2 weeks',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.vivordoColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ),
    ];
  }

  Widget _group(
    String label,
    List<DailyPriority> items, {
    Color? labelColor,
    String? empty,
  }) {
    final colors = context.vivordoColors;
    final open = items.where((p) => !p.completed).toList();
    final done = items.where((p) => p.completed).toList();
    final rows = <Widget>[
      for (final p in open) _plannedRow(p),
      if (open.isEmpty && empty != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Text(empty, style: TextStyle(color: colors.textSecondary)),
        ),
      if (done.isNotEmpty)
        InkWell(
          onTap: () => setState(() => _showCompleted = !_showCompleted),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Icon(
                  _showCompleted
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                  color: colors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  '${done.length} completed',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      if (_showCompleted)
        for (final p in done) _plannedRow(p),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label,
              style: TextStyle(
                color: labelColor ?? colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          _card([
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 52, color: colors.border),
              rows[i],
            ],
          ]),
        ],
      ),
    );
  }

  Widget _plannedRow(DailyPriority p) => SwipeToDelete(
    key: ValueKey(p.reference.path),
    onTap: () => widget.onEdit(context, p),
    onDelete: () => _delete(p),
    confirmTitle: 'Delete priority?',
    confirmMessage: priorityDeleteMessage(
      p.title,
      manual: p.source == 'manual',
    ),
    child: _PriorityTile(
      priority: p,
      today: _day,
      repeatLabel: _recurring(p) ? _labels[p.templateId] ?? 'Repeating' : null,
      busy: _busy.contains(p.reference.path),
      onToggle: () => _toggle(p),
    ),
  );

  List<Widget> _repeatingView(
    List<DailyPriority> schedules,
    List<DailyPriority> all,
  ) {
    final colors = context.vivordoColors;
    if (schedules.isEmpty) {
      return [
        _note(
          'Nothing repeats yet. To repeat a priority, add it or edit it and '
          'choose how often.',
        ),
      ];
    }
    return [
      const SizedBox(height: 12),
      _card([
        for (var i = 0; i < schedules.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 60, color: colors.border),
          _scheduleRow(schedules[i], all),
        ],
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
        child: Text(
          "Tap a schedule to change when it repeats. Each day's copy is "
          'ticked off in Plan.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
      ),
    ];
  }

  Widget _scheduleRow(DailyPriority schedule, List<DailyPriority> all) {
    final colors = context.vivordoColors;
    final occurrences =
        all.where((p) => p.templateId == schedule.templateId).toList()..sort(
          (a, b) =>
              (priorityDueDay(a) ?? _day).compareTo(priorityDueDay(b) ?? _day),
        );
    final next = occurrences.where((p) => !p.completed).firstOrNull;
    final nextDay = next == null ? null : priorityDueDay(next);
    final tomorrow = DateTime(_day.year, _day.month, _day.day + 1);
    final (tag, tagColor) = switch (nextDay) {
      null => ('Done', colors.textSecondary),
      final d when !d.isAfter(_day) => ('Today', _doneGreen),
      final d when DateUtils.isSameDay(d, tomorrow) => (
        'Tomorrow',
        VivordoTheme.brand,
      ),
      final d when d.difference(_day).inDays < 7 => (
        DateFormat('EEE').format(d),
        VivordoTheme.brand,
      ),
      final d => (DateFormat('MMM d').format(d), VivordoTheme.brand),
    };
    final minutes = priorityMinutes(schedule);
    final details = [
      _labels[schedule.templateId] ?? 'Repeating',
      if (schedule.sourceStart != null && !schedule.isAllDay)
        DateFormat.jm().format(schedule.sourceStart!),
      if (minutes != null) formatPriorityMinutes(minutes),
    ].join(' · ');
    return InkWell(
      key: ValueKey('schedule-${schedule.templateId}'),
      onTap: () => widget.onEdit(context, next ?? schedule),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: VivordoTheme.brand.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.repeat_rounded,
                color: VivordoTheme.brand,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schedule.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: tagColor.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  color: tagColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.vivordoColors.border),
    ),
    child: Column(children: children),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: context.vivordoColors.textSecondary),
    ),
  );
}

/// Priorities sorted into the Plan tab's groups.
class _PlanGroups {
  _PlanGroups(this.overdue, this.today, this.later);

  factory _PlanGroups.from(List<DailyPriority> priorities, DateTime day) {
    final overdue = <DailyPriority>[], today = <DailyPriority>[];
    final later = <DateTime, List<DailyPriority>>{};
    for (final p in priorities) {
      if (overdueSince(p, day) != null) {
        overdue.add(p);
        continue;
      }
      final due = priorityDueDay(p) ?? day;
      // Earlier ones still listed were ticked off today.
      if (!due.isAfter(day)) {
        today.add(p);
      } else {
        later.putIfAbsent(due, () => []).add(p);
      }
    }
    final sortedLater = Map.fromEntries(
      later.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return _PlanGroups(overdue, today, sortedLater);
  }

  final List<DailyPriority> overdue;
  final List<DailyPriority> today;
  final Map<DateTime, List<DailyPriority>> later;

  List<DailyPriority> get openToday => [
    ...overdue,
    ...today.where((p) => !p.completed),
  ];
  int get doneToday => today.where((p) => p.completed).length;
}

class _PriorityTile extends StatelessWidget {
  const _PriorityTile({
    required this.priority,
    required this.today,
    required this.repeatLabel,
    required this.busy,
    required this.onToggle,
  });

  final DailyPriority priority;
  final DateTime today;
  final String? repeatLabel;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final p = priority;
    final overdue = overdueSince(p, today);
    final start = p.sourceStart;
    final end = p.sourceEnd;
    final clock = start == null || p.isAllDay
        ? null
        : end == null
        ? DateFormat.jm().format(start)
        : '${DateFormat.jm().format(start)}–${DateFormat.jm().format(end)}';
    final minutes = priorityMinutes(p);
    final effort = switch (p.planning['effort']) {
      'light' => 'Light',
      'moderate' => 'Moderate',
      'demanding' => 'Demanding',
      _ => null,
    };
    final rest = [
      ?clock,
      if (minutes != null && end == null) formatPriorityMinutes(minutes),
      ?effort,
      ?repeatLabel,
    ];
    final onCalendar = p.source == 'calendar' || p.sourceEventKey != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: p.completed ? 'Mark incomplete' : 'Mark completed',
            child: IconButton(
              onPressed: busy ? null : onToggle,
              icon: AppCheckCircle(checked: p.completed, size: 24),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  style: TextStyle(
                    color: p.completed
                        ? colors.textSecondary
                        : colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    decoration: p.completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      if (overdue != null)
                        TextSpan(
                          text: overdueLabel(overdue, today),
                          style: const TextStyle(
                            color: _overdueRed,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (overdue != null && rest.isNotEmpty)
                        const TextSpan(text: ' · '),
                      TextSpan(
                        text: rest.isEmpty && overdue == null
                            ? 'Anytime'
                            : rest.join(' · '),
                      ),
                    ],
                  ),
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onCalendar)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: 'On your calendar',
                child: Icon(
                  Icons.event_outlined,
                  color: colors.textSecondary,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
