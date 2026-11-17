import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/blendr_api.dart';
import '../../data/models.dart';
import '../../state/ads_controller.dart';
import '../../state/auth_controller.dart';
import '../../state/generator_controller.dart';
import '../../state/library_controller.dart';
import '../../state/settings_controller.dart';
import '../accessibility/accessibility_page.dart';
import '../common.dart';
import '../export/export_sheet.dart';
import '../photo/photo_palette_page.dart';
import '../pro/pro_sheet.dart';
import 'swatch.dart';

class GeneratorPage extends ConsumerStatefulWidget {
  const GeneratorPage({super.key});

  @override
  ConsumerState<GeneratorPage> createState() => _GeneratorPageState();
}

class _GeneratorPageState extends ConsumerState<GeneratorPage> {
  bool _saving = false;

  GeneratorController get _generator => ref.read(generatorProvider.notifier);

  /// A palette the user asked for: every few of these, free accounts see an
  /// ad, then an offer to remove ads with Pro.
  Future<void> _generateByUser() async {
    await _generator.generate();
    if (!mounted) return;
    final watched = await ref.read(adsControllerProvider.notifier).generated();
    if (!watched || !mounted || ref.read(isProProvider)) return;
    await showProSheet(context, ProFeature.noAds);
  }

  /// Swipe left: next palette (or a new one). Swipe right: previous.
  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 300) return;
    HapticFeedback.selectionClick();
    if (velocity > 0) {
      _generator.back();
    } else if (ref.read(generatorProvider).canGoForward) {
      _generator.forward();
    } else {
      _generateByUser();
    }
  }

  Future<void> _toggleSaved(GeneratedPalette palette) async {
    if (_saving) return;

    if (ref.read(authProvider).value == null) {
      final signedIn = await showSignInSheet(
        context,
        reason: 'Sign in with Google to keep palettes in your library on any device.',
      );
      if (!signedIn || !mounted) return;
      // The library reloads for the new user; wait so we don't save a duplicate.
      await ref
          .read(libraryProvider.future)
          .catchError((_) => const <SavedPalette>[]);
      if (!mounted) return;
    }

    final library = ref.read(libraryProvider.notifier);
    final existing = library.findMatching(palette);
    setState(() => _saving = true);
    try {
      if (existing != null) {
        await library.delete(existing);
        _generator.unsaved(palette);
        if (!mounted) return;
        showMessage(
          context,
          'Removed from library',
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => library.restore(existing).ignore(),
          ),
        );
      } else {
        await library.save(palette);
        _generator.saved(palette);
        HapticFeedback.lightImpact();
        if (!mounted) return;
        showMessage(context, 'Saved to library');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isPaletteLimit) {
        showProSheet(context, ProFeature.unlimitedSaves);
      } else {
        showMessage(context, describeError(e));
      }
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The saved name if it's in the library, otherwise the name it would get.
  String _nameOf(GeneratedPalette palette) =>
      ref.read(libraryProvider.notifier).findMatching(palette)?.name ??
      LibraryController.suggestName(palette);

  Future<void> _onTool(_Tool tool, GeneratedPalette? palette) async {
    switch (tool) {
      case _Tool.export:
        if (palette == null) return;
        await showExportSheet(context, (
          name: _nameOf(palette),
          kind: palette.kind,
          colors: palette.colors,
        ));
      case _Tool.accessibility:
        if (palette == null ||
            !await requirePro(context, ref, ProFeature.accessibility)) {
          return;
        }
        if (!mounted) return;
        await Navigator.of(context).push(
          AccessibilityPage.route(
            name: _nameOf(palette),
            colors: palette.colors,
          ),
        );
      case _Tool.photo:
        if (!await requirePro(context, ref, ProFeature.photo) || !mounted) {
          return;
        }
        final picked = await pickPhotoPalette(
          context,
          count: ref.read(settingsProvider).colorCount,
        );
        if (picked != null) _generator.show(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(generatorProvider);
    final palette = state.current;
    // Rebuild the bookmark when the library changes.
    final isSaved =
        palette != null &&
        (ref.watch(libraryProvider).value ?? const <SavedPalette>[]).any(
          (s) => palette.sameColorsAs(s.colors),
        );

    ref.listen(generatorProvider.select((s) => s.error), (previous, error) {
      if (error == null) return;
      showMessage(
        context,
        error.message,
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _generator.generate(kind: error.kind),
        ),
      );
    });

    final topInset = MediaQuery.paddingOf(context).top;
    final topColor = palette?.colors.firstOrNull?.color;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Status bar icons must stay readable over the first swatch.
      value:
          topColor == null ||
              ThemeData.estimateBrightnessForColor(topColor) == Brightness.light
          ? SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onHorizontalDragEnd: _onSwipe,
                    child: palette == null
                        ? _Placeholder(
                            failed:
                                state.error?.kind == state.kind &&
                                !state.isLoading,
                            onRetry: _generator.generate,
                          )
                        : _SwatchColumn(
                            palette: palette,
                            locked: state.locked,
                            topPadding: topInset + 56,
                            onCopy: (c) {
                              _generator.copied(palette);
                              copyColors(context, [c]);
                            },
                            onToggleLock: (i) {
                              HapticFeedback.selectionClick();
                              _generator.toggleLock(i);
                            },
                          ),
                  ),
                ),
                Positioned(
                  top: topInset + 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _KindSwitch(
                      kind: state.kind,
                      onChanged: _generator.setKind,
                    ),
                  ),
                ),
                Positioned(
                  top: topInset + 8,
                  right: 12,
                  child: _ToolsMenu(
                    hasPalette: palette != null,
                    onSelected: (tool) => _onTool(tool, palette),
                  ),
                ),
              ],
            ),
          ),
          _ControlBar(
            state: state,
            isSaved: isSaved,
            saving: _saving,
            onBack: _generator.back,
            onForward: _generator.forward,
            onGenerate: () {
              HapticFeedback.lightImpact();
              _generateByUser();
            },
            onSave: palette == null ? null : () => _toggleSaved(palette),
          ),
        ],
      ),
    );
  }
}

