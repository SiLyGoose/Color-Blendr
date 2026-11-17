import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'state/settings_controller.dart';

const ntcLicense = '''
Color names: "Name that Color" by Chirag Mehta (http://chir.ag/projects/ntc).
Licensed under the Creative Commons Attribution 2.5 License:
http://creativecommons.org/licenses/by/2.5/''';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Attribution required by CC BY 2.5; shown on the app's licenses page.
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks([
        'Name that Color (color names)',
      ], ntcLicense),
    ),
  );

  final prefs = await SharedPreferences.getInstance();

  runApp(
    // Riverpod 3 retries failed providers by default; our errors are either
    // shown with a Retry button or mean "sign in again", so don't auto-retry.
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const BlendrApp(),
    ),
  );
}
