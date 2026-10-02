import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

/// Labels for the profile's sex values (PersonalProfile.sex).
const profileSexLabels = {
  'female': 'Female',
  'male': 'Male',
  'unspecified': 'Prefer not to say',
};

/// A wheel of birth years (ages 13–100). Returns the chosen year, or null
/// when dismissed.
Future<int?> showBirthYearPicker(BuildContext context, {int? initial}) {
  final now = DateTime.now().year;
  final years = [for (var y = now - 13; y >= now - 100; y--) y];
  var selected = initial != null && years.contains(initial)
      ? initial
      : now - 30;
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: context.vivordoColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(
              children: [
                Text(
                  'Year of birth',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: sheetContext.vivordoColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, selected),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 216,
            child: CupertinoPicker(
              itemExtent: 40,
              scrollController: FixedExtentScrollController(
                initialItem: years.indexOf(selected),
              ),
              onSelectedItemChanged: (index) => selected = years[index],
              children: [
                for (final year in years)
                  Center(
                    child: Text(
                      '$year',
                      style: TextStyle(
                        fontSize: 20,
                        color: sheetContext.vivordoColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
