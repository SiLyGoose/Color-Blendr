import 'dart:async';
import 'dart:convert';

import 'package:color_blendr/data/ads.dart';
import 'package:color_blendr/data/billing.dart';
import 'package:color_blendr/data/color_source.dart';
import 'package:color_blendr/data/google_auth.dart';
import 'package:color_blendr/data/models.dart';
import 'package:color_blendr/data/palette_style.dart';
import 'package:color_blendr/state/settings_controller.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

PaletteColor color(String hex, [String? name]) =>
    PaletteColor(hex: hex, name: name ?? 'Color $hex', textHex: '000000');

/// Returns queued palettes in order (trimmed to the requested count); throws
/// [error] when set.
class FakeColorSource implements ColorSource {
  FakeColorSource(this.queue);

  final List<List<PaletteColor>> queue;
  final requests =
      <({PaletteKind kind, int count, String? seed, PaletteStyle style})>[];
  Object? error;

  /// When set, generate() waits on it, to test in-flight behavior.
  Completer<void>? gate;

  @override
  Future<List<PaletteColor>> generate(
    PaletteKind kind, {
    required int count,
    required PaletteStyle style,
    String? seedHex,
  }) async {
    requests.add((kind: kind, count: count, seed: seedHex, style: style));
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return queue.removeAt(0).take(count).toList();
  }
}

class FakeGoogleAuth implements GoogleAuth {
  String? idToken = 'google-token';
  int signOuts = 0;

  @override
  Future<String?> signInForIdToken() async => idToken;

  @override
  Future<void> signOut() async => signOuts++;
}

/// Fresh, empty preferences for one test.
Future<Override> testPreferences([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return sharedPreferencesProvider.overrideWithValue(prefs);
}

/// In-memory stand-in for the Color Blendr API, served through a MockClient.
/// Implements just enough of the real rules (limit, Pro gating, folders) for
/// widget tests.
class FakeServer {
  FakeServer({this.pro = false, this.limit = 10});

  bool pro;
  int limit;

  /// What RevenueCat would report: set when a (fake) Play purchase exists.
  /// `/v1/billing/sync` turns it into Pro. Starts as the subscription behind
  /// an already-Pro account, if any.
  StoreSubscription? storePurchase;

  /// How many `/v1/billing/sync` calls to answer with the old plan before
  /// seeing [storePurchase] (RevenueCat not caught up yet).
  int syncLag = 0;

  /// What `/v1/billing/subscription` returns (Pro bought on the website);
  /// null answers 404, as when Stripe doesn't list one.
  Map<String, dynamic>? webSubscription;
  final palettes = <Map<String, dynamic>>[];
  final folders = <Map<String, dynamic>>[];
  final requests = <String>[];
  var _nextId = 1;

  Map<String, dynamic> get user => {
    'id': 'u1',
    'email': 'ada@example.com',
    'name': 'Ada',
    'avatarUrl': null,
    'plan': pro ? 'pro' : 'free',
    'proExpiresAt': null,
    'limits': {'palettes': pro ? null : limit},
    'subscription': pro ? storePurchase?.toJson() : null,
  };

  AuthSession get session => AuthSession(
    token: 'session-token',
    expiresAt: DateTime.now().add(const Duration(days: 30)),
    user: AppUser.fromJson(user),
  );

  /// Adds a saved palette directly, as if made earlier.
  Map<String, dynamic> seedPalette(
    String name,
    List<PaletteColor> colors, {
    String? folderId,
    List<String> tags = const [],
  }) {
    final p = {
      'id': 'p${_nextId++}',
      'name': name,
      'kind': 'palette',
      'colors': [for (final c in colors) c.toJson()],
      'folderId': folderId,
      'tags': tags,
      'createdAt': DateTime.utc(2026, 11, 1).toIso8601String(),
      'updatedAt': DateTime.utc(2026, 11, 1).toIso8601String(),
    };
    palettes.insert(0, p);
    return p;
  }

  http.Client get client => MockClient(_handle);

  http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _upgrade(String code) => _json({
    'error': 'Needs Pro',
    'code': code,
    if (code == 'palette_limit') 'limit': limit,
  }, 402);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    requests.add('${request.method} $path');
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    final segments = request.url.pathSegments;

    switch ((request.method, path)) {
      case ('POST', '/v1/billing/sync'):
        if (syncLag > 0) {
          syncLag--;
        } else if (storePurchase != null) {
          pro = true;
        }
        return _json(user);
      case ('GET', '/v1/billing/subscription'):
        final sub = webSubscription;
        if (sub == null) {
          return _json({'error': 'No web subscription found'}, 404);
        }
        return _json({'subscription': sub});
      case ('GET', '/v1/me'):
        return _json(user);
      case ('GET', '/v1/palettes'):
        return _json({'palettes': palettes});
      case ('GET', '/v1/folders'):
        return _json({'folders': folders});
      case ('POST', '/v1/palettes'):
        final organizes =
            body['folderId'] != null ||
            ((body['tags'] as List?)?.isNotEmpty ?? false);
        if (organizes && !pro) return _upgrade('pro_required');
        if (!pro && palettes.length >= limit) return _upgrade('palette_limit');
        final p = seedPalette(
          body['name'] as String,
          [
            for (final c in body['colors'] as List)
              PaletteColor.fromJson(c as Map<String, dynamic>),
          ],
          folderId: body['folderId'] as String?,
          tags: [...?(body['tags'] as List?)?.cast<String>()],
        );
        return _json(p, 201);
      case ('POST', '/v1/folders'):
        if (!pro) return _upgrade('pro_required');
        final f = {
          'id': 'f${_nextId++}',
          'name': body['name'],
          'createdAt': DateTime.utc(2026, 11, 1).toIso8601String(),
        };
        folders.add(f);
        return _json(f, 201);
    }

    if (segments.length == 3 && segments[1] == 'palettes') {
      final p = palettes.where((p) => p['id'] == segments[2]).firstOrNull;
      if (p == null) return _json({'error': 'Palette not found'}, 404);
      if (request.method == 'DELETE') {
        palettes.remove(p);
        return http.Response('', 204);
      }
      if (request.method == 'PATCH') {
        final organizes =
            body['folderId'] != null ||
            ((body['tags'] as List?)?.isNotEmpty ?? false);
        if (organizes && !pro) return _upgrade('pro_required');
        p.addAll(body);
        return _json(p);
      }
    }
    if (segments.length == 3 &&
        segments[1] == 'folders' &&
        request.method == 'DELETE') {
      folders.removeWhere((f) => f['id'] == segments[2]);
      for (final p in palettes) {
        if (p['folderId'] == segments[2]) p['folderId'] = null;
      }
      return http.Response('', 204);
    }
    return _json({'error': 'Not found'}, 404);
  }
}

