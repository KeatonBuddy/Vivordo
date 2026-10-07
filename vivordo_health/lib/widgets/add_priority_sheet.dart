import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/vivordo_time_picker.dart';
import 'apple_ui.dart';
import 'priority_reminder_picker.dart';
import 'priority_duration_picker.dart';

const _purple = Color(0xFF6254F4);

enum PriorityRepeat { once, daily, selectedDays }

class PriorityDraft {
  const PriorityDraft({
    required this.title,
    required this.date,
    required this.time,
    required this.addToCalendar,
    required this.repeat,
    required this.selectedWeekdays,
    required this.repeatEnd,
    this.reminderMinutes = 60,
    this.reminderTimeMinutes,
    this.completed = false,
    this.deleteRequested = false,
    this.planning = const {},
    this.habit = false,
    this.target = 1,
  });

  final Map<String, dynamic> planning;
  final String title;
  final DateTime date;
  final TimeOfDay? time;
  final bool addToCalendar;
  final PriorityRepeat repeat;
  final Set<int> selectedWeekdays;
  final DateTime? repeatEnd;
  final int reminderMinutes;
  final int? reminderTimeMinutes;
  final bool completed;
  final bool deleteRequested;

  /// A daily habit, done [target] times a day.
  final bool habit;
  final int target;

  DateTime? get scheduledAt => time == null
      ? null
      : DateTime(date.year, date.month, date.day, time!.hour, time!.minute);

  String get recurrence => switch (repeat) {
    PriorityRepeat.once => 'none',
    PriorityRepeat.daily => 'daily',
    PriorityRepeat.selectedDays => 'weekly',
  };

  String get calendarRecurrence {
    const codes = {
      1: 'MO',
      2: 'TU',
      3: 'WE',
      4: 'TH',
      5: 'FR',
      6: 'SA',
      7: 'SU',
    };
    final base = switch (repeat) {
      PriorityRepeat.once => 'none',
      PriorityRepeat.daily => 'daily',
      PriorityRepeat.selectedDays =>
        'weekly:${(selectedWeekdays.toList()..sort()).map((day) => codes[day]).join(',')}',
    };
    if (repeatEnd == null || repeat == PriorityRepeat.once) return base;
    return '$base;until=${DateFormat('yyyyMMdd').format(repeatEnd!)}';
  }
}

Future<PriorityDraft?> showAddPrioritySheet(BuildContext context) =>
    showModalBottomSheet<PriorityDraft>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .68),
      builder: (_) => const _AddPrioritySheet(),
    );

/// The add form for hosting in another sheet. [at] prefills the date and
/// time; [header] replaces the title. Saving pops a [PriorityDraft].
/// [titleController], when given, is owned by the caller (so a title can
/// carry over to another form).
Widget addPriorityForm({
  DateTime? at,
  Widget? header,
  TextEditingController? titleController,
}) =>
    _AddPrioritySheet(at: at, header: header, titleController: titleController);

/// [habitSwitch] offers to make it a habit; [forSchedule] edits a whole
/// repeating schedule rather than one day's copy.
Future<PriorityDraft?> showPriorityEditor(
  BuildContext context,
  PriorityDraft initial, {
  bool occurrenceOnly = false,
  bool habitSwitch = false,
  bool forSchedule = false,
}) => showModalBottomSheet<PriorityDraft>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .68),
  builder: (_) => _AddPrioritySheet(
    initial: initial,
    occurrenceOnly: occurrenceOnly,
    habitSwitch: habitSwitch,
    forSchedule: forSchedule,
  ),
);

class _AddPrioritySheet extends StatefulWidget {
  const _AddPrioritySheet({
    this.initial,
    this.occurrenceOnly = false,
    this.at,
    this.header,
    this.titleController,
    this.habitSwitch = true,
    this.forSchedule = false,
  });
  final PriorityDraft? initial;
  final bool habitSwitch;
  final bool forSchedule;
  final DateTime? at;
  final Widget? header;
  final TextEditingController? titleController;
  final bool occurrenceOnly;

