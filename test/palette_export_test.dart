import 'dart:convert';
import 'dart:typed_data';

import 'package:color_blendr/data/models.dart';
import 'package:color_blendr/data/palette_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  final sunset = (
    name: 'Sunset',
    kind: PaletteKind.palette,
    colors: [
      color('ff5733', 'Orange Red'),
      color('1a2b3c', 'Deep Navy'),
      color('ffffff', 'White'),
    ],
  );

  test('variable names are kebab-case, unique and valid identifiers', () {
    expect(
      variableNames([
        color('000000', 'Orange Red'),
        color('000001', 'Orange Red'),
        color('000002', "Mother's Day"),
        color('000003', '360 Blue'),
        color('000004', '!!!'),
      ]),
      ['orange-red', 'orange-red-2', 'mothers-day', 'color-360-blue', 'color'],
    );
  });

  test('hex codes', () {
    expect(exportText(ExportFormat.hex, sunset), '#FF5733 #1A2B3C #FFFFFF');
  });

  test('CSS variables', () {
    final css = exportText(ExportFormat.css, sunset);
    expect(css, contains(':root {'));
    expect(css, contains('  --orange-red: #ff5733;'));
    expect(css, contains('  --deep-navy: #1a2b3c;'));
    expect(css, isNot(contains('--gradient')));
    expect(css.trim(), endsWith('}'));
  });

  test('CSS for a gradient also includes the gradient', () {
    final css = exportText(ExportFormat.css, (
      name: 'G',
      kind: PaletteKind.gradient,
      colors: sunset.colors,
    ));
    expect(
      css,
      contains(
        '--gradient: linear-gradient(90deg, #ff5733 0%, #1a2b3c 50%, #ffffff 100%);',
      ),
    );
  });

  test('SCSS variables and map', () {
    final scss = exportText(ExportFormat.scss, sunset);
    expect(scss, contains(r'$orange-red: #ff5733;'));
    expect(scss, contains(r'"deep-navy": $deep-navy,'));
    expect(scss, contains(r'$palette: ('));
  });

  test('Tailwind v4 theme', () {
    final tw = exportText(ExportFormat.tailwind, sunset);
    expect(tw, contains('@theme {'));
    expect(tw, contains('  --color-orange-red: #ff5733;'));
  });

  test('JSON round-trips', () {
    final json = jsonDecode(
      exportText(ExportFormat.json, sunset),
    ) as Map<String, dynamic>;
    expect(json['name'], 'Sunset');
    expect(json['kind'], 'palette');
    expect(json['colors'][0], {
      'name': 'Orange Red',
      'hex': '#ff5733',
      'rgb': [255, 87, 51],
    });
  });

  test('CSS gradient stops are evenly spaced', () {
    expect(
      cssGradient([color('000000'), color('ffffff')]),
      'linear-gradient(90deg, #000000 0%, #ffffff 100%)',
    );
    final four = cssGradient(List.generate(4, (i) => color('00000$i')));
    expect(four, contains('#000001 33.33%'));
    expect(four, contains('#000002 66.67%'));
  });

  test('GIMP palette', () {
    final gpl = exportText(ExportFormat.gpl, sunset);
    final lines = const LineSplitter().convert(gpl);
    expect(lines.take(4), ['GIMP Palette', 'Name: Sunset', 'Columns: 3', '#']);
    expect(lines[4], '255  87  51\tOrange Red');
    expect(lines[6], '255 255 255\tWhite');
  });

  test('Adobe swatch exchange file is well formed', () {
    final bytes = exportAse(sunset);
    final data = ByteData.sublistView(bytes);
    var o = 0;
    int u16() => data.getUint16((o += 2) - 2);
    int u32() => data.getUint32((o += 4) - 4);
    String name() {
      final len = u16();
      final units = [for (var i = 0; i < len; i++) u16()];
      expect(units.last, 0, reason: 'null terminated');
      return String.fromCharCodes(units.sublist(0, len - 1));
    }

    expect(ascii.decode(bytes.sublist(0, 4)), 'ASEF');
    o = 4;
    expect([u16(), u16()], [1, 0]);
    expect(u32(), 5, reason: 'group start + 3 colors + group end');

    expect(u16(), 0xC001);
    final groupLength = u32();
    final groupStart = o;
    expect(name(), 'Sunset');
    expect(o - groupStart, groupLength);

    final names = <String>[];
    final rgb = <List<double>>[];
    for (var i = 0; i < 3; i++) {
      expect(u16(), 0x0001);
      final length = u32();
      final start = o;
      names.add(name());
      expect(ascii.decode(bytes.sublist(o, o + 4)), 'RGB ');
      o += 4;
      rgb.add([for (var c = 0; c < 3; c++) data.getFloat32((o += 4) - 4)]);
      expect(u16(), 2, reason: 'normal color');
      expect(o - start, length);
    }
    expect(names, ['Orange Red', 'Deep Navy', 'White']);
    expect(rgb[0][0], closeTo(1.0, 1e-6));
    expect(rgb[0][1], closeTo(87 / 255, 1e-6));
    expect(rgb[2], [1.0, 1.0, 1.0]);

    expect(u16(), 0xC002);
    expect(u32(), 0);
    expect(o, bytes.length);
  });

  test('file names and types', () {
    expect(exportFileName(ExportFormat.ase, sunset), 'sunset.ase');
    expect(
      exportFileName(ExportFormat.wallpaper, sunset),
      'sunset-wallpaper.png',
    );
    expect(
      exportFileName(ExportFormat.gpl, (
        name: '★',
        kind: PaletteKind.gradient,
        colors: sunset.colors,
      )),
      'color-blendr-gradient.gpl',
    );
    expect(exportMimeType(ExportFormat.image), 'image/png');
  });

  test('only hex codes are free', () {
    expect(
      [
        for (final f in ExportFormat.values)
          if (!f.pro) f,
      ],
      [ExportFormat.hex],
    );
  });
}
