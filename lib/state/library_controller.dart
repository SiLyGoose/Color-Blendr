import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/blendr_api.dart';
import '../data/models.dart';
import 'auth_controller.dart';
import 'providers.dart';

/// The signed-in user's saved palettes, newest first. Empty when signed out.
final libraryProvider =
    AsyncNotifierProvider<LibraryController, List<SavedPalette>>(
      LibraryController.new,
    );

/// How full a free library is. Null when signed out, or for Pro (no limit).
final libraryUsageProvider = Provider<({int used, int limit})?>((ref) {
  final limit = ref.watch(authProvider.select((a) => a.value?.paletteLimit));
  final used = ref.watch(libraryProvider.select((l) => l.value?.length));
  if (limit == null || used == null) return null;
  return (used: used, limit: limit);
});

/// Every tag used in the library, most used first, for suggestions and filters.
final libraryTagsProvider = Provider<List<String>>((ref) {
  final palettes = ref.watch(libraryProvider).value ?? const <SavedPalette>[];
  final counts = <String, int>{};
  final display = <String, String>{};
  for (final p in palettes) {
    for (final t in p.tags) {
      final key = t.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => t);
    }
  }
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return List.unmodifiable(keys.map((k) => display[k]!));
});

class LibraryController extends AsyncNotifier<List<SavedPalette>> {
  @override
  Future<List<SavedPalette>> build() async {
    // Reload whenever a different user signs in (or everyone signs out).
    final userId = ref.watch(authProvider.select((a) => a.value?.id));
    if (userId == null) return const [];
    return _guard(() => ref.read(blendrApiProvider).listPalettes());
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// The saved palette with exactly these colors, if any.
  SavedPalette? findMatching(GeneratedPalette palette) {
    for (final saved in state.value ?? const <SavedPalette>[]) {
      if (palette.sameColorsAs(saved.colors)) return saved;
    }
    return null;
  }

  /// Throws [ApiException] with [ApiException.isPaletteLimit] when a free
  /// library is full, without asking the server when we already know.
  Future<SavedPalette> save(
    GeneratedPalette palette, {
    String? name,
    String? folderId,
    List<String> tags = const [],
  }) async {
    final limit = ref.read(authProvider).value?.paletteLimit;
    final count = state.value?.length;
    if (limit != null && count != null && count >= limit) {
      throw ApiException(
        'Free accounts can keep $limit palettes. Upgrade to Pro for unlimited saves.',
        statusCode: 402,
        code: 'palette_limit',
      );
    }
    // Folders and tags only stick with Pro (e.g. undoing a delete after Pro ended).
    final pro = ref.read(isProProvider);
    final saved = await _guard(
      () => ref
          .read(blendrApiProvider)
          .createPalette(
            name: name ?? suggestName(palette),
            kind: palette.kind,
            colors: palette.colors,
            folderId: pro ? folderId : null,
            tags: pro ? tags : const [],
          ),
    );
    _update((list) => [saved, ...list]);
    return saved;
  }

  /// Puts a deleted palette back as it was.
  Future<SavedPalette> restore(SavedPalette palette) => save(
    GeneratedPalette(kind: palette.kind, colors: palette.colors),
    name: palette.name,
    folderId: palette.folderId,
    tags: palette.tags,
  );

  Future<void> rename(SavedPalette palette, String name) => _replace(
    () => ref.read(blendrApiProvider).renamePalette(palette.id, name),
  );

  /// Pro. [folderId] null takes it out of its folder.
  Future<void> move(SavedPalette palette, String? folderId) => _replace(
    () => ref.read(blendrApiProvider).movePalette(palette.id, folderId),
  );

  /// Pro (clearing them isn't).
  Future<void> setTags(SavedPalette palette, List<String> tags) => _replace(
    () => ref.read(blendrApiProvider).setPaletteTags(palette.id, tags),
  );

  /// Removes immediately and puts the palette back if the server refuses.
  Future<void> delete(SavedPalette palette) async {
    final before = state.value ?? const <SavedPalette>[];
    _update((list) => list.where((p) => p.id != palette.id).toList());
    try {
      await _guard(() => ref.read(blendrApiProvider).deletePalette(palette.id));
    } on ApiException catch (e) {
      if (e.statusCode == 404) return; // Already gone.
      if (ref.mounted) state = AsyncData(before);
      rethrow;
    }
  }

  /// A folder was deleted on the server: its palettes are now unfiled.
  void folderDeleted(String folderId) {
    _update(
      (list) => [
        for (final p in list)
          p.folderId == folderId ? p.copyWith(folderId: () => null) : p,
      ],
    );
  }

  Future<void> _replace(Future<SavedPalette> Function() call) async {
    final updated = await _guard(call);
    _update((list) => [for (final p in list) p.id == updated.id ? updated : p]);
  }

  void _update(List<SavedPalette> Function(List<SavedPalette>) change) {
    if (!ref.mounted) return;
    state = AsyncData(List.unmodifiable(change(state.value ?? const [])));
  }

  Future<T> _guard<T>(Future<T> Function() call) => guardApi(ref, call);

  /// "Rangitoto palette": named after the first color, so the library is scannable.
  static String suggestName(GeneratedPalette palette) {
    final first = palette.colors.firstOrNull?.name ?? 'My';
    final name = '$first ${palette.kind.label.toLowerCase()}';
    return name.length <= 60 ? name : name.substring(0, 60);
  }
}

/// Runs an API call, signing out on 401 and re-checking the plan on 402 (Pro
/// may have ended, or started on another device).
Future<T> guardApi<T>(Ref ref, Future<T> Function() call) async {
  try {
    return await call();
  } on ApiException catch (e) {
    if (e.isUnauthorized) {
      await ref.read(authProvider.notifier).handleUnauthorized();
    }
    if (e.needsPro) ref.read(authProvider.notifier).refreshProfile().ignore();
    rethrow;
  }
}
