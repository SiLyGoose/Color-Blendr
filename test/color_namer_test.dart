import 'package:color_blendr/data/color_namer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Names thecolorapi.com returned for these colors (collected 2026-11-17).
///
/// thecolorapi uses an extended Name that Color list, so its answers differ
/// from the original list for some colors: of 35 random-ish colors, 28 match.
/// The 7 that don't are left out below and listed in [thecolorapiDifferences]:
/// 3 names don't exist in the original list, and 4 have a closer entry there.
const thecolorapiNames = {
  // From the app's palette screen before the rewrite.
  '2b301f': 'Rangitoto',
  'b0bef3': 'Perano',
  '8205a0': 'Purple',
  'e1fff6': 'Frosted Mint',
  // Random colors.
  'dda8b2': 'Blossom',
  'ae41d7': 'Medium Purple',
  '24683c': 'Green Pea',
  '8b0e84': 'Violet Eggplant',
  'ff23f8': 'Magenta / Fuchsia',
  '1d6a1f': 'Parsley',
  '2baecb': 'Scooter',
  '3c0d1c': 'Aubergine',
  'd5258c': 'Cerise',
  '563589': 'Gigas',
  'c66e75': 'Contessa',
  '2df788': 'Spring Green',
  'a17b9a': 'Mountbatten Pink',
  '040784': 'Navy Blue',
  '197926': 'Forest Green',
  '5d5421': 'Dallas',
  '3dcb01': 'Harlequin',
  '923dce': 'Purple Heart',
  '525848': 'Siam',
  '97bf1a': 'Lima',
  '10c72a': 'Malachite',
  'cbe3b0': 'Beryl Green',
  'd53e92': 'Cerise',
  'eced13': 'Barberry',
};

/// thecolorapi name → the name this app gives (documentation + regression check).
const thecolorapiDifferences = {
  '5cc6ea': ('Blue Jeans', 'Turquoise Blue'),
  'b0bd44': ('Peridot', 'Celery'),
  '5b40ab': ('Plump Purple', 'Royal Purple'),
  '974bd2': ('Purple Heart', 'Amethyst'),
  'c563f0': ('Lilac', 'Heliotrope'),
  '2a55fd': ('Blue', 'Blue Ribbon'),
  '5e2aad': ('Grape', 'Purple Heart'),
};

void main() {
  final namer = ColorNamer.instance;

  test('exact list entries return their own name', () {
    expect(namer.name('000000'), 'Black');
    expect(namer.name('ffffff'), 'White');
    expect(namer.name('000080'), 'Navy Blue');
  });

  test('matches thecolorapi.com names', () {
    final mismatches = <String>[];
    thecolorapiNames.forEach((hex, expected) {
      final actual = namer.name(hex);
      if (actual != expected) {
        mismatches.add('#$hex: expected "$expected", got "$actual"');
      }
    });
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });

  test('known differences from thecolorapi stay stable', () {
    final mismatches = [
      for (final MapEntry(key: hex, value: names)
          in thecolorapiDifferences.entries)
        if (namer.name(hex) != names.$2)
          '#$hex: expected "${names.$2}", got "${namer.name(hex)}"',
    ];
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });

  test('is case-insensitive', () {
    expect(namer.name('2B301F'), namer.name('2b301f'));
  });
}
