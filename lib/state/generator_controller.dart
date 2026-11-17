import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/color_source.dart';
import '../data/models.dart';
import 'providers.dart';
import 'settings_controller.dart';
import 'taste_controller.dart';

/// One mode's palettes (Palette or Gradient), with its own position and locks.
@immutable
class KindHistory {
  const KindHistory({
    this.entries = const [],
    this.index = -1,
    this.locked = const {},
  });

  /// Every palette generated in this mode this session, oldest first.
  final List<GeneratedPalette> entries;

  /// Position in [entries] of the palette on screen.
  final int index;

  /// Swatch positions that keep their color when generating in this mode.
  final Set<int> locked;

  bool get isEmpty => entries.isEmpty;
  GeneratedPalette? get current =>
      index >= 0 && index < entries.length ? entries[index] : null;
  bool get canGoBack => index > 0;
  bool get canGoForward => index < entries.length - 1;

  /// Adds [palette] after the current one, dropping any "forward" entries
  /// (like a browser), and keeps at most [max] entries.
  KindHistory push(GeneratedPalette palette, {required int max}) {
    final kept = entries.sublist(0, index + 1)..add(palette);
    final trimmed = kept.length > max ? kept.sublist(kept.length - max) : kept;
    return KindHistory(
      entries: List.unmodifiable(trimmed),
      index: trimmed.length - 1,
      locked: locked,
    );
  }

  KindHistory copyWith({int? index, Set<int>? locked}) => KindHistory(
    entries: entries,
    index: index ?? this.index,
    locked: locked ?? this.locked,
  );
}

@immutable
class GeneratorError {
  const GeneratorError(this.kind, this.message);
  final PaletteKind kind;
  final String message;
}

@immutable
class GeneratorState {
  const GeneratorState({
    this.kind = PaletteKind.palette,
    this.histories = const {},
    this.loading = const {},
    this.error,
  });

  /// The mode on screen.
  final PaletteKind kind;

  /// Each mode keeps its own history.
  final Map<PaletteKind, KindHistory> histories;

  /// Modes with a generate request in flight.
  final Set<PaletteKind> loading;

  /// The last failed generate, cleared by the next attempt in that mode.
  final GeneratorError? error;

  KindHistory historyOf(PaletteKind kind) =>
      histories[kind] ?? const KindHistory();
  KindHistory get active => historyOf(kind);

  GeneratedPalette? get current => active.current;
  Set<int> get locked => active.locked;
  bool get canGoBack => active.canGoBack;
  bool get canGoForward => active.canGoForward;
  bool get isLoading => loading.contains(kind);

  GeneratorState copyWith({
    PaletteKind? kind,
    Map<PaletteKind, KindHistory>? histories,
    Set<PaletteKind>? loading,
    GeneratorError? Function()? error,
  }) => GeneratorState(
    kind: kind ?? this.kind,
    histories: histories ?? this.histories,
    loading: loading ?? this.loading,
    error: error != null ? error() : this.error,
  );

  GeneratorState withHistory(PaletteKind kind, KindHistory history) =>
      copyWith(histories: Map.unmodifiable({...histories, kind: history}));
}

final generatorProvider = NotifierProvider<GeneratorController, GeneratorState>(
  GeneratorController.new,
);

class GeneratorController extends Notifier<GeneratorState> {
  /// Per mode, so memory stays bounded on long sessions.
  static const maxHistory = 50;

  /// Generating again sooner than this without touching the palette counts as
  /// a (weak) dislike of its style.
  static const quickSkip = Duration(milliseconds: 1500);

  final Set<PaletteKind> _inFlight = {};

  /// When each palette appeared on screen, and which ones the user engaged
  /// with (copied, locked, saved). Identity-based: one entry per palette shown.
  final Map<GeneratedPalette, DateTime> _shownAt = Map.identity();
  final Set<GeneratedPalette> _engaged = Set.identity();
  final Set<GeneratedPalette> _copyRewarded = Set.identity();
  final Set<GeneratedPalette> _lockRewarded = Set.identity();

  DateTime _now() => ref.read(clockProvider)();
  TasteController get _taste => ref.read(tasteProvider.notifier);

  @override
  GeneratorState build() {
    // A new "colors per palette" setting shows a palette of that size right away.
    ref.listen(settingsProvider.select((s) => s.colorCount), (previous, count) {
      if (previous != count) generate(byUser: false);
    });
    Future.microtask(() => generate(byUser: false));
    return const GeneratorState(loading: {PaletteKind.palette});
  }

