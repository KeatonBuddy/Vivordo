import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

const _pickerPurple = Color(0xFF6254F4);

/// Shows a compact iOS-style wheel picker with explicit Cancel and Done
/// actions. Keeping this in one place makes every time-selection flow feel
/// consistent while preserving the existing nullable [TimeOfDay] contract.
Future<TimeOfDay?> showVivordoTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String title = 'Select Time',
  int minuteInterval = 1,
}) {
  final now = DateTime.now();
  var selectedTime = initialTime;
  final initialDateTime = DateTime(
    now.year,
    now.month,
    now.day,
    initialTime.hour,
    initialTime.minute,
  );

  return showCupertinoModalPopup<TimeOfDay>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .48),
    builder: (sheetContext) {
      final colors = sheetContext.vivordoColors;
      final brightness = Theme.of(sheetContext).brightness;
      return Material(
        color: Colors.transparent,
        child: Container(
          height: 324 + MediaQuery.paddingOf(sheetContext).bottom,
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(sheetContext).bottom,
          ),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: colors.textPrimary.withValues(alpha: .12),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3D000000),
                blurRadius: 24,
                offset: Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 9),
              Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              SizedBox(
                height: 54,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Cancel'),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(sheetContext, selectedTime),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: colors.textPrimary.withValues(alpha: .09),
              ),
              Expanded(
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: brightness,
                    primaryColor: _pickerPurple,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    initialDateTime: initialDateTime,
                    minuteInterval: minuteInterval,
                    use24hFormat: MediaQuery.alwaysUse24HourFormatOf(
                      sheetContext,
                    ),
                    backgroundColor: colors.card,
                    onDateTimeChanged: (value) {
                      selectedTime = TimeOfDay.fromDateTime(value);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The date counterpart of [showVivordoTimePicker]: a calendar grid in the
/// same rounded sheet with Cancel and Done. Use it instead of showDatePicker.
Future<DateTime?> showVivordoDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = 'Date',
}) {
  var selected = DateUtils.dateOnly(initialDate);
  if (selected.isBefore(firstDate)) selected = DateUtils.dateOnly(firstDate);
  if (selected.isAfter(lastDate)) selected = DateUtils.dateOnly(lastDate);

  return showCupertinoModalPopup<DateTime>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .48),
    builder: (sheetContext) {
      final colors = sheetContext.vivordoColors;
      final theme = Theme.of(sheetContext);
      final dark = theme.brightness == Brightness.dark;
      final accent = dark ? const Color(0xFFAFA9EC) : _pickerPurple;
      return Material(
        color: Colors.transparent,
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(sheetContext).bottom + 8,
          ),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: colors.textPrimary.withValues(alpha: .12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 9),
              Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              SizedBox(
                height: 54,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Cancel'),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext, selected),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: colors.textPrimary.withValues(alpha: .09),
              ),
              Theme(
                data: theme.copyWith(
                  colorScheme: theme.colorScheme.copyWith(
                    primary: accent,
                    onPrimary: dark ? const Color(0xFF26215C) : Colors.white,
                  ),
                  datePickerTheme: DatePickerThemeData(
                    backgroundColor: colors.card,
                    dayShape: const WidgetStatePropertyAll(CircleBorder()),
                    todayBorder: BorderSide.none,
                    todayForegroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? (dark ? const Color(0xFF26215C) : Colors.white)
                          : accent,
                    ),
                    weekdayStyle: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    dayStyle: const TextStyle(fontSize: 16),
                  ),
                ),
                // The calendar's grid scrolls, so it would otherwise pad
                // itself by the notch inset even though it sits at the bottom.
                child: MediaQuery.removePadding(
                  context: sheetContext,
                  removeTop: true,
                  removeBottom: true,
                  child: CalendarDatePicker(
                    initialDate: selected,
                    firstDate: firstDate,
                    lastDate: lastDate,
                    onDateChanged: (value) => selected = value,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
