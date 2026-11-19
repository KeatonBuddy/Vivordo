import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
import 'package:vivordo_health/widgets/apple_ui.dart';

void main() {
  // The Duo's inner display, opened like a book, and its fold.
  const screen = Size(951, 669);
  const fold = Rect.fromLTWH(455.5, 0, 40, 669);

  Future<Rect> alertWith(WidgetTester tester, HingeStatus status) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = Stream.value(
      FoldableData(
        capabilities: FoldableCapabilities.unsupported,
        status: status,
        angleDegrees: status == HingeStatus.partiallyOpen ? 110 : 180,
        // Laid flat, the system still lists the fold for a moment; only the
        // hinge says whether it is in the way.
        regions: const [
          ReservedRegion(
            kind: ReservedRegionKind.division,
            bounds: fold,
            isActive: true,
          ),
        ],
        displayFeatures: const [],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        // As main.dart wraps the app.
        builder: (context, child) => FoldableProvider(
          bridgeMode: DisplayFeatureBridgeMode.full,
          debugData: data,
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAppleAlert<bool>(
                  context,
                  title: 'Cancel workout?',
                  actions: const [AppleAlertAction('Keep workout', false)],
                ),
                child: const Text('ask'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
    return tester.getRect(find.byType(AppleAlert));
  }

  testWidgets('partly folded, an alert sits wholly on the trailing half', (
    tester,
  ) async {
    final alert = await alertWith(tester, HingeStatus.partiallyOpen);
    expect(alert.left, greaterThanOrEqualTo(fold.right));
    expect(alert.right, lessThanOrEqualTo(screen.width));
  });

  testWidgets('opened flat, an alert stays centred', (tester) async {
    final alert = await alertWith(tester, HingeStatus.fullyOpen);
    expect(alert.center.dx, closeTo(screen.width / 2, 1));
  });
}
