import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/src/utils/score_breakdown.dart';
import 'package:vivordo_health/widgets/apple_ui.dart';
import 'package:vivordo_health/widgets/daily_brief_card.dart';
import 'package:vivordo_health/widgets/score_breakdown_sheet.dart';
import 'package:vivordo_health/widgets/vivordo_time_picker.dart';

void main() {
  Future<BuildContext> pumpApp(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        // As in main.dart.
        builder: (context, child) => PullDownToCloseSheets(child: child!),
        navigatorObservers: [PullDownToCloseSheets.observer],
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
    expect(find.byIcon(CupertinoIcons.checkmark), findsOneWidget);
  });

  testWidgets('a long info sheet closes when pulled down from the top', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final context = await pumpApp(tester);
    showInfoSheet(
      context,
      icon: Icons.info_outline,
      title: 'Daily Brief data',
      items: [
        for (var i = 0; i < 30; i++) AppleInfoItem('Row $i', 'Detail $i'),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Daily Brief data'), findsOneWidget);
    // Taller than the screen, so the content scrolls.
    expect(find.text('Row 29').hitTestable(), findsNothing);

    await tester.drag(find.text('Row 2'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('Daily Brief data'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('any sheet with scrolling content closes when pulled down', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final context = await pumpApp(tester);
    // The Effort breakdown: short, but its content is a scroll view, which
    // took the drag before.
    showScoreBreakdown(
      context,
      kicker: 'Effort so far',
      score: 18,
      summary: 'Heavier than usual',
      sections: [
        (
          heading: 'Schedule · 18',
          rows: [BreakdownRow('3 priorities ticked off', '', points: 18)],
        ),
      ],
      footer: 'Schedule is what your events and priorities took.',
    );
    await tester.pumpAndSettle();
    expect(find.text('Effort so far'), findsOneWidget);

    await tester.drag(find.text('Heavier than usual'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('Effort so far'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a sheet opened directly closes; a page and a form while typing '
      "don't", (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final context = await pumpApp(tester);
    Future<void> pull(String text) async {
      await tester.drag(find.text(text), const Offset(0, 300));
      await tester.pumpAndSettle();
    }

    // Like the Training load details: showModalBottomSheet with content
    // taller than the screen, not through showAppleSheet.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SingleChildScrollView(
        child: Column(
          children: [
            const Text('Training load'),
            for (var i = 0; i < 40; i++) Text('Week $i'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pull('Training load');
    expect(find.text('Training load'), findsNothing);

    // A full-screen page pulled down stays.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            Scaffold(body: ListView(children: const [Text('A page')])),
      ),
    );
    await tester.pumpAndSettle();
    await pull('A page');
    expect(find.text('A page'), findsOneWidget);
    Navigator.of(tester.element(find.text('A page'))).pop();
    await tester.pumpAndSettle();

    // A form being typed in stays open.
    showAppleSheet<void>(
      context,
      builder: (_) => SingleChildScrollView(
        child: Column(
          children: [
            const Text('New priority'),
            const TextField(),
            for (var i = 0; i < 40; i++) Text('Field $i'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));
    await tester.pumpAndSettle();
    await pull('New priority');
    expect(find.text('New priority'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a sheet closes from a third of the way down, not a nudge', (
    tester,
  ) async {
    final context = await pumpApp(tester);
    // Like Training load: short content that doesn't scroll, so the sheet
    // itself moves, and Flutter alone would spring it back under half way.
    void open() => showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SizedBox(
        height: 400,
        child: Center(child: Text('Training load')),
      ),
    );
    open();
    await tester.pumpAndSettle();
    // A slow nudge (40 of 400) springs back.
    await tester.timedDrag(
      find.text('Training load'),
      const Offset(0, 40),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('Training load'), findsOneWidget);
    // A slow pull of 140 (35%) closes it.
    await tester.timedDrag(
      find.text('Training load'),
      const Offset(0, 140),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('Training load'), findsNothing);
  });

  testWidgets('a sheet with unsaved edits asks before any way of closing', (
    tester,
  ) async {
    final context = await pumpApp(tester);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const DiscardChangesGuard(
        dirty: true,
        child: SizedBox(height: 400, child: Center(child: Text('Edits'))),
      ),
    );
    await tester.pumpAndSettle();

    // Swiping well past half way asks instead of closing.
    await tester.timedDrag(
      find.text('Edits'),
      const Offset(0, 300),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discard Changes'), findsOneWidget);
    await tester.tap(find.text('Keep Editing'));
    await tester.pumpAndSettle();
    expect(find.text('Edits'), findsOneWidget);

    // Tapping outside asks too, and discarding closes it.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard Changes'));
    await tester.pumpAndSettle();
    expect(find.text('Edits'), findsNothing);
  });

  testWidgets('words view breakdown shows states, not numbers', (tester) async {
    final context = await pumpApp(tester);
    showScoreBreakdown(
      context,
      kicker: 'Capacity today',
      score: 78,
      words: (word: 'Recovering', tone: BriefTone.low),
      summary: 'A bit below your usual',
      signed: true,
      sections: [
        (
          heading: null,
          rows: [
            BreakdownRow('Recent load', 'A big day on Monday', points: 6),
            BreakdownRow('Morning check-in', 'Felt good', points: -5),
            BreakdownRow('Not in today', 'Sleep', points: -5.4),
          ],
        ),
      ],
      footer: 'Sleep counts most.',
    );
    await tester.pumpAndSettle();
    expect(find.text('Recovering'), findsOneWidget);
    expect(find.text('78'), findsNothing);
    expect(find.text('Helped most'), findsOneWidget);
    expect(find.text('Held it back'), findsNWidgets(2));
    expect(find.text('+6'), findsNothing);
    // Biggest first.
    final y = tester.getTopLeft(find.text('Recent load')).dy;
    expect(y, lessThan(tester.getTopLeft(find.text('Not in today')).dy));
    expect(
      tester.getTopLeft(find.text('Not in today')).dy,
      lessThan(tester.getTopLeft(find.text('Morning check-in')).dy),
    );
  });

  testWidgets('two short buttons sit side by side; long ones stack, with '
      'cancel at the bottom', (tester) async {
    final context = await pumpApp(tester);
    confirmAction(
      context,
      title: 'Delete this workout?',
      confirmLabel: 'Delete',
    );
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('Cancel')).dy,
      tester.getCenter(find.text('Delete')).dy,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    confirmAction(
      context,
      title: 'Cancel workout?',
      message: 'This discards the workout and everything entered in it.',
      confirmLabel: 'Cancel workout',
      cancelLabel: 'Keep workout',
    );
    await tester.pumpAndSettle();
    final keep = tester.getRect(find.text('Keep workout'));
    final cancel = tester.getRect(find.text('Cancel workout'));
    expect(keep.top, greaterThan(cancel.bottom));
    // Each label on one line: no wrapping inside a 46-point button.
    expect(keep.height, lessThan(30));
    expect(cancel.height, lessThan(30));
    await tester.tap(find.text('Keep workout'));
    await tester.pumpAndSettle();
  });
}
