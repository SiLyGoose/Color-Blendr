import 'dart:typed_data';

import 'package:color_blendr/data/photo_palette.dart';
import 'package:flutter_test/flutter_test.dart';

/// A width×height RGBA image built from horizontal stripes of solid colors.
Uint8List stripes(
  List<(int, int, int, int)> rows, {
  int width = 40,
  int rowHeight = 20,
}) {
  final out = Uint8List(width * rowHeight * rows.length * 4);
  var o = 0;
  for (final (r, g, b, a) in rows) {
    for (var i = 0; i < width * rowHeight; i++) {
      out[o++] = r;
      out[o++] = g;
      out[o++] = b;
      out[o++] = a;
    }
  }
  return out;
}

void main() {
  test('finds the exact colors of a simple image, lightest first', () {
    final image = stripes([
      (200, 30, 40, 255),
      (20, 40, 160, 255),
      (240, 230, 90, 255),
    ]);
    expect(extractPalette(image, count: 3), ['f0e65a', 'c81e28', '1428a0']);
  });

  test('returns fewer colors when the image has fewer', () {
    final solid = stripes([(10, 120, 90, 255), (10, 120, 90, 255)]);
    expect(extractPalette(solid, count: 5), ['0a785a']);
  });

  test('every color it returns is a real pixel from the image', () {
    // A smooth ramp: averaging would invent in-between colors.
    final pixels = <(int, int, int, int)>[
      for (var i = 0; i < 32; i++) (i * 8, 255 - i * 8, 100, 255),
    ];
    final image = stripes(pixels, width: 8, rowHeight: 4);
    final real = {
      for (final (r, g, b, _) in pixels)
        [r, g, b].map((v) => v.toRadixString(16).padLeft(2, '0')).join(),
    };
    final picked = extractPalette(image, count: 5);
    expect(picked, hasLength(5));
    expect(real.containsAll(picked), isTrue);
  });

  test('ignores transparent pixels', () {
    final image = stripes([(255, 0, 0, 0), (0, 0, 255, 255)]);
    expect(extractPalette(image, count: 2), ['0000ff']);
  });

  test('is deterministic for a seed', () {
    final pixels = <(int, int, int, int)>[
      for (var i = 0; i < 50; i++)
        ((i * 37) % 256, (i * 91) % 256, (i * 13) % 256, 255),
    ];
    final image = stripes(pixels, width: 6, rowHeight: 3);
    expect(
      extractPalette(image, count: 5, seed: 3),
      extractPalette(image, count: 5, seed: 3),
    );
  });

  test('empty input', () {
    expect(extractPalette(Uint8List(0), count: 5), isEmpty);
  });
}
