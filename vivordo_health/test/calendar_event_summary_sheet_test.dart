import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/calendar_event_summary_sheet.dart';

void main() {
  testWidgets('calendar event summary exposes event details and edit action', (
    tester,
  ) async {
    CalendarEventSummaryAction? action;
    final start = DateTime(2026, 9, 1, 9);

    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.dark,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              action = await showCalendarEventSummarySheet(
                context,
                event: CalendarEventSummaryData(
                  title: 'Product Review',
                  start: start,
                  end: start.add(const Duration(hours: 1)),
                  isAllDay: false,
                  isRecurring: false,
                  color: Colors.blue,
                  calendarName: 'Google Calendar',
                  canEdit: true,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Event Summary'), findsOneWidget);
    expect(find.text('Product Review'), findsOneWidget);
    expect(find.text('Google Calendar'), findsOneWidget);
    expect(find.text('Edit Event'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.ensureVisible(find.text('Edit Event'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Event'));
    await tester.pumpAndSettle();

    expect(action, CalendarEventSummaryAction.edit);
  });
}
