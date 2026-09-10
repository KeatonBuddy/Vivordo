import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/workout_rest_timer.dart';

void main() {
  testWidgets('rest timer adjusts, pauses, resumes and completes by deadline', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 8, 12);
    final notifications = <DateTime?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          bottomNavigationBar: WorkoutRestTimer(
            now: () => now,
            onDeadlineChanged: (deadline) async => notifications.add(deadline),
          ),
        ),
      ),
    );
    expect(find.text('1:15'), findsOneWidget);
    await tester.tap(find.byTooltip('Add 15 seconds'));
    await tester.pump();
    expect(find.text('1:30'), findsOneWidget);
    await tester.tap(find.byTooltip('Subtract 15 seconds'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(notifications.last, now.add(const Duration(seconds: 75)));
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('0:55'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause_rounded));
    expect(notifications.last, isNull);
    await tester.pump();
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:55'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('0:00'), findsOneWidget);
    expect(find.text('Rest complete'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    expect(notifications.last, isNull);
    await tester.pump();
    expect(find.text('1:15'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
