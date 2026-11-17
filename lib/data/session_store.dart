import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// Persists the API session. Implementations keep the current token in memory
/// so API calls can read it synchronously.
abstract class SessionStore {
  /// The token currently in use, if any (valid after [load]).
  String? get token;

  /// Loads the saved session from storage. Expired sessions are discarded.
  Future<AuthSession?> load();
  Future<void> save(AuthSession session);
  Future<void> updateUser(AppUser user);
  Future<void> clear();
}

/// Stores the session in Android Keystore-backed encrypted storage.
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'session';

  final FlutterSecureStorage _storage;
  AuthSession? _session;

  @override
  String? get token => _session?.token;

  @override
  Future<AuthSession?> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final session = AuthSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (session.isExpired) {
        await clear();
        return null;
      }
      return _session = session;
    } catch (_) {
      // Corrupt or unreadable (e.g. keystore reset after restore): start signed out.
      await clear();
      return null;
    }
  }

  @override
  Future<void> save(AuthSession session) async {
    _session = session;
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  @override
  Future<void> updateUser(AppUser user) async {
    final current = _session;
    if (current == null) return;
    await save(
      AuthSession(
        token: current.token,
        expiresAt: current.expiresAt,
        user: user,
      ),
    );
  }

  @override
  Future<void> clear() async {
    _session = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing more we can do; the in-memory session is already gone.
    }
  }
}

/// In-memory store for tests.
class MemorySessionStore implements SessionStore {
  MemorySessionStore([this._session]);

  AuthSession? _session;

  @override
  String? get token => _session?.token;

  @override
  Future<AuthSession?> load() async => _session;

  @override
  Future<void> save(AuthSession session) async => _session = session;

  @override
  Future<void> updateUser(AppUser user) async {
    final s = _session;
    if (s != null) {
      _session = AuthSession(
        token: s.token,
        expiresAt: s.expiresAt,
        user: user,
      );
    }
  }

  @override
  Future<void> clear() async => _session = null;
}
