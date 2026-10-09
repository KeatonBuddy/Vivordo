import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/add_priority_sheet.dart';

void main() {
  testWidgets('editor returns estimates without discarding planned day', (
    tester,
  ) async {
    PriorityDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Edit'),
              onPressed: () async {
                result = await showPriorityEditor(
                  context,
                  PriorityDraft(
                    title: 'Test',
                    date: DateTime(2026, 9, 22),
                    time: null,
                    addToCalendar: false,
                    repeat: PriorityRepeat.once,
                    selectedWeekdays: const {},
                    repeatEnd: null,
                    reminderTimeMinutes: 600,
                    planning: const {
                      'minutes': 30,
                      'effort': 'light',
                      'plannedDay': '2026-09-22',
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Planned work day'), findsNothing);
    await tester.ensureVisible(find.text('Remove reminder time'));
    await tester.tap(find.text('Remove reminder time'));
    await tester.pumpAndSettle();
    expect(find.text('Remove reminder time'), findsNothing);
    await tester.ensureVisible(find.text('Effort (optional)'));
    await tester.tap(find.text('Effort (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demanding'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Estimated duration'));
    await tester.tap(find.text('Estimated duration'));
    await tester.pumpAndSettle();
    tester
        .widget<CupertinoPicker>(find.byKey(const ValueKey('duration-hours')))
        .onSelectedItemChanged!(1);
    await tester.pump();
    tester
        .widget<CupertinoPicker>(find.byKey(const ValueKey('duration-minutes')))
        .onSelectedItemChanged!(30);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(result?.planning['minutes'], 90);
    expect(result?.reminderTimeMinutes, isNull);
    expect(result?.planning['effort'], 'demanding');
    expect(result?.planning['plannedDay'], '2026-09-22');
  });
}