/// Monthly $2.99, yearly $19.99 (saves 44%), lifetime $39.99.
const fakeOffers = [
  ProOffer(
    title: 'Monthly',
    price: '\$2.99',
    period: 'month',
    priceAmount: 2.99,
  ),
  ProOffer(
    title: 'Yearly',
    price: '\$19.99',
    period: 'year',
    priceAmount: 19.99,
  ),
  ProOffer(title: 'Lifetime', price: '\$39.99', priceAmount: 39.99),
];

/// Scripted stand-in for Play Billing through RevenueCat.
class FakeBilling implements Billing {
  FakeBilling({this.isAvailable = true, this.offers = fakeOffers, this.onBuy});

  @override
  final bool isAvailable;

  /// Empty: Play has nothing to sell.
  List<ProOffer> offers;

  /// Decides what buying does: return false for "backed out", throw a
  /// [BillingException] for a failure. Default: the purchase goes through.
  Future<bool> Function()? onBuy;

  final calls = <String>[];

  @override
  Future<void> identify(String userId) async => calls.add('identify $userId');

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<List<ProOffer>> loadOffers() async {
    calls.add('loadOffers');
    return offers;
  }

  @override
  Future<bool> buy(ProOffer offer) async {
    calls.add('buy ${offer.title}');
    return onBuy == null ? true : await onBuy!();
  }
}

/// Stand-in for AdMob: an ad is "watched" the moment it's shown.
class FakeAds implements Ads {
  FakeAds({this.ready = true});

  /// Whether an ad is loaded.
  bool ready;
  int prepares = 0;
  int shows = 0;

  @override
  Future<void> prepare() async => prepares++;

  @override
  bool get isReady => ready;

  @override
  Future<bool> show() async {
    if (!ready) return false;
    shows++;
    return true;
  }

  @override
  bool privacyOptionsRequired = false;

  @override
  Future<void> showPrivacyOptions() async {}
}
