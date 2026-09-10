import 'package:flutter/material.dart';
import '../src/services/daily_priority_service.dart';
import 'priority_reminder_picker.dart';
import 'vivordo_time_picker.dart';

Future<(String, int, int?)?> showEditPrioritySheet(
  BuildContext context,
  DailyPriority priority,
) => showDialog<(String, int, int?)>(
  context: context,
  builder: (_) => _EditPriority(priority),
);

class _EditPriority extends StatefulWidget {
  const _EditPriority(this.priority);
  final DailyPriority priority;
  @override
  State<_EditPriority> createState() => _EditPriorityState();
}

class _EditPriorityState extends State<_EditPriority> {
  late final _title = TextEditingController(text: widget.priority.title);
  late int _minutes = widget.priority.reminderMinutes;
  late int? _reminderTime = widget.priority.reminderTimeMinutes;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit Priority'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Priority'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reminder'),
            subtitle: Text(
              widget.priority.sourceStart == null || widget.priority.isAllDay
                  ? (_reminderTime == null
                        ? 'Choose reminder time'
                        : TimeOfDay(
                            hour: _reminderTime! ~/ 60,
                            minute: _reminderTime! % 60,
                          ).format(context))
                  : priorityReminderLabel(_minutes),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                widget.priority.sourceStart == null || widget.priority.isAllDay
                ? () async {
                    final value = await showVivordoTimePicker(
                      context: context,
                      initialTime: _reminderTime == null
                          ? TimeOfDay.now()
                          : TimeOfDay(
                              hour: _reminderTime! ~/ 60,
                              minute: _reminderTime! % 60,
                            ),
                    );
                    if (value != null && mounted)
                      setState(
                        () => _reminderTime = value.hour * 60 + value.minute,
                      );
                  }
                : () async {
                    final result = await showPriorityReminderPicker(
                      context,
                      _minutes,
                    );
                    if (result != null && mounted) {
                      setState(() => _minutes = result);
                    }
                  },
          ),
          const Text(
            'Reminders whose time has already passed will not be sent.',
          ),
          if (widget.priority.source != 'manual')
            const Text(
              'Changes apply to this priority only, not the original event or recurring schedule.',
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _title.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (
                _title.text.trim(),
                _minutes,
                _reminderTime,
              )),
        child: const Text('Save Changes'),
      ),
    ],
  );
}
