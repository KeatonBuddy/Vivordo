import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/screens/paywall_screen.dart';
import 'package:vivordo_health/src/services/subscription_service.dart';

void main() {
  final now = DateTime(2026, 11, 1, 12);
  Timestamp at(DateTime time) => Timestamp.fromDate(time);

  test('locks only once Premium is required and not active', () {
    const required = {'required': true};
    bool locked(
      Map<String, dynamic>? config,
      Map<String, dynamic>? sub, {
      bool fromCache = false,
    }) => premiumLocked(
      config: config,
      subscription: sub,
      fromCache: fromCache,
      now: now,
    );

    expect(locked(null, null), isFalse);
    expect(locked({'required': false}, null), isFalse);
    expect(locked(required, null), isTrue);
    // A missing document from the cache waits for the server.
    expect(locked(required, null, fromCache: true), isFalse);
    expect(locked(required, {'active': false}), isTrue);
    expect(
      locked(required, {
        'active': true,
        'expiresAt': at(now.add(const Duration(days: 3))),
      }),
      isFalse,
    );
    expect(
      locked(required, {
        'active': true,
        'expiresAt': at(now.subtract(const Duration(hours: 1))),
      }),
      isTrue,
    );
    expect(locked(required, {'active': true, 'expiresAt': null}), isFalse);
  });

  const yearly = PremiumPlan(
    yearly: true,
    price: r'$69.99',
    amount: 69.99,
    perMonth: r'$5.83',
    freeTrial: (1, 'month'),
  );
  const monthly = PremiumPlan(
    yearly: false,
    price: r'$9.99',
    amount: 9.99,
    freeTrial: (1, 'month'),
  );

  Future<void> show(
    WidgetTester tester,
    List<PremiumPlan> plans, {
    PremiumEnded? ended,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PaywallScreen(
          uid: 'u',
          ended: ended,
          loadPlans: () async => plans,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a new account sees the free month on the yearly plan', (
    tester,
  ) async {
    await show(tester, [yearly, monthly]);
    expect(find.text('Try Vivordo free for a month'), findsOneWidget);
    expect(find.textContaining('Save 42%'), findsOneWidget);
    expect(find.text(r'$69.99/year ($5.83/month)'), findsOneWidget);
    expect(find.text('Start free month'), findsOneWidget);
    expect(
      find.textContaining(r'Free for 1 month, then $69.99 a year.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Monthly', findRichText: true),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Monthly', findRichText: true));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(r'Free for 1 month, then $9.99 a month.'),
      findsOneWidget,
    );
    for (final link in [
      'Restore purchases',
      'Redeem code',
      'Terms',
      'Privacy',
    ]) {
      expect(find.text(link), findsOneWidget);
    }
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('no free month once the Apple ID has used it', (tester) async {
    await show(tester, const [
      PremiumPlan(yearly: true, price: r'$69.99', amount: 69.99),
      PremiumPlan(yearly: false, price: r'$9.99', amount: 9.99),
    ], ended: PremiumEnded.trial);
    expect(find.text('Your free trial has ended'), findsOneWidget);
    expect(find.text(r'Subscribe for $69.99/year'), findsOneWidget);
    expect(find.textContaining('Free for'), findsNothing);
    expect(
      find.textContaining(r'$69.99 a year. Renews automatically'),
      findsOneWidget,
    );
  });

  testWidgets('plans that fail to load can be retried', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PaywallScreen(
          uid: 'u',
          loadPlans: () async {
            if (calls++ == 0) throw StateError('offline');
            return [yearly, monthly];
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't load plans"), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Start free month'), findsOneWidget);
  });
}
