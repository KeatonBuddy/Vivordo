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
