import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:vivordo_health/src/services/daily_priority_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/plan_slot_sheet.dart';

// ignore: subtype_of_sealed_class, must_be_immutable
class _Reference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

DailyPriority _priority(String title, int minutes) => DailyPriority(
  id: title,
  title: title,
  completed: false,
  reference: _Reference(),
  isAllDay: false,
  source: 'manual',
  planning: {'minutes': minutes},
);

void main() {
  testWidgets('leads with the waiting priorities that fit the slot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Object? result;
    final short = _priority('Call Mom', 20);
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showPlanSlotSheet(
              context,
              // "Free now" at 2:07 plans from 2:10.
              start: DateTime(2026, 9, 29, 14, 7, 30),
              end: DateTime(2026, 9, 29, 14, 40),
              waiting: [short, _priority('Prep slides', 120)],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Open from 2:10 PM'), findsOneWidget);
    expect(find.text('20 min · 2:10–2:30 PM'), findsOneWidget);
    // Two hours doesn't fit half an hour.
    expect(find.text('Prep slides'), findsNothing);

    await tester.tap(find.text('Put here'));
    await tester.pumpAndSettle();
    final pick = result as SlotPick;
    expect(pick.priority, same(short));
    expect(pick.start, DateTime(2026, 9, 29, 14, 10));

    // Something new is still one tap away.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New priority or event'));
    await tester.pumpAndSettle();
    expect(find.text('Event'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('Priority'), findsNWidgets(2));
    expect(find.text('10:00 AM'), findsOneWidget);
    // A title typed in one form carries over to the other.
    await tester.enterText(find.byType(TextField).first, 'Plan launch');

    await tester.tap(find.text('Event'));
    await tester.pumpAndSettle();
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Start time'), findsOneWidget);
    // A 20-minute opening ends the event at the opening, not an hour later.
    expect(find.text('10:20 AM'), findsOneWidget);
    expect(find.text('Plan launch'), findsOneWidget);
    await tester.enterText(find.text('Plan launch'), 'Plan launch review');

    await tester.tap(find.text('Priority'));
    await tester.pumpAndSettle();
    expect(find.text('Priority'), findsNWidgets(2));
    expect(find.text('Plan launch review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
