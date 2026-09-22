import 'package:flutter/material.dart';
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
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Estimated minutes (optional)'),
      '90',
    );
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(result?.planning['minutes'], 90);
    expect(result?.planning['effort'], 'light');
    expect(result?.planning['plannedDay'], '2026-09-22');
  });
}
