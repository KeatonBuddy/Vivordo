import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

String priorityReminderLabel(int minutes) => switch (minutes) {
  0 => 'During',
  30 => '30 min before',
  60 => '1 hr before',
  360 => '6 hr before',
  _ => '$minutes min before',
};

Future<int?> showPriorityReminderPicker(
  BuildContext context,
  int current,
) async {
  final selected = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final minutes in [0, 30, 60, 360, -1])
              ListTile(
                title: Text(
                  minutes == -1 ? 'Custom' : priorityReminderLabel(minutes),
                ),
                subtitle: minutes == 0
                    ? const Text('At the selected start time')
                    : null,
                trailing: current == minutes ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, minutes),
              ),
          ],
        ),
      ),
    ),
  );
  if (selected != -1 || !context.mounted) return selected;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CustomReminder(current),
  );
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
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _hours * 60 + _minutes),
                child: const Text('Done'),
              ),
            ],
          ),
          const Text(
            'Custom reminder',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('Hours and minutes before the priority'),
          SizedBox(
            height: 216,
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: Theme.of(context).brightness,
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
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text('0 hr 0 min = at start time · Maximum 7 days'),
          ),
        ],
      ),
    );
  }
}
