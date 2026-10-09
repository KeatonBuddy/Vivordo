import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

/// Null cancels; zero clears the optional estimate. Existing exact values survive.
Future<int?> showPriorityDurationPicker(
  BuildContext context, {
  int? initialMinutes,
}) async {
  final initial = (initialMinutes ?? 0).clamp(0, 1440);
  var hours = initial ~/ 60;
  var minutes = initial % 60;
  final hourController = FixedExtentScrollController(initialItem: hours);
  final minuteController = FixedExtentScrollController(initialItem: minutes);
  try {
    return await showCupertinoModalPopup<int>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .48),
      builder: (context) {
        final colors = context.vivordoColors;
        return StatefulBuilder(
          builder: (context, setState) => Material(
            color: Colors.transparent,
            child: Container(
              height: 324 + MediaQuery.paddingOf(context).bottom,
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(
                  color: colors.textPrimary.withValues(alpha: .12),
                ),
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
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      Expanded(
                        child: Text(
                          'Estimated duration',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: hours * 60 + minutes > 1440
                            ? null
                            : () =>
                                  Navigator.pop(context, hours * 60 + minutes),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  Divider(height: 1, color: colors.border),
                  Text(
                    hours * 60 + minutes > 1440
                        ? 'Maximum estimate is 24 hours'
                        : '0 hours, 0 minutes = Not set',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoPicker.builder(
                            key: const ValueKey('duration-hours'),
                            scrollController: hourController,
                            itemExtent: 40,
                            childCount: 25,
                            onSelectedItemChanged: (value) =>
                                setState(() => hours = value),
                            itemBuilder: (context, index) => Center(
                              child: Text(
                                '$index ${index == 1 ? 'hour' : 'hours'}',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: CupertinoPicker.builder(
                            key: const ValueKey('duration-minutes'),
                            scrollController: minuteController,
                            itemExtent: 40,
                            childCount: 60,
                            onSelectedItemChanged: (value) =>
                                setState(() => minutes = value),
                            itemBuilder: (context, index) => Center(
                              child: Text(
                                '$index min',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  } finally {
    hourController.dispose();
    minuteController.dispose();
  }
}
