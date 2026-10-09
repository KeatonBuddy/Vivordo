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
    // Finished rests go straight back to the chosen length for the next set.
    expect(find.text('1:15'), findsOneWidget);
    expect(find.text('Rest done'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    expect(notifications.last, isNull);
    await tester.pump();
    expect(find.text('1:15'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('adjusting rest keeps the keyboard up; other taps close it', (
    tester,
  ) async {
    final reps = FocusNode();
    void unfocus(PointerDownEvent _) =>
        FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          // As in ActiveWorkoutScreen: set fields close the keyboard on taps
          // outside them, and the rest bar counts as inside.
          bottomNavigationBar: TextFieldTapRegion(
            child: WorkoutRestTimer(onDeadlineChanged: (_) async {}),
          ),
          body: Column(
            children: [
              TextField(focusNode: reps, onTapOutside: unfocus),
              const SizedBox(height: 200, width: 300, child: Text('Elsewhere')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(reps.hasFocus, isTrue);

    for (final control in [
      find.byTooltip('Add 15 seconds'),
      find.byTooltip('Subtract 15 seconds'),
      find.byTooltip('Start rest timer'),
      find.text('Reset'),
    ]) {
      await tester.tap(control);
      await tester.pump();
      expect(reps.hasFocus, isTrue, reason: '$control');
    }

    await tester.tap(find.text('Elsewhere'));
    await tester.pump();
    expect(reps.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox());
    reps.dispose();
  });

  testWidgets('starts from the saved length and saves idle changes', (
    tester,
  ) async {
    final saved = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          bottomNavigationBar: WorkoutRestTimer(
            loadPreset: () async => 120,
            onPresetChanged: saved.add,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('2:00'), findsOneWidget);

    await tester.tap(find.byTooltip('Add 15 seconds'));
    await tester.pump();
    expect(find.text('2:15'), findsOneWidget);
    expect(saved, [135]);

    // Adjusting a running rest changes only that rest.
    await tester.tap(find.byTooltip('Start rest timer'));
    await tester.pump();
    await tester.tap(find.byTooltip('Add 15 seconds'));
    await tester.pump();
    expect(saved, [135]);
    await tester.pumpWidget(const SizedBox());
  });
}
