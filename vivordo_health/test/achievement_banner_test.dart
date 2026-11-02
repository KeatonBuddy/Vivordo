import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/achievement_unlock_service.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/achievement_banner.dart';

AchievementUnlock _unlock(String name) => AchievementUnlock(
  id: name,
  name: name,
  requirement: '',
  badgeAsset: 'assets/achievements/day_planner.png',
);

Future<({List<String> events})> _pump(
  WidgetTester tester,
  List<AchievementUnlock> unlocks,
) async {
  final events = <String>[];
  var shown = true;
  await tester.pumpWidget(
    MaterialApp(
      theme: VivordoTheme.light,
      home: StatefulBuilder(
        builder: (context, setState) => Stack(
          children: [
            if (shown)
              AchievementBanner(
                unlocks: unlocks,
                onOpen: () => events.add('open'),
                onDismissed: () {
                  events.add('dismissed');
                  setState(() => shown = false);
                },
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (events: events);
}

void main() {
  testWidgets('banner names the achievement and leaves after 4 s', (
    tester,
  ) async {
    final (:events) = await _pump(tester, [_unlock('Day planner')]);
    expect(find.text('Achievement unlocked'), findsOneWidget);
    expect(find.text('Day planner'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(events, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(events, ['dismissed']);
    expect(find.text('Day planner'), findsNothing);
  });

  testWidgets('several unlocks share one banner; a tap opens them', (
    tester,
  ) async {
    final (:events) = await _pump(tester, [
      _unlock('Day planner'),
      _unlock('Early bird'),
    ]);
    expect(find.text('2 achievements unlocked'), findsOneWidget);
    expect(find.text('Day planner, Early bird'), findsOneWidget);
    await tester.tap(find.text('Day planner, Early bird'));
    await tester.pumpAndSettle();
    expect(events, ['open', 'dismissed']);
  });
}
