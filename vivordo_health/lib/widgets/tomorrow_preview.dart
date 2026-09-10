import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../src/services/daily_priority_service.dart';
import '../theme/vivordo_theme.dart';

class TomorrowPreviewEvent {
  const TomorrowPreviewEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    required this.onTap,
  });
  final String title;
  final DateTime start, end;
  final bool allDay;
  final VoidCallback onTap;
}

class TomorrowPreview extends StatelessWidget {
  const TomorrowPreview({
    super.key,
    required this.day,
    required this.events,
    required this.priorities,
    required this.onViewDay,
    required this.onEdit,
    required this.onToggle,
    this.loading = false,
    this.error,
  });
  final DateTime day;
  final List<TomorrowPreviewEvent> events;
  final List<DailyPriority> priorities;
  final VoidCallback onViewDay;
  final void Function(DailyPriority) onEdit, onToggle;
  final bool loading;
  final String? error;
  static const purple = Color(0xFF8976FF);
  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              'TOMORROW',
              style: TextStyle(
                color: colors.textSecondary,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              DateFormat('EEE, MMM d').format(day),
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            TextButton(onPressed: onViewDay, child: const Text('View day ›')),
          ],
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.textSecondary.withValues(alpha: .16),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : error != null
                  ? Text(error!, style: TextStyle(color: colors.textSecondary))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${events.length} ${events.length == 1 ? 'event' : 'events'} · ${priorities.length} ${priorities.length == 1 ? 'priority' : 'priorities'}',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const Divider(),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final schedule = _schedule(context);
                            final tasks = _priorities(context);
                            if (constraints.maxWidth < 360 ||
                                MediaQuery.textScalerOf(context).scale(14) >
                                    18) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [schedule, const Divider(), tasks],
                              );
                            }
                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: schedule),
                                  VerticalDivider(
                                    width: 18,
                                    thickness: 1,
                                    color: colors.textSecondary.withValues(
                                      alpha: .25,
                                    ),
                                  ),
                                  Expanded(child: tasks),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        color: context.vivordoColors.textSecondary,
        fontSize: 11,
        letterSpacing: 1,
      ),
    ),
  );
  Widget _schedule(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(context, 'SCHEDULE'),
      if (events.isEmpty)
        const Text('No events scheduled', style: TextStyle(fontSize: 12)),
      for (final event in events.take(2))
        InkWell(
          onTap: event.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                const Icon(Icons.event_outlined, color: purple, size: 18),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        event.allDay
                            ? 'All day'
                            : '${event.start.isBefore(day) ? 'Ongoing' : DateFormat.jm().format(event.start)} · ${_duration(event)}',
                        style: TextStyle(
                          color: context.vivordoColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      if (events.length > 2)
        TextButton(
          onPressed: onViewDay,
          child: Text(
            '+${events.length - 2} more ${events.length == 3 ? 'event' : 'events'}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
    ],
  );
  String _duration(TomorrowPreviewEvent event) {
    final minutes = event.end.difference(event.start).inMinutes;
    return minutes < 60
        ? '$minutes min'
        : '${minutes ~/ 60}h${minutes % 60 == 0 ? '' : ' ${minutes % 60}m'}';
  }

  Widget _priorities(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(context, 'PRIORITIES'),
      if (priorities.isEmpty)
        const Text('No priorities planned', style: TextStyle(fontSize: 12)),
      for (final priority in priorities.take(2))
        InkWell(
          onTap: () => onEdit(priority),
          child: Row(
            children: [
              IconButton(
                tooltip: priority.completed
                    ? 'Mark incomplete'
                    : 'Mark completed',
                onPressed: () => onToggle(priority),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
                icon: Icon(
                  priority.completed
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: purple,
                  size: 22,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      priority.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        decoration: priority.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    Text(
                      priority.sourceStart == null || priority.isAllDay
                          ? 'Anytime'
                          : DateFormat.jm().format(priority.sourceStart!),
                      style: const TextStyle(color: purple, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (priorities.length > 2)
        Text(
          '+${priorities.length - 2} more priorities',
          style: TextStyle(
            color: context.vivordoColors.textSecondary,
            fontSize: 12,
          ),
        ),
    ],
  );
}
