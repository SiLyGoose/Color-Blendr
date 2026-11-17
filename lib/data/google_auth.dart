import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Wraps Google Sign-In (Android Credential Manager). The ID token it returns
/// is exchanged with the Color Blendr API for a session.
abstract class GoogleAuth {
  /// Shows the Google account picker. Returns null if the user dismissed it.
  Future<String?> signInForIdToken();
  Future<void> signOut();
}

class PlatformGoogleAuth implements GoogleAuth {
  PlatformGoogleAuth({required this.serverClientId});

  final String serverClientId;
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  Future<void>? _initialization;

  // google_sign_in must be initialized exactly once.
  Future<void> _ensureInitialized() =>
      _initialization ??= _signIn.initialize(serverClientId: serverClientId);

  @override
  Future<String?> signInForIdToken() async {
    await _ensureInitialized();
    try {
      final account = await _signIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const GoogleAuthException(
          'Google sign-in did not return an ID token.',
        );
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return null;
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          throw GoogleAuthException(
            'Google sign-in is not set up for this build (${e.description ?? e.code.name}).',
          );
        default:
          throw GoogleAuthException(
            'Google sign-in failed${e.description == null ? '' : ': ${e.description}'}',
          );
      }
    }
  }

  @override
  Future<void> signOut() async {
    await _ensureInitialized();
    await _signIn.signOut();
  }
}
