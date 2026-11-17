import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/color_source.dart';

/// Loaded in main() before the app starts, so settings are available synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'Override with SharedPreferences.getInstance() in main()',
  ),
);

@immutable
class AppSettings {
  const AppSettings({this.colorCount = ColorSource.maxColors});

  /// How many colors each generated palette or gradient has (1–5).
  final int colorCount;
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends Notifier<AppSettings> {
  static const _colorCountKey = 'colorCount';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final stored = _prefs.getInt(_colorCountKey);
    return AppSettings(
      colorCount: (stored ?? ColorSource.maxColors).clamp(
        ColorSource.minColors,
        ColorSource.maxColors,
      ),
    );
  }

  Future<void> setColorCount(int count) async {
    final value = count.clamp(ColorSource.minColors, ColorSource.maxColors);
    if (value == state.colorCount) return;
    state = AppSettings(colorCount: value);
    await _prefs.setInt(_colorCountKey, value);
  }
}
