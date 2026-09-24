import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/widgets/contextual_insight_bar.dart';

void main() {
  testWidgets('dismissal lasts only for the current screen visit', (
    tester,
  ) async {
    Future<void> show(String? screen, {bool suppressed = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextualInsightBar(
              insight: screen == null
                  ? null
                  : ScreenInsight(screen, 'Title', 'Advice'),
              suppressed: suppressed,
              collapsed: const Text('Robot'),
              onAsk: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    }

    await show('my_day');
    await tester.tap(find.byTooltip('Dismiss insights for this screen'));
    await tester.pumpAndSettle();
    await show('my_day');
    expect(find.text('Advice'), findsNothing);
    await show('my_day', suppressed: true);
    await show('my_day');
    expect(find.text('Advice'), findsNothing);
    await show('fitness');
    await show('my_day');
    expect(find.text('Advice'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss insights for this screen'));
    await tester.pumpAndSettle();
    await show(null);
    await show('my_day');
    expect(find.text('Advice'), findsOneWidget);
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
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ContextualInsightBar(
              insight: const ScreenInsight(
                'my_day',
                'Your day',
                'Your afternoon is busy.',
              ),
              collapsed: const Text('Robot'),
              onAsk: (value) => prompt = value,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Robot'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
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
      MaterialApp(
        home: Scaffold(
          body: ContextualInsightBar(
            insight: const ScreenInsight('fitness', 'Fitness', 'Advice'),
            suppressed: true,
            collapsed: const Text('Robot'),
            onAsk: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Advice'), findsNothing);
    expect(find.text('Robot'), findsOneWidget);
  });
}