class _SwatchColumn extends StatelessWidget {
  const _SwatchColumn({
    required this.palette,
    required this.locked,
    required this.topPadding,
    required this.onCopy,
    required this.onToggleLock,
  });

  final GeneratedPalette palette;
  final Set<int> locked;
  final double topPadding;
  final ValueChanged<PaletteColor> onCopy;
  final ValueChanged<int> onToggleLock;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Every swatch gets an equal content area; the first one also extends up
        // under the status bar and the mode switch.
        final count = palette.colors.length;
        final share = ((constraints.maxHeight - topPadding) / count).clamp(
          0.0,
          double.infinity,
        );
        return Column(
          children: [
            for (final (i, color) in palette.colors.indexed)
              SizedBox(
                height: i == 0 ? share + topPadding : share,
                child: Swatch(
                  color: color,
                  locked: locked.contains(i),
                  topPadding: i == 0 ? topPadding : 0,
                  onCopy: () => onCopy(color),
                  onToggleLock: () => onToggleLock(i),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Shown while a mode has no palette yet: a spinner, or a retry after a failure.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.failed, required this.onRetry});
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 40,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

class _KindSwitch extends StatelessWidget {
  const _KindSwitch({required this.kind, required this.onChanged});

  final PaletteKind kind;
  final ValueChanged<PaletteKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.92),
      shape: const StadiumBorder(),
      elevation: 3,
      shadowColor: Colors.black26,
      // Equal inset on every side; each segment is its own stadium so the
      // selected pill sits concentrically inside the outer pill.
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _KindPill(
              icon: Icons.palette_outlined,
              label: PaletteKind.palette.label,
              selected: kind == PaletteKind.palette,
              onTap: () => onChanged(PaletteKind.palette),
            ),
            _KindPill(
              icon: Icons.gradient,
              label: PaletteKind.gradient.label,
              selected: kind == PaletteKind.gradient,
              onTap: () => onChanged(PaletteKind.gradient),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selected ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: ShapeDecoration(
              shape: const StadiumBorder(),
              color: selected ? scheme.secondaryContainer : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _Tool { export, accessibility, photo }

/// Export, accessibility check and palette-from-photo, over the top swatch.
class _ToolsMenu extends ConsumerWidget {
  const _ToolsMenu({required this.hasPalette, required this.onSelected});

  final bool hasPalette;
  final ValueChanged<_Tool> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pro = ref.watch(isProProvider);

    PopupMenuItem<_Tool> item(
      _Tool tool,
      IconData icon,
      String label, {
      bool needsPalette = true,
      bool proOnly = true,
    }) => PopupMenuItem(
      value: tool,
      enabled: hasPalette || !needsPalette,
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: proOnly && !pro ? const ProBadge() : null,
      ),
    );

    return Material(
      color: scheme.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black26,
      child: PopupMenuButton<_Tool>(
        tooltip: 'More tools',
        icon: const Icon(Icons.more_vert),
        onSelected: onSelected,
        itemBuilder: (context) => [
          // Hex codes are free, so the menu item itself isn't marked Pro.
          item(_Tool.export, Icons.ios_share, 'Export', proOnly: false),
          item(
            _Tool.accessibility,
            Icons.accessibility_new,
            'Check accessibility',
          ),
          item(
            _Tool.photo,
            Icons.add_photo_alternate_outlined,
            'Palette from photo',
            needsPalette: false,
          ),
        ],
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.state,
    required this.isSaved,
    required this.saving,
    required this.onBack,
    required this.onForward,
    required this.onGenerate,
    required this.onSave,
  });

  final GeneratorState state;
  final bool isSaved;
  final bool saving;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onGenerate;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous palette',
              onPressed: state.canGoBack ? onBack : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Next palette',
              onPressed: state.canGoForward ? onForward : null,
              icon: const Icon(Icons.redo),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: state.isLoading ? null : onGenerate,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: state.isLoading
                      ? const SizedBox.square(
                          key: ValueKey('loading'),
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, key: ValueKey('idle')),
                ),
                label: const Text('Generate'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: isSaved ? 'Remove from library' : 'Save to library',
              onPressed: saving ? null : onSave,
              isSelected: isSaved,
              icon: const Icon(Icons.bookmark_border),
              selectedIcon: const Icon(Icons.bookmark),
            ),
          ],
        ),
      ),
    );
  }
}