  @override
  State<_AddPrioritySheet> createState() => _AddPrioritySheetState();
}

class _AddPrioritySheetState extends State<_AddPrioritySheet> {
  late final TextEditingController _controller;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  TimeOfDay? _time;
  bool _addToCalendar = false;
  PriorityRepeat _repeat = PriorityRepeat.once;
  late Set<int> _selectedWeekdays;
  DateTime? _repeatEnd;
  int _reminderMinutes = 60;
  TimeOfDay? _reminderTime;
  bool _completed = false;
  late Map<String, dynamic> _planning;
  bool _habit = false;
  int _target = 1;
  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _planning = {...?initial?.planning};
    _controller =
        (widget.titleController ?? TextEditingController(text: initial?.title))
          ..addListener(_changed);
    final at = widget.at;
    _date = initial?.date ?? (at == null ? _date : DateUtils.dateOnly(at));
    _time = initial?.time ?? (at == null ? null : TimeOfDay.fromDateTime(at));
    _repeat = initial?.repeat ?? PriorityRepeat.once;
    _repeatEnd = initial?.repeatEnd;
    _completed = initial?.completed ?? false;
    _habit = initial?.habit ?? false;
    _target = initial?.target ?? 1;
    _reminderMinutes = initial?.reminderMinutes ?? 60;
    final reminder = initial?.reminderTimeMinutes;
    _reminderTime = reminder == null
        ? null
        : TimeOfDay(hour: reminder ~/ 60, minute: reminder % 60);
    _selectedWeekdays = initial == null
        ? {_date.weekday}
        : {...initial.selectedWeekdays};
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (widget.titleController == null) _controller.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _pickDate() async {
    final value = await showVivordoDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _date.isBefore(DateUtils.dateOnly(DateTime.now()))
          ? _date
          : DateUtils.dateOnly(DateTime.now()),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showVivordoTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (value != null) setState(() => _time = value);
  }

  Future<void> _pickRepeatEnd() async {
    final choice = await showAppleActionSheet<bool>(
      context,
      title: 'Repeat ends',
      actions: [
        AppleSheetAction('Never', false, selected: _repeatEnd == null),
        AppleSheetAction('On a date', true, selected: _repeatEnd != null),
      ],
    );
    if (choice == null) return;
    if (!choice) {
      setState(() => _repeatEnd = null);
      return;
    }
    if (!mounted) return;
    final value = await showVivordoDatePicker(
      context: context,
      initialDate: _repeatEnd ?? _date.add(const Duration(days: 30)),
      firstDate: _date,
      lastDate: DateTime(2100),
      title: 'Repeat ends',
    );
    if (value != null) setState(() => _repeatEnd = value);
  }

  Future<void> _pickReminderTime() async {
    final value = await showVivordoTimePicker(
      context: context,
      initialTime: _reminderTime ?? TimeOfDay.now(),
    );
    if (value != null && mounted) setState(() => _reminderTime = value);
  }

  /// Whether [field] holds Vivordo AI's estimate rather than the user's
  /// own value (DailyPriorityService.estimateBlanks).
  bool _isEstimate(String field) =>
      (_planning['estimated'] as List?)?.contains(field) == true;

  /// Sets a workload value the user chose, so it's no longer an estimate.
  void _setPlanning(String field, Object? value) {
    _planning[field] = value;
    final estimated = [...?(_planning['estimated'] as List?)]..remove(field);
    if (estimated.isEmpty) {
      _planning.remove('estimated');
    } else {
      _planning['estimated'] = estimated;
    }
  }

