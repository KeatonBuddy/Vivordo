import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:vivordo_health/screens/my_day_screen.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/edit_priority_sheet.dart';

// The row never accesses Firestore; this mock only supplies its model reference.
// ignore: subtype_of_sealed_class, must_be_immutable
class _Reference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  testWidgets('edit popup loads and saves reminder selection', (tester) async {
    (String, int, int?)? result;
    final priority = DailyPriority(
      id: 'timed',
      title: 'Review notes',
      completed: false,
      reference: _Reference(),
      isAllDay: false,
      source: 'manual',
      sourceStart: DateTime(2026, 10, 1, 12),
      reminderMinutes: 360,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showEditPrioritySheet(context, priority);
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('6 hr before'), findsOneWidget);
    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 min before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(result, ('Review notes', 30, null));
  });
  testWidgets('revealed Delete receives taps and removes the priority', (
    tester,
  ) async {
    var deleted = false;
    final priority = DailyPriority(
      id: 'test',
      title: 'Prepare presentation',
      completed: false,
      reference: _Reference(),
      isAllDay: false,
      source: 'manual',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  if (!deleted)
                    priorityRowForTesting(
                      priority: priority,
                      onDelete: () async => setState(() => deleted = true),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.drag(find.text('Prepare presentation'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete priority?'), findsOneWidget);
    expect(deleted, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deleted, isFalse);
    expect(find.text('Prepare presentation'), findsOneWidget);
    await tester.drag(find.text('Prepare presentation'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('Prepare presentation'), findsNothing);
  });
}
