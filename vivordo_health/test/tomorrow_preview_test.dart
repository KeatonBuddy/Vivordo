import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/tomorrow_preview.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

void main() {
  testWidgets(
    'tomorrow shows live counts, events, overflow and working navigation',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var openedDay = false;
      var openedEvent = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: VivordoTheme.dark,
          home: Scaffold(
            body: TomorrowPreview(
              day: DateTime(2026, 9, 11),
              events: List.generate(
                3,
                (i) => TomorrowPreviewEvent(
                  title: 'Event $i',
                  start: DateTime(2026, 9, 11, 9 + i),
                  end: DateTime(2026, 9, 11, 10 + i),
                  allDay: false,
                  onTap: () => openedEvent = true,
                ),
              ),
              priorities: const [],
              onEdit: (_) {},
              onToggle: (_) {},
              onViewDay: () => openedDay = true,
            ),
          ),
        ),
      );
      expect(find.text('3 events · 0 priorities'), findsOneWidget);
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(find.text('Fri, Sep 11'), findsOneWidget);
      expect(find.text('No priorities planned'), findsOneWidget);
      expect(find.text('+1 more event'), findsOneWidget);
      expect(find.text('Event 2'), findsNothing);
      await tester.tap(find.text('Event 0'));
      expect(openedEvent, isTrue);
      await tester.tap(find.text('View day ›'));
      expect(openedDay, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('empty tomorrow is explicit on a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: TomorrowPreview(
            day: DateTime(2026, 9, 11),
            events: const [],
            priorities: const [],
            onEdit: (_) {},
            onToggle: (_) {},
            onViewDay: () {},
          ),
        ),
      ),
    );
    expect(find.text('No events scheduled'), findsOneWidget);
    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.text('No priorities planned'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
