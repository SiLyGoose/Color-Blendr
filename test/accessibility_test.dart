import 'package:color_blendr/data/accessibility.dart';
import 'package:color_blendr/data/color_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('grades follow WCAG 2 thresholds', () {
    expect(WcagGrade.of(2.99), WcagGrade.fail);
    expect(WcagGrade.of(3), WcagGrade.aaLarge);
    expect(WcagGrade.of(4.5), WcagGrade.aa);
    expect(WcagGrade.of(7), WcagGrade.aaa);
  });

  test(
    'pairs every distinct color once, best contrast first, darker as text',
    () {
      final pairs = contrastPairs([
        color('777777'),
        color('ffffff'),
        color('000000'),
        color('ffffff'),
      ]);
      // 3 distinct colors -> 3 pairs among them, plus the repeated white pairs
      // with gray and black (the identical white/white pair is skipped).
      expect(pairs, hasLength(5));
      expect(pairs.first.ratio, closeTo(21, 0.01));
      expect(pairs.first.background.hex, 'ffffff');
      expect(pairs.first.foreground.hex, '000000');
      expect(pairs.first.grade, WcagGrade.aaa);
      for (var i = 1; i < pairs.length; i++) {
        expect(pairs[i - 1].ratio, greaterThanOrEqualTo(pairs[i].ratio));
      }
    },
  );

  test('typical vision leaves colors alone; achromatopsia turns them gray', () {
    expect(simulateVision('FF5733', ColorVision.normal), 'ff5733');
    final gray = simulateVision('ff5733', ColorVision.achromatopsia);
    expect(gray.substring(0, 2), gray.substring(2, 4));
    expect(gray.substring(2, 4), gray.substring(4, 6));
    // Same luminance, so the same contrast against white.
    expect(
      contrastRatio(gray, 'ffffff'),
      closeTo(contrastRatio('ff5733', 'ffffff'), 0.05),
    );
  });

  test('black, white and grays look the same with any vision', () {
    for (final v in ColorVision.values) {
      for (final hex in ['000000', 'ffffff', '808080']) {
        expect(
          oklabDistance(simulateVision(hex, v), hex),
          lessThan(0.01),
          reason: '$v $hex',
        );
      }
    }
  });

  test('flags red/green that red-green color blindness merges, but not for tritanopia', () {
    final colors = [color('d23c3c'), color('6e8c28'), color('2850c8')];
    expect(confusablePairs(colors, ColorVision.normal), isEmpty);
    expect(confusablePairs(colors, ColorVision.deuteranopia), contains((0, 1)));
    expect(
      confusablePairs(colors, ColorVision.tritanopia),
      isNot(contains((0, 1))),
    );
  });

  test('colors already alike are not flagged as a color-vision problem', () {
    final colors = [color('808080'), color('818181')];
    expect(confusablePairs(colors, ColorVision.protanopia), isEmpty);
  });
}
