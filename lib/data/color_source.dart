import 'dart:math' as math;

import 'color_math.dart';
import 'color_namer.dart';
import 'models.dart';
import 'palette_style.dart';

class ColorSourceException implements Exception {
  const ColorSourceException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Produces palettes. The app uses [LocalColorSource]; tests use fakes.
abstract class ColorSource {
  static const minColors = 1;
  static const maxColors = 5;

  /// [count] colors for [kind] in [style]. When [seedHex] is given (a locked
  /// color), the rest are built around it.
  Future<List<PaletteColor>> generate(
    PaletteKind kind, {
    required int count,
    required PaletteStyle style,
    String? seedHex,
  });
}

/// Generates palettes on the device, instantly and offline, in OKLCH.
///
/// Palettes follow the look of palett.es, measured from a sample of its output
/// (2026-11-17): mostly muted, light-leaning colors from one main hue family
/// plus one or two accents, usually with a near-gray or off-white. Each color
/// gets a role:
/// - main: the base hue family
/// - accent: a hue related to the base by the style's [Harmony]
/// - neutral: a barely tinted gray/off-white, which rests the eye
///
/// Gradients step one hue from light to dark. Names come from [ColorNamer];
/// text colors from WCAG contrast.
class LocalColorSource implements ColorSource {
  LocalColorSource({math.Random? random, ColorNamer? namer})
    : _random = random ?? math.Random(),
      _namer = namer ?? ColorNamer.instance;

  final math.Random _random;
  final ColorNamer _namer;

  @override
  Future<List<PaletteColor>> generate(
    PaletteKind kind, {
    required int count,
    required PaletteStyle style,
    String? seedHex,
  }) async {
    final n = count.clamp(ColorSource.minColors, ColorSource.maxColors);
    final seedKey = seedHex == null ? null : normalizeHex(seedHex);
    final seed = seedKey == null ? null : Oklch.fromHex(seedKey);
    final colors = switch (kind) {
      PaletteKind.palette => _palette(seed, n, style),
      PaletteKind.gradient => _gradient(seed, n, style),
    };
    final hexes = _distinct(colors);
    // The OKLCH round trip can move a channel by one step; return the seed
    // exactly so a locked color isn't shown next to a near-twin of itself.
    if (seed != null) {
      final i = hexes.indexOf(seed.toHex());
      if (i >= 0) hexes[i] = seedKey!;
    }
    return [for (final hex in hexes) describe(hex)];
  }

  PaletteColor describe(String hex) {
    final key = normalizeHex(hex);
    return PaletteColor(
      hex: key,
      name: _namer.name(key),
      textHex: readableTextHex(key),
    );
  }

  // --- Palette ---------------------------------------------------------------

  List<Oklch> _palette(Oklch? seed, int n, PaletteStyle style) {
    final harmony = style.harmony ?? Harmony.analogous;
    final neutralChance = (style.neutrals ?? Neutrals.some).chance;
    final baseHue = seed?.h ?? _random.nextDouble() * 360;

    // Accent hues for this palette: one or two of the harmony's offsets.
    final offsets = [...harmony.accentOffsets]..shuffle(_random);
    final accentHues = [
      for (final o in offsets.take(n >= 4 && _random.nextBool() ? 2 : 1))
        baseHue + o,
    ];

    List<Oklch> attempt() {
      final out = <Oklch>[?seed];
      while (out.length < n) {
        final isFirstFree = out.isEmpty;
        final roll = _random.nextDouble();
        if (!isFirstFree && roll < neutralChance) {
          out.add(_neutral(baseHue));
        } else if (isFirstFree ||
            roll < neutralChance + (1 - neutralChance) * 0.55) {
          out.add(_chromatic(baseHue, style));
        } else {
          out.add(
            _chromatic(accentHues[_random.nextInt(accentHues.length)], style),
          );
        }
      }
      return out;
    }

    // palett.es palettes span a good range of lightness (p10 ≈ 0.22); retry
    // the rare flat result so colors stay distinguishable.
    var colors = attempt();
    for (
      var tries = 0;
      tries < 6 && n >= 3 && _lightnessRange(colors) < 0.25;
      tries++
    ) {
      colors = attempt();
    }
    return colors..shuffle(_random);
  }

  Oklch _chromatic(double hue, PaletteStyle style) {
    // Chroma skews low (median ≈ 0.11 at "balanced" vibrance) so that, with
    // neutrals mixed in, palettes match palett.es's overall median of ≈ 0.08.
    final chroma =
        (0.05 + 0.17 * math.pow(_random.nextDouble(), 1.5)) *
        style.vibrance.chromaScale;
    return Oklch(
      _lightness(style.tone),
      chroma.clamp(0.02, 0.3),
      hue + _between(-12, 12),
    );
  }

  Oklch _neutral(double hue) {
    // Tinted toward the main hue so grays feel like part of the palette.
    final light = _random.nextDouble() < 0.55;
    return Oklch(
      light ? _between(0.88, 0.98) : _between(0.25, 0.6),
      _between(0.004, 0.03),
      hue + _between(-20, 20),
    );
  }

  /// Mostly mid-to-light tones with some deep shades (median ≈ 0.67).
  double _lightness(Tone tone) {
    if (_random.nextDouble() < tone.darkShare) return _between(0.25, 0.45);
    return switch (tone) {
      Tone.dark => _between(0.5, 0.82),
      Tone.balanced => _between(0.55, 0.93),
      Tone.light => _between(0.68, 0.96),
    };
  }

  static double _lightnessRange(List<Oklch> colors) {
    final ls = colors.map((c) => c.l);
    return ls.reduce(math.max) - ls.reduce(math.min);
  }

  // --- Gradient --------------------------------------------------------------

  List<Oklch> _gradient(Oklch? seed, int n, PaletteStyle style) {
    final hue = seed?.h ?? _random.nextDouble() * 360;
    final baseChroma =
        (seed?.c ?? _between(0.07, 0.15)).clamp(0.05, 0.18) *
        style.vibrance.chromaScale;
    if (n == 1) return [seed ?? Oklch(_lightness(style.tone), baseChroma, hue)];

    final (top, bottom) = switch (style.tone) {
      Tone.dark => (0.86, 0.22),
      Tone.balanced => (0.94, 0.32),
      Tone.light => (0.97, 0.5),
    };
    // Light to dark, with chroma peaking mid-ramp (very light and very dark
    // colors can't hold much chroma) and a slight hue drift.
    final drift = _between(-10, 10);
    return [
      for (var i = 0; i < n; i++)
        () {
          final t = i / (n - 1);
          return Oklch(
            top - t * (top - bottom),
            baseChroma * (0.45 + 0.55 * math.sin(math.pi * t)),
            hue + (t - 0.5) * drift,
          );
        }(),
    ];
  }

  // --- Helpers ---------------------------------------------------------------

  /// Converts to hex, nudging lightness on the rare chance two colors collide.
  List<String> _distinct(List<Oklch> colors) {
    final seen = <String>{};
    final out = <String>[];
    for (var color in colors) {
      var hex = color.toHex();
      for (var tries = 0; seen.contains(hex) && tries < 8; tries++) {
        color = color.copyWith(
          l: (color.l + (color.l > 0.5 ? -0.04 : 0.04)).clamp(0.0, 1.0),
        );
        hex = color.toHex();
      }
      seen.add(hex);
      out.add(hex);
    }
    return out;
  }

  double _between(double a, double b) => a + _random.nextDouble() * (b - a);
}
