import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/plan_slot_sheet.dart';

void main() {
  testWidgets('toggle switches between the priority and event forms', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPlanSlotSheet(
              context,
              start: DateTime(2026, 9, 29, 10),
              end: DateTime(2026, 9, 29, 10, 20),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('PRIORITY'), findsOneWidget);
    expect(find.text('10:00 AM'), findsOneWidget);

    await tester.tap(find.text('Event'));
    await tester.pumpAndSettle();
    expect(find.text('PRIORITY'), findsNothing);
    expect(find.text('Start time'), findsOneWidget);
    // A 20-minute opening ends the event at the opening, not an hour later.
    expect(find.text('10:20 AM'), findsOneWidget);

    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();
    expect(find.text('PRIORITY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
