import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:vivordo_health/theme/vivordo_theme.dart';

import '../src/services/subscription_service.dart';
import '../widgets/apple_ui.dart';
import '../widgets/launch_splash.dart';
import '../widgets/privacy_support_links.dart';
import 'onboarding_flow_screen.dart' show onboardingLight;
import 'profile_screen.dart' show SettingsScreen;

const _purple = VivordoTheme.brand;
const _page = Color(0xFFF2F2F7);
const _ink = Color(0xFF1C1C1E);
// iOS secondary label grey, dark enough for 4.5:1 on the page.
const _grey = Color(0xFF6C6C70);
const _line = Color(0xFFE5E5EA);
const _green = Color(0xFF0F6E56);

/// Shows [child] unless a subscription is required and this account doesn't
/// have it, in which case it shows the paywall (premiumLocked). The
/// subscription document is written by the server, so the gate opens by
/// itself once a purchase, restore or code reaches it.
class PremiumGate extends StatefulWidget {
  const PremiumGate({super.key, required this.uid, required this.child});

  final String uid;
  final Widget child;

  @override
  State<PremiumGate> createState() => _PremiumGateState();
}

class _PremiumGateState extends State<PremiumGate> {
  // Before the paywall first shows for an account, the server is asked once
  // (refreshSubscription): staff on the list are unlocked there, and a
  // purchase whose webhook hasn't arrived yet is picked up.
  String? _checkedUid;
  Future<void>? _check;

