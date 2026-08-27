import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

const _purple = Color(0xFF6254F4);

Color _calendarColor(String? hex) {
  final value = hex?.replaceFirst('#', '');
  if (value == null || value.length != 6) return _purple;
  return Color(int.parse('FF$value', radix: 16));
}

class CalendarEventDraft {
  const CalendarEventDraft({
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.isAllDay,
    required this.recurrence,
    required this.calendarId,
  });

  final String title;
  final DateTime date;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final bool isAllDay;
  final String recurrence;
  final String calendarId;

  DateTime get start => DateTime(
    date.year,
    date.month,
    date.day,
    isAllDay ? 0 : startTime.hour,
    isAllDay ? 0 : startTime.minute,
  );

  DateTime get end {
    if (isAllDay) return DateUtils.dateOnly(date).add(const Duration(days: 1));
    var value = DateTime(
      date.year,
      date.month,
      date.day,
      endTime.hour,
      endTime.minute,
    );
    if (!value.isAfter(start)) value = value.add(const Duration(days: 1));
    return value;
  }
}

Future<CalendarEventDraft?> showAddCalendarEventSheet(
  BuildContext context, {
  required DateTime initialStart,
  DateTime? initialEnd,
}) => showModalBottomSheet<CalendarEventDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .68),
  builder: (_) => _AddCalendarEventSheet(
    initialStart: initialStart,
    initialEnd: initialEnd ?? initialStart.add(const Duration(hours: 1)),
  ),
);

enum _RepeatChoice { once, daily, selectedDays }

class _AddCalendarEventSheet extends StatefulWidget {
  const _AddCalendarEventSheet({
    required this.initialStart,
    required this.initialEnd,
  });

  final DateTime initialStart;
  final DateTime initialEnd;

  @override
  State<_AddCalendarEventSheet> createState() => _AddCalendarEventSheetState();
}

