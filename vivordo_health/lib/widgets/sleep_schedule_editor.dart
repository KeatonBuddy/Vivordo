import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/utils/sleep_schedule.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/apple_ui.dart';
import 'package:vivordo_health/widgets/vivordo_time_picker.dart';

/// Bed and wake times, with an optional weekend pair. Used by onboarding and
/// Sleep preferences.
class SleepScheduleEditor extends StatelessWidget {
  const SleepScheduleEditor({
    super.key,
    required this.schedule,
    required this.onChanged,
  });

  final SleepSchedule schedule;
  final ValueChanged<SleepSchedule> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final s = schedule;
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: colors.textSecondary),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.weekendsDiffer) label('Sunday to Thursday nights'),
          _TimeRow(
            label: 'Bedtime',
            minutes: s.bed,
            onChanged: (m) => onChanged(_copy(s, bed: m)),
          ),
          _TimeRow(
            label: 'Wake up',
            minutes: s.wake,
            onChanged: (m) => onChanged(_copy(s, wake: m)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: MergeSemantics(
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Weekends are different',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                  AppSwitch(
                    value: s.weekendsDiffer,
                    onChanged: (on) => onChanged(
                      SleepSchedule(
                        bed: s.bed,
                        wake: s.wake,
                        weekendBed: on ? s.bed : null,
                        weekendWake: on ? s.wake : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (s.weekendsDiffer) ...[
            label('Friday and Saturday nights'),
            _TimeRow(
              label: 'Bedtime',
              minutes: s.weekendBed!,
              onChanged: (m) => onChanged(_copy(s, weekendBed: m)),
            ),
            _TimeRow(
              label: 'Wake up',
              minutes: s.weekendWake!,
              onChanged: (m) => onChanged(_copy(s, weekendWake: m)),
            ),
          ],
        ],
      ),
    );
  }

  static SleepSchedule _copy(
    SleepSchedule s, {
    int? bed,
    int? wake,
    int? weekendBed,
    int? weekendWake,
  }) => SleepSchedule(
    bed: bed ?? s.bed,
    wake: wake ?? s.wake,
    weekendBed: weekendBed ?? s.weekendBed,
    weekendWake: weekendWake ?? s.weekendWake,
  );
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final picked = await showVivordoTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        title: label,
        minuteInterval: 15,
      );
      if (picked != null) onChanged(picked.hour * 60 + picked.minute);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
          Text(
            DateFormat.jm().format(
              DateTime(2000).add(Duration(minutes: minutes)),
            ),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: VivordoTheme.brand,
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            color: context.vivordoColors.textSecondary,
          ),
        ],
      ),
    ),
  );
}
