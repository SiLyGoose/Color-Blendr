import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';

/// What gets exported: a palette's name, mode and colors in order.
typedef ExportSource = ({
  String name,
  PaletteKind kind,
  List<PaletteColor> colors,
});

/// Every way a palette can leave the app. [pro] formats need Color Blendr Pro.
enum ExportFormat {
  hex('Hex codes', '#FF5733 #1A2B3C', pro: false),
  css('CSS variables', ':root { --name: #hex; }'),
  scss('SCSS variables', r'$name: #hex;'),
  tailwind('Tailwind CSS', '@theme colors (Tailwind v4)'),
  json('JSON', 'Names, hex and RGB values'),
  cssGradient('CSS gradient', 'linear-gradient(…)'),
  gpl('GIMP / Krita / Inkscape', '.gpl palette file', file: true),
  ase('Adobe swatches', '.ase for Illustrator, Photoshop…', file: true),
  image('Image', 'PNG of the palette', file: true),
  wallpaper('Phone wallpaper', 'PNG sized for this screen', file: true);

  const ExportFormat(
    this.label,
    this.description, {
    this.pro = true,
    this.file = false,
  });

  final String label;
  final String description;
  final bool pro;

  /// Shared as a file rather than as text.
  final bool file;

  bool get isImage => this == image || this == wallpaper;
}

// --- Text formats --------------------------------------------------------------

/// The text for a text format (or for .gpl, which is a text file).
String exportText(ExportFormat format, ExportSource p) {
  final names = variableNames(p.colors);
  final title = '${p.name} (${p.kind.label.toLowerCase()}) from Color Blendr';
  String hexOf(PaletteColor c) => '#${c.hex}';
  final buffer = StringBuffer();

  switch (format) {
    case ExportFormat.hex:
      return p.colors.map((c) => c.label).join(' ');

    case ExportFormat.css:
      buffer.writeln('/* $title */');
      buffer.writeln(':root {');
      for (final (i, c) in p.colors.indexed) {
        buffer.writeln('  --${names[i]}: ${hexOf(c)};');
      }
      if (p.kind == PaletteKind.gradient && p.colors.length > 1) {
        buffer.writeln('  --gradient: ${cssGradient(p.colors)};');
      }
      buffer.write('}');

    case ExportFormat.scss:
      buffer.writeln('// $title');
      for (final (i, c) in p.colors.indexed) {
        buffer.writeln('\$${names[i]}: ${hexOf(c)};');
      }
      buffer.writeln();
      buffer.writeln('\$palette: (');
      for (final (i, _) in p.colors.indexed) {
        buffer.writeln('  "${names[i]}": \$${names[i]},');
      }
      buffer.write(');');

    case ExportFormat.tailwind:
      buffer.writeln('/* $title */');
      buffer.writeln('@theme {');
      for (final (i, c) in p.colors.indexed) {
        buffer.writeln('  --color-${names[i]}: ${hexOf(c)};');
      }
      buffer.write('}');

    case ExportFormat.json:
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert({
        'name': p.name,
        'kind': p.kind.name,
        'colors': [
          for (final c in p.colors)
            {'name': c.name, 'hex': hexOf(c), 'rgb': _rgb(c.hex)},
        ],
      });

    case ExportFormat.cssGradient:
      return 'background: ${cssGradient(p.colors)};';

    case ExportFormat.gpl:
      buffer.writeln('GIMP Palette');
      buffer.writeln('Name: ${_oneLine(p.name)}');
      buffer.writeln('Columns: ${p.colors.length}');
      buffer.writeln('#');
      for (final c in p.colors) {
        final [r, g, b] = _rgb(c.hex);
        buffer.writeln(
          '${'$r'.padLeft(3)} ${'$g'.padLeft(3)} ${'$b'.padLeft(3)}\t${_oneLine(c.name)}',
        );
      }
      return buffer.toString();

    case ExportFormat.ase:
    case ExportFormat.image:
    case ExportFormat.wallpaper:
      throw ArgumentError.value(format, 'format', 'is not a text format');
  }
  return buffer.toString();
}

