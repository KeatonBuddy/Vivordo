import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:vivordo_health/src/utils/priority_reminder.dart';
import 'package:vivordo_health/src/utils/notification_navigation.dart';
import 'package:vivordo_health/widgets/priority_reminder_picker.dart';

void main() {
  test('untimed reminders use the priority date and chosen clock time', () {
    final now = DateTime(2026, 9, 8, 8);
    DateTime? reminder({
      DateTime? start,
      bool allDay = false,
      bool completed = false,
      int? clock = 570,
    }) => priorityReminderTime(
      start: start,
      minutesBefore: 60,
      completed: completed,
      allDay: allDay,
      now: now,
      priorityDate: DateTime(2026, 9, 8),
      reminderTimeMinutes: clock,
    );
    expect(reminder(), DateTime(2026, 9, 8, 9, 30));
    expect(reminder(allDay: true), DateTime(2026, 9, 8, 9, 30));
    expect(reminder(clock: null), isNull);
    expect(reminder(clock: 420), isNull);
    expect(reminder(completed: true), isNull);
    // A timed priority ignores the independent clock time and uses its offset.
    expect(reminder(start: DateTime(2026, 9, 8, 12)), DateTime(2026, 9, 8, 11));
  });
  testWidgets('custom wheels restore and save hours and minutes', (
    tester,
  ) async {
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPriorityReminderPicker(context, 95);
              },
              child: const Text('Reminder'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Reminder'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    final hours = tester.widget<CupertinoPicker>(
      find.byKey(const ValueKey('reminder-hours')),
    );
    final minutes = tester.widget<CupertinoPicker>(
      find.byKey(const ValueKey('reminder-minutes')),
    );
    expect(hours.scrollController!.selectedItem, 1);
    expect(minutes.scrollController!.selectedItem, 35);
    hours.scrollController!.jumpToItem(2);
    minutes.scrollController!.jumpToItem(5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result, 125);
  });
  final now = DateTime(2026, 9, 8, 8);
  final start = DateTime(2026, 9, 9, 1);
  DateTime? reminder(
    int minutes, {
    bool completed = false,
    bool allDay = false,
    DateTime? at,
  }) => priorityReminderTime(
    start: at ?? start,
    minutesBefore: minutes,
    completed: completed,
    allDay: allDay,
    now: now,
  );
  test('preset and custom offsets use the selected start time', () {
    for (final minutes in [0, 30, 60, 360, 95]) {
      expect(reminder(minutes), start.subtract(Duration(minutes: minutes)));
    }
    expect(reminder(360), DateTime(2026, 9, 8, 19));
  });
  test('completed, untimed, all-day and past reminders do not schedule', () {
    expect(reminder(60, completed: true), isNull);
    expect(reminder(60, allDay: true), isNull);
    expect(reminder(60, at: now.add(const Duration(minutes: 30))), isNull);
    expect(
      priorityReminderTime(
        start: null,
        minutesBefore: 60,
        completed: false,
        allDay: false,
        now: now,
      ),
      isNull,
    );
  });
  test('IDs are stable and distinguish dates and users', () {
    const a = 'users/a/daily_priorities/2026-09-08/items/task';
    expect(priorityNotificationId(a), priorityNotificationId(a));
    expect(priorityNotificationId(a), greaterThanOrEqualTo(10000));
    expect(
      priorityNotificationId(a),
      isNot(priorityNotificationId(a.replaceFirst('/a/', '/b/'))),
    );
    expect(
      priorityNotificationId(a),
      isNot(priorityNotificationId(a.replaceFirst('09-08', '09-09'))),
    );
  });
  test('reminders open My Day and labels explain the offset', () {
    expect(notificationRouteStack('calendar'), ['/home', '/calendar']);
    expect(priorityReminderLabel(0), 'During');
    expect(priorityReminderLabel(60), '1 hr before');
    expect(priorityReminderLabel(95), '95 min before');
  });
}
