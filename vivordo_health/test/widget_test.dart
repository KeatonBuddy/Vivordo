import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/welcome_beta_screen.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

void main() {
  testWidgets('Vivordo welcome screen renders its primary content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: VivordoTheme.light, home: const WelcomeBetaScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Vivordo!'), findsOneWidget);
    expect(find.text('BETA TESTER'), findsOneWidget);
    expect(find.text("Let's go  →"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
