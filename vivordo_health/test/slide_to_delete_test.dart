import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/profile_screen.dart';

void main() {
  testWidgets('lays out inside an AlertDialog and confirms a full slide', (
    tester,
  ) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 240,
                      maxWidth: 320,
                    ),
                    child: SlideToDelete(
                      enabled: true,
                      onConfirmed: () => confirmed = true,
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Slide to delete'), findsOneWidget);

    final slider = find.byType(SlideToDelete);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(300, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(confirmed, isTrue);
  });

  testWidgets('uses the compact password label while disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: SlideToDelete(enabled: false, onConfirmed: _noop),
          ),
        ),
      ),
    );

    expect(find.text('Enter password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