  void _submit({bool deleteRequested = false}) {
    final title = _controller.text.trim();
    if (!deleteRequested && title.isEmpty) return;
    if (!deleteRequested &&
        !_habit &&
        _addToCalendar &&
        _time != null &&
        _planning['minutes'] == null) {
      showToast(
        context,
        'Add an estimated duration before creating a timed calendar event.',
      );
      return;
    }
    Navigator.pop(
      context,
      PriorityDraft(
        title: title,
        planning: _habit ? const {} : _planning,
        date: _habit && !_editing ? DateUtils.dateOnly(DateTime.now()) : _date,
        time: _habit ? null : _time,
        addToCalendar: !_habit && _addToCalendar,
        habit: _habit,
        target: _habit ? _target : 1,
        repeat: _repeat,
        selectedWeekdays: _selectedWeekdays,
        repeatEnd: _repeatEnd,
        reminderMinutes: _reminderMinutes,
        completed: _completed,
        deleteRequested: deleteRequested,
        reminderTimeMinutes: _reminderTime == null
            ? null
            : _reminderTime!.hour * 60 + _reminderTime!.minute,
      ),
    );
  }

  String get _dateLabel => DateUtils.isSameDay(_date, DateTime.now())
      ? 'Today'
      : DateFormat('MMM d, y').format(_date);

