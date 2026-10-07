import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';
import 'package:vivordo_health/widgets/app_tour.dart';

void main() {
  test('needsTour per screen until its version is saved', () {
    expect(needsTour(null, 'home'), isTrue);
    expect(needsTour({'home': kTourVersion - 1}, 'home'), isTrue);
    expect(needsTour({'home': kTourVersion}, 'home'), isFalse);
    expect(needsTour({'home': kTourVersion}, 'fitness'), isTrue);
  });

  testWidgets('steps switch tabs, type out, and finish', (tester) async {
    // Each step waits two frames before measuring, then types for a while.
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
    }

    final target = GlobalKey();
    final tabs = <int>[];
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: VivordoTheme.light,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 40,
                bottom: 40,
                child: SizedBox(key: target, width: 60, height: 60),
              ),
              Positioned.fill(
                child: AppTour(
                  steps: [
                    const TourStep('Hello there.'),
                    TourStep('Look here.', tab: 2, target: target),
                  ],
                  onSelectTab: tabs.add,
                  onFinished: () => finished = true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await settle();
    expect(find.text('Hello there.'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(tabs, isEmpty);

    await tester.tap(find.text('Next'));
    await settle();
    expect(tabs, [2]);
    expect(find.text('Look here.'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await settle();
    expect(finished, isTrue);
  });
}
