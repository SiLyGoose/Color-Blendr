import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/palette_export.dart';

/// Draws the palette as a PNG of [size] pixels.
///
/// Palettes are equal bands (side by side when landscape, stacked when
/// portrait); gradients are a smooth blend in the same direction. With
/// [labels], each color's hex code and name are printed on it.
Future<Uint8List> renderPalettePng(
  ExportSource p, {
  required Size size,
  required bool labels,
}) async {
  final recorder = ui.PictureRecorder();
  final rect = Offset.zero & size;
  final canvas = Canvas(recorder, rect);
  final colors = p.colors;
  final n = colors.length;
  final stacked = size.height > size.width;
  final extent = stacked ? size.height : size.width;

  if (n == 0) {
    canvas.drawRect(rect, Paint()..color = Colors.white);
  } else if (p.kind == PaletteKind.gradient && n > 1) {
    final shader = ui.Gradient.linear(
      Offset.zero,
      stacked ? Offset(0, size.height) : Offset(size.width, 0),
      [for (final c in colors) c.color],
      [for (var i = 0; i < n; i++) i / (n - 1)],
    );
    canvas.drawRect(rect, Paint()..shader = shader);
  } else {
    final band = extent / n;
    for (final (i, c) in colors.indexed) {
      final r = stacked
          ? Rect.fromLTWH(0, i * band, size.width, band + 1)
          : Rect.fromLTWH(i * band, 0, band + 1, size.height);
      canvas.drawRect(r, Paint()..color = c.color);
    }
  }

  if (labels && n > 0) {
    final shortSide = stacked ? size.width : size.height;
    final hexSize = shortSide * 0.045;
    final nameSize = shortSide * 0.028;
    final band = extent / n;
    for (final (i, c) in colors.indexed) {
      final hex = _paragraph(
        c.label,
        c.textColor,
        hexSize,
        FontWeight.w600,
        stacked ? size.width : band,
      );
      final name = _paragraph(
        c.name,
        c.textColor.withValues(alpha: 0.75),
        nameSize,
        FontWeight.w400,
        stacked ? size.width : band,
      );
      final blockHeight = hex.height + name.height;
      final Offset origin;
      if (stacked) {
        origin = Offset(0, i * band + (band - blockHeight) / 2);
      } else {
        origin = Offset(
          i * band,
          size.height - blockHeight - size.height * 0.08,
        );
      }
      canvas.drawParagraph(hex, origin);
      canvas.drawParagraph(name, origin.translate(0, hex.height));
    }
  }

  final image = await recorder.endRecording().toImage(
    size.width.round(),
    size.height.round(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

ui.Paragraph _paragraph(
  String text,
  Color color,
  double fontSize,
  FontWeight weight,
  double width,
) {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: TextAlign.center,
            maxLines: 1,
            ellipsis: '…',
          ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
            letterSpacing: 1,
          ),
        )
        ..addText(text);
  return builder.build()..layout(ui.ParagraphConstraints(width: width));
}
