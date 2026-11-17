import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Google Play purchases through RevenueCat.
///
/// This only buys. Whether the account has Pro is always read
/// back from the Color Blendr API (`POST /v1/billing/sync`), which checks with
/// RevenueCat using a secret key the app doesn't have. See
/// docs/monetization.md.
abstract class Billing {
  /// False when this build can't sell (no RevenueCat key, or a test key in a
  /// release build).
  bool get isAvailable;

  /// Ties purchases to our account id. Call after sign-in and on startup with
  /// a saved session. Never anonymous, so a purchase can't land on a
  /// RevenueCat id the API ignores.
  Future<void> identify(String userId);

  /// Call on sign-out and account deletion.
  Future<void> signOut();

  /// Everything Pro is sold as (e.g. monthly, yearly, lifetime), in the order
  /// to show them. Empty if there's nothing to buy.
  Future<List<ProOffer>> loadOffers();

  /// Opens Play's purchase dialog. Returns false if the user backed out.
  /// Throws [BillingException] on any other failure.
  Future<bool> buy(ProOffer offer);
}

class BillingException implements Exception {
  const BillingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One way to buy Pro. Play policy requires the paywall to show the price,
/// the billing period and the renewal terms.
@immutable
class ProOffer {
  const ProOffer({
    required this.title,
    required this.price,
    this.period,
    this.priceAmount,
    this.handle,
  });

  /// "Monthly", "Yearly", "Lifetime".
  final String title;

  /// Localized, e.g. "$1.99".
  final String price;

  /// "month", "year"… Null for a one-time purchase (lifetime).
  final String? period;

  /// The price as a number in the store currency, for comparing plans.
  final double? priceAmount;

  /// The store package to buy. Opaque outside [Billing].
  final Object? handle;

  bool get isLifetime => period == null;

  /// "$1.99/month", or just "$29.99" for lifetime.
  String get priceLabel => isLifetime ? price : '$price/$period';

  /// What the user agrees to, shown under the buy button.
  String get terms => isLifetime
      ? '$price once. One-time purchase, no subscription.'
      : '$price per $period, renews automatically. Cancel anytime in Google Play.';

  /// How much a yearly plan saves over paying [monthly] for twelve months,
  /// as a whole percentage, or null if it doesn't apply.
  int? savingsOver(ProOffer monthly) {
    final yearly = priceAmount, perMonth = monthly.priceAmount;
    if (period != 'year' || monthly.period != 'month') return null;
    if (yearly == null || perMonth == null || perMonth <= 0) return null;
    final percent = ((1 - yearly / (perMonth * 12)) * 100).floor();
    return percent >= 5 ? percent : null;
  }
}

/// For builds that can't sell: nothing to buy.
class UnavailableBilling implements Billing {
  const UnavailableBilling();

  @override
  bool get isAvailable => false;
  @override
  Future<void> identify(String userId) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<List<ProOffer>> loadOffers() async => const [];
  @override
  Future<bool> buy(ProOffer offer) async => false;
}

class RevenueCatBilling implements Billing {
  RevenueCatBilling(this._apiKey);

  /// RevenueCat's public SDK key (`goog_…`, or `test_…` for its Test Store in
  /// debug builds). Safe to ship.
  final String _apiKey;

  /// The account the SDK was set up for, so repeat calls are cheap.
  String? _userId;
  Future<void>? _configuring;

  @override
  bool get isAvailable => true;

  @override
  Future<void> identify(String userId) async {
    if (_userId == userId) return;
    await _guard(() async {
      if (await Purchases.isConfigured) {
        await Purchases.logIn(userId);
      } else {
        await (_configuring ??= Purchases.configure(
          PurchasesConfiguration(_apiKey)..appUserID = userId,
        ));
      }
    });
    _userId = userId;
  }

  @override
  Future<void> signOut() async {
    if (_userId == null) return;
    _userId = null;
    try {
      if (await Purchases.isConfigured) await Purchases.logOut();
    } on PlatformException {
      // Already anonymous, or the SDK isn't ready: nothing to undo.
    }
  }

