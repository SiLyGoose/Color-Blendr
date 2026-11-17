import 'package:color_blendr/data/ads.dart';
import 'package:color_blendr/data/session_store.dart';
import 'package:color_blendr/state/ads_controller.dart';
import 'package:color_blendr/state/auth_controller.dart';
import 'package:color_blendr/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late DateTime now;
  late FakeAds ads;

  Future<ProviderContainer> start({FakeServer? signedIn}) async {
    final container = ProviderContainer(
      overrides: [
        adsProvider.overrideWithValue(ads),
        clockProvider.overrideWithValue(() => now),
        sessionStoreProvider.overrideWithValue(
          MemorySessionStore(signedIn?.session),
        ),
        if (signedIn != null)
          httpClientProvider.overrideWithValue(signedIn.client),
        billingProvider.overrideWithValue(FakeBilling()),
        googleAuthProvider.overrideWithValue(FakeGoogleAuth()),
        await testPreferences(),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    // Keep auth alive, as the app's screens do.
    container.listen(authProvider, (_, _) {});
    await container.read(authProvider.future);
    return container;
  }

  /// Generates [n] palettes; returns how many of them ended with an ad.
  Future<int> generate(ProviderContainer c, int n) async {
    var watched = 0;
    for (var i = 0; i < n; i++) {
      if (await c.read(adsControllerProvider.notifier).generated()) watched++;
    }
    return watched;
  }

  setUp(() {
    now = DateTime(2026, 11, 17, 12);
    ads = FakeAds();
  });

  test('signed out: an ad on every fifth generate', () async {
    final c = await start();
    expect(await generate(c, 4), 0);
    expect(await generate(c, 1), 1);
    expect(ads.prepares, 1);

    now = now.add(const Duration(minutes: 5));
    expect(await generate(c, 4), 0);
    expect(await generate(c, 1), 1);
    expect(ads.shows, 2);
  });

  test('never two ads within a minute', () async {
    final c = await start();
    expect(await generate(c, 5), 1);

    now = now.add(const Duration(seconds: 30));
    expect(await generate(c, 10), 0, reason: 'too soon after the last ad');

    now = now.add(AdsController.minGap);
    expect(await generate(c, 1), 1, reason: 'already past five generates');
  });

  test('an ad that is not loaded yet shows on a later generate', () async {
    final c = await start();
    ads.ready = false;
    expect(await generate(c, 6), 0);
    ads.ready = true;
    expect(await generate(c, 1), 1);
    expect(await generate(c, 4), 0, reason: 'the count starts over');
  });

  test('free accounts see ads', () async {
    final c = await start(signedIn: FakeServer());
    expect(await generate(c, 5), 1);
  });

  test('Pro never sees ads or loads the ad SDK', () async {
    final c = await start(signedIn: FakeServer(pro: true));
    await c.read(adsControllerProvider.notifier).prepare();
    expect(await generate(c, 20), 0);
    expect(ads.prepares, 0);
    expect(ads.shows, 0);
  });

  test('a debug build without an ad unit uses Google test ads; release shows '
      'none', () {
    expect(
      interstitialUnitFor('', releaseBuild: false),
      testInterstitialUnitId,
    );
    expect(interstitialUnitFor('', releaseBuild: true), isNull);
    expect(
      interstitialUnitFor('ca-app-pub-1/2', releaseBuild: true),
      'ca-app-pub-1/2',
    );
  });
}
