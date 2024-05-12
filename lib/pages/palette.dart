import 'package:color_blendr/pages/base/basePage.dart';
import 'package:color_blendr/util/blendrPaletteUtil.dart';
import 'package:flutter/material.dart';

import 'base/paletteBasePage.dart';

class PalettePage extends PaletteBasePage {
  const PalettePage({required GlobalKey<BasePageState> key}) : super(key: key);

  @override
  PalettePageState createState() => PalettePageState();
}

class PalettePageState extends PaletteBasePageState {
  @override
  Future<Map<String, PaletteEntry>> fetchData() async {
    return await BlendrPaletteUtil.generatePalette();
  }
}