  /// Makes a new palette for [kind] (default: the mode on screen), keeping that
  /// mode's locked colors in place. Locked colors also seed the generator so
  /// the rest match. Ignored while that mode already has a request in flight.
  ///
  /// [byUser] is false for automatic generates (first palette, settings
  /// changes), which never count as skipping the previous palette.
  Future<void> generate({PaletteKind? kind, bool byUser = true}) async {
    final k = kind ?? state.kind;
    if (_inFlight.contains(k)) return;
    _inFlight.add(k);

    final history = state.historyOf(k);
    final current = history.current;
    if (byUser && current != null) _maybeRecordSkip(current);

    state = state.copyWith(
      loading: Set.unmodifiable({...state.loading, k}),
      error: () => state.error?.kind == k ? null : state.error,
    );

    final count = ref.read(settingsProvider).colorCount;
    // Locks on positions beyond the color count no longer apply.
    final locked = {
      for (final i in history.locked)
        if (i < count) i,
    };
    final lockedColors = <int, PaletteColor>{
      if (current != null)
        for (final i in locked)
          if (i < current.colors.length) i: current.colors[i],
    };
    final style = _taste.nextStyle(k);

    try {
      final fresh = await ref
          .read(colorSourceProvider)
          .generate(
            k,
            count: count,
            style: style,
            seedHex: lockedColors.values.firstOrNull?.hex,
          );
      if (!ref.mounted) return;
      final next = GeneratedPalette(
        kind: k,
        colors: mergeLocked(fresh, lockedColors),
        style: style,
      );
      final updated = state.historyOf(k).push(next, max: maxHistory);
      state = state.withHistory(
        k,
        updated.copyWith(locked: Set.unmodifiable(locked)),
      );
      _markShown(next);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        error: () => GeneratorError(
          k,
          e is ColorSourceException
              ? e.message
              : 'Something went wrong. Try again.',
        ),
      );
    } finally {
      _inFlight.remove(k);
      if (ref.mounted) {
        state = state.copyWith(
          loading: Set.unmodifiable({...state.loading}..remove(k)),
        );
      }
    }
  }

  /// Shows [kind]'s most recent palette; only generates if it has none yet.
  void setKind(PaletteKind kind) {
    if (kind == state.kind) return;
    state = state.copyWith(kind: kind);
    final current = state.historyOf(kind).current;
    if (current == null) {
      generate(kind: kind, byUser: false);
    } else {
      _markShown(current);
    }
  }

  void toggleLock(int position) {
    final history = state.active;
    final locked = {...history.locked};
    final locking = !locked.remove(position);
    if (locking) locked.add(position);
    state = state.withHistory(
      state.kind,
      history.copyWith(locked: Set.unmodifiable(locked)),
    );

    final current = history.current;
    if (locking && current != null) {
      _engaged.add(current);
      if (_lockRewarded.add(current)) _taste.locked(current);
    }
  }

  void back() {
    final history = state.active;
    if (history.canGoBack) {
      final moved = history.copyWith(index: history.index - 1);
      state = state.withHistory(state.kind, moved);
      _markShown(moved.current!);
    }
  }

  void forward() {
    final history = state.active;
    if (history.canGoForward) {
      final moved = history.copyWith(index: history.index + 1);
      state = state.withHistory(state.kind, moved);
      _markShown(moved.current!);
    }
  }

  /// Shows a saved palette in its mode (e.g. "Open" from the library).
  void open(SavedPalette palette) =>
      show(GeneratedPalette(kind: palette.kind, colors: palette.colors));

  /// Shows [palette] (e.g. one pulled from a photo) in its mode, after the
  /// current one, with no colors locked.
  void show(GeneratedPalette palette) {
    final entry = palette.style == null
        ? palette
        : GeneratedPalette(kind: palette.kind, colors: palette.colors);
    final history = state.historyOf(entry.kind).push(entry, max: maxHistory);
    state = state
        .copyWith(kind: entry.kind)
        .withHistory(entry.kind, history.copyWith(locked: const {}));
    _markShown(entry);
  }

  // --- Feedback from the screen ------------------------------------------------

  /// A color from [palette] was copied.
  void copied(GeneratedPalette palette) {
    _engaged.add(palette);
    if (_copyRewarded.add(palette)) _taste.copied(palette);
  }

  void saved(GeneratedPalette palette) {
    _engaged.add(palette);
    _taste.saved(palette);
  }

  void unsaved(GeneratedPalette palette) {
    _engaged.add(palette);
    _taste.unsaved(palette);
  }

  void _markShown(GeneratedPalette palette) {
    _shownAt[palette] = _now();
    // Forget palettes that have dropped out of every history.
    if (_shownAt.length > 2 * maxHistory * PaletteKind.values.length) {
      final live = Set<GeneratedPalette>.identity()
        ..addAll(state.histories.values.expand((h) => h.entries));
      _shownAt.removeWhere((p, _) => !live.contains(p));
      _engaged.retainWhere(live.contains);
      _copyRewarded.retainWhere(live.contains);
      _lockRewarded.retainWhere(live.contains);
    }
  }

  void _maybeRecordSkip(GeneratedPalette palette) {
    final shown = _shownAt[palette];
    if (shown == null || _engaged.contains(palette)) return;
    if (_now().difference(shown) < quickSkip) _taste.skipped(palette);
  }
}

/// Puts each locked color back at its position and fills the other positions
/// with fresh colors, skipping fresh colors that duplicate a locked one.
@visibleForTesting
List<PaletteColor> mergeLocked(
  List<PaletteColor> fresh,
  Map<int, PaletteColor> locked,
) {
  if (locked.isEmpty) return List.unmodifiable(fresh);
  final lockedHexes = locked.values.map((c) => c.hex).toSet();
  final pool = fresh.where((c) => !lockedHexes.contains(c.hex)).toList();
  var next = 0;
  final out = <PaletteColor>[];
  for (var i = 0; i < fresh.length; i++) {
    final keep = locked[i];
    if (keep != null) {
      out.add(keep);
    } else if (next < pool.length) {
      out.add(pool[next++]);
    } else {
      out.add(fresh[i]);
    }
  }
  return List.unmodifiable(out);
}
