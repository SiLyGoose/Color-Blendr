import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../data/palette_style.dart';
import 'settings_controller.dart';

@immutable
class TasteState {
  const TasteState({this.model = const StyleModel()});

  final StyleModel model;
}

/// Learns the user's palette style from their actions. Everything stays on the
/// device (shared preferences); nothing is sent to the server.
final tasteProvider = NotifierProvider<TasteController, TasteState>(
  TasteController.new,
);

class TasteController extends Notifier<TasteState> {
  /// Every this-many palettes, one steps outside the learned style to see
  /// whether the user likes something different.
  static const offStyleEvery = 5;

  static const _modelKey = 'styleModel';

  /// The old "Learn my style" switch. Learning is always on now.
  static const _legacyEnabledKey = 'learnStyle';

  final math.Random _random = math.Random();
  int _generated = 0;

  @override
  TasteState build() {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.remove(_legacyEnabledKey).ignore();
    var model = const StyleModel();
    try {
      final raw = prefs.getString(_modelKey);
      if (raw != null) {
        model = StyleModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Unreadable: start fresh.
    }
    return TasteState(model: model);
  }

  /// The style for the next palette: the learned style, except every
  /// [offStyleEvery]th palette, which tries something outside it. Reactions to
  /// that one are learned like any other, so the style can widen over time.
  PaletteStyle nextStyle(PaletteKind kind) {
    _generated++;
    final palette = kind == PaletteKind.palette;
    return _generated % offStyleEvery == 0
        ? state.model.sampleOffStyle(_random, palette: palette)
        : state.model.sample(_random, palette: palette);
  }

  void saved(GeneratedPalette p) => _reward(p, StyleModel.saved);
  void unsaved(GeneratedPalette p) => _reward(p, StyleModel.unsaved);
  void locked(GeneratedPalette p) => _reward(p, StyleModel.locked);
  void copied(GeneratedPalette p) => _reward(p, StyleModel.copied);
  void skipped(GeneratedPalette p) => _reward(p, StyleModel.quickSkip);

  Future<void> reset() async {
    state = const TasteState();
    await ref.read(sharedPreferencesProvider).remove(_modelKey);
  }

  void _reward(GeneratedPalette palette, double amount) {
    final style = palette.style;
    if (style == null) return;
    final model = state.model.reward(style, amount);
    state = TasteState(model: model);
    ref
        .read(sharedPreferencesProvider)
        .setString(_modelKey, jsonEncode(model.toJson()))
        .ignore();
  }
}
