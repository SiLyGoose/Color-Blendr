import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/auth_controller.dart';
import '../../state/folders_controller.dart';
import '../../state/library_controller.dart';
import '../accessibility/accessibility_page.dart';
import '../common.dart';
import '../export/export_sheet.dart';
import '../pro/pro_sheet.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, required this.onCreate, required this.onOpen});

  /// Switch to the generator tab.
  final VoidCallback onCreate;

  /// Show a saved palette in the generator.
  final ValueChanged<SavedPalette> onOpen;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  /// Showing one folder's palettes; null shows everything.
  String? _folderId;

  /// Showing palettes with this tag (any case); null shows every tag.
  String? _tag;

  Future<void> _newFolder() async {
    if (!await requirePro(context, ref, ProFeature.folders) || !mounted) return;
    final folder = await promptNewFolder(context, ref);
    if (folder != null && mounted) setState(() => _folderId = folder.id);
  }

  Future<void> _renameFolder(Folder folder) async {
    if (!await requirePro(context, ref, ProFeature.folders) || !mounted) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Rename folder',
        initial: folder.name,
        maxLength: 40,
      ),
    );
    if (name == null || name == folder.name) return;
    try {
      await ref.read(foldersProvider.notifier).rename(folder, name);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${folder.name}”?'),
        content: const Text('The palettes in it stay in your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(foldersProvider.notifier).delete(folder);
      if (mounted) setState(() => _folderId = null);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final library = ref.watch(libraryProvider);
    final folders = ref.watch(foldersProvider).value ?? const <Folder>[];
    final signedIn = auth.value != null;

    // The open folder may have been deleted (here or on another device).
    final folder = folders.where((f) => f.id == _folderId).firstOrNull;
    if (_folderId != null &&
        folder == null &&
        ref.watch(foldersProvider).hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _folderId = null);
      });
    }

    final Widget body;
    if (auth.isLoading && !auth.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!signedIn) {
      body = const MessageView(
        icon: Icons.collections_bookmark_outlined,
        title: 'Your saved palettes live here',
        body: 'Sign in to save palettes and get to them from any device.',
        action: GoogleSignInButton(),
      );
    } else {
      body = switch (library) {
        AsyncValue(:final value?) when value.isEmpty => MessageView(
          icon: Icons.bookmark_add_outlined,
          title: 'No saved palettes yet',
          body: 'Tap the bookmark on any palette to keep it here.',
          action: FilledButton.tonalIcon(
            onPressed: widget.onCreate,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Create a palette'),
          ),
        ),
        AsyncValue(:final value?) => _LibraryList(
          palettes: value,
          folders: folders,
          folder: folder,
          tag: _tag,
          onFolder: (id) => setState(() => _folderId = id),
          onTag: (tag) => setState(() => _tag = tag),
          onOpen: widget.onOpen,
        ),
        AsyncValue(:final error?) => MessageView(
          icon: Icons.cloud_off_outlined,
          title: "Couldn't load your library",
          body: describeError(error),
          action: FilledButton.tonal(
            onPressed: () => ref.invalidate(libraryProvider),
            child: const Text('Try again'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(folder?.name ?? 'Library'),
        actions: [
          if (signedIn && folder == null)
            IconButton(
              tooltip: 'New folder',
              onPressed: _newFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          if (folder != null)
            PopupMenuButton<bool>(
              tooltip: 'Folder options',
              onSelected: (rename) =>
                  rename ? _renameFolder(folder) : _deleteFolder(folder),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: true,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename folder'),
                  ),
                ),
                PopupMenuItem(
                  value: false,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete folder'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: body,
      ),
    );
  }
}

class _LibraryList extends ConsumerWidget {
  const _LibraryList({
    required this.palettes,
    required this.folders,
    required this.folder,
    required this.tag,
    required this.onFolder,
    required this.onTag,
    required this.onOpen,
  });

  final List<SavedPalette> palettes;
  final List<Folder> folders;
  final Folder? folder;
  final String? tag;
  final ValueChanged<String?> onFolder;
  final ValueChanged<String?> onTag;
  final ValueChanged<SavedPalette> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(libraryUsageProvider);
    final folderNames = {for (final f in folders) f.id: f.name};
    final shown = [
      for (final p in palettes)
        if ((folder == null || p.folderId == folder!.id) &&
            (tag == null ||
                p.tags.any((t) => t.toLowerCase() == tag!.toLowerCase())))
          p,
    ];

    final header = <Widget>[
      if (usage != null) _UsageBanner(used: usage.used, limit: usage.limit),
      if (folders.isNotEmpty || tag != null)
        _FilterBar(
          folders: folders,
          folder: folder,
          tag: tag,
          onFolder: onFolder,
          onTag: onTag,
        ),
    ];

    return RefreshIndicator(
      onRefresh: () => Future.wait([
        ref.read(libraryProvider.notifier).refresh(),
        ref.refresh(foldersProvider.future),
        ref.read(authProvider.notifier).refreshProfile(),
      ]),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          ...header,
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: MessageView(
                icon: tag != null
                    ? Icons.sell_outlined
                    : Icons.folder_open_outlined,
                title: 'Nothing here yet',
                body: tag != null
                    ? 'No palettes${folder != null ? ' in this folder' : ''} are tagged “$tag”.'
                    : 'Use “Move to folder” in a palette’s menu to file it here.',
              ),
            ),
          for (final p in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PaletteCard(
                key: ValueKey(p.id),
                palette: p,
                folderName: folder == null ? folderNames[p.folderId] : null,
                onOpen: () => onOpen(p),
                onTag: onTag,
              ),
            ),
        ],
      ),
    );
  }
}

