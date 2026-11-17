import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/palette_export.dart';
import '../../state/auth_controller.dart';
import '../common.dart';
import '../pro/pro_sheet.dart';
import 'palette_image.dart';

/// Lists every export format. Hex codes are free; the rest are Pro.
Future<void> showExportSheet(BuildContext context, ExportSource source) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      // Keep the top of the sheet below the status bar (the app draws edge to edge).
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            _ExportSheet(source: source, controller: controller),
      ),
    );

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({required this.source, required this.controller});
  final ExportSource source;
  final ScrollController controller;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  ExportFormat? _busy;

  ExportSource get _source => widget.source;

  static IconData _icon(ExportFormat f) => switch (f) {
    ExportFormat.hex => Icons.tag,
    ExportFormat.css ||
    ExportFormat.scss ||
    ExportFormat.tailwind => Icons.code,
    ExportFormat.json => Icons.data_object,
    ExportFormat.cssGradient => Icons.gradient,
    ExportFormat.gpl || ExportFormat.ase => Icons.palette_outlined,
    ExportFormat.image => Icons.image_outlined,
    ExportFormat.wallpaper => Icons.wallpaper,
  };

  Future<void> _export(ExportFormat format) async {
    if (format.pro && !await requirePro(context, ref, ProFeature.export)) {
      return;
    }
    if (!mounted) return;

    if (format == ExportFormat.hex) {
      await copyColors(context, _source.colors);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!format.file) {
      await _showText(format);
      return;
    }

    setState(() => _busy = format);
    try {
      final Uint8List bytes;
      switch (format) {
        case ExportFormat.gpl:
          bytes = utf8.encode(exportText(format, _source));
        case ExportFormat.ase:
          bytes = exportAse(_source);
        case ExportFormat.image:
          bytes = await renderPalettePng(
            _source,
            size: const Size(1600, 1000),
            labels: true,
          );
        case ExportFormat.wallpaper:
          final view = View.of(context);
          bytes = await renderPalettePng(
            _source,
            size: view.physicalSize.width < view.physicalSize.height
                ? view.physicalSize
                : view.physicalSize.flipped,
            labels: false,
          );
        default:
          throw StateError('$format is not a file format');
      }
      await _shareFile(bytes, format);
    } catch (e) {
      if (mounted) showMessage(context, 'Couldn’t export: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _shareFile(Uint8List bytes, ExportFormat format) async {
    final name = exportFileName(format, _source);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, mimeType: exportMimeType(format), name: name),
        ],
        fileNameOverrides: [name],
        subject: _source.name,
      ),
    );
  }

  Future<void> _showText(ExportFormat format) => showDialog<void>(
    context: context,
    builder: (context) => _TextExportDialog(
      title: format.label,
      text: exportText(format, _source),
      onShare: (text) => SharePlus.instance.share(
        ShareParams(text: text, subject: _source.name),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pro = ref.watch(isProProvider);
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Export “${_source.name}”',
            style: theme.textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final format in ExportFormat.values)
          ListTile(
            enabled: _busy == null,
            leading: Icon(_icon(format)),
            title: Text(format.label),
            subtitle: Text(format.description),
            trailing: _busy == format
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : format.pro && !pro
                ? const ProBadge()
                : Icon(
                    format.file ? Icons.ios_share : Icons.content_copy,
                    size: 20,
                  ),
            onTap: () => _export(format),
          ),
      ],
    );
  }
}

class _TextExportDialog extends StatelessWidget {
  const _TextExportDialog({
    required this.title,
    required this.text,
    required this.onShare,
  });

  final String title;
  final String text;
  final Future<void> Function(String text) onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(title),
      content: Container(
        constraints: const BoxConstraints(maxHeight: 360),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => onShare(text), child: const Text('Share')),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            await HapticFeedback.selectionClick();
            if (!context.mounted) return;
            showMessage(context, 'Copied $title');
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.content_copy, size: 18),
          label: const Text('Copy'),
        ),
      ],
    );
  }
}
