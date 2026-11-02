import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../src/services/subscription_service.dart';
import '../theme/vivordo_theme.dart';
import '../widgets/apple_ui.dart';

/// Settings → Subscription: the plan and when it renews or ends, and
/// Apple's change/cancel page, restore and codes.
/// Billing itself stays with Apple.
class SubscriptionSettingsScreen extends StatefulWidget {
  const SubscriptionSettingsScreen({super.key, required this.uid});

  final String uid;

  @override
  State<SubscriptionSettingsScreen> createState() =>
      _SubscriptionSettingsScreenState();
}

class _SubscriptionSettingsScreenState
    extends State<SubscriptionSettingsScreen> {
  late final _subscription = FirebaseFirestore.instance
      .collection('subscriptions')
      .doc(widget.uid)
      .snapshots();
  Future<String?>? _price;
  String? _priceFor;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      debugPrint('Subscription action failed: $error');
      if (mounted) showToast(context, failure, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() => _run(() async {
    final restored = await SubscriptionService.restore(widget.uid);
    if (mounted) {
      showToast(
        context,
        restored
            ? 'Your subscription is active.'
            : 'No Vivordo subscription found on this Apple ID.',
        kind: restored ? ToastKind.success : ToastKind.info,
      );
    }
  }, "Couldn't restore purchases. Try again.");

  @override
  Widget build(BuildContext context) {
    final colors = context.vivordoColors;
    return Scaffold(
      backgroundColor: colors.page,
      appBar: AppBar(
        backgroundColor: colors.page,
        title: const Text('Subscription'),
      ),
      body: StreamBuilder(
        stream: _subscription,
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final product = data?['productId'] as String?;
          // The price comes from the store, so it's in the person's own
          // currency; fetched once per plan.
          if (product != null && product != _priceFor) {
            _priceFor = product;
            _price = SubscriptionService.priceOf(widget.uid, product);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              FutureBuilder(
                future: _price,
                builder: (context, price) {
                  final summary = subscriptionSummary(
                    data,
                    now: DateTime.now(),
                    price: price.data,
                  );
                  return AppleFormGroup(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              snapshot.hasData ? summary.title : 'Loading…',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            for (final line in summary.lines) ...[
                              const SizedBox(height: 4),
                              Text(
                                line,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              AppleFormGroup(
                header: 'Manage',
                footer:
                    'Billing, refunds and cancelling are handled by Apple. '
                    '"Change or cancel plan" opens your App Store '
                    'subscriptions.',
                children: [
                  AppleFormRow(
                    label: 'Change or cancel plan',
                    chevron: true,
                    onTap: _busy
                        ? null
                        : () => _run(
                            () => SubscriptionService.manage(widget.uid),
                            "Couldn't open your subscriptions. Try again.",
                          ),
                  ),
                  AppleFormRow(
                    label: 'Restore purchases',
                    onTap: _busy ? null : _restore,
                  ),
                  AppleFormRow(
                    label: 'Redeem a code',
                    onTap: _busy
                        ? null
                        : () => _run(
                            () => SubscriptionService.redeemCode(widget.uid),
                            "Couldn't open code redemption. Try again.",
                          ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
