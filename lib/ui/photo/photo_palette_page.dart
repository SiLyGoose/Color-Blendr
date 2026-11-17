import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/color_math.dart';
import '../../data/color_namer.dart';
import '../../data/models.dart';
import '../../data/photo_palette.dart';
import '../common.dart';

/// Asks for a camera shot or a gallery photo, then lets the user build a
/// palette of up to [count] colors from it. Resolves to the palette, or null
/// if they back out at any step.
Future<GeneratedPalette?> pickPhotoPalette(
  BuildContext context, {
  required int count,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose a photo'),
            onTap: () => Navigator.of(context).pop(ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.of(context).pop(ImageSource.camera),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;

  final XFile? file;
  try {
    // Downscaled by the picker, which also applies the photo's rotation.
    file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 92,
    );
  } on PlatformException catch (e) {
    if (context.mounted) {
      showMessage(
        context,
        'Couldn’t open the ${source.name}: ${e.message ?? e.code}',
      );
    }
    return null;
  }
  if (file == null || !context.mounted) return null;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return null;

  return Navigator.of(context).push<GeneratedPalette>(
    MaterialPageRoute(
      builder: (_) => PhotoPalettePage(bytes: bytes, count: count),
    ),
  );
}

/// Shows the photo with the colors pulled from it. Tap a swatch, then tap the
/// photo to replace that color with the one under your finger.
class PhotoPalettePage extends StatefulWidget {
  const PhotoPalettePage({super.key, required this.bytes, required this.count});

  final Uint8List bytes;
  final int count;

  @override
  State<PhotoPalettePage> createState() => _PhotoPalettePageState();
}

class _PhotoPalettePageState extends State<PhotoPalettePage> {
  /// Longest side the photo is decoded at: plenty for the screen and picking.
  static const _maxSide = 1200;

  ui.Image? _image;
  Uint8List? _rgba;
  List<String> _hexes = const [];
  int _selected = 0;
  int _seed = 7;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale =
          _maxSide /
          (descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height);
      final codec = await descriptor.instantiateCodec(
        targetWidth: scale < 1 ? (descriptor.width * scale).round() : null,
        targetHeight: scale < 1 ? (descriptor.height * scale).round() : null,
      );
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!mounted || data == null) {
        image.dispose();
        return;
      }
      final rgba = data.buffer.asUint8List();
      setState(() {
        _image = image;
        _rgba = rgba;
        _hexes = extractPalette(rgba, count: widget.count, seed: _seed);
      });
    } catch (_) {
      if (!mounted) return;
      showMessage(context, 'Couldn’t read that photo. Try another one.');
      Navigator.of(context).pop();
    }
  }

  void _reshuffle() {
    final rgba = _rgba;
    if (rgba == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _seed++;
      _hexes = extractPalette(rgba, count: widget.count, seed: _seed);
      _selected = _selected.clamp(0, _hexes.length - 1);
    });
  }

  /// Sets the selected swatch to the photo's color at [local], given the
  /// photo is drawn with BoxFit.contain in [box].
  void _pickAt(Offset local, Size box) {
    final image = _image, rgba = _rgba;
    if (image == null || rgba == null || _hexes.isEmpty) return;
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, imageSize, box).destination;
    final origin = Offset(
      (box.width - fitted.width) / 2,
      (box.height - fitted.height) / 2,
    );
    final p = local - origin;
    if (p.dx < 0 || p.dy < 0 || p.dx > fitted.width || p.dy > fitted.height) {
      return;
    }

    final cx = (p.dx / fitted.width * image.width).floor().clamp(
      0,
      image.width - 1,
    );
    final cy = (p.dy / fitted.height * image.height).floor().clamp(
      0,
      image.height - 1,
    );
    // Average a 3×3 patch so photo noise doesn't decide the color.
    var r = 0, g = 0, b = 0, n = 0;
    for (var y = cy - 1; y <= cy + 1; y++) {
      for (var x = cx - 1; x <= cx + 1; x++) {
        if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
        final o = (y * image.width + x) * 4;
        r += rgba[o];
        g += rgba[o + 1];
        b += rgba[o + 2];
        n++;
      }
    }
    final hex = [
      r ~/ n,
      g ~/ n,
      b ~/ n,
    ].map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    if (hex == _hexes[_selected]) return;
    setState(() => _hexes = [..._hexes]..[_selected] = hex);
  }

  void _use() {
    final colors = [
      for (final hex in _hexes)
        PaletteColor(
          hex: hex,
          name: ColorNamer.instance.name(hex),
          textHex: readableTextHex(hex),
        ),
    ];
    Navigator.of(context)
        .pop(GeneratedPalette(kind: PaletteKind.palette, colors: colors));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = _image;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Palette from photo'),
        actions: [
          IconButton(
            tooltip: 'Pick different colors',
            onPressed: image == null ? null : _reshuffle,
            icon: const Icon(Icons.shuffle),
          ),
        ],
      ),
      body: image == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final box = constraints.biggest;
                          return GestureDetector(
                            onTapDown: (d) => _pickAt(d.localPosition, box),
                            onPanUpdate: (d) => _pickAt(d.localPosition, box),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: RawImage(
                                image: image,
                                fit: BoxFit.contain,
                                width: box.width,
                                height: box.height,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Text(
                    'Tap a color, then tap the photo to change it',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        for (final (i, hex) in _hexes.indexed)
                          Expanded(
                            child: _PickSwatch(
                              hex: hex,
                              selected: i == _selected,
                              onTap: () => setState(() => _selected = i),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: _hexes.isEmpty ? null : _use,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Use this palette'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _PickSwatch extends StatelessWidget {
  const _PickSwatch({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(hex);
    final onColor = colorFromHex(readableTextHex(hex));
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        selected: selected,
        button: true,
        label: '#${hex.toUpperCase()}',
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 64,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: selected
                ? Icon(Icons.colorize, color: onColor, size: 20)
                : null,
          ),
        ),
      ),
    );
  }
}
