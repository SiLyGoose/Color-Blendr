import 'dart:math';

import 'package:color_blendr/data/color_math.dart';
import 'package:color_blendr/data/color_source.dart';
import 'package:color_blendr/data/models.dart';
import 'package:color_blendr/data/palette_style.dart';
import 'package:flutter_test/flutter_test.dart';

const balanced = PaletteStyle(
  harmony: Harmony.analogous,
  vibrance: Vibrance.balanced,
  tone: Tone.balanced,
  neutrals: Neutrals.some,
);

void main() {
  group('LocalColorSource', () {
    for (final kind in PaletteKind.values) {
      for (var count = 1; count <= 5; count++) {
        test(
          '${kind.name} makes exactly $count valid, distinct, readable colors',
          () async {
            final random = Random(count * 31 + kind.index);
            final source = LocalColorSource(random: random);
            for (var round = 0; round < 40; round++) {
              final style = const _AnyStyle().pick(random, kind);
              final colors = await source.generate(
                kind,
                count: count,
                style: style,
              );
              expect(colors, hasLength(count));
              expect(
                colors.map((c) => c.hex).toSet(),
                hasLength(count),
                reason: 'distinct',
              );
              for (final c in colors) {
                expect(c.hex, matches(RegExp(r'^[0-9a-f]{6}$')));
                expect(c.name, isNotEmpty);
                expect(
                  contrastRatio(c.hex, c.textHex),
                  greaterThanOrEqualTo(4.5),
                  reason: '${c.label} text must meet WCAG AA',
                );
              }
            }
          },
        );
      }
    }

    test('clamps the count to 1–5', () async {
      final source = LocalColorSource(random: Random(1));
      expect(
        await source.generate(PaletteKind.palette, count: 0, style: balanced),
        hasLength(1),
      );
      expect(
        await source.generate(PaletteKind.palette, count: 9, style: balanced),
        hasLength(5),
      );
    });

    test(
      'a palette built from a locked color contains that exact color',
      () async {
        final source = LocalColorSource(random: Random(7));
        for (final seed in ['2b301f', 'b0bef3', '8205a0', 'e1fff6', 'ff5733']) {
          final colors = await source.generate(
            PaletteKind.palette,
            count: 5,
            style: balanced,
            seedHex: seed,
          );
          expect(colors.map((c) => c.hex), contains(seed));
        }
      },
    );

    test('a gradient keeps one hue and goes from light to dark', () async {
      final source = LocalColorSource(random: Random(3));
      for (final tone in Tone.values) {
        for (var round = 0; round < 20; round++) {
          final style = PaletteStyle(vibrance: Vibrance.balanced, tone: tone);
          final colors = await source.generate(
            PaletteKind.gradient,
            count: 5,
            style: style,
          );
          final shades = colors.map((c) => Oklch.fromHex(c.hex)).toList();
          for (var i = 1; i < shades.length; i++) {
            expect(shades[i].l, lessThan(shades[i - 1].l));
          }
        }
      }
    });

    test(
      'vibrance and tone change the output the way their names say',
      () async {
        Future<(double, double)> medians(PaletteStyle style) async {
          final source = LocalColorSource(random: Random(11));
          final ls = <double>[], cs = <double>[];
          for (var i = 0; i < 300; i++) {
            for (final c in await source.generate(
              PaletteKind.palette,
              count: 5,
              style: style,
            )) {
              final o = Oklch.fromHex(c.hex);
              ls.add(o.l);
              cs.add(o.c);
            }
          }
          return (_median(ls), _median(cs));
        }

        final muted = await medians(
          const PaletteStyle(
            harmony: Harmony.analogous,
            vibrance: Vibrance.muted,
            tone: Tone.balanced,
            neutrals: Neutrals.few,
          ),
        );
        final vivid = await medians(
          const PaletteStyle(
            harmony: Harmony.analogous,
            vibrance: Vibrance.vivid,
            tone: Tone.balanced,
            neutrals: Neutrals.few,
          ),
        );
        final dark = await medians(
          const PaletteStyle(
            harmony: Harmony.analogous,
            vibrance: Vibrance.balanced,
            tone: Tone.dark,
            neutrals: Neutrals.few,
          ),
        );
        final light = await medians(
          const PaletteStyle(
            harmony: Harmony.analogous,
            vibrance: Vibrance.balanced,
            tone: Tone.light,
            neutrals: Neutrals.few,
          ),
        );
        expect(vivid.$2, greaterThan(muted.$2 * 1.5));
        expect(light.$1, greaterThan(dark.$1 + 0.1));
      },
    );

    test('default styles look like palett.es (measured 2026-11-17)', () async {
      // palett.es, 49 palettes in OKLCH: median L 0.67, median C 0.082,
      // 67% of palettes have a neutral (C < 0.035), 43% a light neutral
      // (L > 0.85), median lightness range 0.51.
      final random = Random(2026);
      final source = LocalColorSource(random: random);
      final ls = <double>[], cs = <double>[], ranges = <double>[];
      var withNeutral = 0, withLightNeutral = 0;
      const n = 600;
      for (var i = 0; i < n; i++) {
        final style = const _AnyStyle().pick(random, PaletteKind.palette);
        final p = [
          for (final c in await source.generate(
            PaletteKind.palette,
            count: 5,
            style: style,
          ))
            Oklch.fromHex(c.hex),
        ];
        ls.addAll(p.map((c) => c.l));
        cs.addAll(p.map((c) => c.c));
        ranges.add(
          p.map((c) => c.l).reduce(max) - p.map((c) => c.l).reduce(min),
        );
        if (p.any((c) => c.c < 0.035)) withNeutral++;
        if (p.any((c) => c.c < 0.035 && c.l > 0.85)) withLightNeutral++;
      }
      final stats = {
        'median L': _median(ls),
        'median C': _median(cs),
        'with neutral': withNeutral / n,
        'with light neutral': withLightNeutral / n,
        'median L range': _median(ranges),
      };
      // ignore: avoid_print
      print(
        'Default style vs palett.es: ${stats.map((k, v) => MapEntry(k, v.toStringAsFixed(3)))}',
      );
      expect(stats['median L'], inInclusiveRange(0.6, 0.75));
      expect(stats['median C'], inInclusiveRange(0.06, 0.11));
      expect(stats['with neutral'], inInclusiveRange(0.5, 0.82));
      expect(stats['with light neutral'], inInclusiveRange(0.25, 0.6));
      expect(stats['median L range'], inInclusiveRange(0.38, 0.65));
    });

    test('is fast enough to feel instant', () async {
      final source = LocalColorSource(random: Random(9));
      await source.generate(
        PaletteKind.palette,
        count: 5,
        style: balanced,
      ); // warm up names
      final watch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        await source.generate(PaletteKind.palette, count: 5, style: balanced);
        await source.generate(
          PaletteKind.gradient,
          count: 5,
          style: const PaletteStyle(
            vibrance: Vibrance.balanced,
            tone: Tone.balanced,
          ),
        );
      }
      final perPalette = watch.elapsedMicroseconds / 200 / 1000;
      // ignore: avoid_print
      print(
        'LocalColorSource: ${perPalette.toStringAsFixed(2)} ms per 5-color palette',
      );
      expect(perPalette, lessThan(50));
    });

    test('is the same for the same random seed', () async {
      final a = await LocalColorSource(random: Random(42))
          .generate(PaletteKind.palette, count: 5, style: balanced);
      final b = await LocalColorSource(random: Random(42))
          .generate(PaletteKind.palette, count: 5, style: balanced);
      expect(a, b);
    });
  });

  group('color math', () {
    test('OKLCH round-trips sRGB colors', () {
      final random = Random(5);
      for (var i = 0; i < 500; i++) {
        final hex = random.nextInt(0x1000000).toRadixString(16).padLeft(6, '0');
        expect(
          _channelDistance(Oklch.fromHex(hex).toHex(), hex),
          lessThanOrEqualTo(1),
          reason: hex,
        );
      }
    });

    test('out-of-gamut colors are mapped into sRGB', () {
      expect(
        const Oklch(0.7, 0.4, 150).toHex(),
        matches(RegExp(r'^[0-9a-f]{6}$')),
      );
    });

    test('picks the more readable text color', () {
      expect(readableTextHex('000000'), 'ffffff');
      expect(readableTextHex('ffffff'), '000000');
      expect(readableTextHex('2b301f'), 'ffffff');
      expect(readableTextHex('b0bef3'), '000000');
    });
  });
}

/// Samples styles the way an untrained user gets them.
class _AnyStyle {
  const _AnyStyle();
  PaletteStyle pick(Random random, PaletteKind kind) =>
      const StyleModel().sample(random, palette: kind == PaletteKind.palette);
}

double _median(List<double> xs) => (List.of(xs)..sort())[xs.length ~/ 2];

int _channelDistance(String a, String b) {
  final x = int.parse(a, radix: 16), y = int.parse(b, radix: 16);
  var m = 0;
  for (final shift in [16, 8, 0]) {
    final d = (((x >> shift) & 0xff) - ((y >> shift) & 0xff)).abs();
    if (d > m) m = d;
  }
  return m;
}
