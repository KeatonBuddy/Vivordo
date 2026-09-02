import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

const _summaryPurple = Color(0xFF6B5CE7);

enum CalendarEventSummaryAction { edit, delete }

class CalendarEventSummaryData {
  const CalendarEventSummaryData({
    required this.title,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.isRecurring,
    required this.color,
    required this.calendarName,
    required this.canEdit,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool isAllDay;
  final bool isRecurring;
  final Color color;
  final String calendarName;
  final bool canEdit;

  String get durationLabel {
    if (isAllDay) return 'All-day event';
    final minutes = end.difference(start).inMinutes;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }
}

Future<CalendarEventSummaryAction?> showCalendarEventSummarySheet(
  BuildContext context, {
  required CalendarEventSummaryData event,
}) => showModalBottomSheet<CalendarEventSummaryAction>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (context) => _CalendarEventSummarySheet(event: event),
);

class _CalendarEventSummarySheet extends StatelessWidget {
  const _CalendarEventSummarySheet({required this.event});

  final CalendarEventSummaryData event;

  (String, Color) get _status {
    final now = DateTime.now();
    if (!now.isBefore(event.end)) {
      return ('COMPLETED', const Color(0xFF20A968));
    }
    if (!now.isBefore(event.start)) {
      return ('IN PROGRESS', const Color(0xFFFF9F0A));
    }
    return ('UPCOMING', _summaryPurple);
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
                              color: _summaryPurple.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.calendar_month_rounded,
                              color: _summaryPurple,
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
                          value: event.calendarName,
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
                        onPressed: event.canEdit
                            ? () => Navigator.pop(
                                context,
                                CalendarEventSummaryAction.edit,
                              )
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: _summaryPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          event.canEdit
                              ? 'Edit Event'
                              : '${event.calendarName} event · Read only',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (event.canEdit) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => Navigator.pop(
                            context,
                            CalendarEventSummaryAction.delete,
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
                    if (!event.canEdit) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${event.calendarName} events are currently read-only in Vivordo.',
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
      color: _summaryPurple,
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
              Icon(icon, color: _summaryPurple, size: 23),
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
