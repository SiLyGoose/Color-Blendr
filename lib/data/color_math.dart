import 'dart:math' as math;

/// A color in OKLCH: perceptual lightness (0–1), chroma (0–~0.37) and hue
/// (degrees). Equal steps in OKLCH look like equal steps to the eye, which
/// makes it a good space for generating harmonious palettes.
/// https://bottosson.github.io/posts/oklab/
class Oklch {
  const Oklch(this.l, this.c, this.h);

  final double l;
  final double c;
  final double h;

  Oklch copyWith({double? l, double? c, double? h}) =>
      Oklch(l ?? this.l, c ?? this.c, h ?? this.h);

  factory Oklch.fromHex(String hex) {
    final v = int.parse(hex, radix: 16);
    final r = _toLinear(((v >> 16) & 0xff) / 255);
    final g = _toLinear(((v >> 8) & 0xff) / 255);
    final b = _toLinear((v & 0xff) / 255);

    final l_ = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    final m_ = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    final s_ = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);

    final lightness = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
    final a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    final bb = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;

    final hue = math.atan2(bb, a) * 180 / math.pi;
    return Oklch(lightness, math.sqrt(a * a + bb * bb), (hue + 360) % 360);
  }

  /// The nearest displayable color, as 6 lowercase hex digits. Out-of-gamut
  /// colors keep their lightness and hue and lose chroma until they fit.
  String toHex() {
    var rgb = _toLinearRgb(this);
    if (!_inGamut(rgb)) {
      var lo = 0.0, hi = c;
      for (var i = 0; i < 24; i++) {
        final mid = (lo + hi) / 2;
        if (_inGamut(_toLinearRgb(copyWith(c: mid)))) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      rgb = _toLinearRgb(copyWith(c: lo));
    }
    return rgb
        .map(
          (ch) => (_fromLinear(ch.clamp(0.0, 1.0)) * 255).round().clamp(0, 255),
        )
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  String toString() =>
      'oklch(${l.toStringAsFixed(3)} ${c.toStringAsFixed(3)} ${h.toStringAsFixed(1)})';
}

List<double> _toLinearRgb(Oklch color) {
  final hr = color.h * math.pi / 180;
  final a = color.c * math.cos(hr);
  final b = color.c * math.sin(hr);

  final l_ = color.l + 0.3963377774 * a + 0.2158037573 * b;
  final m_ = color.l - 0.1055613458 * a - 0.0638541728 * b;
  final s_ = color.l - 0.0894841775 * a - 1.2914855480 * b;
  final l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;

  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  ];
}

bool _inGamut(List<double> rgb) =>
    rgb.every((ch) => ch >= -1e-4 && ch <= 1 + 1e-4);

double _toLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _fromLinear(double c) => c <= 0.0031308
    ? 12.92 * c
    : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

double _cbrt(double x) =>
    x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

/// WCAG 2 relative luminance of a 6-digit hex color.
double relativeLuminance(String hex) {
  final v = int.parse(hex, radix: 16);
  final r = _toLinear(((v >> 16) & 0xff) / 255);
  final g = _toLinear(((v >> 8) & 0xff) / 255);
  final b = _toLinear((v & 0xff) / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG contrast ratio between two colors (1–21).
double contrastRatio(String hexA, String hexB) {
  final a = relativeLuminance(hexA), b = relativeLuminance(hexB);
  final hi = math.max(a, b), lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// Black or white, whichever reads better on [hex] ("000000" or "ffffff").
String readableTextHex(String hex) =>
    contrastRatio(hex, '000000') >= contrastRatio(hex, 'ffffff')
    ? '000000'
    : 'ffffff';

// --- Linear RGB and OKLab, for color-vision simulation and photo palettes ----

/// Linear-light RGB (each 0–1) of an 8-bit sRGB channel triple.
(double, double, double) linearFromRgb8(int r, int g, int b) =>
    (_toLinear(r / 255), _toLinear(g / 255), _toLinear(b / 255));

/// Linear-light RGB (each 0–1) of a 6-digit hex color.
(double, double, double) linearRgbOf(String hex) {
  final v = int.parse(hex, radix: 16);
  return linearFromRgb8((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff);
}

/// 6 lowercase hex digits from linear-light RGB; out-of-range values are clamped.
String hexFromLinearRgb(double r, double g, double b) => [r, g, b]
    .map((ch) => (_fromLinear(ch.clamp(0.0, 1.0)) * 255).round().clamp(0, 255))
    .map((v) => v.toRadixString(16).padLeft(2, '0'))
    .join();

/// OKLab (L, a, b) of a linear-light RGB color.
(double, double, double) oklabFromLinear(double r, double g, double b) {
  final l_ = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  final m_ = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  final s_ = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return (
    0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
  );
}

/// Perceptual distance between two colors (Euclidean in OKLab). About 0.02 is
/// barely noticeable side by side; under ~0.05 colors are easy to confuse.
double oklabDistance(String hexA, String hexB) {
  final (l1, a1, b1) = oklabOf(hexA);
  final (l2, a2, b2) = oklabOf(hexB);
  return math.sqrt(
    (l1 - l2) * (l1 - l2) + (a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2),
  );
}

/// OKLab (L, a, b) of a 6-digit hex color.
(double, double, double) oklabOf(String hex) {
  final (r, g, b) = linearRgbOf(hex);
  return oklabFromLinear(r, g, b);
}
