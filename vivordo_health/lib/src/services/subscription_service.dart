import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Whether Vivordo is locked behind the paywall for this account.
///
/// [config] is `app_config/premium`: nothing is locked until its `required`
/// is true (the launch switch, also enforced by the server's
/// requirePremium). [subscription] is `subscriptions/{uid}`, written only by
/// the server from RevenueCat. A missing document read from the cache
/// ([fromCache]) isn't proof of no subscription, so it doesn't lock.
bool premiumLocked({
  required Map<String, dynamic>? config,
  required Map<String, dynamic>? subscription,
  required bool fromCache,
  required DateTime now,
}) {
  if (config?['required'] != true) return false;
  if (subscription == null) return !fromCache;
  if (subscription['active'] != true) return true;
  final expires = (subscription['expiresAt'] as Timestamp?)?.toDate();
  return expires != null && !expires.isAfter(now);
}

/// One plan on the paywall, in the store's own currency.
class PremiumPlan {
  const PremiumPlan({
    required this.yearly,
    required this.price,
    required this.amount,
    this.perMonth,
    this.freeTrial,
    this.package,
  });

  final bool yearly;

  /// Localized price, like "$69.99".
  final String price;
  final double amount;

  /// A yearly plan's price per month, like "$5.83".
  final String? perMonth;

  /// Free intro period this account can still get, like (1, "month"); null
  /// when there's none or the Apple ID already used it.
  final (int, String)? freeTrial;

  /// What RevenueCat buys; null only in tests.
  final Package? package;
}

/// The Vivordo subscription through RevenueCat. The app user id is the Firebase uid,
/// so RevenueCat's webhook and the refreshSubscription function write the
/// result to `subscriptions/{uid}`, which unlocks the app.
class SubscriptionService {
  /// RevenueCat's public iOS key ("appl_…"). Not a secret.
  static const appleApiKey = 'appl_WngvVygZUiJqbPFRnhdBAIkkPsu';

  /// RevenueCat's Test Store key: pretend purchases of the dashboard's
  /// products, no App Store needed. Debug builds only; RevenueCat refuses
  /// Test Store purchases in a release.
  // ponytail: debug builds always use the Test Store; switch to
  // appleApiKey here to test StoreKit sandbox purchases from Xcode.
  static const _testStoreKey = 'test_PuLaSpEkCSqWpxIJcxaCLWrNYyC';

  static String get _apiKey => kDebugMode ? _testStoreKey : appleApiKey;

  /// The entitlement's identifier in RevenueCat, as in functions/
  /// subscription.js.
  static const entitlement = 'vivordo_premium';

  static String? _uid;
  static Future<void>? _setup;

  /// Configures RevenueCat for [uid] once per signed-in account, so StoreKit
  /// renewals and codes redeemed outside the app reach RevenueCat.
  static Future<void> signIn(String uid) {
    if (_apiKey.isEmpty) {
      return Future.error(StateError('RevenueCat key not set'));
    }
    if (_uid != uid) {
      _uid = uid;
      _setup = _configure(uid).onError((Object error, stack) {
        _uid = null;
        Error.throwWithStackTrace(error, stack);
      });
    }
    return _setup!;
  }

  static Future<void> _configure(String uid) async {
    if (await Purchases.isConfigured) {
      await Purchases.logIn(uid);
    } else {
      await Purchases.configure(
        PurchasesConfiguration(_apiKey)..appUserID = uid,
      );
    }
  }

  /// The yearly and monthly plans of the current offering, yearly first.
  static Future<List<PremiumPlan>> plans(String uid) async {
    await signIn(uid);
    final offering = (await Purchases.getOfferings()).current;
    final packages = [?offering?.annual, ?offering?.monthly];
    if (packages.isEmpty) throw StateError('No current offering');
    final eligibility =
        await Purchases.checkTrialOrIntroductoryPriceEligibility([
          for (final p in packages) p.storeProduct.identifier,
        ]);
    return [
      for (final p in packages)
        PremiumPlan(
          yearly: p.packageType == PackageType.annual,
          price: p.storeProduct.priceString,
          amount: p.storeProduct.price,
          perMonth: p.storeProduct.pricePerMonthString,
          freeTrial: _freeTrial(
            p.storeProduct.introductoryPrice,
            eligibility[p.storeProduct.identifier]?.status,
          ),
          package: p,
        ),
    ];
  }

  // Only an intro offer Apple confirms this Apple ID can still get counts,
  // so the paywall never promises a free month Apple then charges for.
  static (int, String)? _freeTrial(
    IntroductoryPrice? intro,
    IntroEligibilityStatus? status,
  ) {
    if (intro == null ||
        intro.price != 0 ||
        status != IntroEligibilityStatus.introEligibilityStatusEligible) {
      return null;
    }
    final unit = switch (intro.periodUnit) {
      PeriodUnit.day => 'day',
      PeriodUnit.week => 'week',
      PeriodUnit.month => 'month',
      PeriodUnit.year => 'year',
      _ => null,
    };
    return unit == null ? null : (intro.periodNumberOfUnits, unit);
  }

  /// Buys [plan]. False when the person cancelled Apple's sheet.
  static Future<bool> purchase(String uid, PremiumPlan plan) async {
    await signIn(uid);
    try {
      await Purchases.purchase(PurchaseParams.package(plan.package!));
    } on PlatformException catch (error) {
      if (PurchasesErrorHelper.getErrorCode(error) ==
          PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      rethrow;
    }
    await refresh();
    return true;
  }

  /// Restores an earlier purchase on this Apple ID. True when that gives
  /// this account Premium.
  static Future<bool> restore(String uid) async {
    await signIn(uid);
    final info = await Purchases.restorePurchases();
    await refresh();
    return info.entitlements.active.containsKey(entitlement);
  }

  /// Apple's offer code sheet. The redemption arrives through RevenueCat's
  /// webhook, which unlocks the app.
  static Future<void> redeemCode(String uid) async {
    await signIn(uid);
    await Purchases.presentCodeRedemptionSheet();
  }

  /// Asks the server to re-read RevenueCat (the webhook does this too), so
  /// a purchase unlocks without waiting, and a staff email on the list is
  /// granted access. Never throws.
  static Future<void> refresh() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('refreshSubscription')
          .call<void>();
    } catch (error) {
      debugPrint('refreshSubscription failed: $error');
    }
  }
}
