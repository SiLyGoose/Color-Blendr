import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';

/// One full-width color band. Tap copies the hex; long-press or the lock button
/// keeps it when generating.
class Swatch extends StatelessWidget {
  const Swatch({
    super.key,
    required this.color,
    required this.locked,
    required this.onCopy,
    required this.onToggleLock,
    this.topPadding = 0,
  });

  final PaletteColor color;
  final bool locked;
  final VoidCallback onCopy;
  final VoidCallback onToggleLock;

  /// Extra space above the content (for the status bar on the first swatch).
  final double topPadding;

  static const _duration = Duration(milliseconds: 380);

  @override
  Widget build(BuildContext context) {
    final text = color.textColor;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: '${color.label}, ${color.name}${locked ? ', locked' : ''}',
      hint: 'Tap to copy. Long press to ${locked ? 'unlock' : 'lock'}.',
      child: AnimatedContainer(
        duration: _duration,
        curve: Curves.easeOutCubic,
        color: color.color,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onCopy,
            onLongPress: () {
              HapticFeedback.mediumImpact();
              onToggleLock();
            },
            splashColor: text.withValues(alpha: 0.12),
            highlightColor: text.withValues(alpha: 0.06),
            child: Padding(
              padding: EdgeInsets.only(top: topPadding),
              child: Stack(
                children: [
                  Center(
                    child: AnimatedSwitcher(
                      duration: _duration,
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.15),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(color.hex),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            color.label,
                            style: textTheme.titleLarge?.copyWith(
                              color: text.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            color.name,
                            style: textTheme.bodyMedium?.copyWith(
                              color: text.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton(
                        tooltip: locked ? 'Unlock color' : 'Lock color',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          onToggleLock();
                        },
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            locked ? Icons.lock : Icons.lock_open_outlined,
                            key: ValueKey(locked),
                            color: text.withValues(alpha: locked ? 0.9 : 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
