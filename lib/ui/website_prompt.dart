import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/config.dart';
import 'common.dart';

/// Opens the Color Blendr website in the browser.
Future<void> openWebsite(BuildContext context) async {
  final opened = await launchUrl(
    AppConfig.websiteUrl,
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    showMessage(context, 'Couldn’t open the website');
  }
}

/// A one-time "check out our website" popup.
///
/// It waits until the [showOnLaunch]th launch, so it never lands on top of
/// the first-run sign-in and ad consent, and it's shown once at most.
abstract final class WebsitePrompt {
  static const showOnLaunch = 3;
  static const _launchesKey = 'websitePrompt.launches';
  static const _shownKey = 'websitePrompt.shown';

  /// Call once per app start, from the home screen.
  static void onLaunch(BuildContext context, SharedPreferences prefs) {
    if (prefs.getBool(_shownKey) ?? false) return;
    final launches = (prefs.getInt(_launchesKey) ?? 0) + 1;
    prefs.setInt(_launchesKey, launches).ignore();
    if (launches < showOnLaunch) return;

    // Let the home screen settle before interrupting.
    Timer(const Duration(seconds: 3), () {
      if (!context.mounted) return;
      // Something else is open (a sheet, a dialog): try again next launch.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      prefs.setBool(_shownKey, true).ignore();
      showWebsiteDialog(context);
    });
  }
}

Future<void> showWebsiteDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        icon: const Icon(Icons.language),
        title: const Text('Color Blendr on the web'),
        content: Text(
          'Make palettes on your computer too. Sign in with the same Google '
          'account and your saved palettes are there.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Not now'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              openWebsite(context);
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Visit website'),
          ),
        ],
      );
    },
  );
}
