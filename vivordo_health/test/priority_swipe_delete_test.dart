import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:vivordo_health/screens/my_day_screen.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/edit_priority_sheet.dart';
import 'package:vivordo_health/widgets/add_priority_sheet.dart';

// The row never accesses Firestore; this mock only supplies its model reference.
// ignore: subtype_of_sealed_class, must_be_immutable
class _Reference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  testWidgets('edit popup loads and saves reminder selection', (tester) async {
    PriorityDraft? result;
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
            builder: (context) => priorityRowForTesting(
              priority: priority,
              onDelete: () async {},
              onEdit: () async {
                result = await showEditPrioritySheet(context, priority);
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review notes'));
    await tester.pumpAndSettle();
    expect(find.text('6 hr before'), findsOneWidget);
    await tester.ensureVisible(find.text('Reminder'));
    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 min before'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(result?.title, 'Review notes');
    expect(result?.reminderMinutes, 30);
    expect(result?.time, const TimeOfDay(hour: 12, minute: 0));
  });
  testWidgets(
    'untimed editor includes schedule, completion and confirmed delete',
    (tester) async {
      PriorityDraft? result;
      final priority = DailyPriority(
        id: 'untimed',
        title: 'Finish notes',
        completed: false,
        reference: _Reference(),
        isAllDay: false,
        source: 'manual',
        date: DateTime(2026, 9, 1),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: VivordoTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showEditPrioritySheet(context, priority);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Priority'), findsOneWidget);
      expect(find.text('Choose reminder time'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      await tester.ensureVisible(find.text('Mark as completed'));
      await tester.tap(find.text('Mark as completed'));
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(result?.completed, isTrue);
      expect(result?.date, DateTime(2026, 9, 1));
      expect(result?.time, isNull);
      result = null;
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete Priority'));
      await tester.tap(find.text('Delete Priority'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('Delete Priority'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(result?.deleteRequested, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
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
