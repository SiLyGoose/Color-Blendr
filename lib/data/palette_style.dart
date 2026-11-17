import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// How accent hues relate to the main hue (offsets in degrees).
enum Harmony {
  analogous('Analogous', [35, -35, 55]),
  complementary('Complementary', [180]),
  splitComplementary('Split complementary', [150, 210]),
  triadic('Triadic', [120, 240]),
  tetradic('Tetradic', [90, 180, 270]);

  const Harmony(this.label, this.accentOffsets);
  final String label;
  final List<double> accentOffsets;
}

enum Vibrance {
  muted('Muted', 0.65),
  balanced('Balanced', 1.0),
  vivid('Vivid', 1.4);

  const Vibrance(this.label, this.chromaScale);
  final String label;

  /// Multiplies every non-neutral color's chroma.
  final double chromaScale;
}

enum Tone {
  dark('Dark', 0.45),
  balanced('Balanced', 0.25),
  light('Light', 0.1);

  const Tone(this.label, this.darkShare);
  final String label;

  /// Chance that a color is a deep shade rather than a mid/light tone.
  final double darkShare;
}

enum Neutrals {
  few('Few neutrals', 0.06),
  some('Some neutrals', 0.21),
  many('Many neutrals', 0.4);

  const Neutrals(this.label, this.chance);
  final String label;

  /// Chance that a color is a near-gray / off-white.
  final double chance;
}

/// The style a palette was generated with. Harmony and neutrals only apply to
/// palettes; gradients use vibrance and tone.
@immutable
class PaletteStyle {
  const PaletteStyle({
    this.harmony,
    required this.vibrance,
    required this.tone,
    this.neutrals,
  });

  final Harmony? harmony;
  final Vibrance vibrance;
  final Tone tone;
  final Neutrals? neutrals;

  /// "gene.option" keys of the traits this style used, for learning.
  List<String> get traitKeys => [
    if (harmony != null) 'harmony.${harmony!.name}',
    'vibrance.${vibrance.name}',
    'tone.${tone.name}',
    if (neutrals != null) 'neutrals.${neutrals!.name}',
  ];

  @override
  bool operator ==(Object other) =>
      other is PaletteStyle &&
      other.harmony == harmony &&
      other.vibrance == vibrance &&
      other.tone == tone &&
      other.neutrals == neutrals;

  @override
  int get hashCode => Object.hash(harmony, vibrance, tone, neutrals);

  @override
  String toString() => traitKeys.join(', ');
}

/// One trait (e.g. vibrance) with its options and how likely each is by default.
class _Gene<T extends Enum> {
  const _Gene(this.name, this.options, this.prior);
  final String name;
  final List<T> options;

  /// Default probabilities, tuned so untrained palettes resemble palett.es.
  final List<double> prior;

  String key(T option) => '$name.${option.name}';
}

const _harmony = _Gene('harmony', Harmony.values, [0.3, 0.2, 0.2, 0.18, 0.12]);
const _vibrance = _Gene('vibrance', Vibrance.values, [0.3, 0.5, 0.2]);
const _tone = _Gene('tone', Tone.values, [0.2, 0.55, 0.25]);
const _neutrals = _Gene('neutrals', Neutrals.values, [0.25, 0.5, 0.25]);

/// Learns which styles the user likes from feedback (saves, copies, locks,
/// quick skips) and samples new styles accordingly.
///
/// Each trait option has a score. Sampling weight = prior × e^score, mixed with
/// a little [exploration] of the prior so no option ever disappears. Real
/// exploration comes from [sampleOffStyle], which the app uses for every few
/// palettes. Scores decay a little with every update so recent taste counts more.
@immutable
class StyleModel {
  const StyleModel([this.scores = const {}]);

  /// "gene.option" → learned score (0 = no opinion).
  final Map<String, double> scores;

  static const exploration = 0.05;
  static const maxScore = 3.0;
  static const decay = 0.98;

  /// Feedback strengths.
  static const saved = 1.0;
  static const unsaved = -0.6;
  static const locked = 0.4;
  static const copied = 0.3;
  static const quickSkip = -0.15;

  bool get isUntrained => scores.values.every((s) => s.abs() < 0.05);

