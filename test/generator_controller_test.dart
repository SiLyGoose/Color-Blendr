import 'dart:async';

import 'package:color_blendr/data/color_source.dart';
import 'package:color_blendr/data/models.dart';
import 'package:color_blendr/data/palette_style.dart';
import 'package:color_blendr/state/generator_controller.dart';
import 'package:color_blendr/state/providers.dart';
import 'package:color_blendr/state/settings_controller.dart';
import 'package:color_blendr/state/taste_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

List<PaletteColor> palette(String prefix) => [
  for (var i = 1; i <= 5; i++)
    color('$prefix$i$prefix$i$prefix$i'.substring(0, 6)),
];

void main() {
  late FakeColorSource source;
  late ProviderContainer container;
  late DateTime now;

  GeneratorState state() => container.read(generatorProvider);
  GeneratorController controller() =>
      container.read(generatorProvider.notifier);

  Future<void> settle() => pumpEventQueue();

  setUp(() async {
    now = DateTime(2026, 11, 17, 12);
    source = FakeColorSource([for (final p in 'abcdefg'.split('')) palette(p)]);
    container = ProviderContainer(
      overrides: [
        colorSourceProvider.overrideWithValue(source),
        clockProvider.overrideWithValue(() => now),
        await testPreferences(),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    // Providers start lazily; start the generator now, like the screen does on open.
    container.listen(generatorProvider, (_, _) {});
  });

  test('generates a palette on start', () async {
    expect(state().isLoading, isTrue);
    await settle();
    expect(state().isLoading, isFalse);
    expect(state().current!.colors, palette('a'));
    expect(state().canGoBack, isFalse);
  });

  test(
    'back and forward walk the history; generating drops the forward branch',
    () async {
      await settle();
      await controller().generate();
      await controller().generate();
      expect(state().current!.colors, palette('c'));

      controller().back();
      controller().back();
      expect(state().current!.colors, palette('a'));
      expect(state().canGoForward, isTrue);

      await controller().generate();
      expect(state().current!.colors, palette('d'));
      expect(state().active.entries.length, 2);
      expect(state().canGoForward, isFalse);
    },
  );

  test('locked colors stay put and seed the next palette', () async {
    await settle();
    final keep = state().current!.colors[2];
    controller().toggleLock(2);

    await controller().generate();

    expect(source.requests.last.seed, keep.hex);
    expect(state().current!.colors[2], keep);
    expect(state().current!.colors[0], palette('b')[0]);
  });

  group('separate palette and gradient histories', () {
    test(
      'switching to a mode with no history generates its first palette',
      () async {
        await settle();
        controller().setKind(PaletteKind.gradient);
        await settle();
        expect(source.requests.last.kind, PaletteKind.gradient);
        expect(state().current!.kind, PaletteKind.gradient);
        expect(state().current!.colors, palette('b'));
      },
    );

    test(
      'switching back shows that mode\'s latest palette without generating',
      () async {
        await settle();
        await controller().generate(); // palette: a, b
        controller().setKind(PaletteKind.gradient);
        await settle(); // gradient: c
        final requestsBefore = source.requests.length;

        controller().setKind(PaletteKind.palette);
        await settle();
        expect(
          source.requests.length,
          requestsBefore,
          reason: 'no new palette fetched',
        );
        expect(state().current!.colors, palette('b'));

        controller().setKind(PaletteKind.gradient);
        await settle();
        expect(source.requests.length, requestsBefore);
        expect(state().current!.colors, palette('c'));
      },
    );

    test('back/forward and locks only apply to the mode on screen', () async {
      await settle();
      await controller().generate(); // palette: a, b
      controller().back(); // palette shows a
      controller().toggleLock(0);

      controller().setKind(PaletteKind.gradient);
      await settle(); // gradient: c
      expect(state().canGoBack, isFalse);
      expect(state().locked, isEmpty);

      controller().setKind(PaletteKind.palette);
      expect(state().current!.colors, palette('a'), reason: 'position kept');
      expect(state().locked, {0}, reason: 'locks kept');
      expect(state().canGoForward, isTrue);
    });

    test(
      'a request in flight lands in its own mode even after switching',
      () async {
        await settle(); // palette: a
        source.gate = Completer();
        unawaited(controller().generate()); // palette request, waiting
        controller().setKind(
          PaletteKind.gradient,
        ); // empty: starts a gradient request
        expect(state().isLoading, isTrue);
        source.gate!.complete();
        source.gate = null;
        await settle();

        expect(
          state().historyOf(PaletteKind.palette).entries.map((p) => p.colors),
          [palette('a'), palette('b')],
        );
        expect(
          state().historyOf(PaletteKind.gradient).entries.map((p) => p.colors),
          [palette('c')],
        );
        expect(state().kind, PaletteKind.gradient);
        expect(state().current!.colors, palette('c'));
      },
    );
  });

  group('colors per palette', () {
    test('uses the saved setting', () async {
      await settle();
      expect(source.requests.last.count, 5);
      await container.read(settingsProvider.notifier).setColorCount(3);
      await settle();
      expect(source.requests.last.count, 3);
      expect(state().current!.colors, hasLength(3));
    });

    test('changing it regenerates the mode on screen right away', () async {
      await settle();
      final before = source.requests.length;
      await container.read(settingsProvider.notifier).setColorCount(2);
      await settle();
      expect(source.requests.length, before + 1);
      expect(state().current!.colors, hasLength(2));
    });

    test('drops locks on positions that no longer exist', () async {
      await settle();
      controller().toggleLock(1);
      controller().toggleLock(4);
      await container.read(settingsProvider.notifier).setColorCount(3);
      await settle();
      expect(state().locked, {1});
      expect(source.requests.last.seed, palette('a')[1].hex);
    });

    test('is clamped to 1–5', () async {
      final settings = container.read(settingsProvider.notifier);
      await settings.setColorCount(0);
      expect(
        container.read(settingsProvider).colorCount,
        ColorSource.minColors,
      );
      await settings.setColorCount(12);
      expect(
        container.read(settingsProvider).colorCount,
        ColorSource.maxColors,
      );
    });
  });

  test(
    'a failure keeps the current palette and reports which mode failed',
    () async {
      await settle();
      source.error = const ColorSourceException('Service down');
      await controller().generate();
      expect(state().current!.colors, palette('a'));
      expect(state().error?.message, 'Service down');
      expect(state().error?.kind, PaletteKind.palette);
      expect(state().isLoading, isFalse);
    },
  );

  test('open() shows a saved palette in its own mode', () async {
    await settle();
    controller().open(
      SavedPalette(
        id: 'p1',
        name: 'Saved',
        kind: PaletteKind.gradient,
        colors: palette('e'),
        createdAt: DateTime(2026),
      ),
    );
    expect(state().kind, PaletteKind.gradient);
    expect(state().current!.colors, palette('e'));
    expect(
      state().historyOf(PaletteKind.palette).current!.colors,
      palette('a'),
    );
  });

  group('learning from what the user does', () {
    Map<String, double> scores() => container.read(tasteProvider).model.scores;
    double scoreFor(GeneratedPalette p) =>
        p.style!.traitKeys.map((k) => scores()[k] ?? 0).reduce((a, b) => a + b);

    test('each palette records the style it was generated with', () async {
      await settle();
      expect(state().current!.style, isNotNull);
      expect(state().current!.style, source.requests.last.style);
    });

    test(
      'generating again right away without touching it counts as a skip',
      () async {
        await settle();
        final first = state().current!;
        now = now.add(const Duration(milliseconds: 600));
        await controller().generate();
        expect(scoreFor(first), lessThan(0));
      },
    );

    test('taking time before generating is not a skip', () async {
      await settle();
      now = now.add(const Duration(seconds: 5));
      await controller().generate();
      expect(scores(), isEmpty);
    });

    test('copying, locking and saving count as liking it (copy and lock once each)', () async {
      await settle();
      final p = state().current!;
      controller().copied(p);
      final afterCopy = scoreFor(p);
      controller().copied(p);
      expect(scoreFor(p), afterCopy, reason: 'second copy adds nothing');
      expect(afterCopy, greaterThan(0));

      controller().toggleLock(0);
      final afterLock = scoreFor(p);
      expect(afterLock, greaterThan(afterCopy));
      controller().toggleLock(0); // unlock
      controller().toggleLock(0); // lock again
      expect(
        scoreFor(p),
        afterLock,
        reason: 'locking the same palette again adds nothing',
      );

      controller().saved(p);
      expect(scoreFor(p), greaterThan(afterLock));
    });

    test(
      'a palette the user engaged with is never counted as skipped',
      () async {
        await settle();
        final p = state().current!;
        controller().copied(p);
        final liked = scoreFor(p);
        now = now.add(const Duration(milliseconds: 300));
        await controller().generate();
        expect(scoreFor(p), liked);
      },
    );

    test('automatic generates (settings changes) are not skips', () async {
      await settle();
      await container.read(settingsProvider.notifier).setColorCount(3);
      await settle();
      expect(scores(), isEmpty);
    });

    test('learned style shapes the next palettes', () async {
      await settle();
      final taste = container.read(tasteProvider.notifier);
      const liked = PaletteStyle(
        harmony: Harmony.analogous,
        vibrance: Vibrance.muted,
        tone: Tone.light,
        neutrals: Neutrals.some,
      );
      for (var i = 0; i < 6; i++) {
        taste.saved(
          const GeneratedPalette(
            kind: PaletteKind.palette,
            colors: [],
            style: liked,
          ),
        );
      }
      final styles = [
        for (var i = 0; i < 400; i++) taste.nextStyle(PaletteKind.palette),
      ];
      final mutedShare =
          styles.where((s) => s.vibrance == Vibrance.muted).length /
          styles.length;
      expect(mutedShare, greaterThan(0.6));
    });

    test('every fifth palette steps outside the learned style', () async {
      await settle();
      final taste = container.read(tasteProvider.notifier);
      const liked = PaletteStyle(
        harmony: Harmony.analogous,
        vibrance: Vibrance.muted,
        tone: Tone.light,
        neutrals: Neutrals.some,
      );
      for (var i = 0; i < 6; i++) {
        taste.saved(
          const GeneratedPalette(
            kind: PaletteKind.palette,
            colors: [],
            style: liked,
          ),
        );
      }
      // Line the counter up so the next off-style palette is the 5th call.
      while (true) {
        final s = taste.nextStyle(PaletteKind.palette);
        if (s.vibrance != Vibrance.muted &&
            s.tone != Tone.light &&
            s.harmony != Harmony.analogous &&
            s.neutrals != Neutrals.some) {
          break;
        }
      }
      for (var round = 0; round < 40; round++) {
        final batch = [
          for (var i = 0; i < 5; i++) taste.nextStyle(PaletteKind.palette),
        ];
        final off = batch.last;
        expect(off.vibrance, isNot(Vibrance.muted));
        expect(off.tone, isNot(Tone.light));
        expect(off.harmony, isNot(Harmony.analogous));
        expect(off.neutrals, isNot(Neutrals.some));
      }
    });

    test('liking an off-style palette is learned like any other', () async {
      await settle();
      final taste = container.read(tasteProvider.notifier);
      const vivid = PaletteStyle(
        harmony: Harmony.triadic,
        vibrance: Vibrance.vivid,
        tone: Tone.dark,
        neutrals: Neutrals.few,
      );
      taste.saved(
        const GeneratedPalette(
          kind: PaletteKind.palette,
          colors: [],
          style: vivid,
        ),
      );
      expect(scores()['vibrance.vivid'], greaterThan(0));
    });
  });

  group('mergeLocked', () {
    test('drops fresh duplicates of locked colors', () {
      final locked = {0: color('aaaaaa')};
      final fresh = [
        color('111111'),
        color('aaaaaa'),
        color('222222'),
        color('333333'),
      ];
      expect(mergeLocked(fresh, locked).map((c) => c.hex), [
        'aaaaaa',
        '111111',
        '222222',
        '333333',
      ]);
    });
  });
}
