import 'package:flutter/foundation.dart';

import 'color_math.dart';
import 'models.dart';

/// WCAG 2 contrast grades for text.
enum WcagGrade {
  /// Under 3:1. Not enough for any text.
  fail('Fail'),

  /// 3:1. Large text only (24px, or 18.66px bold) and UI parts like icons.
  aaLarge('AA Large'),

  /// 4.5:1. Body text.
  aa('AA'),

  /// 7:1. Body text, enhanced.
  aaa('AAA');

  const WcagGrade(this.label);
  final String label;

  static WcagGrade of(double ratio) => ratio >= 7
      ? aaa
      : ratio >= 4.5
      ? aa
      : ratio >= 3
      ? aaLarge
      : fail;
}

/// Two palette colors used as text on background.
@immutable
class ContrastPair {
  const ContrastPair(this.background, this.foreground, this.ratio);

  final PaletteColor background;
  final PaletteColor foreground;

  /// 1–21.
  final double ratio;

  WcagGrade get grade => WcagGrade.of(ratio);
}

/// Every pair of distinct colors in the palette, best contrast first. For each
/// pair the darker color is the text, which reads the same either way round.
List<ContrastPair> contrastPairs(List<PaletteColor> colors) {
  final pairs = <ContrastPair>[];
  for (var i = 0; i < colors.length; i++) {
    for (var j = i + 1; j < colors.length; j++) {
      final a = colors[i], b = colors[j];
      if (a.hex == b.hex) continue;
      final aLighter = relativeLuminance(a.hex) >= relativeLuminance(b.hex);
      pairs.add(
        ContrastPair(
          aLighter ? a : b,
          aLighter ? b : a,
          contrastRatio(a.hex, b.hex),
        ),
      );
    }
  }
  pairs.sort((x, y) => y.ratio.compareTo(x.ratio));
  return pairs;
}

/// Ways of seeing color, for simulation.
enum ColorVision {
  normal('Typical vision', 'How most people see it'),
  protanopia('Protanopia', 'No red cones (about 1% of men)'),
  deuteranopia('Deuteranopia', 'No green cones (about 1% of men)'),
  tritanopia('Tritanopia', 'No blue cones (rare)'),
  achromatopsia('Achromatopsia', 'No color at all (very rare)');

  const ColorVision(this.label, this.description);
  final String label;
  final String description;
}

// Machado, Oliveira & Fernandes (2009), severity 1.0, applied in linear RGB.
// https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html
const _protan = [
  [0.152286, 1.052583, -0.204868],
  [0.114503, 0.786281, 0.099216],
  [-0.003882, -0.048116, 1.051998],
];
const _deutan = [
  [0.367322, 0.860646, -0.227968],
  [0.280085, 0.672501, 0.047413],
  [-0.011820, 0.042940, 0.968881],
];
const _tritan = [
  [1.255528, -0.076749, -0.178779],
  [-0.078411, 0.930809, 0.147602],
  [0.004733, 0.691367, 0.303900],
];

/// How [hex] looks with [vision], as 6 lowercase hex digits.
String simulateVision(String hex, ColorVision vision) {
  final (r, g, b) = linearRgbOf(hex);
  final List<List<double>> m;
  switch (vision) {
    case ColorVision.normal:
      return normalizeHex(hex);
    case ColorVision.achromatopsia:
      final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      return hexFromLinearRgb(y, y, y);
    case ColorVision.protanopia:
      m = _protan;
    case ColorVision.deuteranopia:
      m = _deutan;
    case ColorVision.tritanopia:
      m = _tritan;
  }
  return hexFromLinearRgb(
    m[0][0] * r + m[0][1] * g + m[0][2] * b,
    m[1][0] * r + m[1][1] * g + m[1][2] * b,
    m[2][0] * r + m[2][1] * g + m[2][2] * b,
  );
}

/// Below this OKLab distance two swatches are hard to tell apart.
const confusableDistance = 0.05;

/// Positions (i < j) of colors that are distinct with typical vision but hard
/// to tell apart with [vision].
List<(int, int)> confusablePairs(
  List<PaletteColor> colors,
  ColorVision vision,
) {
  final seen = [for (final c in colors) simulateVision(c.hex, vision)];
  return [
    for (var i = 0; i < colors.length; i++)
      for (var j = i + 1; j < colors.length; j++)
        if (oklabDistance(colors[i].hex, colors[j].hex) >= confusableDistance &&
            oklabDistance(seen[i], seen[j]) < confusableDistance)
          (i, j),
  ];
}
