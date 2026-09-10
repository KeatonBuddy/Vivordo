import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../src/services/daily_priority_service.dart';
import '../theme/vivordo_theme.dart';

const _accent = Color(0xFF8976FF);

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

class AllPrioritiesScreen extends StatefulWidget {
  const AllPrioritiesScreen({
    super.key,
    required this.onAdd,
    required this.onEdit,
    this.priorities,
  });
  final Future<void> Function(BuildContext) onAdd;
  final Future<void> Function(BuildContext, DailyPriority) onEdit;
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
  bool _showCompleted = true;
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
        if (mounted) _message('Could not refresh recurring priorities.');
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

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _toggle(DailyPriority p) async {
    final key = p.reference.path;
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      await DailyPriorityService.setCompleted(p, !p.completed);
    } catch (_) {
      if (mounted) _message('Could not update priority. Please try again.');
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  bool _recurring(DailyPriority p) => p.source == 'recurring_manual';
  bool _upcoming(DailyPriority p) =>
      (p.date ?? p.sourceStart ?? _day).isAfter(_day) &&
      !DateUtils.isSameDay(p.date ?? p.sourceStart, _day);
  String _subtitle(DailyPriority p) {
    final date = p.date ?? p.sourceStart ?? _day;
    final time = p.sourceStart == null || p.isAllDay
        ? null
        : DateFormat.jm().format(p.sourceStart!);
    final end = p.sourceEnd;
    final clock = time != null && end != null
        ? '$time–${DateFormat.jm().format(end)}'
        : time;
    final label = DateUtils.isSameDay(date, _day) || date.isBefore(_day)
        ? null
        : DateUtils.isSameDay(date, _day.add(const Duration(days: 1)))
        ? 'Tomorrow'
        : DateFormat('MMM d').format(date);
    return [
      if (_recurring(p)) _labels[p.templateId] ?? 'Repeating',
      ?label,
      ?clock,
      if (clock == null && label == null) 'Anytime',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'All Priorities',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.chevron_left, color: _accent, size: 34),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton.filled(
              tooltip: 'Add priority',
              style: IconButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => widget.onAdd(context),
              icon: const Icon(Icons.add),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<DailyPriority>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load priorities. Please reopen this screen.',
                style: TextStyle(color: colors.textSecondary),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = distinctPriorities(snapshot.data!);
          final visible = all
              .where((p) => _showCompleted || !p.completed)
              .toList();
          final today = visible
              .where((p) => !_recurring(p) && !_upcoming(p))
              .toList();
          final upcoming = visible
              .where((p) => !_recurring(p) && _upcoming(p))
              .toList();
          final recurring = visible.where(_recurring).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 110),
            children: [
              _panel(
                Row(
                  children: [
                    _stat(
                      Icons.event_available_outlined,
                      Colors.greenAccent,
                      '${all.length}',
                      'priorities',
                    ),
                    _stat(
                      Icons.today_outlined,
                      Colors.blueAccent,
                      '${all.where((p) => !p.completed && !_upcoming(p)).length}',
                      'due today',
                    ),
                    _stat(
                      Icons.sync,
                      _accent,
                      '${all.where(_recurring).length}',
                      'recurring',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _showCompleted ? 'Including completed' : 'Incomplete only',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  PopupMenuButton<bool>(
                    tooltip: 'Filter priorities',
                    icon: const Icon(Icons.tune, color: _accent),
                    initialValue: _showCompleted,
                    onSelected: (value) =>
                        setState(() => _showCompleted = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: true,
                        child: Text('Include completed'),
                      ),
                      PopupMenuItem(
                        value: false,
                        child: Text('Incomplete only'),
                      ),
                    ],
                  ),
                ],
              ),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'No priorities here yet. Add one to get started.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              if (today.isNotEmpty) _section('TODAY', today),
              if (upcoming.isNotEmpty) _section('UPCOMING', upcoming),
              if (recurring.isNotEmpty) _section('RECURRING', recurring),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent),
                  padding: const EdgeInsets.all(18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () => widget.onAdd(context),
                icon: const Icon(Icons.add),
                label: const Text(
                  'Add priority',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _panel(Widget child) => Container(
    decoration: BoxDecoration(
      color: context.vivordoColors.card,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
  Widget _stat(IconData icon, Color color, String count, String label) =>
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 10),
              Text(
                '$count $label',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
  Widget _section(String title, List<DailyPriority> priorities) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title · ${priorities.length}',
          style: TextStyle(
            color: context.vivordoColors.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        _panel(
          Column(
            children: [
              for (var i = 0; i < priorities.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 18, endIndent: 18),
                _row(priorities[i]),
              ],
            ],
          ),
        ),
      ],
    ),
  );
  Widget _row(DailyPriority p) => ListTile(
    key: ValueKey(p.reference.path),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    leading: IconButton(
      tooltip: p.completed ? 'Mark incomplete' : 'Mark completed',
      onPressed: _busy.contains(p.reference.path) ? null : () => _toggle(p),
      icon: Icon(
        p.completed ? Icons.check_circle : Icons.radio_button_unchecked,
        color: p.completed ? _accent : context.vivordoColors.textSecondary,
        size: 28,
      ),
    ),
    title: Text(
      p.title,
      style: TextStyle(
        decoration: p.completed ? TextDecoration.lineThrough : null,
        color: p.completed
            ? context.vivordoColors.textSecondary
            : context.vivordoColors.textPrimary,
      ),
    ),
    subtitle: Text(
      _subtitle(p),
      style: TextStyle(
        color: p.sourceStart == null
            ? context.vivordoColors.textSecondary
            : _accent,
      ),
    ),
    onTap: () => widget.onEdit(context, p),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_recurring(p))
          const Icon(Icons.sync, color: _accent, size: 22)
        else if (p.source != 'manual')
          const Icon(Icons.event_outlined, color: Colors.blueAccent, size: 22),
        IconButton(
          tooltip: 'Edit priority',
          onPressed: () => widget.onEdit(context, p),
          icon: const Icon(Icons.more_horiz),
        ),
      ],
    ),
  );
}
