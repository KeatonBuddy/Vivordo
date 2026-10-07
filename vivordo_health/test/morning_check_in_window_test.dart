import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/morning_check_in_card.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 2, hour, minute);

  test('the check-in is asked from 5 AM until midnight', () {
    // After midnight you haven't slept yet.
    expect(morningCheckInOpen(at(0, 30)), isFalse);
    expect(morningCheckInOpen(at(4, 59)), isFalse);
    expect(morningCheckInOpen(at(5)), isTrue);
    expect(morningCheckInOpen(at(12)), isTrue);
    expect(morningCheckInOpen(at(23, 59)), isTrue);
  });

  test('Home shows it until both questions are answered or dismissed', () {
    expect(checkInDue(const {}, at(20)), isTrue);
    expect(checkInDue(const {'feel': 75}, at(9)), isTrue);
    expect(checkInDue(const {'feel': 75, 'sleep': 50}, at(9)), isFalse);
    expect(checkInDue(const {'dismissed': true}, at(9)), isFalse);
    // Not loaded yet, or before 5 AM.
    expect(checkInDue(null, at(9)), isFalse);
    expect(checkInDue(const {}, at(3)), isFalse);
  });

  test('the pop-up: once a day, mornings only, until 3 dismissals', () {
    expect(checkInPopupDue(const {}, at(7), 0), isTrue);
    expect(checkInPopupDue(const {'feel': 75}, at(11, 59), 2), isTrue);
    // Afternoon, already shown today, answered, or dismissed too often.
    expect(checkInPopupDue(const {}, at(12), 0), isFalse);
    expect(checkInPopupDue(const {'prompted': true}, at(7), 0), isFalse);
    expect(checkInPopupDue(const {'feel': 75, 'sleep': 50}, at(7), 0), isFalse);
    expect(checkInPopupDue(const {}, at(7), 3), isFalse);
    expect(checkInPopupDue(const {}, at(4), 0), isFalse);
  });

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

  testWidgets('the sheet asks sleep, then feel, then closes itself', (
    tester,
  ) async {
    final context = await pumpApp(tester);
    final saved = <String>[];
    final result = showMorningCheckInSheet(
      context,
      feel: null,
      sleep: null,
      sleepHours: 6.8,
      onFeel: (l) => saved.add('feel:$l'),
      onSleep: (l) => saved.add('sleep:$l'),
    );
    await tester.pumpAndSettle();
    expect(find.text('How did you sleep?'), findsOneWidget);
    expect(find.text('6 h 48 m recorded'), findsOneWidget);
    await tester.tap(find.text('Okay'));
    await tester.pumpAndSettle();
    expect(find.text('How do you feel?'), findsOneWidget);
    expect(find.text('Slept okay'), findsOneWidget);
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    expect(find.text("You're set for today"), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(saved, ['sleep:Okay', 'feel:Good']);
  });

  testWidgets(
    'a question answered on the card is skipped; Not today dismisses',
    (tester) async {
      final context = await pumpApp(tester);
      final result = showMorningCheckInSheet(
        context,
        feel: null,
        sleep: 'Good',
        sleepHours: null,
        onFeel: (_) {},
        onSleep: (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.text('How do you feel?'), findsOneWidget);
      await tester.tap(find.text('Not today'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    },
  );
}
