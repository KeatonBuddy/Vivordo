import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/utils/day_fixes.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/day_fixes_card.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 8, hour, minute);
  String t(String time) => time.replaceAll(' ', ' ');

  final move = DayFix(
    kind: DayFixKind.movePriority,
    id: 'deck',
    title: 'Finalize pitch deck',
    demandSaved: 8.2,
  );
  final buffer = DayFix(
    kind: DayFixKind.buffer,
    id: 'call',
    title: 'Client call',
    demandSaved: 3.6,
    start: at(13, 30),
    end: at(14, 30),
    newStart: at(13, 45),
    after: 'Design review',
    guests: 2,
  );
  final energy = DayFix(
    kind: DayFixKind.energySlot,
    id: 'deep',
    title: 'Deep work',
    demandSaved: 0,
    start: at(15),
    end: at(16),
    newStart: at(10),
  );

  Widget app(Widget child) => MaterialApp(
    theme: VivordoTheme.light,
    home: Scaffold(body: child),
  );

  testWidgets('the card lists fixes with their real saving; X hides it', (
    tester,
  ) async {
    final opened = <DayFix>[];
    var hidden = false;
    await tester.pumpWidget(
      app(
        DayFixesCard(
          fixes: [move, buffer, energy],
          onOpen: opened.add,
          onHide: () => hidden = true,
        ),
      ),
    );
    expect(find.text('Move "Finalize pitch deck"'), findsOneWidget);
    expect(find.text('−8'), findsOneWidget);
    expect(find.text('15-min buffer before Client call'), findsOneWidget);
    expect(find.text('−4'), findsOneWidget);
    expect(find.text('Deep work at ${t('10 AM')}'), findsOneWidget);
    expect(find.text('Fits peak'), findsOneWidget);

    await tester.pumpWidget(
      app(
        DayFixesCard(
          fixes: [
            DayFix(
              kind: DayFixKind.addBreak,
              id: 'break',
              title: 'Break',
              demandSaved: 0,
              start: at(14),
              end: at(14, 15),
              newStart: at(14),
              after: 'Planning',
              runMinutes: 105,
            ),
          ],
          onOpen: opened.add,
          onHide: () {},
        ),
      ),
    );
    expect(find.text('15-min break at ${t('2 PM')}'), findsOneWidget);
    expect(find.text('After 1 h 45 of back-to-back'), findsOneWidget);
    expect(find.text('Breather'), findsOneWidget);

    await tester.pumpWidget(
      app(
        DayFixesCard(
          fixes: [move, buffer, energy],
          onOpen: opened.add,
          onHide: () => hidden = true,
        ),
      ),
    );
    await tester.tap(find.text('15-min buffer before Client call'));
    expect(opened.single, buffer);
    await tester.tap(find.byTooltip('Hide until tomorrow'));
    expect(hidden, isTrue);
  });

  testWidgets('the time sheet shows before, after, guests and Demand', (
    tester,
  ) async {
    late Future<bool> result;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showDayFixTimeSheet(
              context,
              fix: buffer,
              demandNow: 74,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add 15 minutes before Client call'), findsOneWidget);
    expect(find.text('${t('1:45 PM')} – ${t('2:45 PM')}'), findsOneWidget);
    expect(
      find.textContaining('2 guests will get the new time'),
      findsOneWidget,
    );
    expect(find.text('  →  70'), findsOneWidget);
    await tester.tap(find.text('Move to ${t('1:45 PM')}'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('the day picker starts on the lightest day', (tester) async {
    late Future<DateTime?> result;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showMovePrioritySheet(
              context,
              fix: move,
              demandNow: 74,
              days: Future.value([
                (day: DateTime(2026, 10, 9), demand: 41.0),
                (day: DateTime(2026, 10, 10), demand: 18.0),
                (day: DateTime(2026, 10, 11), demand: 33.0),
              ]),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Move to Saturday'), findsOneWidget);
    expect(find.text('The lightest of the next 3 days.'), findsOneWidget);
    await tester.tap(find.text('Sun'));
    await tester.pump();
    await tester.tap(find.text('Move to Sunday'));
    await tester.pumpAndSettle();
    expect(await result, DateTime(2026, 10, 11));
  });

  testWidgets('the evening card and sheets talk about tomorrow', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        DayFixesCard(
          fixes: [move, buffer],
          tomorrow: true,
          onOpen: (_) {},
          onHide: () {},
        ),
      ),
    );
    expect(find.text('WAYS TO LIGHTEN TOMORROW'), findsOneWidget);
    expect(find.byTooltip('Hide until morning'), findsOneWidget);

    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDayFixTimeSheet(
              context,
              fix: buffer,
              demandNow: 89,
              tomorrow: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add 15 minutes before Client call tomorrow'),
      findsOneWidget,
    );
    expect(find.text("Tomorrow's Demand"), findsOneWidget);
  });
}