  PaletteStyle sample(math.Random random, {required bool palette}) =>
      PaletteStyle(
        harmony: palette ? _pick(_harmony, random) : null,
        vibrance: _pick(_vibrance, random),
        tone: _pick(_tone, random),
        neutrals: palette ? _pick(_neutrals, random) : null,
      );

  /// A style that deliberately steps outside what the user has learned to like,
  /// to test whether they like something different. Every trait the user leans
  /// toward is swapped for one of its other options (chosen by the default
  /// mix); traits with no lean are sampled as usual. Untrained, this is the
  /// same as [sample].
  PaletteStyle sampleOffStyle(math.Random random, {required bool palette}) =>
      PaletteStyle(
        harmony: palette ? _pickOffStyle(_harmony, random) : null,
        vibrance: _pickOffStyle(_vibrance, random),
        tone: _pickOffStyle(_tone, random),
        neutrals: palette ? _pickOffStyle(_neutrals, random) : null,
      );

  /// Returns a new model nudged by [amount] toward (or away from) [style].
  StyleModel reward(PaletteStyle style, double amount) {
    final next = {for (final e in scores.entries) e.key: e.value * decay};
    for (final key in style.traitKeys) {
      next[key] = ((next[key] ?? 0) + amount).clamp(-maxScore, maxScore);
    }
    next.removeWhere((_, v) => v.abs() < 0.01);
    return StyleModel(Map.unmodifiable(next));
  }

  /// Probability of each option of a trait, for display and tests.
  Map<String, double> probabilities(String gene) {
    final g = _genes.firstWhere((g) => g.name == gene);
    return {
      for (final (i, p) in _probabilities(g).indexed) g.key(g.options[i]): p,
    };
  }

  /// The options the user clearly prefers, e.g. ["Muted", "Light"].
  List<String> get preferences => [for (final g in _genes) ?_favorite(g)];

  String? _favorite(_Gene g) {
    final probs = _probabilities(g);
    var best = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[best]) best = i;
    }
    // Only call it a preference if learning moved it well above its default.
    final score = scores[g.key(g.options[best])] ?? 0;
    if (score < 0.75 || probs[best] < g.prior[best] + 0.1) return null;
    return (g.options[best] as dynamic).label as String;
  }

  T _pick<T extends Enum>(_Gene<T> gene, math.Random random) {
    final probs = _probabilities(gene);
    var roll = random.nextDouble();
    for (var i = 0; i < probs.length; i++) {
      roll -= probs[i];
      if (roll <= 0) return gene.options[i];
    }
    return gene.options.last;
  }

  T _pickOffStyle<T extends Enum>(_Gene<T> gene, math.Random random) {
    final favorite = _leaning(gene);
    if (favorite == null) return _pick(gene, random);
    final total = 1 - gene.prior[favorite];
    var roll = random.nextDouble() * total;
    for (var i = 0; i < gene.options.length; i++) {
      if (i == favorite) continue;
      roll -= gene.prior[i];
      if (roll <= 0) return gene.options[i];
    }
    return gene.options[favorite == gene.options.length - 1
        ? 0
        : gene.options.length - 1];
  }

  /// Index of the option the user leans toward in [gene], or null if learning
  /// hasn't favored any option of it.
  int? _leaning(_Gene gene) {
    final probs = _probabilities(gene);
    var best = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[best]) best = i;
    }
    return (scores[gene.key(gene.options[best])] ?? 0) > 0 ? best : null;
  }

  List<double> _probabilities(_Gene gene) {
    final weights = [
      for (var i = 0; i < gene.options.length; i++)
        gene.prior[i] * math.exp(scores[gene.key(gene.options[i])] ?? 0),
    ];
    final total = weights.reduce((a, b) => a + b);
    return [
      for (var i = 0; i < weights.length; i++)
        (1 - exploration) * weights[i] / total + exploration * gene.prior[i],
    ];
  }

  static const List<_Gene> _genes = [_harmony, _vibrance, _tone, _neutrals];

  Map<String, dynamic> toJson() => {'v': 1, 'scores': scores};

  factory StyleModel.fromJson(Map<String, dynamic> json) {
    final raw = json['scores'];
    if (json['v'] != 1 || raw is! Map) return const StyleModel();
    return StyleModel(
      Map.unmodifiable({
        for (final e in raw.entries)
          if (e.value is num)
            e.key as String: (e.value as num).toDouble().clamp(
              -maxScore,
              maxScore,
            ),
      }),
    );
  }
}