/// "7 of 10 free saves used", with a way to Pro.
class _UsageBanner extends StatelessWidget {
  const _UsageBanner({required this.used, required this.limit});
  final int used;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = used >= limit;
    final scheme = theme.colorScheme;
    return Card.filled(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      color: full ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    full
                        ? 'Your free library is full'
                        : '$used of $limit free saves used',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (used / limit).clamp(0.0, 1.0),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => showProSheet(context, ProFeature.unlimitedSaves),
              child: const Text('Get Pro'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.folders,
    required this.folder,
    required this.tag,
    required this.onFolder,
    required this.onTag,
  });

  final List<Folder> folders;
  final Folder? folder;
  final String? tag;
  final ValueChanged<String?> onFolder;
  final ValueChanged<String?> onTag;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (tag != null) ...[
            InputChip(
              avatar: const Icon(Icons.sell_outlined, size: 18),
              label: Text(tag!),
              selected: true,
              showCheckmark: false,
              onDeleted: () => onTag(null),
              deleteButtonTooltipMessage: 'Show all tags',
              onPressed: () => onTag(null),
            ),
            const SizedBox(width: 8),
          ],
          if (folders.isNotEmpty) ...[
            ChoiceChip(
              label: const Text('All'),
              selected: folder == null,
              onSelected: (_) => onFolder(null),
            ),
            for (final f in folders) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                avatar: const Icon(Icons.folder_outlined, size: 18),
                label: Text(f.name),
                selected: folder?.id == f.id,
                onSelected: (_) => onFolder(folder?.id == f.id ? null : f.id),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

enum _Action { open, rename, move, tags, export, accessibility, copy, delete }

class _PaletteCard extends ConsumerWidget {
  const _PaletteCard({
    super.key,
    required this.palette,
    required this.folderName,
    required this.onOpen,
    required this.onTag,
  });

  final SavedPalette palette;

  /// Shown when listing everything, so you can see where it's filed.
  final String? folderName;
  final VoidCallback onOpen;
  final ValueChanged<String> onTag;

  Future<void> _attempt(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) showMessage(context, describeError(e));
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) =>
          NameDialog(title: 'Rename palette', initial: palette.name),
    );
    if (name == null || name == palette.name || !context.mounted) return;
    await _attempt(
      context,
      () => ref.read(libraryProvider.notifier).rename(palette, name),
    );
  }

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    if (!await requirePro(context, ref, ProFeature.folders) ||
        !context.mounted) {
      return;
    }
    final choice = await showMoveToFolderSheet(
      context,
      ref,
      current: palette.folderId,
    );
    if (choice == null ||
        choice.folderId == palette.folderId ||
        !context.mounted) {
      return;
    }
    await _attempt(
      context,
      () => ref.read(libraryProvider.notifier).move(palette, choice.folderId),
    );
  }

  Future<void> _editTags(BuildContext context, WidgetRef ref) async {
    if (!await requirePro(context, ref, ProFeature.tags) || !context.mounted) {
      return;
    }
    final tags = await showDialog<List<String>>(
      context: context,
      builder: (context) => _TagsDialog(initial: palette.tags),
    );
    if (tags == null || !context.mounted) return;
    await _attempt(
      context,
      () => ref.read(libraryProvider.notifier).setTags(palette, tags),
    );
  }

  Future<void> _accessibility(BuildContext context, WidgetRef ref) async {
    if (!await requirePro(context, ref, ProFeature.accessibility) ||
        !context.mounted) {
      return;
    }
    await Navigator.of(
      context,
    ).push(AccessibilityPage.route(name: palette.name, colors: palette.colors));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final library = ref.read(libraryProvider.notifier);
    // The card leaves the list as soon as the delete starts, so hold on to
    // the messenger rather than this card's context.
    final messenger = ScaffoldMessenger.of(context);
    void say(String message, {SnackBarAction? action}) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          duration: Duration(milliseconds: action == null ? 2000 : 4000),
        ),
      );
    try {
      await library.delete(palette);
      say(
        'Deleted “${palette.name}”',
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => library.restore(palette).catchError((Object e) {
            say(describeError(e));
            return palette;
          }).ignore(),
        ),
      );
    } catch (e) {
      say(describeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pro = ref.watch(isProProvider);
    final details = [
      palette.kind.label,
      '${palette.colors.length} colors',
      ?folderName,
    ].join(' · ');

    PopupMenuItem<_Action> item(
      _Action value,
      IconData icon,
      String label, {
      bool proOnly = false,
    }) => PopupMenuItem(
      value: value,
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: proOnly && !pro ? const ProBadge() : null,
      ),
    );

    return Card.filled(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 88,
              child:
                  palette.kind == PaletteKind.gradient &&
                      palette.colors.length > 1
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [for (final c in palette.colors) c.color],
                        ),
                      ),
                    )
                  : Row(
                      // A childless ColoredBox takes its minimum height, so stretch
                      // the swatches to the full strip.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final c in palette.colors)
                          Expanded(child: ColoredBox(color: c.color)),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          palette.name,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (palette.tags.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in palette.tags)
                                ActionChip(
                                  label: Text(t),
                                  onPressed: () => onTag(t),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  labelStyle: theme.textTheme.labelSmall,
                                  tooltip: 'Show palettes tagged “$t”',
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<_Action>(
                    tooltip: 'Palette options',
                    onSelected: (action) => switch (action) {
                      _Action.open => onOpen(),
                      _Action.rename => _rename(context, ref),
                      _Action.move => _move(context, ref),
                      _Action.tags => _editTags(context, ref),
                      _Action.export => showExportSheet(context, (
                        name: palette.name,
                        kind: palette.kind,
                        colors: palette.colors,
                      )),
                      _Action.accessibility => _accessibility(context, ref),
                      _Action.copy => copyColors(context, palette.colors),
                      _Action.delete => _delete(context, ref),
                    },
                    itemBuilder: (context) => [
                      item(_Action.open, Icons.open_in_new, 'Open'),
                      item(_Action.rename, Icons.edit_outlined, 'Rename'),
                      item(
                        _Action.move,
                        Icons.drive_file_move_outline,
                        'Move to folder',
                        proOnly: true,
                      ),
                      item(
                        _Action.tags,
                        Icons.sell_outlined,
                        'Edit tags',
                        proOnly: true,
                      ),
                      item(_Action.export, Icons.ios_share, 'Export'),
                      item(
                        _Action.accessibility,
                        Icons.accessibility_new,
                        'Check accessibility',
                        proOnly: true,
                      ),
                      item(_Action.copy, Icons.copy, 'Copy hex codes'),
                      item(_Action.delete, Icons.delete_outline, 'Delete'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a name and creates the folder. Null if cancelled or it failed
/// (the error is shown).
Future<Folder?> promptNewFolder(BuildContext context, WidgetRef ref) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) =>
        const NameDialog(title: 'New folder', maxLength: 40, action: 'Create'),
  );
  if (name == null || !context.mounted) return null;
  try {
    return await ref.read(foldersProvider.notifier).create(name);
  } catch (e) {
    if (context.mounted) showMessage(context, describeError(e));
    return null;
  }
}

/// Lets the user pick a folder (or none, or a new one). Null if dismissed;
/// otherwise the chosen folder id, which is null for "No folder".
Future<({String? folderId})?> showMoveToFolderSheet(
  BuildContext context,
  WidgetRef ref, {
  required String? current,
}) {
  return showModalBottomSheet<({String? folderId})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // Keep the top of the sheet below the status bar (the app draws edge to edge).
    useSafeArea: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final folders = ref.watch(foldersProvider).value ?? const <Folder>[];
        Widget option(String? id, IconData icon, String label) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: current == id ? const Icon(Icons.check) : null,
          onTap: () => Navigator.of(context).pop((folderId: id)),
        );
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Text(
                    'Move to folder',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                option(null, Icons.folder_off_outlined, 'No folder'),
                for (final f in folders)
                  option(f.id, Icons.folder_outlined, f.name),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('New folder…'),
                  onTap: () async {
                    final folder = await promptNewFolder(context, ref);
                    if (folder != null && context.mounted) {
                      Navigator.of(context).pop((folderId: folder.id));
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// One-line name entry. Pops the trimmed name, or nothing on cancel.
class NameDialog extends StatefulWidget {
  const NameDialog({
    super.key,
    required this.title,
    this.initial = '',
    this.maxLength = 60,
    this.action = 'Save',
  });

  final String title;
  final String initial;
  final int maxLength;
  final String action;

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

/// Edits a palette's tags. Pops the new list, or nothing on cancel.
class _TagsDialog extends ConsumerStatefulWidget {
  const _TagsDialog({required this.initial});
  final List<String> initial;

  @override
  ConsumerState<_TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends ConsumerState<_TagsDialog> {
  static const _maxTags = 10;
  static const _maxLength = 30;

  late final List<String> _tags = [...widget.initial];
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _has(String tag) =>
      _tags.any((t) => t.toLowerCase() == tag.toLowerCase());

  void _add(String raw) {
    final tag = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    _controller.clear();
    if (tag.isEmpty || _has(tag) || _tags.length >= _maxTags) return;
    setState(() => _tags.add(tag));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = ref
        .watch(libraryTagsProvider)
        .where((t) => !_has(t))
        .take(8)
        .toList();
    final full = _tags.length >= _maxTags;

    return AlertDialog(
      title: const Text('Tags'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !full,
              maxLength: _maxLength,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: full ? 'Up to $_maxTags tags' : 'Add a tag',
                suffixIcon: IconButton(
                  tooltip: 'Add tag',
                  onPressed: full ? null : () => _add(_controller.text),
                  icon: const Icon(Icons.add),
                ),
              ),
              onSubmitted: _add,
            ),
            if (_tags.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _tags)
                    InputChip(
                      label: Text(t),
                      onDeleted: () => setState(() => _tags.remove(t)),
                      deleteButtonTooltipMessage: 'Remove “$t”',
                    ),
                ],
              ),
            if (suggestions.isNotEmpty && !full) ...[
              const SizedBox(height: 16),
              Text(
                'Used before',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in suggestions)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(t),
                      onPressed: () => _add(t),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            // Keep whatever is still typed in the field.
            final pending = _controller.text.trim();
            if (pending.isNotEmpty) _add(pending);
            Navigator.of(context).pop(List<String>.of(_tags));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
