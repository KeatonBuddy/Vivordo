import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/apple_ui.dart';
import 'package:vivordo_health/widgets/vivordo_time_picker.dart';

void main() {
  Future<BuildContext> pumpApp(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('confirmAction returns true only for the confirm button', (
    tester,
  ) async {
    final context = await pumpApp(tester);
    var result = confirmAction(
      context,
      title: 'Delete this workout?',
      message: "This can't be undone.",
      confirmLabel: 'Delete',
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete this workout?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);

    result = confirmAction(
      context,
      title: 'Unblock Sam?',
      confirmLabel: 'Unblock',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('stacked alert and action sheet return the chosen value', (
    tester,
  ) async {
    final context = await pumpApp(tester);
    final scope = showAppleAlert<String>(
      context,
      title: 'Delete "Team sync"?',
      actions: const [
        AppleAlertAction('Delete this event only', 'one', destructive: true),
        AppleAlertAction('Delete all future events', 'all', destructive: true),
        AppleAlertAction('Cancel', 'cancel', bold: true),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all future events'));
    await tester.pumpAndSettle();
    expect(await scope, 'all');

    final source = showAppleActionSheet<String>(
      context,
      title: 'Profile photo',
      actions: const [
        AppleSheetAction('Take photo', 'camera'),
        AppleSheetAction('Choose from library', 'gallery'),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from library'));
    await tester.pumpAndSettle();
    expect(await source, 'gallery');
  });

  testWidgets('toast shows a floating message with its action', (tester) async {
    final context = await pumpApp(tester);
    var undone = false;
    showToast(
      context,
      'Moved to Saturday',
      actionLabel: 'Undo',
      onAction: () => undone = true,
    );
    await tester.pumpAndSettle();
    expect(find.text('Moved to Saturday'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    expect(undone, isTrue);
  });

  testWidgets('form sheet Done and info sheet button work', (tester) async {
    final context = await pumpApp(tester);
    final controller = TextEditingController();
    final saved = showAppleSheet<String>(
      context,
      builder: (sheetContext) => AppleFormSheet(
        title: 'Log activity',
        doneLabel: 'Add',
        onDone: () => Navigator.pop(sheetContext, controller.text),
        children: [
          AppleFormGroup(
            footer: "Counts toward today's Exercise ring.",
            children: [
              AppleFormTextRow(
                label: 'Activity',
                controller: controller,
                placeholder: 'Walk',
              ),
              const AppleFormRow(
                label: 'Duration',
                trailing: AppleValuePill('20 min'),
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Evening walk');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(await saved, 'Evening walk');

    final info = showInfoSheet(
      context,
      icon: Icons.favorite,
      title: 'Your stress score',
      summary: 'Compares this hour with your own normal.',
      items: const [AppleInfoItem('Not a diagnosis', 'A wellness estimate.')],
    );
    await tester.pumpAndSettle();
    expect(find.text('Not a diagnosis'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await info;
  });

  testWidgets('date picker returns the tapped day on Done', (tester) async {
    final context = await pumpApp(tester);
    final picked = showVivordoDatePicker(
      context: context,
      initialDate: DateTime(2026, 10, 6),
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2026, 12, 31),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(await picked, DateTime(2026, 10, 15));
  });

  testWidgets('segmented control and check circle', (tester) async {
    var range = '12W';
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                AppSegmented<String>(
                  segments: const {'4W': '4W', '12W': '12W', '6M': '6M'},
                  value: range,
                  onChanged: (value) => setState(() => range = value),
                ),
                const AppCheckCircle(checked: true),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('6M'));
    await tester.pumpAndSettle();
    expect(range, '6M');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });
}
