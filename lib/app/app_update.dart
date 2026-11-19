import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Keeps people on the newest version from Google Play.
///
/// Google Play says when a newer version is out for this phone (it knows about
/// staged rollouts and the app's review state, so nobody is locked out before
/// they can actually get the update). When one is, [UpdateGate] replaces the
/// whole app with [lockScreen] until they update.
///
/// If the check can't run (no network, Play is slow, or the app wasn't
/// installed from Play, such as debug builds and APKs installed by hand), the
/// person is let in.
abstract final class AppUpdate {
  static const packageName = 'org.ColorBlendr.color_blendr';

  /// Build with `--dart-define=FORCE_UPDATE_SCREEN=true` to see the screen.
  static const _forceScreen = bool.fromEnvironment('FORCE_UPDATE_SCREEN');

  /// True once Play reports a newer version. It stays true until the app is
  /// updated (installing the update restarts the app).
  static final required = ValueNotifier<bool>(_forceScreen);

  static DateTime? _lastCheck;

  /// Asks Play whether a newer version is out. Never throws.
  static Future<void> check({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (required.value) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _lastCheck = DateTime.now();
    try {
      final info = await InAppUpdate.checkForUpdate().timeout(timeout);
      if (info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress) {
        required.value = true;
      }
    } catch (e) {
      debugPrint('Update check skipped: $e');
    }
  }

  /// Checks again when the app comes back from the background, at most every
  /// [_recheckEvery], so returning from an ad or a purchase doesn't recheck.
  static const _recheckEvery = Duration(minutes: 15);

  static void checkOnResume() {
    final last = _lastCheck;
    if (last != null && DateTime.now().difference(last) < _recheckEvery) {
      return;
    }
    unawaited(check());
  }

  /// Opens the app's Google Play page. Returns false if nothing could open it.
  static Future<bool> openStore() async {
    final targets = [
      Uri.parse('market://details?id=$packageName'),
      Uri.parse('https://play.google.com/store/apps/details?id=$packageName'),
    ];
    for (final uri in targets) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (e) {
        debugPrint('Could not open $uri: $e');
      }
    }
    return false;
  }
}

/// Shows [lockScreen] in place of the whole app while an update is required.
/// Use it in `MaterialApp.builder`, so no route, dialog or back press gets
/// past it.
class UpdateGate extends StatefulWidget {
  final Widget child;
  final Widget lockScreen;
  const UpdateGate({super.key, required this.child, required this.lockScreen});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppUpdate.required.addListener(_changed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppUpdate.required.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppUpdate.checkOnResume();
  }

  @override
  Widget build(BuildContext context) =>
      AppUpdate.required.value ? widget.lockScreen : widget.child;
}
