import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/blendr_api.dart';
import '../data/models.dart';
import 'auth_controller.dart';
import 'library_controller.dart';
import 'providers.dart';

/// The signed-in user's library folders (Pro), oldest first. Empty when
/// signed out. Folders made while on Pro stay listed after it ends, so they
/// can still be browsed and deleted.
final foldersProvider = AsyncNotifierProvider<FoldersController, List<Folder>>(
  FoldersController.new,
);

class FoldersController extends AsyncNotifier<List<Folder>> {
  @override
  Future<List<Folder>> build() async {
    final userId = ref.watch(authProvider.select((a) => a.value?.id));
    if (userId == null) return const [];
    return guardApi(ref, () => ref.read(blendrApiProvider).listFolders());
  }

  /// Pro. Throws [ApiException] (409) if the name is taken, ignoring case.
  Future<Folder> create(String name) async {
    final folder = await guardApi(
      ref,
      () => ref.read(blendrApiProvider).createFolder(name),
    );
    _update((list) => [...list, folder]);
    return folder;
  }

  /// Pro.
  Future<void> rename(Folder folder, String name) async {
    final updated = await guardApi(
      ref,
      () => ref.read(blendrApiProvider).renameFolder(folder.id, name),
    );
    _update((list) => [for (final f in list) f.id == updated.id ? updated : f]);
  }

  /// Its palettes stay in the library, unfiled.
  Future<void> delete(Folder folder) async {
    try {
      await guardApi(
        ref,
        () => ref.read(blendrApiProvider).deleteFolder(folder.id),
      );
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow; // 404: already gone.
    }
    _update((list) => list.where((f) => f.id != folder.id).toList());
    ref.read(libraryProvider.notifier).folderDeleted(folder.id);
  }

  void _update(List<Folder> Function(List<Folder>) change) {
    if (!ref.mounted) return;
    state = AsyncData(List.unmodifiable(change(state.value ?? const [])));
  }
}
