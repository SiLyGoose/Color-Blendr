import 'dart:convert';

import 'package:color_blendr/data/blendr_api.dart';
import 'package:color_blendr/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

void main() {
  BlendrApi api(MockClientHandler handler, {String? token = 'session-token'}) =>
      BlendrApi(
        client: MockClient(handler),
        baseUrl: 'https://api.example.test',
        sessionToken: () => token,
      );

  test(
    'exchanges a Google ID token for a session without sending a bearer token',
    () async {
      final session = await api((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://api.example.test/v1/auth/google',
        );
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(jsonDecode(request.body), {'idToken': 'google-id'});
        return http.Response(
          jsonEncode({
            'token': 'abc',
            'expiresAt': '2027-02-15T00:00:00.000Z',
            'user': {
              'id': 'u1',
              'email': 'a@b.c',
              'name': 'Ada',
              'avatarUrl': null,
            },
          }),
          200,
        );
      }).signInWithGoogle('google-id');

      expect(session.token, 'abc');
      expect(session.user.displayName, 'Ada');
    },
  );

  test('sends the session token and parses palettes', () async {
    final palettes = await api((request) async {
      expect(request.headers['authorization'], 'Bearer session-token');
      return http.Response(
        jsonEncode({
          'palettes': [
            {
              'id': 'p1',
              'name': 'Sunset',
              'kind': 'gradient',
              'colors': [color('ff5733').toJson()],
              'createdAt': '2026-11-17T00:00:00.000Z',
              'updatedAt': '2026-11-17T00:00:00.000Z',
            },
          ],
        }),
        200,
      );
    }).listPalettes();

    expect(palettes.single.kind, PaletteKind.gradient);
    expect(palettes.single.colors.single.label, '#FF5733');
  });

  test('401 is reported as unauthorized', () async {
    final call = api(
      (_) async => http.Response('{"error":"Unauthorized"}', 401),
    ).me();
    await expectLater(
      call,
      throwsA(
        isA<ApiException>().having(
          (e) => e.isUnauthorized,
          'isUnauthorized',
          true,
        ),
      ),
    );
  });

  test('no stored session means unauthorized without a network call', () async {
    var called = false;
    final call = api((_) async {
      called = true;
      return http.Response('', 200);
    }, token: null).listPalettes();
    await expectLater(
      call,
      throwsA(
        isA<ApiException>().having(
          (e) => e.isUnauthorized,
          'isUnauthorized',
          true,
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('surfaces validation messages but hides server internals', () async {
    await expectLater(
      api((_) async => http.Response('{"error":"name: too long"}', 400))
          .renamePalette('p1', 'x'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'name: too long',
        ),
      ),
    );
    await expectLater(
      api((_) async => http.Response('{"error":"stack trace"}', 500))
          .listPalettes(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          isNot(contains('stack')),
        ),
      ),
    );
  });

  test('network failures become a friendly ApiException', () async {
    await expectLater(
      api((_) async => throw http.ClientException('socket closed'))
          .listPalettes(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('connection'),
        ),
      ),
    );
  });
}