  Future<void> _checkOnce() {
    if (_checkedUid != widget.uid) {
      _checkedUid = widget.uid;
      _check = SubscriptionService.refresh().timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );
    }
    return _check!;
  }

  final _config = FirebaseFirestore.instance
      .collection('app_config')
      .doc('premium')
      .snapshots();
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _subscription = _watch(
    widget.uid,
  );

  // Metadata changes too: a missing document first read from the cache has
  // to be confirmed by the server before it locks anyone out.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> _watch(String uid) =>
      FirebaseFirestore.instance
          .collection('subscriptions')
          .doc(uid)
          .snapshots(includeMetadataChanges: true);

  @override
  void didUpdateWidget(PremiumGate old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _subscription = _watch(widget.uid);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: _config,
    builder: (context, config) {
      // Unreadable settings fail open: the server still gates paid features.
      if (config.hasError) return widget.child;
      if (!config.hasData) return const LaunchSplash();
      if (config.data!.data()?['required'] != true) return widget.child;
      return StreamBuilder(
        stream: _subscription,
        builder: (context, subscription) {
          if (subscription.hasError) return widget.child;
          final snapshot = subscription.data;
          if (snapshot == null) return const LaunchSplash();
          final data = snapshot.data();
          final locked = premiumLocked(
            config: config.data!.data(),
            subscription: data,
            fromCache: snapshot.metadata.isFromCache,
            now: DateTime.now(),
          );
          if (!locked) return widget.child;
          // If the server unlocks the account, the stream rebuilds this
          // before the paywall is ever shown.
          return FutureBuilder(
            future: _checkOnce(),
            builder: (context, check) =>
                check.connectionState != ConnectionState.done
                ? const _Loading()
                : PaywallScreen(
                    uid: widget.uid,
                    ended: switch (data?['period']) {
                      null when data == null => null,
                      'trial' => PremiumEnded.trial,
                      _ => PremiumEnded.subscription,
                    },
                  ),
          );
        },
      );
    },
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// What ran out, for someone who was subscribed before.
enum PremiumEnded { trial, subscription }

/// The hard paywall: after onboarding for new accounts ([ended] null), and
/// in place of the app once a trial or subscription ends. Settings stays
/// reachable, so anyone can still sign out or delete their account.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.uid,
    this.ended,
    this.loadPlans,
  });

  final String uid;
  final PremiumEnded? ended;

  /// Replaces RevenueCat in tests.
  final Future<List<PremiumPlan>> Function()? loadPlans;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  late Future<List<PremiumPlan>> _plans = _load();
  bool _yearly = true;
  bool _busy = false;

  Future<List<PremiumPlan>> _load() =>
      widget.loadPlans?.call() ?? SubscriptionService.plans(widget.uid);

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      debugPrint('Paywall action failed: $error');
      if (mounted) showToast(context, failure, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _subscribe(PremiumPlan plan) => _run(() async {
    await SubscriptionService.purchase(widget.uid, plan);
  }, "Couldn't complete the purchase. You haven't been charged.");

  Future<void> _restore() => _run(() async {
    final restored = await SubscriptionService.restore(widget.uid);
    if (!restored && mounted) {
      showToast(context, 'No Vivordo subscription found on this Apple ID.');
    }
  }, "Couldn't restore purchases. Try again.");

  Future<void> _redeem() => _run(
    () => SubscriptionService.redeemCode(widget.uid),
    "Couldn't open code redemption. Try again.",
  );

  @override
  Widget build(BuildContext context) => onboardingLight(
    Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: FutureBuilder(
          future: _plans,
          builder: (context, snapshot) {
            final plans = snapshot.data ?? const <PremiumPlan>[];
            final selected = plans
                .where((plan) => plan.yearly == _yearly)
                .firstOrNull;
            return Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Settings',
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                    icon: const Icon(Icons.settings_outlined, color: _grey),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    children: [
                      _header(selected),
                      const SizedBox(height: 18),
                      ..._features,
                      if (snapshot.hasError)
                        _LoadFailed(
                          onRetry: () => setState(() {
                            _plans = _load();
                          }),
                        )
                      else if (!snapshot.hasData)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        for (final plan in plans)
                          _PlanTile(
                            plan: plan,
                            saving: plan.yearly ? _saving(plans) : null,
                            selected: plan == selected,
                            onTap: () => setState(() => _yearly = plan.yearly),
                          ),
                    ],
                  ),
                ),
                _footer(selected),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _header(PremiumPlan? selected) {
    final (title, body) = switch (widget.ended) {
      PremiumEnded.trial => (
        'Your free trial has ended',
        'Your data is safe. Subscribe to pick up where you left off.',
      ),
      PremiumEnded.subscription => (
        'Your subscription has ended',
        'Your data is safe. Subscribe to pick up where you left off.',
      ),
      null => (
        selected?.freeTrial == null
            ? 'Subscribe to Vivordo'
            : 'Try Vivordo free for ${_trialLength(selected!.freeTrial!, article: true)}',
        'Everything Vivordo does, from day one.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.2,
            color: _ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: const TextStyle(fontSize: 15, height: 1.45, color: _grey),
        ),
      ],
    );
  }

  static const _features = [
    _Feature('Capacity, Demand and Effort every day'),
    _Feature('My Day plans and ways to lighten it'),
    _Feature('Burnout check and weekly review'),
    _Feature('Vivordo AI, up to 100 messages a day'),
    _Feature('Sleep, stress, fitness and Circle'),
  ];

  Widget _footer(PremiumPlan? selected) {
    final trial = selected?.freeTrial;
    final period = selected?.yearly == true ? 'year' : 'month';
    final terms = selected == null
        ? null
        : '${trial == null ? '${selected.price} a $period.' : 'Free for ${_trialLength(trial)}, then ${selected.price} a $period.'} '
              'Renews automatically unless cancelled at least 24 hours '
              'before the period ends. Cancel anytime in Settings → '
              'Apple ID → Subscriptions.';
    final linkStyle = const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: _purple,
    );
    Widget link(String label, VoidCallback? onTap) => TextButton(
      onPressed: _busy ? null : onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 36),
      ),
      child: Text(label, style: linkStyle),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: selected == null || _busy
                  ? null
                  : () => _subscribe(selected),
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                disabledBackgroundColor: const Color(0xFFD1CEFF),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      switch ((selected, trial)) {
                        (null, _) => 'Subscribe',
                        (_, (1, final unit)) => 'Start free $unit',
                        (_, (_, _)) => 'Start free trial',
                        (final plan?, null) =>
                          'Subscribe for ${plan.price}/$period',
                      },
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          if (terms != null) ...[
            const SizedBox(height: 8),
            Text(
              terms,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.4, color: _grey),
            ),
          ],
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              link('Restore purchases', _restore),
              link('Redeem code', _redeem),
              link(
                'Terms',
                () => openVivordoLink(context, Uri.parse(vivordoTermsUrl)),
              ),
              link(
                'Privacy',
                () => openVivordoLink(context, Uri.parse(vivordoPrivacyUrl)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Save 42%": the yearly plan against twelve months of the monthly one.
int? _saving(List<PremiumPlan> plans) {
  final yearly = plans.where((plan) => plan.yearly).firstOrNull;
  final monthly = plans.where((plan) => !plan.yearly).firstOrNull;
  if (yearly == null || monthly == null || monthly.amount <= 0) return null;
  final saving = (100 * (1 - yearly.amount / (monthly.amount * 12))).round();
  return saving > 0 ? saving : null;
}

/// "1 month", or with [article] "a month".
String _trialLength((int, String) trial, {bool article = false}) =>
    switch (trial) {
      (1, final unit) => article ? 'a $unit' : '1 $unit',
      (final count, final unit) => '$count ${unit}s',
    };

class _Feature extends StatelessWidget {
  const _Feature(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_rounded, size: 20, color: _green),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, height: 1.35, color: _ink),
          ),
        ),
      ],
    ),
  );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.saving,
    required this.selected,
    required this.onTap,
  });

  final PremiumPlan plan;
  final int? saving;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The billed amount leads (App Review 3.1.2); savings, the monthly
    // equivalent and the free period follow in smaller type.
    final trial = plan.freeTrial;
    final details = [
      plan.yearly ? 'Yearly' : 'Monthly',
      if (plan.yearly && plan.perMonth != null) '${plan.perMonth}/month',
      if (saving != null) 'Save $saving%',
      // Non-breaking spaces keep "1 month free" on one line.
      if (trial != null)
        '${_trialLength(trial)} free'.replaceAll(' ', '\u00A0'),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFEEEDFE) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? _purple : _line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${plan.price}/${plan.yearly ? 'year' : 'month'}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        style: const TextStyle(fontSize: 13, color: _grey),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? _purple : const Color(0xFFC7C7CC),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        const Text(
          "Couldn't load plans. Check your connection.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: _grey),
        ),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
