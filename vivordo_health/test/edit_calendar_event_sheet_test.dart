import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/apple_ui.dart' show AppSwitch;
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
    expect(find.text('Repeat'), findsNWidgets(2));
    expect(find.text('Every 2 weeks on Mon, Wed'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
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
    final custom = find.ancestor(
      of: find.text('Custom…'),
      matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
    );
    expect(
      find.descendant(
        of: custom,
        matching: find.byIcon(CupertinoIcons.checkmark_alt),
      ),
      findsOneWidget,
    );

    // The menu item, not its text box, takes the tap.
    await tester.tap(find.text('Every year'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Every year'), findsOneWidget);
    expect(find.text('Every 2 weeks on Mon, Wed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning off all-day gives the event real hours', (tester) async {
    final event = gcal.Event()
      ..summary = 'Offsite'
      ..start = (gcal.EventDateTime()..date = DateTime(2026, 8, 26))
      ..end = (gcal.EventDateTime()..date = DateTime(2026, 8, 27));
    CalendarEventEditResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showEditCalendarEventSheet(
              context,
              event: event,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(find.text('10:00 AM'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final draft = result!.draft!;
    expect(draft.isAllDay, isFalse);
    expect(draft.start, DateTime(2026, 8, 26, 9));
    expect(draft.end, DateTime(2026, 8, 26, 10));
  });

  test('moving the start keeps the event length', () {
    TimeOfDay t(int h, [int m = 0]) => TimeOfDay(hour: h, minute: m);
    expect(
      keepEventLength(oldStart: t(9), oldEnd: t(10), newStart: t(11)),
      t(12),
    );
    expect(
      keepEventLength(oldStart: t(9), oldEnd: t(10, 30), newStart: t(23)),
      t(0, 30),
    );
    // An overnight event keeps its length too.
    expect(
      keepEventLength(oldStart: t(22), oldEnd: t(1), newStart: t(21)),
      t(0),
    );
  });
}