  @override
  Future<List<ProOffer>> loadOffers() => _guard(() async {
    final offering = (await Purchases.getOfferings()).current;
    if (offering == null) return const <ProOffer>[];
    final packages = [...offering.availablePackages]
      ..sort((a, b) => _order(a.packageType).compareTo(_order(b.packageType)));
    return [
      for (final p in packages)
        ProOffer(
          title: _title(p),
          price: p.storeProduct.priceString,
          period: _isOneTime(p)
              ? null
              : periodName(p.storeProduct.subscriptionPeriod),
          priceAmount: p.storeProduct.price,
          handle: p,
        ),
    ];
  });

  static bool _isOneTime(Package p) =>
      p.packageType == PackageType.lifetime ||
      p.storeProduct.productCategory == ProductCategory.nonSubscription ||
      p.storeProduct.subscriptionPeriod == null;

  /// Shorter commitments first, lifetime last.
  static int _order(PackageType type) => switch (type) {
    PackageType.weekly => 0,
    PackageType.monthly => 1,
    PackageType.twoMonth => 2,
    PackageType.threeMonth => 3,
    PackageType.sixMonth => 4,
    PackageType.annual => 5,
    PackageType.lifetime => 6,
    _ => 7,
  };

  static String _title(Package p) => switch (p.packageType) {
    PackageType.weekly => 'Weekly',
    PackageType.monthly => 'Monthly',
    PackageType.twoMonth => 'Every 2 months',
    PackageType.threeMonth => 'Every 3 months',
    PackageType.sixMonth => 'Every 6 months',
    PackageType.annual => 'Yearly',
    PackageType.lifetime => 'Lifetime',
    _ => p.storeProduct.title,
  };

  @override
  Future<bool> buy(ProOffer offer) async {
    final package = offer.handle;
    if (package is! Package) {
      throw const BillingException('That offer isn’t available.');
    }
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      return true;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return false;
      throw BillingException(describePurchaseError(code));
    }
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw BillingException(
        describePurchaseError(PurchasesErrorHelper.getErrorCode(e)),
      );
    }
  }
}

/// RevenueCat's SDK refuses to run with a Test Store key (`test_…`) in a
/// release build, and Play testing tracks are release builds. So those builds
/// don't sell rather than crash.
bool canSellWith(String key, {required bool releaseBuild}) =>
    key.isNotEmpty && !(releaseBuild && key.startsWith('test_'));

/// "P1W" → "week". Anything unexpected reads as "period".
@visibleForTesting
String periodName(String? iso) => switch (iso) {
  'P1W' || 'P7D' => 'week',
  'P1M' => 'month',
  'P2M' => '2 months',
  'P3M' => '3 months',
  'P6M' => '6 months',
  'P1Y' || 'P12M' => 'year',
  _ => 'period',
};

@visibleForTesting
String describePurchaseError(PurchasesErrorCode code) => switch (code) {
  PurchasesErrorCode.networkError =>
    'Couldn’t reach Google Play. Check your connection.',
  PurchasesErrorCode.paymentPendingError =>
    'Your payment is pending. Pro turns on once Google Play confirms it.',
  PurchasesErrorCode.purchaseNotAllowedError =>
    'Purchases aren’t allowed on this device or account.',
  PurchasesErrorCode.productAlreadyPurchasedError =>
    'This Google Play account already owns Pro. Reopen the app, or sign in '
        'with the Color Blendr account that bought it.',
  PurchasesErrorCode.productNotAvailableForPurchaseError =>
    'Pro isn’t available to buy right now.',
  PurchasesErrorCode.storeProblemError =>
    'Google Play had a problem. Try again in a moment.',
  PurchasesErrorCode.receiptInUseByOtherSubscriberError ||
  PurchasesErrorCode.receiptAlreadyInUseError =>
    'This Google Play purchase belongs to another Color Blendr account.',
  _ => 'The purchase didn’t go through. Try again.',
};
