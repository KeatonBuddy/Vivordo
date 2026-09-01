import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/login_screen.dart';

void main() {
  testWidgets('shows Apple sign-in on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Apple'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('hides Apple sign-in outside iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue with Apple'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
