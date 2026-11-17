import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google's sample interstitial unit: always fills with a labeled test ad.
/// https://developers.google.com/admob/android/test-ads
const testInterstitialUnitId = 'ca-app-pub-3940256099942544/1033173712';

/// The ad unit to show, or null for no ads. Debug builds always use Google's
/// test unit (clicking your own live ads can get the AdMob account banned).
/// Release builds use [configured], or show no ads if it's empty.
String? interstitialUnitFor(String configured, {required bool releaseBuild}) {
  if (configured.isEmpty) return null;
  return releaseBuild ? configured : testInterstitialUnitId;
}

/// Full-screen ads between generates, for free accounts.
abstract class Ads {
  /// Asks for consent where the law needs it (the EEA, the UK and
  /// Switzerland), starts the ad SDK and loads the first ad. Safe to call
  /// more than once.
  Future<void> prepare();

  /// Whether an ad is loaded and can be shown now.
  bool get isReady;

  /// Shows the loaded ad. Completes when the user closes it: true if it was
  /// shown, false if there was nothing to show. Loads the next one either way.
  Future<bool> show();

  /// Whether the user must be able to change their ad consent from the app
  /// (Settings → Ad privacy choices). Known after [prepare].
  bool get privacyOptionsRequired;

  /// Opens Google's consent form again.
  Future<void> showPrivacyOptions();
}

class NoAds implements Ads {
  const NoAds();

  @override
  Future<void> prepare() async {}
  @override
  bool get isReady => false;
  @override
  Future<bool> show() async => false;
  @override
  bool get privacyOptionsRequired => false;
  @override
  Future<void> showPrivacyOptions() async {}
}

/// AdMob interstitials, with Google's consent form (UMP).
class AdMobAds implements Ads {
  AdMobAds(this.unitId);

  final String unitId;

  /// AdMob drops a loaded interstitial after an hour; reload before then.
  static const _maxAge = Duration(minutes: 55);

  /// Wait this long after a failed load before trying again.
  static const _retryAfter = Duration(seconds: 30);

  Future<void>? _prepared;
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;

  InterstitialAd? _ad;
  DateTime? _loadedAt;
  bool _loading = false;
  DateTime? _failedAt;

  @override
  Future<void> prepare() => _prepared ??= _prepare();

  Future<void> _prepare() async {
    try {
      await _gatherConsent();
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      _privacyOptionsRequired =
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
      if (!_canRequestAds) return;
      await MobileAds.instance.initialize();
      _load();
    } catch (e) {
      // No ads is better than a broken app.
      debugPrint('Ads unavailable: $e');
    }
  }

  /// Updates what Google knows about consent, and shows the consent form if
  /// this user needs one and hasn't answered it yet.
  Future<void> _gatherConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired((error) {
        if (error != null) debugPrint('Consent form: ${error.message}');
        if (!done.isCompleted) done.complete();
      }),
      (error) {
        // Offline, say. Consent from an earlier launch still counts.
        debugPrint('Consent info: ${error.message}');
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  bool get _fresh =>
      _ad != null &&
      _loadedAt != null &&
      DateTime.now().difference(_loadedAt!) < _maxAge;

  @override
  bool get isReady {
    if (_fresh) return true;
    _load(); // Missing or stale: start the next one.
    return false;
  }

  void _load() {
    if (!_canRequestAds || _loading || _fresh) return;
    final failedAt = _failedAt;
    if (failedAt != null && DateTime.now().difference(failedAt) < _retryAfter) {
      return;
    }
    _ad?.dispose();
    _ad = null;
    _loading = true;
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _failedAt = null;
          _ad = ad;
          _loadedAt = DateTime.now();
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          _failedAt = DateTime.now();
          debugPrint('Ad failed to load: ${error.message}');
        },
      ),
    );
  }

  @override
  Future<bool> show() async {
    if (!_fresh) return false;
    final ad = _ad!;
    _ad = null;
    _loadedAt = null;
    final closed = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        debugPrint('Ad failed to show: ${error.message}');
        if (!closed.isCompleted) closed.complete(false);
      },
    );
    try {
      await ad.show();
    } catch (e) {
      ad.dispose();
      if (!closed.isCompleted) closed.complete(false);
    }
    final shown = await closed.future;
    _load();
    return shown;
  }

  @override
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  @override
  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) debugPrint('Privacy options: ${error.message}');
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    // Their answer decides whether ads may load at all.
    _canRequestAds = await ConsentInformation.instance.canRequestAds();
    if (_canRequestAds) {
      await MobileAds.instance.initialize();
      _load();
    }
  }
}
