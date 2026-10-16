import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vivordo_health/src/services/subscription_service.dart';

void main() {
  final now = DateTime(2026, 10, 16, 12);
  Map<String, dynamic> sub({
    String product = 'yearly',
    String period = 'normal',
    bool renews = true,
    bool billingIssue = false,
    DateTime? expires,
  }) => {
    'active': true,
    'productId': product,
    'period': period,
    'willRenew': renews,
    'billingIssue': billingIssue,
    'expiresAt': Timestamp.fromDate(expires ?? DateTime(2026, 11, 13)),
  };

  test('the plan, and when it renews or ends', () {
    var s = subscriptionSummary(
      sub(period: 'trial'),
      now: now,
      price: r'CA$69.99',
    );
    expect(s.title, 'Vivordo · Yearly');
    expect(s.lines, [
      'Free trial ends Nov 13',
      r'Then CA$69.99 a year, renews Nov 13',
    ]);

    s = subscriptionSummary(
      sub(product: 'monthly', period: 'trial', renews: false),
      now: now,
    );
    expect(s.title, 'Vivordo · Monthly');
    expect(s.lines.last, "Won't renew · access ends Nov 13");

    s = subscriptionSummary(sub(), now: now, price: r'CA$69.99');
    expect(s.lines, [r'Renews Nov 13 · CA$69.99 a year']);

    s = subscriptionSummary(sub(renews: false), now: now);
    expect(s.lines, ['Cancelled · access until Nov 13']);

    s = subscriptionSummary(sub(billingIssue: true), now: now);
    expect(s.lines.last, startsWith("Apple couldn't charge"));
  });

  test('free access, and nothing active', () {
    expect(
      subscriptionSummary(
        sub(product: 'rc_promo_vivordo_premium_custom'),
        now: now,
      ).title,
      'Free access',
    );
    expect(subscriptionSummary(null, now: now).title, 'Not subscribed');
    expect(
      subscriptionSummary({...sub(), 'active': false}, now: now).title,
      'Not subscribed',
    );
    // Past its expiry, even if not yet marked inactive.
    expect(
      subscriptionSummary(sub(expires: DateTime(2026, 10, 1)), now: now).title,
      'Not subscribed',
    );
  });
}
