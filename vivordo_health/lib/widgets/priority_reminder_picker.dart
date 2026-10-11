import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../theme/vivordo_theme.dart';
import 'apple_ui.dart';

String priorityReminderLabel(int minutes) => switch (minutes) {
  0 => 'At start time',
  30 => '30 min before',
  60 => '1 hr before',
  360 => '6 hr before',
  _ => '$minutes min before',
};

Future<int?> showPriorityReminderPicker(
  BuildContext context,
  int current,
) async {
  const presets = [0, 30, 60, 360];
  final selected = await showAppleActionSheet<int>(
    context,
    title: 'Reminder',
    actions: [
      for (final minutes in presets)
        AppleSheetAction(
          minutes == 0 ? 'At start time' : priorityReminderLabel(minutes),
          minutes,
          selected: current == minutes,
        ),
      AppleSheetAction('Custom', -1, selected: !presets.contains(current)),
    ],
  );
  if (selected != -1 || !context.mounted) return selected;
  return showAppleSheet<int>(context, builder: (_) => _CustomReminder(current));
}

class _CustomReminder extends StatefulWidget {
  const _CustomReminder(this.current);
  final int current;
  @override
  State<_CustomReminder> createState() => _CustomReminderState();
}

class _CustomReminderState extends State<_CustomReminder> {
  late int _hours = widget.current.clamp(0, 10080) ~/ 60;
  late int _minutes = widget.current.clamp(0, 10080) % 60;
  late final _hoursController = FixedExtentScrollController(
    initialItem: _hours,
  );
  late final _minutesController = FixedExtentScrollController(
    initialItem: _minutes,
  );
  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return AppleFormSheet(
      title: 'Custom reminder',
      onDone: () => Navigator.pop(context, _hours * 60 + _minutes),
      children: [
        Text(
          'Hours and minutes before the priority',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
        SizedBox(
          height: 216,
          child: CupertinoTheme(
            data: CupertinoThemeData(
              brightness: Theme.of(context).brightness,
              textTheme: CupertinoTextThemeData(
                pickerTextStyle: TextStyle(
                  fontSize: 21,
                  color: colors.textPrimary,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    key: const ValueKey('reminder-hours'),
                    scrollController: _hoursController,
                    itemExtent: 36,
                    onSelectedItemChanged: (value) {
                      setState(() {
                        _hours = value;
                        if (_hours == 168) _minutes = 0;
                      });
                      if (_hours == 168) _minutesController.jumpToItem(0);
                    },
                    children: [
                      for (var hour = 0; hour <= 168; hour++)
                        Center(child: Text('$hour hr')),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    key: const ValueKey('reminder-minutes'),
                    scrollController: _minutesController,
                    itemExtent: 36,
                    onSelectedItemChanged: (value) =>
                        setState(() => _minutes = _hours == 168 ? 0 : value),
                    children: [
                      for (
                        var minute = 0;
                        minute < (_hours == 168 ? 1 : 60);
                        minute++
                      )
                        Center(child: Text('$minute min')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          '0 hr 0 min = at start time · Maximum 7 days',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
      ],
    );
  }
}