  String get _repeatSummary {
    const names = {
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
      7: 'Sun',
    };
    final days = _selectedWeekdays.toList()..sort();
    return 'Repeats every week on ${days.map((day) => names[day]).join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final lightMode = Theme.of(context).brightness == Brightness.light;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: keyboard),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: colors.textPrimary.withValues(alpha: .18)),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 32)],
        ),
        child: Column(
          children: [
            const SizedBox(height: 14),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 14, 2),
              child: Row(
                children: [
                  const SizedBox(width: 42),
                  Expanded(
                    child:
                        widget.header ??
                        Text(
                          '${_editing ? 'Edit' : 'Add'} '
                          '${_habit ? 'Habit' : 'Priority'}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Label(_habit ? 'HABIT' : 'PRIORITY'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _controller,
                      autofocus: !_editing,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _habit
                            ? 'Drink water, take meds, go for a walk'
                            : 'What do you want to accomplish?',
                        filled: true,
                        fillColor: colors.textPrimary.withValues(alpha: .04),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    if (widget.habitSwitch) ...[
                      const SizedBox(height: 14),
                      _Card(
                        children: [
                          _SwitchRow(
                            icon: Icons.loop_rounded,
                            label: 'Habit',
                            detail: 'A small thing you do most days',
                            value: _habit,
                            onChanged: (value) => setState(() {
                              _habit = value;
                              // A habit always repeats.
                              if (value && _repeat == PriorityRepeat.once) {
                                _repeat = PriorityRepeat.daily;
                              }
                            }),
                          ),
                        ],
                      ),
                    ],
                    if (_habit) ...[
                      const SizedBox(height: 26),
                      const _Label('GOAL'),
                      const SizedBox(height: 10),
                      _Card(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.flag_outlined,
                                  color: _purple,
                                  size: 23,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    'Times a day',
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Fewer',
                                  onPressed: _target > 1
                                      ? () => setState(() => _target--)
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '$_target',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'More',
                                  color: _purple,
                                  onPressed: _target < 20
                                      ? () => setState(() => _target++)
                                      : null,
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                          ),
                          _Row(
                            icon: Icons.notifications_outlined,
                            label: 'Reminder',
                            value: _reminderTime?.format(context) ?? 'Off',
                            onTap: _pickReminderTime,
                          ),
                          if (_reminderTime != null)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _reminderTime = null),
                              child: const Text('Remove reminder'),
                            ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 26),
                      const _Label('WORKLOAD ESTIMATE'),
                      const SizedBox(height: 10),
                      _Card(
                        children: [
                          _Row(
                            icon: Icons.timer_outlined,
                            label: 'Estimated duration',
                            value: _planning['minutes'] == null
                                ? 'Not set'
                                : '${_isEstimate('minutes') ? '≈ ' : ''}'
                                      '${(_planning['minutes'] as num).toInt() ~/ 60} hr ${(_planning['minutes'] as num).toInt() % 60} min',
                            onTap: () async {
                              FocusScope.of(context).unfocus();
                              final minutes = await showPriorityDurationPicker(
                                context,
                                initialMinutes: (_planning['minutes'] as num?)
                                    ?.toInt(),
                              );
                              if (minutes != null && mounted) {
                                setState(
                                  () => _setPlanning(
                                    'minutes',
                                    minutes == 0 ? null : minutes,
                                  ),
                                );
                              }
                            },
                          ),
                          _Row(
                            icon: Icons.bar_chart_rounded,
                            label: 'Effort (optional)',
                            value:
                                (_planning['effort'] != null &&
                                        _isEstimate('effort')
                                    ? '≈ '
                                    : '') +
                                switch (_planning['effort']) {
                                  'light' => 'Light',
                                  'moderate' => 'Moderate',
                                  'demanding' => 'Demanding',
                                  _ => 'Not set',
                                },
                            onTap: () async {
                              FocusScope.of(context).unfocus();
                              final selected =
                                  await showCupertinoModalPopup<String>(
                                    context: context,
                                    builder: (sheetContext) => CupertinoTheme(
                                      data: CupertinoThemeData(
                                        brightness: Theme.of(
                                          context,
                                        ).brightness,
                                        primaryColor: _purple,
                                      ),
                                      child: CupertinoActionSheet(
                                        title: const Text('Effort'),
                                        message: const Text(
                                          'How demanding will this priority feel?',
                                        ),
                                        actions: [
                                          for (final choice in const [
                                            ('light', 'Light'),
                                            ('moderate', 'Moderate'),
                                            ('demanding', 'Demanding'),
                                            ('clear', 'Not set'),
                                          ])
                                            CupertinoActionSheetAction(
                                              isDefaultAction:
                                                  (_planning['effort'] ??
                                                      'clear') ==
                                                  choice.$1,
                                              onPressed: () => Navigator.pop(
                                                sheetContext,
                                                choice.$1,
                                              ),
                                              child: Text(choice.$2),
                                            ),
                                        ],
                                        cancelButton:
                                            CupertinoActionSheetAction(
                                              onPressed: () =>
                                                  Navigator.pop(sheetContext),
                                              child: const Text('Cancel'),
                                            ),
                                      ),
                                    ),
                                  );
                              if (selected != null && mounted) {
                                setState(
                                  () => _setPlanning(
                                    'effort',
                                    selected == 'clear' ? null : selected,
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      const _Label('SCHEDULE'),
                      const SizedBox(height: 10),
                      _Card(
                        children: [
                          _Row(
                            icon: Icons.calendar_month_rounded,
                            label: 'Date',
                            value: _dateLabel,
                            onTap: _pickDate,
                          ),
                          _Row(
                            icon: Icons.schedule_rounded,
                            label: 'Time',
                            value: _time?.format(context) ?? 'Add time',
                            onTap: _pickTime,
                          ),
                          _Row(
                            icon: Icons.notifications_outlined,
                            label: 'Reminder',
                            value: _time == null
                                ? (_reminderTime?.format(context) ??
                                      'Choose reminder time')
                                : priorityReminderLabel(_reminderMinutes),
                            onTap: () async {
                              if (_time == null) return _pickReminderTime();
                              final value = await showPriorityReminderPicker(
                                context,
                                _reminderMinutes,
                              );
                              if (value != null && mounted) {
                                setState(() => _reminderMinutes = value);
                              }
                            },
                          ),
                          if (_time == null && _reminderTime != null)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _reminderTime = null),
                              child: const Text('Remove reminder time'),
                            ),
                          if (_time != null)
                            TextButton(
                              onPressed: () => setState(() => _time = null),
                              child: const Text('Remove time'),
                            ),
                          _SwitchRow(
                            icon: Icons.event_available_rounded,
                            label: 'Add to calendar',
                            detail: 'Create an event in your calendar',
                            value: _addToCalendar,
                            onChanged: (value) =>
                                setState(() => _addToCalendar = value),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 26),
                    if (_habit && _editing)
                      Text(
                        'Changes apply to every day it repeats.',
                        style: TextStyle(color: colors.textSecondary),
                      )
                    else ...[
                      _Label(
                        widget.occurrenceOnly ? 'THIS OCCURRENCE' : 'REPEAT',
                      ),
                      const SizedBox(height: 10),
                      if (widget.occurrenceOnly)
                        const Text(
                          'Changes apply to this priority only, not the original calendar event or recurring schedule.',
                        )
                      else
                        _RepeatSelector(
                          value: _repeat,
                          allowOnce: !_habit,
                          onChanged: (value) => setState(() => _repeat = value),
                        ),
                      if (_repeat == PriorityRepeat.selectedDays) ...[
                        const SizedBox(height: 16),
                        _Weekdays(
                          selected: _selectedWeekdays,
                          onChanged: (value) =>
                              setState(() => _selectedWeekdays = value),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            _repeatSummary,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      if (_repeat != PriorityRepeat.once) ...[
                        const SizedBox(height: 14),
                        _Card(
                          children: [
                            _Row(
                              icon: null,
                              label: 'Ends',
                              value: _repeatEnd == null
                                  ? 'Never'
                                  : DateFormat('MMM d, y').format(_repeatEnd!),
                              onTap: _pickRepeatEnd,
                            ),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 28),
                    if (_editing && !_habit) ...[
                      _Card(
                        children: [
                          AppleFormRow(
                            label: 'Mark as completed',
                            leading: AppCheckCircle(checked: _completed),
                            onTap: () =>
                                setState(() => _completed = !_completed),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4148F5), Color(0xFF5D45DC)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: FilledButton(
                          onPressed:
                              _controller.text.trim().isEmpty ||
                                  (_repeat == PriorityRepeat.selectedDays &&
                                      _selectedWeekdays.isEmpty)
                              ? null
                              : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white.withValues(
                              alpha: lightMode ? .78 : .58,
                            ),
                            shadowColor: Colors.transparent,
                          ),
                          child: Text(
                            _editing
                                ? 'Save Changes'
                                : _habit
                                ? 'Add Habit'
                                : 'Add Priority',
                            style: const TextStyle(fontSize: 17),
                          ),
                        ),
                      ),
                    ),
                    if (_editing) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            widget.forSchedule
                                ? 'Delete Habit'
                                : 'Delete Priority',
                          ),
                          onPressed: () async {
                            final confirmed = await confirmAction(
                              context,
                              title: widget.forSchedule
                                  ? 'Delete habit?'
                                  : 'Delete priority?',
                              message: widget.forSchedule
                                  ? 'It stops repeating. Days you already did are kept.'
                                  : "This won't delete the original calendar event or recurring schedule.",
                              confirmLabel: 'Delete',
                            );
                            if (confirmed && mounted) {
                              _submit(deleteRequested: true);
                            }
                          },
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

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFFA9A7D8),
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.vivordoColors.textPrimary.withValues(alpha: .035),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(
        color: context.vivordoColors.textPrimary.withValues(alpha: .13),
      ),
    ),
    child: Material(
      color: Colors.transparent,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index < children.length - 1)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: context.vivordoColors.textPrimary.withValues(alpha: .09),
              ),
          ],
        ],
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData? icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: _purple, size: 23),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: colors.textPrimary, fontSize: 16),
              ),
            ),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textSecondary, fontSize: 15),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: _purple, size: 23),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: colors.textPrimary, fontSize: 16),
                ),
                Text(
                  detail,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _RepeatSelector extends StatelessWidget {
  const _RepeatSelector({
    required this.value,
    required this.onChanged,
    this.allowOnce = true,
  });
  final PriorityRepeat value;
  final ValueChanged<PriorityRepeat> onChanged;
  final bool allowOnce;
  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    final choices = [
      if (allowOnce) (PriorityRepeat.once, 'Once'),
      (PriorityRepeat.daily, 'Every day'),
      (PriorityRepeat.selectedDays, 'Selected days'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colors.textPrimary.withValues(alpha: .13)),
      ),
      child: Row(
        children: [
          for (final choice in choices)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(choice.$1),
                borderRadius: BorderRadius.circular(13),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: value == choice.$1
                        ? const LinearGradient(
                            colors: [Color(0xFF494AF5), Color(0xFF6546E7)],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Text(
                    choice.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: value == choice.$1
                          ? Colors.white
                          : colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Weekdays extends StatelessWidget {
  const _Weekdays({required this.selected, required this.onChanged});
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  @override
  Widget build(BuildContext context) {
    const days = [
      (7, 'S'),
      (1, 'M'),
      (2, 'T'),
      (3, 'W'),
      (4, 'T'),
      (5, 'F'),
      (6, 'S'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final day in days)
          InkWell(
            onTap: () {
              final updated = Set<int>.from(selected);
              if (updated.contains(day.$1)) {
                if (updated.length > 1) updated.remove(day.$1);
              } else {
                updated.add(day.$1);
              }
              onChanged(updated);
            },
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected.contains(day.$1) ? _purple : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected.contains(day.$1)
                      ? _purple
                      : context.vivordoColors.textSecondary.withValues(
                          alpha: .5,
                        ),
                ),
              ),
              child: Text(
                day.$2,
                style: TextStyle(
                  color: selected.contains(day.$1)
                      ? Colors.white
                      : context.vivordoColors.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<PriorityDraft?> showEditPrioritySheet(
  BuildContext context,
  DailyPriority priority,
) {
  final start = priority.sourceStart;
  final date = priority.date ?? start ?? DateTime.now();
  return showPriorityEditor(
    context,
    PriorityDraft(
      title: priority.title,
      planning: {
        ...priority.planning,
        if (priority.planning['minutes'] == null &&
            !priority.isAllDay &&
            priority.sourceStart != null &&
            priority.sourceEnd != null &&
            priority.sourceEnd!.isAfter(priority.sourceStart!))
          'minutes': priority.sourceEnd!
              .difference(priority.sourceStart!)
              .inMinutes,
      },
      date: DateUtils.dateOnly(date),
      time: start == null || priority.isAllDay
          ? null
          : TimeOfDay.fromDateTime(start),
      addToCalendar: false,
      repeat: PriorityRepeat.once,
      selectedWeekdays: {date.weekday},
      repeatEnd: null,
      reminderMinutes: priority.reminderMinutes,
      reminderTimeMinutes: priority.reminderTimeMinutes,
      completed: priority.completed,
    ),
    occurrenceOnly: priority.source != 'manual',
    habitSwitch: priority.source == 'recurring_manual',
  );
}

/// Edits a habit's schedule, applying the change to every day from today.
Future<void> showHabitEditor(
  BuildContext context,
  PriorityTemplate habit,
) async {
  final reminder = habit.reminderTimeMinutes;
  final result = await showPriorityEditor(
    context,
    PriorityDraft(
      title: habit.title,
      date: DateUtils.dateOnly(DateTime.now()),
      time: null,
      addToCalendar: false,
      repeat: habit.recurrence == 'daily'
          ? PriorityRepeat.daily
          : PriorityRepeat.selectedDays,
      selectedWeekdays: habit.weekdays,
      repeatEnd: habit.endDate,
      reminderTimeMinutes: reminder,
      habit: true,
      target: habit.target,
    ),
    habitSwitch: true,
    forSchedule: true,
  );
  if (result == null) return;
  try {
    if (result.deleteRequested) {
      await DailyPriorityService.deleteSchedule(habit.id);
    } else {
      await DailyPriorityService.updateSchedule(
        habit.id,
        title: result.title,
        habit: result.habit,
        target: result.target,
        reminderTimeMinutes: result.reminderTimeMinutes,
      );
    }
  } catch (_) {
    if (context.mounted) {
      showToast(
        context,
        "Couldn't update the habit. Try again.",
        kind: ToastKind.error,
      );
    }
  }
}
