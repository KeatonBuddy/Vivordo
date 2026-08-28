import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

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
  });

  final String title;
  final DateTime date;
  final TimeOfDay? time;
  final bool addToCalendar;
  final PriorityRepeat repeat;
  final Set<int> selectedWeekdays;
  final DateTime? repeatEnd;

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
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .68),
      builder: (_) => const _AddPrioritySheet(),
    );

class _AddPrioritySheet extends StatefulWidget {
  const _AddPrioritySheet();

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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController()..addListener(_changed);
    _selectedWeekdays = {_date.weekday};
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateUtils.dateOnly(DateTime.now()),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (value != null) setState(() => _time = value);
  }

  Future<void> _pickRepeatEnd() async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Repeat ends',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('Never'),
              trailing: _repeatEnd == null
                  ? const Icon(Icons.check_rounded, color: _purple)
                  : null,
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.event_rounded),
              title: const Text('On a date'),
              onTap: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    if (!choice) {
      setState(() => _repeatEnd = null);
      return;
    }
    if (!mounted) return;
    final value = await showDatePicker(
      context: context,
      initialDate: _repeatEnd ?? _date.add(const Duration(days: 30)),
      firstDate: _date,
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _repeatEnd = value);
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      PriorityDraft(
        title: title,
        date: _date,
        time: _time,
        addToCalendar: _addToCalendar,
        repeat: _repeat,
        selectedWeekdays: _selectedWeekdays,
        repeatEnd: _repeatEnd,
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
                    child: Text(
                      'Add Priority',
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
                    const _Label('PRIORITY'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'What do you want to accomplish?',
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
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.event_available_rounded,
                                color: _purple,
                                size: 23,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Add to calendar',
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      'Create an event in your calendar',
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _addToCalendar,
                                activeThumbColor: Colors.white,
                                activeTrackColor: _purple,
                                onChanged: (value) =>
                                    setState(() => _addToCalendar = value),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    const _Label('REPEAT'),
                    const SizedBox(height: 10),
                    _RepeatSelector(
                      value: _repeat,
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
                    const SizedBox(height: 28),
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
                          onPressed: _controller.text.trim().isEmpty
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
                          child: const Text(
                            'Add Priority',
                            style: TextStyle(fontSize: 17),
                          ),
                        ),
                      ),
                    ),
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

class _RepeatSelector extends StatelessWidget {
  const _RepeatSelector({required this.value, required this.onChanged});
  final PriorityRepeat value;
  final ValueChanged<PriorityRepeat> onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    const choices = [
      (PriorityRepeat.once, 'Once'),
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
