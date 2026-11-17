import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app/config.dart';
import '../data/ads.dart';
import '../data/billing.dart';
import '../data/blendr_api.dart';
import '../data/color_source.dart';
import '../data/google_auth.dart';
import '../data/session_store.dart';

/// Infrastructure providers. Tests override these with fakes.

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Current time; overridden in tests.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Palettes are generated and named on the device: instant and offline.
final colorSourceProvider = Provider<ColorSource>((ref) => LocalColorSource());

/// Play purchases through RevenueCat. Unavailable without a key, and in
/// release builds with a Test Store key (the SDK would crash on purpose).
final billingProvider = Provider<Billing>(
  (ref) =>
      canSellWith(AppConfig.revenueCatGoogleKey, releaseBuild: kReleaseMode)
      ? RevenueCatBilling(AppConfig.revenueCatGoogleKey)
      : const UnavailableBilling(),
);

/// Full-screen ads for free accounts: Google's test ads in debug builds.
final adsProvider = Provider<Ads>((ref) {
  final unit = interstitialUnitFor(
    AppConfig.adMobInterstitialId,
    releaseBuild: kReleaseMode,
  );
  return unit == null ? const NoAds() : AdMobAds(unit);
});

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

final googleAuthProvider = Provider<GoogleAuth>(
  (ref) => PlatformGoogleAuth(serverClientId: AppConfig.googleServerClientId),
);

final blendrApiProvider = Provider<BlendrApi>((ref) {
  final sessions = ref.watch(sessionStoreProvider);
  return BlendrApi(
    client: ref.watch(httpClientProvider),
    baseUrl: AppConfig.apiBaseUrl,
    sessionToken: () => sessions.token,
  );
});
