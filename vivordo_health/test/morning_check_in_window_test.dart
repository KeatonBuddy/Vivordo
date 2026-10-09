import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/daily_tags.dart';
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

  testWidgets('one screen: sleep, tags and feel, then it closes itself', (
    tester,
  ) async {
    final context = await pumpApp(tester);
    final saved = <String>[];
    final hours = ValueNotifier<double?>(null);
    addTearDown(hours.dispose);
    final result = showMorningCheckInSheet(
      context,
      feel: null,
      sleep: null,
      sleepHours: hours,
      tags: const {},
      onFeel: (l) => saved.add('feel:$l'),
      onSleep: (l) => saved.add('sleep:$l'),
      onTags: (t) => saved.add('tags:${t.join(',')}'),
    );
    await tester.pumpAndSettle();
    expect(find.text('How did you sleep?'), findsOneWidget);
    expect(find.textContaining('Anything from last night?'), findsOneWidget);
    expect(find.text('How do you feel?'), findsOneWidget);
    // Sleep that syncs while it's open shows up.
    expect(find.textContaining('recorded'), findsNothing);
    hours.value = 6.8;
    await tester.pump();
    expect(find.textContaining('6 h 48 m recorded'), findsOneWidget);

    // Feel first, then sleep: whichever comes second starts the wait.
    await tester.tap(find.text('Good').last);
    await tester.tap(find.text('Okay').first);
    await tester.pump(const Duration(milliseconds: 1000));
    // A tag in the pause restarts it, so it lands.
    await tester.tap(find.text('Alcohol'));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text("You're set for today"), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text("You're set for today"), findsOneWidget);
    expect(find.text('Tagged alcohol'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(saved, ['feel:Good', 'sleep:Okay', 'tags:alcohol']);
  });

  testWidgets('earlier answers show selected; Not today dismisses', (
    tester,
  ) async {
    final context = await pumpApp(tester);
    final result = showMorningCheckInSheet(
      context,
      feel: null,
      sleep: 'Good',
      sleepHours: ValueNotifier(null),
      tags: const {'late_meal'},
      onFeel: (_) {},
      onSleep: (_) {},
      onTags: (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('How do you feel?'), findsOneWidget);
    await tester.tap(find.text('Not today'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('Home shows a one-line row that says what is left', (
    tester,
  ) async {
    var taps = 0;
    Future<void> show(int left) => tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: CheckInRow(left: left, onTap: () => taps++),
        ),
      ),
    );
    await show(2);
    expect(find.text('Daily check-in'), findsOneWidget);
    expect(find.text('2 taps'), findsOneWidget);
    await show(1);
    expect(find.text('1 left'), findsOneWidget);
    await tester.tap(find.byType(CheckInRow));
    expect(taps, 1);
  });

  test('tags read as a phrase in the offered order', () {
    expect(
      dailyTagsPhrase(const {'late_meal', 'alcohol'}),
      'alcohol and late meal',
    );
    expect(dailyTagsPhrase(const {'sick'}), 'sick');
    expect(dailyTagsPhrase(const {}), '');
  });
}