class _AddCalendarEventSheetState extends State<_AddCalendarEventSheet> {
  late final TextEditingController _titleController;
  late DateTime _date;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  bool _isAllDay = false;
  _RepeatChoice _repeat = _RepeatChoice.once;
  late Set<int> _selectedWeekdays;
  List<WritableCalendar> _calendars = const [];
  WritableCalendar _selectedCalendar = const WritableCalendar(
    id: 'primary',
    name: 'Personal',
    isPrimary: true,
    colorHex: '#6254F4',
  );
  bool _loadingCalendars = true;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController()..addListener(_titleChanged);
    _date = DateUtils.dateOnly(widget.initialStart);
    _startTime = TimeOfDay.fromDateTime(widget.initialStart);
    _endTime = TimeOfDay.fromDateTime(widget.initialEnd);
    _selectedWeekdays = {_date.weekday};
    _loadCalendars();
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_titleChanged)
      ..dispose();
    super.dispose();
  }

  void _titleChanged() => setState(() {});

  Future<void> _loadCalendars() async {
    try {
      final calendars = await CalendarService.getWritableCalendars();
      if (!mounted) return;
      setState(() {
        _calendars = calendars;
        if (calendars.isNotEmpty) {
          _selectedCalendar = calendars.firstWhere(
            (calendar) => calendar.isPrimary,
            orElse: () => calendars.first,
          );
        }
        _loadingCalendars = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCalendars = false);
    }
  }

  Future<void> _pickCalendar() async {
    if (_loadingCalendars) return;
    if (_calendars.isEmpty) {
      setState(() => _loadingCalendars = true);
      await _loadCalendars();
      if (!mounted || _calendars.isNotEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load writable calendars.')),
      );
      return;
    }

    final selected = await showModalBottomSheet<WritableCalendar>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .62,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Choose calendar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _calendars.length,
                  itemBuilder: (context, index) {
                    final calendar = _calendars[index];
                    final isSelected = calendar.id == _selectedCalendar.id;
                    return ListTile(
                      leading: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _calendarColor(calendar.colorHex),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 14, height: 14),
                      ),
                      title: Text(calendar.name),
                      subtitle: calendar.isPrimary
                          ? const Text('Primary calendar')
                          : null,
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded, color: _purple)
                          : null,
                      onTap: () => Navigator.pop(sheetContext, calendar),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedCalendar = selected);
    }
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null) setState(() => _date = value);
  }

  Future<void> _pickTime({required bool start}) async {
    final value = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (value == null) return;
    setState(() {
      if (start) {
        _startTime = value;
      } else {
        _endTime = value;
      }
    });
  }

  String get _recurrence {
    if (_repeat == _RepeatChoice.daily) return 'daily';
    if (_repeat == _RepeatChoice.once) return 'none';
    const codes = {
      1: 'MO',
      2: 'TU',
      3: 'WE',
      4: 'TH',
      5: 'FR',
      6: 'SA',
      7: 'SU',
    };
    final days = _selectedWeekdays.toList()..sort();
    return 'weekly:${days.map((day) => codes[day]).join(',')}';
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      CalendarEventDraft(
        title: title,
        date: _date,
        startTime: _startTime,
        endTime: _endTime,
        isAllDay: _isAllDay,
        recurrence: _recurrence,
        calendarId: _selectedCalendar.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
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
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 32,
              offset: Offset(0, -8),
            ),
          ],
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
              padding: const EdgeInsets.fromLTRB(22, 10, 14, 4),
              child: Row(
                children: [
                  const SizedBox(width: 42),
                  Expanded(
                    child: Text(
                      'Add Event',
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
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SheetLabel('EVENT'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _titleController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: colors.textPrimary, fontSize: 17),
                      decoration: InputDecoration(
                        hintText: 'Event title',
                        filled: true,
                        fillColor: colors.textPrimary.withValues(alpha: .045),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: colors.textPrimary.withValues(alpha: .14),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: colors.textPrimary.withValues(alpha: .14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const _SheetLabel('SCHEDULE'),
                    const SizedBox(height: 10),
                    _SheetCard(
                      children: [
                        _PickerRow(
                          icon: Icons.calendar_month_rounded,
                          label: 'Date',
                          value: DateFormat('MMMM d, y').format(_date),
                          onTap: _pickDate,
                        ),
                        _PickerRow(
                          icon: Icons.schedule_rounded,
                          label: 'Start time',
                          value: _startTime.format(context),
                          enabled: !_isAllDay,
                          onTap: () => _pickTime(start: true),
                        ),
                        _PickerRow(
                          icon: Icons.schedule_rounded,
                          label: 'End time',
                          value: _endTime.format(context),
                          enabled: !_isAllDay,
                          onTap: () => _pickTime(start: false),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'All-day event',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Switch(
                                value: _isAllDay,
                                activeThumbColor: Colors.white,
                                activeTrackColor: _purple,
                                onChanged: (value) =>
                                    setState(() => _isAllDay = value),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    const _SheetLabel('REPEAT'),
                    const SizedBox(height: 10),
                    _RepeatSelector(
                      value: _repeat,
                      onChanged: (value) => setState(() => _repeat = value),
                    ),
                    if (_repeat == _RepeatChoice.selectedDays) ...[
                      const SizedBox(height: 12),
                      _WeekdaySelector(
                        selected: _selectedWeekdays,
                        onChanged: (days) =>
                            setState(() => _selectedWeekdays = days),
                      ),
                    ],
                    const SizedBox(height: 26),
                    const _SheetLabel('CALENDAR'),
                    const SizedBox(height: 10),
                    _SheetCard(
                      children: [
                        _PickerRow(
                          icon: Icons.calendar_month_rounded,
                          label: 'Calendar',
                          value: _loadingCalendars
                              ? 'Loading…'
                              : _selectedCalendar.name,
                          calendarColor: _calendarColor(
                            _selectedCalendar.colorHex,
                          ),
                          enabled: !_loadingCalendars,
                          onTap: _pickCalendar,
                        ),
                      ],
                    ),
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
                          onPressed: _titleController.text.trim().isEmpty
                              ? null
                              : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Add Event',
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

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);
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

class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colors.textPrimary.withValues(alpha: .13)),
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
                color: colors.textPrimary.withValues(alpha: .09),
              ),
          ],
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.enabled = true,
    this.calendarColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final bool enabled;
  final Color? calendarColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Opacity(
      opacity: enabled ? 1 : .42,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Row(
            children: [
              Icon(icon, color: _purple, size: 23),
              const SizedBox(width: 16),
              SizedBox(
                width: 105,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textPrimary, fontSize: 16),
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (calendarColor != null) ...[
                      const SizedBox(width: 9),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: calendarColor,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 11, height: 11),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepeatSelector extends StatelessWidget {
  const _RepeatSelector({required this.value, required this.onChanged});
  final _RepeatChoice value;
  final ValueChanged<_RepeatChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    const choices = [
      (_RepeatChoice.once, 'Once'),
      (_RepeatChoice.daily, 'Every day'),
      (_RepeatChoice.selectedDays, 'Selected days'),
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
                borderRadius: BorderRadius.circular(13),
                onTap: () => onChanged(choice.$1),
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

class _WeekdaySelector extends StatelessWidget {
  const _WeekdaySelector({required this.selected, required this.onChanged});
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
            borderRadius: BorderRadius.circular(99),
            onTap: () {
              final updated = Set<int>.from(selected);
              if (updated.contains(day.$1)) {
                if (updated.length > 1) updated.remove(day.$1);
              } else {
                updated.add(day.$1);
              }
              onChanged(updated);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected.contains(day.$1)
                    ? _purple
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Text(
                day.$2,
                style: TextStyle(
                  color: selected.contains(day.$1)
                      ? Colors.white
                      : context.vivordoColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
