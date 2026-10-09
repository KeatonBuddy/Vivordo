import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/add_priority_sheet.dart';
import 'package:vivordo_health/widgets/apple_ui.dart';

void main() {
  testWidgets('disabled Add Priority text remains visible in light mode', (
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

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add Priority'),
    );
    final disabledColor = button.style?.foregroundColor?.resolve({
      WidgetState.disabled,
    });

    expect(disabledColor, Colors.white.withValues(alpha: .78));
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

    expect(find.text('Add Habit'), findsWidgets);
    expect(find.text('WORKLOAD ESTIMATE'), findsNothing);
    expect(find.text('Add to calendar'), findsNothing);
    expect(find.text('Once'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add Habit'));
    await tester.pumpAndSettle();

    expect(draft?.habit, isTrue);
    expect(draft?.target, 3);
    expect(draft?.recurrence, 'daily');
    expect(draft?.time, isNull);
    expect(draft?.addToCalendar, isFalse);
  });
}
