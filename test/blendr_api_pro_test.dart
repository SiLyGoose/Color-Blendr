import 'dart:convert';

import 'package:color_blendr/data/billing.dart';
import 'package:color_blendr/data/blendr_api.dart';
import 'package:color_blendr/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show PurchasesErrorCode;

import 'fakes.dart';

void main() {
  BlendrApi api(MockClientHandler handler) => BlendrApi(
    client: MockClient(handler),
    baseUrl: 'https://api.example.test',
    sessionToken: () => 'session-token',
  );

  final userJson = {
    'id': 'u1',
    'email': 'a@b.c',
    'name': 'Ada',
    'avatarUrl': null,
  };

  group('plan', () {
    test('parses Pro with an end date and no limit', () {
      final user = AppUser.fromJson({
        ...userJson,
        'plan': 'pro',
        'proExpiresAt': '2027-01-01T00:00:00.000Z',
        'limits': {'palettes': null},
      });
      expect(user.isPro, isTrue);
      expect(user.proExpiresAt, DateTime.utc(2027));
      expect(user.paletteLimit, isNull);
    });

    test('parses free with its limit', () {
      final user = AppUser.fromJson({
        ...userJson,
        'plan': 'free',
        'proExpiresAt': null,
        'limits': {'palettes': 10},
      });
      expect(user.isPro, isFalse);
      expect(user.paletteLimit, 10);
    });

    test('a profile saved before plans existed reads as free with the default limit', () {
      final user = AppUser.fromJson(userJson);
      expect(user.isPro, isFalse);
      expect(user.paletteLimit, AppUser.defaultPaletteLimit);
    });

    test('survives a save and load round trip', () {
      final pro = AppUser.fromJson({
        ...userJson,
        'plan': 'pro',
        'limits': {'palettes': null},
      });
      final again = AppUser.fromJson(
        jsonDecode(jsonEncode(pro.toJson())) as Map<String, dynamic>,
      );
      expect(again.isPro, isTrue);
      expect(again.paletteLimit, isNull);
    });
  });

  test('402 carries the upgrade reason', () async {
    final call =
        api(
          (_) async => http.Response(
            jsonEncode({
              'error': 'Free accounts can keep 10 palettes.',
              'code': 'palette_limit',
              'limit': 10,
            }),
            402,
          ),
        ).createPalette(
          name: 'x',
          kind: PaletteKind.palette,
          colors: [color('ffffff')],
        );
    await expectLater(
      call,
      throwsA(
        isA<ApiException>()
            .having((e) => e.needsPro, 'needsPro', true)
            .having((e) => e.isPaletteLimit, 'isPaletteLimit', true)
            .having((e) => e.message, 'message', contains('10 palettes')),
      ),
    );
  });

  test(
    'palettes carry folder and tags; create only sends them when set',
    () async {
      final bodies = <Object?>[];
      final client = api((request) async {
        bodies.add(jsonDecode(request.body));
        return http.Response(
          jsonEncode({
            'id': 'p1',
            'name': 'Sunset',
            'kind': 'palette',
            'colors': [color('ff5733').toJson()],
            'folderId': 'f1',
            'tags': ['warm'],
            'createdAt': '2026-11-17T00:00:00.000Z',
            'updatedAt': '2026-11-17T00:00:00.000Z',
          }),
          201,
        );
      });
      final saved = await client.createPalette(
        name: 'Sunset',
        kind: PaletteKind.palette,
        colors: [color('ff5733')],
      );
      expect(saved.folderId, 'f1');
      expect(saved.tags, ['warm']);
      expect((bodies.single as Map).containsKey('folderId'), isFalse);
      expect((bodies.single as Map).containsKey('tags'), isFalse);

      await client.createPalette(
        name: 'Sunset',
        kind: PaletteKind.palette,
        colors: [color('ff5733')],
        folderId: 'f1',
        tags: ['warm'],
      );
      expect(bodies.last, containsPair('folderId', 'f1'));
      expect(bodies.last, containsPair('tags', ['warm']));
    },
  );

  test(
    'move sends an explicit null to unfile; tags replace the list',
    () async {
      final sent = <List<Object?>>[];
      final client = api((request) async {
        sent.add([request.method, request.url.path, jsonDecode(request.body)]);
        return http.Response(
          jsonEncode({
            'id': 'p1',
            'name': 'Sunset',
            'kind': 'palette',
            'colors': [color('ff5733').toJson()],
            'createdAt': '2026-11-17T00:00:00.000Z',
            'updatedAt': '2026-11-17T00:00:00.000Z',
          }),
          200,
        );
      });
      await client.movePalette('p1', null);
      await client.setPaletteTags('p1', ['a', 'b']);
      expect(sent, [
        [
          'PATCH',
          '/v1/palettes/p1',
          {'folderId': null},
        ],
        [
          'PATCH',
          '/v1/palettes/p1',
          {
            'tags': ['a', 'b'],
          },
        ],
      ]);
    },
  );

  test('folder endpoints', () async {
    final seen = <String>[];
    final client = api((request) async {
      seen.add('${request.method} ${request.url.path} ${request.body}');
      final folder = {
        'id': 'f1',
        'name': 'Brand',
        'createdAt': '2026-11-17T00:00:00.000Z',
      };
      return switch (request.method) {
        'GET' => http.Response(
          jsonEncode({
            'folders': [folder],
          }),
          200,
        ),
        'DELETE' => http.Response('', 204),
        _ => http.Response(jsonEncode(folder), 200),
      };
    });
    expect((await client.listFolders()).single.name, 'Brand');
    expect((await client.createFolder('Brand')).id, 'f1');
    await client.renameFolder('f1', 'Brand');
    await client.deleteFolder('f1');
    expect(seen, [
      'GET /v1/folders ',
      'POST /v1/folders {"name":"Brand"}',
      'PATCH /v1/folders/f1 {"name":"Brand"}',
      'DELETE /v1/folders/f1 ',
    ]);
  });

  group('billing', () {
    test('parses the subscription behind Pro, and its absence', () {
      final user = AppUser.fromJson({
        ...userJson,
        'plan': 'pro',
        'limits': {'palettes': null},
        'subscription': {
          'productId': 'pro:weekly',
          'expiresAt': '2026-11-24T00:00:00.000Z',
          'willRenew': true,
          'billingIssue': false,
        },
      });
      expect(user.subscription?.productId, 'pro:weekly');
      expect(user.subscription?.expiresAt, DateTime.utc(2026, 11, 24));
      expect(user.subscription?.willRenew, isTrue);
      final again = AppUser.fromJson(
        jsonDecode(jsonEncode(user.toJson())) as Map<String, dynamic>,
      );
      expect(again.subscription?.willRenew, isTrue);
      expect(
        AppUser.fromJson({...userJson, 'subscription': null}).subscription,
        isNull,
      );
    });

    group('web subscription', () {
      Map<String, dynamic> sub(String status) => {
        'status': status,
        'interval': 'month',
        'amount': 499,
        'currency': 'usd',
        'invoices': <Object>[],
      };
      http.Response reply(Object body, [int status = 200]) =>
          http.Response(jsonEncode(body), status);

      test(
        'a running live subscription wins without asking test mode',
        () async {
          final asked = <String>[];
          final found = await api((r) async {
            asked.add(r.url.query);
            return reply({'subscription': sub('active')});
          }).webSubscription();
          expect(found?.status, 'active');
          expect(found?.test, isFalse);
          expect(asked, ['']);
        },
      );

      test('an ended live one loses to a running test one', () async {
        final found = await api((r) async {
          final test = r.url.queryParameters['test'] == '1';
          return reply({'subscription': sub(test ? 'active' : 'canceled')});
        }).webSubscription();
        expect(found?.status, 'active');
        expect(found?.test, isTrue);
      });

      test('an ended live one is shown when test mode has none', () async {
        final found = await api((r) async {
          if (r.url.queryParameters['test'] == '1') {
            return reply({
              'error': 'Test purchases are only for test accounts',
            }, 403);
          }
          return reply({'subscription': sub('canceled')});
        }).webSubscription();
        expect(found?.status, 'canceled');
        expect(found?.test, isFalse);
      });

      test('none anywhere is null', () async {
        final found = await api(
          (r) async => reply({'error': 'No web subscription found'}, 404),
        ).webSubscription();
        expect(found, isNull);
      });
    });

    test('sync posts with no body and returns the profile', () async {
      late http.Request sent;
      final user = await api((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            ...userJson,
            'plan': 'pro',
            'limits': {'palettes': null},
          }),
          200,
        );
      }).syncBilling();
      expect(sent.method, 'POST');
      expect(sent.url.path, '/v1/billing/sync');
      expect(sent.body, isEmpty);
      expect(user.isPro, isTrue);
    });

    test('billing periods read naturally', () {
      expect(periodName('P1W'), 'week');
      expect(periodName('P1M'), 'month');
      expect(periodName('P1Y'), 'year');
      expect(periodName(null), 'period');
    });

    test('store errors get readable messages', () {
      expect(
        describePurchaseError(PurchasesErrorCode.networkError),
        contains('connection'),
      );
      expect(
        describePurchaseError(PurchasesErrorCode.paymentPendingError),
        contains('pending'),
      );
      expect(
        describePurchaseError(
          PurchasesErrorCode.receiptInUseByOtherSubscriberError,
        ),
        contains('another Color Blendr account'),
      );
      expect(
        describePurchaseError(PurchasesErrorCode.unknownError),
        isNotEmpty,
      );
    });

    test('builds without a key have nothing to sell', () async {
      const billing = UnavailableBilling();
      expect(billing.isAvailable, isFalse);
      expect(await billing.loadOffers(), isEmpty);
    });

    test('plans describe their price and terms', () {
      const monthly = ProOffer(
        title: 'Monthly',
        price: '\$2.99',
        period: 'month',
        priceAmount: 2.99,
      );
      const yearly = ProOffer(
        title: 'Yearly',
        price: '\$19.99',
        period: 'year',
        priceAmount: 19.99,
      );
      const lifetime = ProOffer(
        title: 'Lifetime',
        price: '\$39.99',
        priceAmount: 39.99,
      );
      expect(monthly.priceLabel, '\$2.99/month');
      expect(lifetime.priceLabel, '\$39.99');
      expect(lifetime.isLifetime, isTrue);
      expect(monthly.terms, contains('renews automatically'));
      expect(lifetime.terms, contains('One-time purchase'));
      expect(yearly.savingsOver(monthly), 44);
      expect(monthly.savingsOver(monthly), isNull);
      expect(lifetime.savingsOver(monthly), isNull);
      // A yearly plan that isn't cheaper gets no badge.
      const pricey = ProOffer(
        title: 'Yearly',
        price: '\$40',
        period: 'year',
        priceAmount: 40,
      );
      expect(pricey.savingsOver(monthly), isNull);
    });

    test('test store keys never reach a release build', () {
      expect(canSellWith('', releaseBuild: false), isFalse);
      expect(canSellWith('test_abc', releaseBuild: false), isTrue);
      expect(canSellWith('test_abc', releaseBuild: true), isFalse);
      expect(canSellWith('goog_abc', releaseBuild: true), isTrue);
    });
  });
}
