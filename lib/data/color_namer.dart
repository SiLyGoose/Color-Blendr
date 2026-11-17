import 'color_names.dart';

/// Names colors offline with the "Name that Color" algorithm (Chirag Mehta,
/// CC BY 2.5), the same list and distance formula thecolorapi.com uses.
class ColorNamer {
  ColorNamer._();

  static final ColorNamer instance = ColorNamer._();

  late final List<_Entry> _entries = [
    for (final (hex, name) in ntcColorNames)
      _Entry(hex, name, _rgb(hex), _hsl(hex)),
  ];

  final Map<String, String> _cache = {};

  /// Closest color name for a 6-digit hex (any case, no '#').
  String name(String hex) {
    final key = hex.toUpperCase();
    return _cache[key] ??= _lookup(key);
  }

  String _lookup(String hex) {
    final rgb = _rgb(hex);
    final hsl = _hsl(hex);
    var best = -1;
    var bestName = 'Unknown';
    for (final e in _entries) {
      if (e.hex == hex) return e.name;
      final d1 =
          _sq(rgb.$1 - e.rgb.$1) +
          _sq(rgb.$2 - e.rgb.$2) +
          _sq(rgb.$3 - e.rgb.$3);
      final d2 =
          _sq(hsl.$1 - e.hsl.$1) +
          _sq(hsl.$2 - e.hsl.$2) +
          _sq(hsl.$3 - e.hsl.$3);
      final d = d1 + d2 * 2;
      if (best < 0 || best > d) {
        best = d;
        bestName = e.name;
      }
    }
    return bestName;
  }

  static int _sq(int x) => x * x;

  static (int, int, int) _rgb(String hex) {
    final v = int.parse(hex, radix: 16);
    return ((v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff);
  }

  /// ntc.js's HSL (from Farbtastic), each component scaled to 0–255 and
  /// truncated toward zero, quirks included, so results match ntc exactly.
  static (int, int, int) _hsl(String hex) {
    final (ri, gi, bi) = _rgb(hex);
    final r = ri / 255, g = gi / 255, b = bi / 255;
    final min = [r, g, b].reduce((x, y) => x < y ? x : y);
    final max = [r, g, b].reduce((x, y) => x > y ? x : y);
    final delta = max - min;
    final l = (min + max) / 2;
    var s = 0.0;
    if (l > 0 && l < 1) s = delta / (l < 0.5 ? 2 * l : 2 - 2 * l);
    var h = 0.0;
    if (delta > 0) {
      if (max == r && max != g) h += (g - b) / delta;
      if (max == g && max != b) h += 2 + (b - r) / delta;
      if (max == b && max != r) h += 4 + (r - g) / delta;
      h /= 6;
    }
    return ((h * 255).truncate(), (s * 255).truncate(), (l * 255).truncate());
  }
}

class _Entry {
  _Entry(this.hex, this.name, this.rgb, this.hsl);
  final String hex;
  final String name;
  final (int, int, int) rgb;
  final (int, int, int) hsl;
}
