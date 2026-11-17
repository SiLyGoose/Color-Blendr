import 'dart:math' as math;
import 'dart:typed_data';

import 'color_math.dart';

/// Picks up to [count] colors that represent an image, given its pixels as
/// RGBA bytes (4 per pixel, any size).
///
/// Clusters a sample of the pixels with k-means in OKLab (so "close" means
/// close to the eye), then snaps each cluster to the real pixel nearest its
/// center: averages come out muddy, real pixels keep the photo's vividness.
/// Returns 6-digit lowercase hex colors, lightest first; fewer than [count]
/// when the image has fewer distinct colors. Deterministic for a given [seed].
List<String> extractPalette(
  Uint8List rgba, {
  required int count,
  int maxSamples = 4000,
  int iterations = 12,
  int seed = 7,
}) {
  final samples = _sample(rgba, maxSamples);
  if (samples.isEmpty || count <= 0) return const [];

  final random = math.Random(seed);
  var centers = _kMeansPlusPlus(samples, count, random);

  for (var iter = 0; iter < iterations; iter++) {
    final sums = List.generate(centers.length, (_) => [0.0, 0.0, 0.0, 0.0]);
    for (final s in samples) {
      final k = _nearest(centers, s.lab);
      final sum = sums[k];
      sum[0] += s.lab.$1;
      sum[1] += s.lab.$2;
      sum[2] += s.lab.$3;
      sum[3] += 1;
    }
    final next = <_Lab>[];
    var moved = false;
    for (final (k, sum) in sums.indexed) {
      if (sum[3] == 0) continue; // Empty cluster: drop it.
      final c = (sum[0] / sum[3], sum[1] / sum[3], sum[2] / sum[3]);
      if (_dist2(c, centers[k]) > 1e-8) moved = true;
      next.add(c);
    }
    final shrank = next.length != centers.length;
    centers = next;
    if (!moved && !shrank) break;
  }

  // Snap each center to its nearest real pixel; skip near-duplicates.
  final picked = <_Sample>[];
  for (final center in centers) {
    var best = samples.first;
    var bestD = double.infinity;
    for (final s in samples) {
      final d = _dist2(s.lab, center);
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    if (picked.every((p) => _dist2(p.lab, best.lab) > 0.02 * 0.02)) {
      picked.add(best);
    }
  }
  picked.sort((a, b) => b.lab.$1.compareTo(a.lab.$1));
  return [for (final p in picked) p.hex];
}

typedef _Lab = (double, double, double);

class _Sample {
  _Sample(this.hex, this.lab);
  final String hex;
  final _Lab lab;
}

/// Evenly spaced opaque pixels, at most [max] of them.
List<_Sample> _sample(Uint8List rgba, int max) {
  final pixels = rgba.length ~/ 4;
  if (pixels == 0) return const [];
  final step = math.max(1, pixels ~/ max);
  final cache = <int, _Sample>{};
  final out = <_Sample>[];
  for (var i = 0; i < pixels; i += step) {
    final o = i * 4;
    if (rgba[o + 3] < 128) continue; // Mostly transparent.
    final r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
    final key = (r << 16) | (g << 8) | b;
    out.add(
      cache[key] ??= () {
        final (lr, lg, lb) = linearFromRgb8(r, g, b);
        return _Sample(
          key.toRadixString(16).padLeft(6, '0'),
          oklabFromLinear(lr, lg, lb),
        );
      }(),
    );
  }
  return out;
}

/// k-means++ seeding: each new center is picked with probability proportional
/// to its squared distance from the centers chosen so far.
List<_Lab> _kMeansPlusPlus(List<_Sample> samples, int k, math.Random random) {
  final centers = <_Lab>[samples[random.nextInt(samples.length)].lab];
  final d2 = [for (final s in samples) _dist2(s.lab, centers.first)];
  while (centers.length < k) {
    final total = d2.fold(0.0, (a, b) => a + b);
    // Every sample sits on a center: no more distinct colors.
    if (total <= 0) break;
    var target = random.nextDouble() * total;
    var chosen = samples.length - 1;
    for (var i = 0; i < samples.length; i++) {
      target -= d2[i];
      if (target <= 0) {
        chosen = i;
        break;
      }
    }
    final c = samples[chosen].lab;
    centers.add(c);
    for (var i = 0; i < samples.length; i++) {
      d2[i] = math.min(d2[i], _dist2(samples[i].lab, c));
    }
  }
  return centers;
}

int _nearest(List<_Lab> centers, _Lab p) {
  var best = 0;
  var bestD = double.infinity;
  for (var k = 0; k < centers.length; k++) {
    final d = _dist2(centers[k], p);
    if (d < bestD) {
      bestD = d;
      best = k;
    }
  }
  return best;
}

double _dist2(_Lab a, _Lab b) {
  final dl = a.$1 - b.$1, da = a.$2 - b.$2, db = a.$3 - b.$3;
  return dl * dl + da * da + db * db;
}