/// `linear-gradient(90deg, #a 0%, #b 100%)` with evenly spaced stops.
String cssGradient(List<PaletteColor> colors) {
  if (colors.isEmpty) return 'none';
  if (colors.length == 1) {
    return 'linear-gradient(90deg, #${colors.single.hex}, #${colors.single.hex})';
  }
  final stops = [
    for (final (i, c) in colors.indexed)
      '#${c.hex} ${_percent(i * 100 / (colors.length - 1))}',
  ];
  return 'linear-gradient(90deg, ${stops.join(', ')})';
}

String _percent(double v) {
  final rounded = (v * 100).round() / 100;
  return rounded == rounded.roundToDouble()
      ? '${rounded.round()}%'
      : '$rounded%';
}

/// Kebab-case variable names from the color names ("Orange Red" →
/// "orange-red"), made unique with -2, -3…
List<String> variableNames(List<PaletteColor> colors) {
  final used = <String, int>{};
  return [
    for (final c in colors)
      () {
        var base = c.name
            .toLowerCase()
            .replaceAll(RegExp(r"['’]"), '')
            .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '');
        if (base.isEmpty) base = 'color';
        // CSS and SCSS identifiers can't start with a digit.
        if (RegExp(r'^[0-9]').hasMatch(base)) base = 'color-$base';
        final n = (used[base] ?? 0) + 1;
        used[base] = n;
        return n == 1 ? base : '$base-$n';
      }(),
  ];
}

List<int> _rgb(String hex) {
  final v = int.parse(hex, radix: 16);
  return [(v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
}

String _oneLine(String s) => s.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();

// --- Adobe Swatch Exchange -----------------------------------------------------

/// An .ase file: one group named after the palette, holding its colors as
/// RGB process swatches. Big-endian, names in UTF-16 with a null terminator.
Uint8List exportAse(ExportSource p) {
  final out = BytesBuilder();
  void u16(int v) => out.add([(v >> 8) & 0xff, v & 0xff]);
  void u32(int v) =>
      out.add([(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
  void f32(double v) =>
      out.add((ByteData(4)..setFloat32(0, v)).buffer.asUint8List());

  List<int> nameField(String name) {
    final units = _oneLine(name).codeUnits;
    final field = BytesBuilder();
    final count = units.length + 1;
    field.add([(count >> 8) & 0xff, count & 0xff]);
    for (final u in units) {
      field.add([(u >> 8) & 0xff, u & 0xff]);
    }
    field.add([0, 0]);
    return field.takeBytes();
  }

  out.add(ascii.encode('ASEF'));
  u16(1);
  u16(0);
  u32(p.colors.length + 2); // group start + colors + group end

  final groupName = nameField(p.name);
  u16(0xC001);
  u32(groupName.length);
  out.add(groupName);

  for (final c in p.colors) {
    final name = nameField(c.name);
    u16(0x0001);
    u32(name.length + 4 + 12 + 2);
    out.add(name);
    out.add(ascii.encode('RGB '));
    for (final channel in _rgb(c.hex)) {
      f32(channel / 255);
    }
    u16(2); // normal (process) color
  }

  u16(0xC002);
  u32(0);
  return out.takeBytes();
}

// --- File names ----------------------------------------------------------------

/// "sunset-palette.ase"
String exportFileName(ExportFormat format, ExportSource p) {
  var base = p.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.isEmpty) base = 'color-blendr-${p.kind.name}';
  final ext = switch (format) {
    ExportFormat.gpl => 'gpl',
    ExportFormat.ase => 'ase',
    ExportFormat.image || ExportFormat.wallpaper => 'png',
    ExportFormat.json => 'json',
    ExportFormat.scss => 'scss',
    ExportFormat.css ||
    ExportFormat.tailwind ||
    ExportFormat.cssGradient => 'css',
    ExportFormat.hex => 'txt',
  };
  return format == ExportFormat.wallpaper
      ? '$base-wallpaper.$ext'
      : '$base.$ext';
}

/// MIME type to share [format] as.
String exportMimeType(ExportFormat format) => switch (format) {
  ExportFormat.image || ExportFormat.wallpaper => 'image/png',
  ExportFormat.ase => 'application/octet-stream',
  ExportFormat.json => 'application/json',
  _ => 'text/plain',
};
