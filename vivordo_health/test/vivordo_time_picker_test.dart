import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/vivordo_time_picker.dart';

void main() {
  testWidgets('Apple-style time picker returns the selected time', (
    tester,
  ) async {
    TimeOfDay? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await showVivordoTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 9, minute: 30),
                title: 'Start Time',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Start Time'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(selected, const TimeOfDay(hour: 9, minute: 30));
  });
}
