import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/signup_screen.dart';
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

    expect(
      find.text('Know your energy before your day uses it'),
      findsOneWidget,
    );
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('I have an account'), findsOneWidget);
    // App Review rejects production apps that call themselves beta.
    expect(find.textContaining('Beta'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'create account puts email first, then Apple and Google',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
      await tester.pumpAndSettle();

      final create = tester.getTopLeft(find.text('Create account')).dy;
      final apple = tester.getTopLeft(find.text('Continue with Apple')).dy;
      final google = tester.getTopLeft(find.text('Continue with Google')).dy;
      expect(create, lessThan(apple));
      expect(apple, lessThan(google));
      // Everyone agrees to the Terms before an account exists.
      // Below the fold in the test's small window: scroll it into view.
      await tester.ensureVisible(
        find.text('Privacy Policy', skipOffstage: false),
      );
      await tester.pumpAndSettle();
      final agree = tester.getTopLeft(find.text('Terms')).dy;
      expect(agree, greaterThan(google));
      expect(
        find.text('By continuing you agree to the ', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
