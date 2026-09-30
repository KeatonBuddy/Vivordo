import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:vivordo_health/src/services/calendar_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/add_calendar_event_sheet.dart';

void main() {
  test('moving one occurrence shifts the whole series by the same amount', () {
    final (start, end) = CalendarService.shiftSeries(
      seriesStart: DateTime(2026, 10, 1, 9),
      occurrenceStart: DateTime(2026, 10, 15, 9),
      start: DateTime(2026, 10, 15, 10, 30),
      end: DateTime(2026, 10, 15, 11),
    );
    expect(start, DateTime(2026, 10, 1, 10, 30));
    expect(end, DateTime(2026, 10, 1, 11));
  });

  Future<void> openOccurrence(WidgetTester tester) async {
    final occurrence = gcal.Event()
      ..id = 'review_20261015T140000Z'
      ..recurringEventId = 'review'
      ..summary = 'Review'
      ..start = (gcal.EventDateTime()
        ..dateTime = DateTime(2026, 10, 15, 9).toUtc())
      ..end = (gcal.EventDateTime()
        ..dateTime = DateTime(2026, 10, 15, 10).toUtc());
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showEditCalendarEventSheet(context, event: occurrence),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('saving an occurrence asks which events to change', (
    tester,
  ) async {
    await openOccurrence(tester);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(find.text('Edit repeating event'), findsOneWidget);
    expect(find.text('This event'), findsOneWidget);
    await tester.tap(find.text('All events'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Event'), findsNothing);
  });

  testWidgets('a new repeat rule can only apply to the whole series', (
    tester,
  ) async {
    await openOccurrence(tester);
    await tester.tap(find.text('Does not repeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every week'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(find.text('This event'), findsNothing);
    expect(find.text('All events'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Event'), findsOneWidget);
  });

  testWidgets('deleting a one-off event keeps the plain confirmation', (
    tester,
  ) async {
    EventScope? scope;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => scope = await confirmEventDelete(
              context,
              title: 'Dentist',
              repeating: false,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete event?'), findsOneWidget);
    expect(find.text('All events'), findsNothing);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(scope, EventScope.thisEvent);
  });
}
