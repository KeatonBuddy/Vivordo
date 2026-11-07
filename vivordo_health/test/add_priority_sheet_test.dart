import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/add_priority_sheet.dart';
import 'package:vivordo_health/widgets/apple_ui.dart';

void main() {
  testWidgets('Add stays disabled until the priority has a name', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddPrioritySheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    CupertinoButton add() =>
        tester.widget(find.widgetWithText(CupertinoButton, 'Add'));
    expect(add().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Plan the week');
    await tester.pump();
    expect(add().onPressed, isNotNull);
  });

  testWidgets('the Habit switch swaps the workload for a daily goal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PriorityDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => draft = await showAddPrioritySheet(context),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Drink water');
    await tester.tap(find.byType(AppSwitch).first);
    await tester.pumpAndSettle();

    expect(find.text('New Habit'), findsOneWidget);
    expect(find.text('Workload estimate'), findsNothing);
    expect(find.text('Add to calendar'), findsNothing);
    expect(find.text('Once'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.widgetWithText(CupertinoButton, 'Add'));
    await tester.pumpAndSettle();

    expect(draft?.habit, isTrue);
    expect(draft?.target, 3);
    expect(draft?.recurrence, 'daily');
    expect(draft?.time, isNull);
    expect(draft?.addToCalendar, isFalse);
  });

  testWidgets("a carried-over priority's calendar event goes on today", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateUtils.dateOnly(DateTime.now());
    final tuesday = today.subtract(const Duration(days: 3));
    PriorityDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => draft = await showPriorityEditor(
              context,
              PriorityDraft(
                title: 'Grocery run',
                date: tuesday,
                time: null,
                addToCalendar: false,
                repeat: PriorityRepeat.once,
                selectedWeekdays: {tuesday.weekday},
                repeatEnd: null,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Add to calendar'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(AppSwitch),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoButton, 'Save'));
    await tester.pumpAndSettle();

    expect(draft?.addToCalendar, isTrue);
    expect(draft?.date, today);
  });

  testWidgets('a timed calendar priority adds without a duration', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final nine = DateUtils.dateOnly(
      DateTime.now(),
    ).add(const Duration(days: 5, hours: 9));
    Object? draft;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            // As the calendar's "+" opens it: a time, no duration.
            onPressed: () async => draft = await showModalBottomSheet<Object>(
              context: context,
              isScrollControlled: true,
              builder: (_) => addPriorityForm(at: nine),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Test');
    await tester.tap(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Add to calendar'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(AppSwitch),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoButton, 'Add'));
    await tester.pumpAndSettle();

    expect(draft, isA<PriorityDraft>());
    final saved = draft! as PriorityDraft;
    expect(saved.addToCalendar, isTrue);
    expect(saved.scheduledAt, nine);
  });
}
