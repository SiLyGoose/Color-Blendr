import 'package:color_blendr/app/app.dart';
import 'package:color_blendr/data/ads.dart';
import 'package:color_blendr/data/billing.dart';
import 'package:color_blendr/data/models.dart';
import 'package:color_blendr/data/session_store.dart';
import 'package:color_blendr/state/providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';

void main() {
  /// Starts the app signed in to [server], with [billing] (default: a
  /// working Play store selling Pro for $1.99/week).
  Future<FakeServer> pumpSignedIn(
    WidgetTester tester,
    FakeServer server, {
    Billing? billing,
    Ads ads = const NoAds(),
  }) async {
    final source = FakeColorSource([
      for (final d in '0123456789ab'.split(''))
        [
          color('2b301$d', 'Rangitoto'),
          color('b0bef$d', 'Perano'),
          color('8205a$d', 'Purple'),
        ],
    ]);
    final prefs = await testPreferences();
    // Clipboard and haptics: answer instead of waiting on a platform that isn't there.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          colorSourceProvider.overrideWithValue(source),
          sessionStoreProvider.overrideWithValue(
            MemorySessionStore(server.session),
          ),
          googleAuthProvider.overrideWithValue(FakeGoogleAuth()),
          httpClientProvider.overrideWithValue(server.client),
          billingProvider.overrideWithValue(billing ?? FakeBilling()),
          adsProvider.overrideWithValue(ads),
          prefs,
        ],
        child: const BlendrApp(),
      ),
    );
    await tester.pumpAndSettle();
    return server;
  }

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  Finder inSheet(String text) =>
      find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

  Future<void> openTool(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('More tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  void seed(FakeServer server, int n) {
    for (var i = 0; i < n; i++) {
      server.seedPalette('Saved $i', [color('00000$i'), color('ffffff')]);
    }
  }

  testWidgets('a full free library shows the upgrade sheet instead of saving', (
    tester,
  ) async {
    final server = FakeServer(limit: 2);
    seed(server, 2);
    await pumpSignedIn(tester, server);

    await tester.tap(find.byTooltip('Save to library'));
    await tester.pumpAndSettle();

    expect(find.text('Your library is full'), findsOneWidget);
    expect(find.textContaining('keep up to 2 palettes'), findsOneWidget);
    expect(server.requests, isNot(contains('POST /v1/palettes')));
  });

  testWidgets('the server refusing a save also shows the upgrade sheet', (
    tester,
  ) async {
    // The app last saw Pro (no limit), but Pro has since ended and the
    // server says the library is full.
    final server = FakeServer(pro: true);
    await pumpSignedIn(tester, server);
    server
      ..pro = false
      ..limit = 0;

    await tester.tap(find.byTooltip('Save to library'));
    await tester.pumpAndSettle();
    expect(find.text('Your library is full'), findsOneWidget);
  });

  testWidgets(
    'free accounts get the upgrade sheet for accessibility and photos',
    (tester) async {
      await pumpSignedIn(tester, FakeServer());

      await openTool(tester, 'Check accessibility');
      expect(inSheet('Color Blendr Pro'), findsOneWidget);
      expect(find.text('Text contrast'), findsNothing);

      Navigator.of(tester.element(inSheet('Color Blendr Pro'))).pop();
      await tester.pumpAndSettle();
      await openTool(tester, 'Palette from photo');
      expect(
        find.textContaining('Pull a palette out of any photo'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Pro opens the accessibility check', (tester) async {
    await pumpSignedIn(tester, FakeServer(pro: true));
    await openTool(tester, 'Check accessibility');
    expect(find.text('Color vision'), findsOneWidget);
    expect(find.text('Deuteranopia'), findsOneWidget);
  });

  testWidgets('export: hex codes are free, CSS is Pro', (tester) async {
    await pumpSignedIn(tester, FakeServer());
    await openTool(tester, 'Export');

    await tester.tap(find.text('CSS variables'));
    await tester.pumpAndSettle();
    expect(find.text('Export anywhere'), findsOneWidget);
    Navigator.of(tester.element(find.text('Export anywhere'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hex codes'));
    await tester.pumpAndSettle();
    expect(find.text('Copied 3 hex codes'), findsOneWidget);
  });

  testWidgets('Pro sees the CSS export', (tester) async {
    await pumpSignedIn(tester, FakeServer(pro: true));
    await openTool(tester, 'Export');
    await tester.tap(find.text('CSS variables'));
    await tester.pumpAndSettle();
    expect(find.textContaining('--rangitoto: #2b3010;'), findsOneWidget);
  });

  testWidgets('the library shows how full a free account is', (tester) async {
    final server = FakeServer();
    seed(server, 3);
    await pumpSignedIn(tester, server);
    await tester.tap(tab('Library'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 10 free saves used'), findsOneWidget);
  });

  testWidgets('Pro has no usage banner and can file palettes into folders', (
    tester,
  ) async {
    final server = FakeServer(pro: true);
    seed(server, 1);
    await pumpSignedIn(tester, server);
    await tester.tap(tab('Library'));
    await tester.pumpAndSettle();
    expect(find.textContaining('free saves used'), findsNothing);

    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Brand');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(server.folders.single['name'], 'Brand');
    expect(
      find.text('Nothing here yet'),
      findsOneWidget,
      reason: 'opens the new, empty folder',
    );

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Palette options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to folder'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Brand'));
    await tester.pumpAndSettle();

    expect(server.palettes.single['folderId'], server.folders.single['id']);
    expect(find.text('Palette · 2 colors · Brand'), findsOneWidget);
  });

  testWidgets('free accounts get the upgrade sheet for folders', (
    tester,
  ) async {
    await pumpSignedIn(tester, FakeServer());
    await tester.tap(tab('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    expect(find.text('Organize with folders'), findsOneWidget);
  });

  testWidgets('settings shows the plan', (tester) async {
    await pumpSignedIn(tester, FakeServer(pro: true));
    await tester.tap(tab('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Color Blendr Pro'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('the upgrade sheet closes with its close button', (tester) async {
    await pumpSignedIn(tester, FakeServer());
    await openTool(tester, 'Check accessibility');
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  group('buying Pro', () {
    const weekly = StoreSubscription(productId: 'pro:weekly', willRenew: true);

    Future<void> openPaywall(WidgetTester tester) async {
      await openTool(tester, 'Check accessibility');
    }

    Finder buyButton() => find.text('Get Pro · \$19.99/year');

    testWidgets('offers every plan with the terms Play requires', (
      tester,
    ) async {
      final billing = FakeBilling();
      await pumpSignedIn(tester, FakeServer(), billing: billing);
      await openPaywall(tester);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Yearly'), findsOneWidget);
      expect(find.text('Lifetime'), findsOneWidget);
      expect(find.text('Save 44%'), findsOneWidget);

      // Yearly is picked to start with.
      expect(buyButton(), findsOneWidget);
      expect(
        find.text(
          '\$19.99 per year, renews automatically. Cancel anytime in Google Play.',
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Lifetime'));
      await tester.tap(find.text('Lifetime'));
      await tester.pumpAndSettle();
      expect(find.text('Get Pro · \$39.99'), findsOneWidget);
      expect(
        find.text('\$39.99 once. One-time purchase, no subscription.'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Get Pro · \$39.99'));
      await tester.tap(find.text('Get Pro · \$39.99'));
      await tester.pumpAndSettle();
      expect(billing.calls, contains('buy Lifetime'));
    });

    testWidgets('a purchase is confirmed by the API, then unlocks Pro', (
      tester,
    ) async {
      final server = FakeServer();
      final billing = FakeBilling(
        onBuy: () async {
          server.storePurchase = weekly;
          return true;
        },
      );
      await pumpSignedIn(tester, server, billing: billing);
      expect(
        billing.calls,
        contains('identify u1'),
        reason: 'tied to our account id',
      );

      await openPaywall(tester);
      await tester.ensureVisible(buyButton());
      await tester.tap(buyButton());
      await tester.pumpAndSettle();

      expect(server.requests, contains('POST /v1/billing/sync'));
      expect(find.text('Welcome to Pro!'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing, reason: 'sheet closed');

      // Pro tools now open directly.
      await openTool(tester, 'Check accessibility');
      expect(find.text('Color vision'), findsOneWidget);
    });

    testWidgets('Pro waits for the API, never for the store', (tester) async {
      // The store says "purchased" but RevenueCat has nothing: no Pro.
      final server = FakeServer();
      await pumpSignedIn(tester, server, billing: FakeBilling());
      await openPaywall(tester);
      await tester.ensureVisible(buyButton());
      await tester.tap(buyButton());
      await tester.pump();
      expect(find.text('Purchase received, activating…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();

      expect(
        server.requests.where((r) => r == 'POST /v1/billing/sync'),
        hasLength(2),
        reason: 'asks again after the API cooldown',
      );
      expect(
        find.text('Purchase received. Pro will turn on in a minute or two.'),
        findsOneWidget,
      );
      await tester.tap(tab('Settings'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Free plan'), findsOneWidget);
    });

    testWidgets('a slow store check is retried once', (tester) async {
      final server = FakeServer()..syncLag = 1;
      final billing = FakeBilling(
        onBuy: () async {
          server.storePurchase = weekly;
          return true;
        },
      );
      await pumpSignedIn(tester, server, billing: billing);
      await openPaywall(tester);
      await tester.ensureVisible(buyButton());
      await tester.tap(buyButton());
      await tester.pump();
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Pro!'), findsOneWidget);
    });

    testWidgets('backing out of Play does nothing', (tester) async {
      final server = FakeServer();
      await pumpSignedIn(
        tester,
        server,
        billing: FakeBilling(onBuy: () async => false),
      );
      await openPaywall(tester);
      await tester.ensureVisible(buyButton());
      await tester.tap(buyButton());
      await tester.pumpAndSettle();
      expect(server.requests, isNot(contains('POST /v1/billing/sync')));
      expect(buyButton(), findsOneWidget, reason: 'sheet stays open');
    });

    testWidgets('store errors are shown', (tester) async {
      await pumpSignedIn(
        tester,
        FakeServer(),
        billing: FakeBilling(
          onBuy: () async =>
              throw const BillingException('Google Play had a problem.'),
        ),
      );
      await openPaywall(tester);
      await tester.ensureVisible(buyButton());
      await tester.tap(buyButton());
      await tester.pumpAndSettle();
      expect(find.text('Google Play had a problem.'), findsOneWidget);
    });

    testWidgets('nothing for sale in Play shows a retry', (tester) async {
      final billing = FakeBilling()..offers = const [];
      await pumpSignedIn(tester, FakeServer(), billing: billing);
      await openPaywall(tester);
      expect(find.text('Couldn’t load Pro from Google Play.'), findsOneWidget);
      billing.offers = fakeOffers;
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(buyButton(), findsOneWidget);
    });

    testWidgets('builds without a store key say purchases are unavailable', (
      tester,
    ) async {
      await pumpSignedIn(
        tester,
        FakeServer(),
        billing: FakeBilling(isAvailable: false),
      );
      await openPaywall(tester);
      expect(
        find.text('Purchases aren’t available in this build'),
        findsOneWidget,
      );
    });

    testWidgets('signing out signs the store out too', (tester) async {
      final billing = FakeBilling();
      await pumpSignedIn(tester, FakeServer(), billing: billing);
      await tester.tap(tab('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(billing.calls.last, 'signOut');
    });
  });

  group('subscription in settings', () {
    Future<void> openSettings(
      WidgetTester tester,
      StoreSubscription sub, {
      Map<String, dynamic>? webSubscription,
    }) async {
      final server = FakeServer(pro: true)
        ..storePurchase = sub
        ..webSubscription = webSubscription;
      await pumpSignedIn(tester, server);
      await tester.tap(tab('Settings'));
      await tester.pumpAndSettle();
    }

    testWidgets('renewing', (tester) async {
      await openSettings(
        tester,
        StoreSubscription(
          expiresAt: DateTime(2026, 12, 4, 12),
          willRenew: true,
        ),
      );
      expect(find.text('Renews on Dec 4, 2026'), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
      expect(find.text('Payment problem'), findsNothing);
    });

    testWidgets('cancelled, with a payment problem', (tester) async {
      await openSettings(
        tester,
        StoreSubscription(
          expiresAt: DateTime(2026, 12, 4, 12),
          billingIssue: true,
        ),
      );
      expect(find.text('Ends on Dec 4, 2026'), findsOneWidget);
      expect(find.text('Payment problem'), findsOneWidget);
    });

    testWidgets('lifetime has nothing to manage', (tester) async {
      await openSettings(
        tester,
        const StoreSubscription(productId: 'lifetime'),
      );
      expect(find.text('Lifetime'), findsOneWidget);
      expect(find.text('Manage subscription'), findsNothing);
    });

    testWidgets('deleting the account warns that Play keeps charging', (
      tester,
    ) async {
      await openSettings(
        tester,
        StoreSubscription(
          expiresAt: DateTime(2026, 12, 4, 12),
          willRenew: true,
        ),
      );
      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('doesn’t cancel your Google Play subscription'),
        findsOneWidget,
      );
    });

    final webSub = StoreSubscription(
      expiresAt: DateTime(2026, 12, 4, 12),
      willRenew: true,
      store: 'stripe',
    );

    testWidgets('bought on the web: details instead of Google Play', (
      tester,
    ) async {
      await openSettings(tester, webSub);
      expect(find.text('Renews on Dec 4, 2026'), findsOneWidget);
      expect(find.text('Subscription details'), findsOneWidget);
      expect(find.text('Manage subscription'), findsNothing);
      expect(find.text('Change or cancel in Google Play'), findsNothing);

      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Cancel it first in Subscription details'),
        findsOneWidget,
      );
      // The dialog only: the settings list behind it has "Rate Color Blendr".
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Google Play'),
        ),
        findsNothing,
      );
    });

    testWidgets('web subscription details: plan, next payment, invoices', (
      tester,
    ) async {
      await openSettings(
        tester,
        webSub,
        webSubscription: {
          'status': 'active',
          'plan': 'yearly',
          'amount': 3599,
          'currency': 'usd',
          'interval': 'year',
          'currentPeriodEnd': DateTime(2027, 11, 19, 12).toIso8601String(),
          'cancelAt': null,
          'endedAt': null,
          'invoices': [
            {
              'id': 'in_2',
              'date': DateTime(2026, 11, 19, 12).toIso8601String(),
              'amount': 3599,
              'currency': 'usd',
              'status': 'paid',
              'refunded': false,
              'url': 'https://invoice.stripe.com/i/paid',
            },
            {
              'id': 'in_1',
              'date': DateTime(2026, 10, 19, 12).toIso8601String(),
              'amount': 499,
              'currency': 'usd',
              'status': 'open',
              'refunded': false,
              'url': 'https://invoice.stripe.com/i/open',
            },
          ],
        },
      );
      await tester.tap(find.text('Subscription details'));
      await tester.pumpAndSettle();

      expect(inSheet('Color Blendr Pro · Yearly'), findsOneWidget);
      expect(inSheet('\$35.99 per year'), findsOneWidget);
      expect(inSheet('Active'), findsOneWidget);
      expect(
        inSheet('Next payment: \$35.99 on November 19, 2027.'),
        findsOneWidget,
      );
      expect(inSheet('Paid'), findsOneWidget);
      expect(inSheet('Due'), findsOneWidget);

      ListTile row(String date) => tester.widget<ListTile>(
        find.ancestor(of: inSheet(date), matching: find.byType(ListTile)),
      );
      expect(row('Nov 19, 2026').onTap, isNotNull, reason: 'paid: receipt');
      expect(
        row('Oct 19, 2026').onTap,
        isNull,
        reason: 'unpaid: Stripe’s page would ask for payment',
      );
    });

    testWidgets('web subscription details: cancelled', (tester) async {
      await openSettings(
        tester,
        webSub,
        webSubscription: {
          'status': 'active',
          'amount': 499,
          'currency': 'usd',
          'interval': 'month',
          'currentPeriodEnd': DateTime(2026, 12, 4, 12).toIso8601String(),
          'cancelAt': DateTime(2026, 12, 4, 12).toIso8601String(),
          'invoices': <Object>[],
        },
      );
      await tester.tap(find.text('Subscription details'));
      await tester.pumpAndSettle();

      expect(inSheet('Cancelled'), findsOneWidget);
      expect(
        inSheet(
          'Cancelled. You keep Pro until December 4, 2026, and won’t be charged again.',
        ),
        findsOneWidget,
      );
      expect(inSheet('No invoices yet.'), findsOneWidget);
    });

    Map<String, dynamic> monthly() => {
      'status': 'active',
      'amount': 499,
      'currency': 'usd',
      'interval': 'month',
      'currentPeriodEnd': DateTime(2026, 12, 4, 12).toIso8601String(),
      'cancelAt': null,
      'invoices': <Object>[],
    };

    Future<void> openDetails(WidgetTester tester) async {
      await tester.tap(find.text('Subscription details'));
      await tester.pumpAndSettle();
    }

    testWidgets('cancelling from the app, after confirming', (tester) async {
      await openSettings(tester, webSub, webSubscription: monthly());
      await openDetails(tester);

      await tester.tap(find.text('Change subscription'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'To switch between monthly and yearly, or to change your '
          'card, use the Color Blendr website, under Account.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel subscription'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel your subscription?'), findsOneWidget);

      // Backing out changes nothing.
      await tester.tap(find.text('Keep Pro'));
      await tester.pumpAndSettle();
      expect(inSheet('Active'), findsOneWidget);

      await tester.tap(find.text('Change subscription'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel subscription'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel subscription'),
        ),
      );
      await tester.pumpAndSettle();

      expect(inSheet('Cancelled'), findsOneWidget);
      expect(
        inSheet(
          'Cancelled. You keep Pro until December 4, 2026, and won’t be charged again.',
        ),
        findsOneWidget,
      );
      // The Settings tile behind the sheet follows the API's new profile.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Ends on Dec 4, 2026'), findsOneWidget);
    });

    testWidgets('resuming a cancelled subscription from the app', (
      tester,
    ) async {
      await openSettings(
        tester,
        webSub,
        webSubscription: {
          ...monthly(),
          'cancelAt': DateTime(2026, 12, 4, 12).toIso8601String(),
        },
      );
      await openDetails(tester);
      await tester.tap(find.text('Change subscription'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel subscription'), findsNothing);
      await tester.tap(find.text('Keep my subscription'));
      await tester.pumpAndSettle();

      expect(inSheet('Active'), findsOneWidget);
      expect(
        inSheet('Next payment: \$4.99 on December 4, 2026.'),
        findsOneWidget,
      );
    });

    testWidgets('an ended subscription has nothing to change', (tester) async {
      await openSettings(
        tester,
        webSub,
        webSubscription: {...monthly(), 'status': 'canceled'},
      );
      await openDetails(tester);
      expect(inSheet('Ended'), findsOneWidget);
      expect(find.text('Change subscription'), findsNothing);
    });
  });
  group('ads', () {
    Future<void> generate(WidgetTester tester, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.text('Generate'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('free: an ad every fifth generate, then the offer to remove '
        'ads', (tester) async {
      final ads = FakeAds();
      await pumpSignedIn(tester, FakeServer(), ads: ads);
      expect(ads.prepares, 1, reason: 'loads the first ad up front');

      await generate(tester, 4);
      expect(ads.shows, 0);
      expect(find.text('Go ad-free'), findsNothing);

      await generate(tester, 1);
      expect(ads.shows, 1);
      expect(inSheet('Go ad-free'), findsOneWidget);
      expect(inSheet('No ads'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Go ad-free'), findsNothing);
    });

    testWidgets('Pro sees no ads', (tester) async {
      final ads = FakeAds();
      await pumpSignedIn(tester, FakeServer(pro: true), ads: ads);
      await generate(tester, 6);
      expect(ads.prepares, 0, reason: 'Pro never loads the ad SDK');
      expect(ads.shows, 0);
      expect(find.text('Go ad-free'), findsNothing);
    });

    testWidgets('no ad loaded: no offer either', (tester) async {
      final ads = FakeAds(ready: false);
      await pumpSignedIn(tester, FakeServer(), ads: ads);
      await generate(tester, 5);
      expect(ads.shows, 0);
      expect(find.text('Go ad-free'), findsNothing);
    });
  });
}
