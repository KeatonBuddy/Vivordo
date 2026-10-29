import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/contextual_insight_bar.dart';

void main() {
  Widget bar({
    required String? screen,
    required InsightMemory memory,
    String message = 'Advice',
    bool suppressed = false,
    ValueNotifier<double>? lift,
    List<int>? waves,
    VoidCallback? onTap,
    ValueChanged<String>? onAsk,
  }) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: ContextualInsightBar(
          insight: screen == null
              ? null
              : ScreenInsight(screen, 'Title', message),
          suppressed: suppressed,
          memory: memory,
          lift: lift,
          button: (_, count) {
            waves?.add(count);
            return const Text('Robot');
          },
          onButtonTap: (_) => onTap?.call(),
          onAsk: onAsk ?? (_) {},
        ),
      ),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  testWidgets('a new insight opens once; later visits show a dot and wave', (
    tester,
  ) async {
    final memory = InsightMemory();
    final lift = ValueNotifier<double>(0);
    final waves = <int>[];
    await tester.pumpWidget(
      bar(screen: 'my_day', memory: memory, lift: lift, waves: waves),
    );
    await settle(tester);
    expect(find.text('Advice'), findsOneWidget);
    expect(lift.value, 1, reason: 'the button rises so the bar can widen');
    await tester.tap(find.byTooltip('Dismiss insights for this screen'));
    await tester.pumpAndSettle();
    expect(find.text('Advice'), findsNothing);
    expect(lift.value, 0);
    expect(find.bySemanticsLabel(RegExp('insight available')), findsOne);

    // Another screen, then back: the same insight doesn't open by itself,
    // and the robot waves once about it.
    await tester.pumpWidget(bar(screen: 'fitness', memory: memory));
    await settle(tester);
    await tester.tap(find.byTooltip('Dismiss insights for this screen'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      bar(screen: 'my_day', memory: memory, waves: waves..clear()),
    );
    await settle(tester);
    expect(find.text('Advice'), findsNothing);
    expect(waves.last, 1);
    await tester.pumpWidget(
      bar(screen: 'fitness', memory: memory, waves: waves..clear()),
    );
    await settle(tester);
    final before = waves.last;
    await tester.pumpWidget(
      bar(screen: 'my_day', memory: memory, waves: waves..clear()),
    );
    await settle(tester);
    expect(waves.last, before, reason: 'only one wave per insight');

    // Tapping the button opens it; new text opens by itself again.
    await tester.tap(find.text('Robot'));
    await tester.pumpAndSettle();
    expect(find.text('Advice'), findsOneWidget);
    await tester.pumpWidget(bar(screen: 'fitness', memory: memory));
    await settle(tester);
    await tester.pumpWidget(
      bar(screen: 'my_day', memory: memory, message: 'New advice'),
    );
    await settle(tester);
    expect(find.text('New advice'), findsOneWidget);
  });

  testWidgets('without an insight the button opens Vivordo AI', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      bar(screen: null, memory: InsightMemory(), onTap: () => taps++),
    );
    await settle(tester);
    await tester.tap(find.text('Robot'));
    expect(taps, 1);
  });

  testWidgets('a quick tab switch morphs one robot button, never a copy', (
    tester,
  ) async {
    // Switching again just as an insight card opens reverses the morph. The
    // pill grows out of the button, so there is only ever one robot, and it
    // must never carry a GlobalKey (main_navigation.dart once did, which
    // crashed the old crossfade with "Duplicate GlobalKey").
    final memory = InsightMemory();
    await tester.pumpWidget(bar(screen: 'home', memory: memory));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.pumpWidget(bar(screen: 'my_day', memory: memory));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(bar(screen: 'fitness', memory: memory));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Robot'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('Robot'), findsOneWidget);
  });

  test('only the selected tab and top route provide advice', () {
    final controller = ScreenInsightController();
    final root = MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'main-tabs'),
      builder: (_) => const SizedBox(),
    );
    final sleep = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    final modal = MaterialPageRoute<void>(builder: (_) => const SizedBox());
    controller.publish(
      'day',
      root,
      const ScreenInsight('my_day', 'Day', 'Day advice'),
    );
    controller.publish(
      'fitness',
      root,
      const ScreenInsight('fitness', 'Fitness', 'Fitness advice'),
    );
    controller.publish(
      'sleep',
      sleep,
      const ScreenInsight('sleep', 'Sleep', 'Sleep advice'),
    );
    controller.select(root, 'my_day');
    expect(controller.current?.message, 'Day advice');
    controller.select(root, 'fitness');
    expect(controller.current?.message, 'Fitness advice');
    controller.select(sleep, 'fitness');
    expect(controller.current?.message, 'Sleep advice');
    controller.select(modal, 'fitness');
    expect(controller.current, isNull);
    controller.select(root, 'home');
    expect(controller.current, isNull);
    controller.dispose();
  });

  testWidgets('preview expands, passes context only on tap, and dismisses', (
    tester,
  ) async {
    String? prompt;
    await tester.pumpWidget(
      bar(
        screen: 'my_day',
        memory: InsightMemory(),
        message: 'Your afternoon is busy.',
        onAsk: (value) => prompt = value,
      ),
    );
    expect(find.text('Robot'), findsOneWidget);
    await settle(tester);
    expect(find.text('Your afternoon is busy.'), findsOneWidget);
    expect(prompt, isNull);
    await tester.tap(find.byTooltip('Expand insight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask Vivordo AI'));
    expect(prompt, contains('Your afternoon is busy.'));
    await tester.tap(find.byTooltip('Dismiss insights for this screen'));
    await tester.pump();
    expect(find.text('Robot'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Robot'), findsOneWidget);
  });

  testWidgets('suppressed advice stays collapsed', (tester) async {
    await tester.pumpWidget(
      bar(screen: 'fitness', memory: InsightMemory(), suppressed: true),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Advice'), findsNothing);
    expect(find.text('Robot'), findsOneWidget);
  });
}
