import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';
import 'providers.dart';

final adsControllerProvider = NotifierProvider<AdsController, AdsState>(
  AdsController.new,
);

class AdsState {
  const AdsState({this.privacyOptionsRequired = false});

  /// Show "Ad privacy choices" in Settings (required in the EEA and UK).
  final bool privacyOptionsRequired;
}

/// Free accounts (and signed-out users) see a full-screen ad every [every]th
/// palette they generate. Pro has no ads.
class AdsController extends Notifier<AdsState> {
  /// Ads come after this many generates.
  static const every = 5;

  /// Never two ads closer together than this, however fast someone taps.
  /// AdMob's policies rule out ads after every few taps, and it keeps the app
  /// pleasant. Set to zero for strictly every fifth generate.
  static const minGap = Duration(seconds: 60);

  int _generates = 0;
  DateTime? _lastAd;
  bool _prepared = false;
  bool _showing = false;

  @override
  AdsState build() => const AdsState();

  /// Free and the plan is known (a Pro account still loading shows no ads).
  bool get _showsAds {
    final auth = ref.read(authProvider);
    return auth.hasValue && !(auth.value?.isPro ?? false);
  }

  /// Asks for consent and loads the first ad, once we know this user sees
  /// ads. Called when the plan is known, and again before each count.
  Future<void> prepare() async {
    if (_prepared || !_showsAds) return;
    _prepared = true;
    final ads = ref.read(adsProvider);
    await ads.prepare();
    if (!ref.mounted) return;
    state = AdsState(privacyOptionsRequired: ads.privacyOptionsRequired);
  }

  /// Counts a palette the user asked for. Returns true once they have
  /// watched and closed an ad, so the caller can offer to remove ads.
  ///
  /// If no ad is loaded when one is due (offline, no fill), the next
  /// generate tries again.
  Future<bool> generated() async {
    if (!_showsAds || _showing) return false;
    unawaited(prepare());
    _generates++;
    if (_generates < every) return false;
    final now = ref.read(clockProvider)();
    final last = _lastAd;
    if (last != null && now.difference(last) < minGap) return false;
    final ads = ref.read(adsProvider);
    if (!ads.isReady) return false;

    _showing = true;
    try {
      final shown = await ads.show();
      if (shown) {
        _generates = 0;
        _lastAd = ref.read(clockProvider)();
      }
      return shown;
    } finally {
      _showing = false;
    }
  }

  Future<void> showPrivacyOptions() async {
    final ads = ref.read(adsProvider);
    await ads.showPrivacyOptions();
    if (!ref.mounted) return;
    state = AdsState(privacyOptionsRequired: ads.privacyOptionsRequired);
  }
}
