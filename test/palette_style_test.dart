import 'dart:convert';
import 'dart:math';

import 'package:color_blendr/data/palette_style.dart';
import 'package:flutter_test/flutter_test.dart';

const mutedLight = PaletteStyle(
  harmony: Harmony.analogous,
  vibrance: Vibrance.muted,
  tone: Tone.light,
  neutrals: Neutrals.some,
);

void main() {
  test('an untrained model samples the default mix', () {
    const model = StyleModel();
    expect(model.isUntrained, isTrue);
    expect(model.preferences, isEmpty);
    expect(
      model.probabilities('vibrance')['vibrance.balanced'],
      closeTo(0.5, 1e-9),
    );
  });

  test('saving a style makes its traits more likely', () {
    var model = const StyleModel();
    for (var i = 0; i < 3; i++) {
      model = model.reward(mutedLight, StyleModel.saved);
    }
    expect(
      model.probabilities('vibrance')['vibrance.muted']!,
      greaterThan(0.5),
    );
    expect(model.probabilities('tone')['tone.light']!, greaterThan(0.5));
    expect(model.preferences, containsAll(['Muted', 'Light', 'Analogous']));
  });

  test('sampling follows the learned probabilities', () {
    var model = const StyleModel();
    for (var i = 0; i < 4; i++) {
      model = model.reward(mutedLight, StyleModel.saved);
    }
    final random = Random(1);
    final muted = List.generate(
      2000,
      (_) => model.sample(random, palette: true),
    ).where((s) => s.vibrance == Vibrance.muted).length;
    expect(
      muted / 2000,
      closeTo(model.probabilities('vibrance')['vibrance.muted']!, 0.04),
    );
  });

  test('never stops exploring: every option keeps a minimum chance', () {
    var model = const StyleModel();
    for (var i = 0; i < 100; i++) {
      model = model.reward(mutedLight, StyleModel.saved);
    }
    for (final gene in ['harmony', 'vibrance', 'tone', 'neutrals']) {
      for (final p in model.probabilities(gene).values) {
        expect(p, greaterThanOrEqualTo(StyleModel.exploration * 0.12 - 1e-9));
      }
    }
  });

  test('scores are capped and decay so taste can change', () {
    var model = const StyleModel();
    for (var i = 0; i < 100; i++) {
      model = model.reward(mutedLight, StyleModel.saved);
    }
    expect(model.scores.values.every((s) => s <= StyleModel.maxScore), isTrue);

    const vivid = PaletteStyle(
      harmony: Harmony.triadic,
      vibrance: Vibrance.vivid,
      tone: Tone.dark,
      neutrals: Neutrals.few,
    );
    for (var i = 0; i < 30; i++) {
      model = model.reward(vivid, StyleModel.saved);
    }
    expect(
      model.probabilities('vibrance')['vibrance.vivid']!,
      greaterThan(model.probabilities('vibrance')['vibrance.muted']!),
    );
  });

  test('off-style sampling avoids every trait the user leans toward', () {
    var model = const StyleModel();
    for (var i = 0; i < 3; i++) {
      model = model.reward(mutedLight, StyleModel.saved);
    }
    final random = Random(2);
    final styles = List.generate(
      500,
      (_) => model.sampleOffStyle(random, palette: true),
    );
    for (final s in styles) {
      expect(s.vibrance, isNot(Vibrance.muted));
      expect(s.tone, isNot(Tone.light));
      expect(s.harmony, isNot(Harmony.analogous));
      expect(s.neutrals, isNot(Neutrals.some));
    }
    // It still varies among the remaining options.
    expect(styles.map((s) => s.vibrance).toSet(), {
      Vibrance.balanced,
      Vibrance.vivid,
    });
  });

  test('off-style sampling only changes traits with a lean', () {
    const gradient = PaletteStyle(
      vibrance: Vibrance.vivid,
      tone: Tone.balanced,
    );
    var model = const StyleModel();
    for (var i = 0; i < 3; i++) {
      model = model.reward(gradient, StyleModel.saved);
    }
    final random = Random(3);
    final styles = List.generate(
      500,
      (_) => model.sampleOffStyle(random, palette: true),
    );
    expect(styles.every((s) => s.vibrance != Vibrance.vivid), isTrue);
    // No lean on harmony yet, so all harmonies still show up.
    expect(styles.map((s) => s.harmony).toSet(), Harmony.values.toSet());
  });

  test('untrained, off-style sampling is just the default mix', () {
    const model = StyleModel();
    final random = Random(4);
    final styles = List.generate(
      500,
      (_) => model.sampleOffStyle(random, palette: true),
    );
    expect(styles.map((s) => s.vibrance).toSet(), Vibrance.values.toSet());
  });

  test('quick skips push a style down', () {
    var model = const StyleModel();
    for (var i = 0; i < 10; i++) {
      model = model.reward(mutedLight, StyleModel.quickSkip);
    }
    expect(model.probabilities('vibrance')['vibrance.muted']!, lessThan(0.3));
  });

  test('gradient styles only learn vibrance and tone', () {
    const gradient = PaletteStyle(vibrance: Vibrance.vivid, tone: Tone.dark);
    final model = const StyleModel().reward(gradient, StyleModel.saved);
    expect(model.scores.keys, unorderedEquals(['vibrance.vivid', 'tone.dark']));
  });

  test('round-trips through JSON and ignores garbage', () {
    final model = const StyleModel().reward(mutedLight, StyleModel.saved);
    final restored = StyleModel.fromJson(
      jsonDecode(jsonEncode(model.toJson())) as Map<String, dynamic>,
    );
    expect(restored.scores, model.scores);
    expect(StyleModel.fromJson({'v': 99}).scores, isEmpty);
    expect(
      StyleModel.fromJson({
        'v': 1,
        'scores': {'tone.light': 'x', 'tone.dark': 99},
      }).scores,
      {'tone.dark': StyleModel.maxScore},
    );
  });
}
