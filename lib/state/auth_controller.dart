import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/blendr_api.dart';
import '../data/models.dart';
import 'providers.dart';

/// The signed-in user, or null when signed out.
///
/// Starts from the session saved on the device so the app opens instantly, then
/// confirms it with the API in the background.
final authProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

/// Whether the signed-in account has Color Blendr Pro. False when signed out.
///
/// This only decides what the app shows; the API enforces Pro on its own.
final isProProvider = Provider<bool>(
  (ref) => ref.watch(authProvider).value?.isPro ?? false,
);

class AuthController extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final session = await ref.read(sessionStoreProvider).load();
    if (session == null) return null;
    _identifyForBilling(session.user.id);
    unawaited(refreshProfile());
    return session.user;
  }

  /// Purchases always belong to our account id. Billing trouble never blocks
  /// signing in; buying retries the setup.
  void _identifyForBilling(String userId) {
    ref.read(billingProvider).identify(userId).catchError((Object _) {});
  }

  /// After a purchase: asks the API to re-check Google Play (via
  /// RevenueCat) and keeps the profile it returns. Returns the new profile.
  Future<AppUser> syncBilling() async {
    final user = await ref.read(blendrApiProvider).syncBilling();
    if (ref.mounted) {
      await ref.read(sessionStoreProvider).updateUser(user);
      state = AsyncData(user);
    }
    return user;
  }

  /// Cancels or resumes the subscription bought on the website, keeps the
  /// profile the API returns (renewal shown in Settings), and returns the
  /// updated subscription.
  Future<WebSubscription?> setWebRenewal({
    required bool cancel,
    required bool test,
  }) async {
    final result = await ref
        .read(blendrApiProvider)
        .setWebRenewal(cancel: cancel, test: test);
    if (ref.mounted) {
      await ref.read(sessionStoreProvider).updateUser(result.user);
      if (ref.mounted) state = AsyncData(result.user);
    }
    return result.subscription;
  }

  /// Fetches the profile (including the plan) from the API. Quietly keeps the
  /// saved one when offline.
  Future<void> refreshProfile() async {
    if (ref.read(sessionStoreProvider).token == null) return;
    try {
      final user = await ref.read(blendrApiProvider).me();
      if (!ref.mounted) return;
      await ref.read(sessionStoreProvider).updateUser(user);
      if (ref.mounted) state = AsyncData(user);
    } on ApiException catch (e) {
      if (e.isUnauthorized && ref.mounted) await handleUnauthorized();
      // Offline or server trouble: keep the saved profile.
    }
  }

  /// Signs in with Google. Returns false if the user dismissed the picker.
  /// Throws [ApiException] or a Google sign-in error on failure.
  Future<bool> signIn() async {
    final idToken = await ref.read(googleAuthProvider).signInForIdToken();
    if (idToken == null) return false;
    final session = await ref.read(blendrApiProvider).signInWithGoogle(idToken);
    await ref.read(sessionStoreProvider).save(session);
    _identifyForBilling(session.user.id);
    if (ref.mounted) state = AsyncData(session.user);
    return true;
  }

  Future<void> signOut() async {
    try {
      await ref.read(blendrApiProvider).signOut();
    } on ApiException {
      // Still sign out locally; the server session expires on its own.
    }
    await _clearLocal();
  }

  /// Permanently deletes the account and all saved palettes.
  Future<void> deleteAccount() async {
    await ref.read(blendrApiProvider).deleteAccount();
    await _clearLocal();
  }

  /// Call when the API rejects the session (401).
  Future<void> handleUnauthorized() => _clearLocal();

  Future<void> _clearLocal() async {
    await ref.read(sessionStoreProvider).clear();
    try {
      await ref.read(billingProvider).signOut();
    } catch (_) {
      // Billing isn't set up; nothing to undo.
    }
    try {
      await ref.read(googleAuthProvider).signOut();
    } catch (_) {
      // Not signed in with Google on this device; nothing to do.
    }
    if (ref.mounted) state = const AsyncData(null);
  }
}
