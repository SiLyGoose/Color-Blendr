import 'package:material_ui/material_ui.dart';

import '../../data/accessibility.dart';
import '../../data/models.dart';

/// Text contrast grades for every color pair, and the palette as seen with
/// each kind of color blindness. Pro.
class AccessibilityPage extends StatelessWidget {
  const AccessibilityPage({
    super.key,
    required this.name,
    required this.colors,
  });

  final String name;
  final List<PaletteColor> colors;

  static Route<void> route({
    required String name,
    required List<PaletteColor> colors,
  }) => MaterialPageRoute(
    builder: (_) => AccessibilityPage(name: name, colors: colors),
  );

  @override
  Widget build(BuildContext context) {
    final pairs = contrastPairs(colors);
    final usable = pairs.where((p) => p.grade != WcagGrade.fail).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _Header(
            title: 'Color vision',
            body:
                'How “$name” looks to people with color blindness. Colors that '
                'blend together are flagged.',
          ),
          for (final vision in ColorVision.values)
            _VisionRow(vision: vision, colors: colors),
          const SizedBox(height: 16),
          _Header(
            title: 'Text contrast',
            body: pairs.isEmpty
                ? 'Add a second color to check contrast.'
                : '$usable of ${pairs.length} color pairs work for text (WCAG 2). '
                      'AA needs 4.5:1 for body text; large text needs 3:1.',
          ),
          for (final pair in pairs) _ContrastTile(pair: pair),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisionRow extends StatelessWidget {
  const _VisionRow({required this.vision, required this.colors});
  final ColorVision vision;
  final List<PaletteColor> colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seen = [
      for (final c in colors) colorFromHex(simulateVision(c.hex, vision)),
    ];
    final clashes = vision == ColorVision.normal
        ? const <(int, int)>[]
        : confusablePairs(colors, vision);
    final clashing = {
      for (final (a, b) in clashes) ...[a, b],
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, c) in seen.indexed)
                    Expanded(
                      child: ColoredBox(
                        color: c,
                        child: clashing.contains(i)
                            ? Center(
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 20,
                                  color:
                                      ThemeData.estimateBrightnessForColor(c) ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vision.label, style: theme.textTheme.titleSmall),
                  Text(
                    clashes.isEmpty
                        ? vision.description
                        : '${vision.description}. ${_describeClashes(clashes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: clashes.isEmpty
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Colors 1 and 3 look alike."
  static String _describeClashes(List<(int, int)> clashes) {
    final parts = [for (final (a, b) in clashes) '${a + 1} and ${b + 1}'];
    final joined = parts.length == 1
        ? parts.single
        : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
    return 'Colors $joined look alike.';
  }
}

class _ContrastTile extends StatelessWidget {
  const _ContrastTile({required this.pair});
  final ContrastPair pair;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grade = pair.grade;
    final scheme = theme.colorScheme;
    final (badgeBg, badgeFg) = switch (grade) {
      WcagGrade.fail => (scheme.errorContainer, scheme.onErrorContainer),
      WcagGrade.aaLarge => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      WcagGrade.aa ||
      WcagGrade.aaa => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card.outlined(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Container(
              width: 120,
              height: 72,
              color: pair.background.color,
              alignment: Alignment.center,
              child: Text(
                'Aa',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: pair.foreground.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pair.ratio.toStringAsFixed(2)}:1',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '${pair.foreground.label} on ${pair.background.label}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  grade.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: badgeFg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
