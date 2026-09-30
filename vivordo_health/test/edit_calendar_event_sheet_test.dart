import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/add_calendar_event_sheet.dart';

void main() {
  testWidgets('edit calendar sheet shows the editable event controls', (
    tester,
  ) async {
    final event = gcal.Event()
      ..summary = 'Vivordo App Development'
      ..start = (gcal.EventDateTime()
        ..dateTime = DateTime(2026, 8, 26, 9).toUtc())
      ..end = (gcal.EventDateTime()
        ..dateTime = DateTime(2026, 8, 26, 10, 30).toUtc())
      ..recurrence = ['RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE'];

    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showEditCalendarEventSheet(context, event: event),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Edit Event'), findsOneWidget);
    expect(find.text('Vivordo App Development'), findsOneWidget);
    expect(find.text('Start time'), findsOneWidget);
    expect(find.text('End time'), findsOneWidget);
    expect(find.text('All-day event'), findsOneWidget);
    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Every 2 weeks on Mon, Wed'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('Delete Event'), findsOneWidget);

    await tester.ensureVisible(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    for (final option in [
      'Does not repeat',
      'Every day',
      'Every week',
      'Every month',
      'Every year',
      'Selected days',
      'Custom…',
    ]) {
      expect(find.text(option), findsOneWidget);
    }
    final custom = tester.widget<CheckedPopupMenuItem<Object?>>(
      find.ancestor(
        of: find.text('Custom…'),
        matching: find.byWidgetPredicate((w) => w is CheckedPopupMenuItem),
      ),
    );
    expect(custom.checked, isTrue);

    // The menu item, not its text box, takes the tap.
    await tester.tap(find.text('Every year'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Every year'), findsOneWidget);
    expect(find.text('Every 2 weeks on Mon, Wed'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
