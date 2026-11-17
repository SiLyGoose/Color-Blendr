import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;

  /// The API's machine-readable reason, when it gives one: "pro_required" or
  /// "palette_limit" (both with status 402).
  final String? code;

  /// The session is missing, expired or revoked: the user must sign in again.
  bool get isUnauthorized => statusCode == 401;

  /// The action needs Color Blendr Pro (a Pro-only feature, or a full free library).
  bool get needsPro => statusCode == 402;

  bool get isPaletteLimit => code == 'palette_limit';

  @override
  String toString() => message;
}

/// Client for the Color Blendr API (Neon Function in `api/`).
class BlendrApi {
  BlendrApi({
    required http.Client client,
    required String baseUrl,
    required String? Function() sessionToken,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client, // ignore: prefer_initializing_formals
       _base = Uri.parse(baseUrl),
       _sessionToken = sessionToken; // ignore: prefer_initializing_formals

  final http.Client _client;
  final Uri _base;
  final String? Function() _sessionToken;
  final Duration timeout;

  // --- Auth ------------------------------------------------------------------

  Future<AuthSession> signInWithGoogle(String idToken) async {
    final json = await _send(
      'POST',
      '/v1/auth/google',
      body: {'idToken': idToken},
      authenticated: false,
    );
    return AuthSession.fromJson(json as Map<String, dynamic>);
  }

  Future<void> signOut() => _send('DELETE', '/v1/auth/session');

  Future<AppUser> me() async =>
      AppUser.fromJson(await _send('GET', '/v1/me') as Map<String, dynamic>);

  Future<void> deleteAccount() => _send('DELETE', '/v1/me');

  /// Asks the API to re-check the account's Google Play purchase (after
  /// buying or restoring). Returns the profile with the resulting plan.
  Future<AppUser> syncBilling() async => AppUser.fromJson(
    await _send('POST', '/v1/billing/sync') as Map<String, dynamic>,
  );

  // --- Palettes --------------------------------------------------------------

  Future<List<SavedPalette>> listPalettes() async {
    final json = await _send('GET', '/v1/palettes') as Map<String, dynamic>;
    return (json['palettes'] as List)
        .map((p) => SavedPalette.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// A free library that is full fails with [ApiException.isPaletteLimit].
  /// [folderId] and [tags] need Pro.
  Future<SavedPalette> createPalette({
    required String name,
    required PaletteKind kind,
    required List<PaletteColor> colors,
    String? folderId,
    List<String> tags = const [],
  }) async {
    final json = await _send(
      'POST',
      '/v1/palettes',
      body: {
        'name': name,
        'kind': kind.name,
        'colors': colors.map((c) => c.toJson()).toList(),
        'folderId': ?folderId,
        if (tags.isNotEmpty) 'tags': tags,
      },
    );
    return SavedPalette.fromJson(json as Map<String, dynamic>);
  }

  Future<SavedPalette> renamePalette(String id, String name) =>
      _updatePalette(id, {'name': name});

  /// Files the palette in [folderId], or takes it out of its folder when null.
  Future<SavedPalette> movePalette(String id, String? folderId) =>
      _updatePalette(id, {'folderId': folderId});

  /// Replaces the palette's tags. The server trims and de-duplicates them.
  Future<SavedPalette> setPaletteTags(String id, List<String> tags) =>
      _updatePalette(id, {'tags': tags});

  Future<SavedPalette> _updatePalette(
    String id,
    Map<String, Object?> patch,
  ) async {
    final json = await _send('PATCH', '/v1/palettes/$id', body: patch);
    return SavedPalette.fromJson(json as Map<String, dynamic>);
  }

  Future<void> deletePalette(String id) => _send('DELETE', '/v1/palettes/$id');

  // --- Folders ---------------------------------------------------------------

  Future<List<Folder>> listFolders() async {
    final json = await _send('GET', '/v1/folders') as Map<String, dynamic>;
    return (json['folders'] as List)
        .map((f) => Folder.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  Future<Folder> createFolder(String name) async {
    final json = await _send('POST', '/v1/folders', body: {'name': name});
    return Folder.fromJson(json as Map<String, dynamic>);
  }

  Future<Folder> renameFolder(String id, String name) async {
    final json = await _send('PATCH', '/v1/folders/$id', body: {'name': name});
    return Folder.fromJson(json as Map<String, dynamic>);
  }

  Future<void> deleteFolder(String id) => _send('DELETE', '/v1/folders/$id');

  // --- Transport -------------------------------------------------------------

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
  }) async {
    final request = http.Request(method, _base.resolve(path));
    if (authenticated) {
      final token = _sessionToken();
      if (token == null) {
        throw const ApiException('Please sign in again.', statusCode: 401);
      }
      request.headers['authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );
    } on TimeoutException {
      throw const ApiException(
        'Color Blendr is taking too long to respond. Try again.',
      );
    } catch (_) {
      throw const ApiException(
        "Couldn't reach Color Blendr. Check your connection.",
      );
    }

    final status = response.statusCode;
    if (status == 204) return null;
    Object? json;
    if (response.body.isNotEmpty) {
      try {
        json = jsonDecode(response.body);
      } on FormatException {
        json = null;
      }
    }
    if (status >= 200 && status < 300) return json;

    if (status == 401) {
      throw const ApiException('Please sign in again.', statusCode: 401);
    }
    final serverMessage = json is Map ? json['error'] : null;
    final code = json is Map ? json['code'] : null;
    throw ApiException(
      status >= 500
          ? 'Something went wrong on our side. Try again in a moment.'
          : (serverMessage is String
                ? serverMessage
                : 'Request failed ($status).'),
      statusCode: status,
      code: code is String ? code : null,
    );
  }
}
